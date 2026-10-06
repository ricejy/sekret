"""Resume a frozen interrupted screen without replacing any existing evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'model_comparison'))
from validate_text_report import validate_report


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def text_hash(value):
    return hashlib.sha256(value.encode()).hexdigest()


def guarded_run(command, out, err, *, free_bytes, reserve=3 * 1024**3, timeout=120):
    if free_bytes() < reserve:
        return {'stop_reason': 'disk_reserve_before_launch'}
    start = time.monotonic()
    process = subprocess.Popen(command, stdout=out, stderr=err)
    reason = None
    try:
        while process.poll() is None:
            if free_bytes() < reserve:
                reason = 'disk_reserve_during_run'
                break
            if time.monotonic() - start >= timeout:
                reason = 'timeout'
                break
            time.sleep(0.25)
    finally:
        if process.poll() is None:
            process.send_signal(signal.SIGINT)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
    result = {'exit_code': process.returncode, 'process_seconds': time.monotonic() - start}
    if reason:
        result['stop_reason'] = reason
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('run_dir', type=Path)
    args = parser.parse_args()
    run_dir = args.run_dir.resolve()
    if run_dir.parent != (HERE / 'results').resolve():
        raise ValueError('Expected a direct child of this evaluation results directory')
    manifest = json.loads((run_dir / 'manifest.json').read_text())
    suite_path = HERE.parent / 'model_comparison/broader-text-v1.json'
    assert digest(suite_path) == manifest['suite_sha256'] == 'd3cfa3104a58a512bd7354ea71cff11f4ecc88353861fa6e88534572f4dc87c4'
    assert digest(run_dir / 'suite.json') == manifest['suite_sha256']
    assert digest(HERE / 'profile.json') == manifest['profile_sha256']
    profile = json.loads((HERE / 'profile.json').read_text())
    assert json.loads((run_dir / 'profile.json').read_text()) == profile
    binary = HERE / '.build/release/QwenCLI'
    assert digest(binary) == manifest['binary_sha256']
    model = HERE / 'artifacts' / profile['modelFile']
    assert model.stat().st_size == profile['modelBytes']
    assert digest(model) == manifest['model_sha256'] == profile['modelSHA256']
    for name, expected in manifest['reference_sha256'].items():
        assert digest(HERE / 'artifacts' / name) == expected
    assert manifest['preflight'] == '30/30 native/publisher prompt and token-ID matches'
    suite = json.loads(suite_path.read_text())
    native_list = json.loads((run_dir / 'native-tokens.json').read_text())
    native = {item['id']: item for item in native_list}
    assert len(native_list) == len(native) == len(suite['cases']) == 30
    sys.path.insert(0, str(HERE.parent / 'liquid_text/artifacts/diagnostic-reference/python'))
    from tokenizers import Tokenizer, __version__
    assert __version__ == manifest['tokenizer_version']
    tokenizer = Tokenizer.from_file(str(HERE / 'artifacts/tokenizer.json'))
    for case in suite['cases']:
        prompt = ('<|im_start|>system\n' + suite['text_system'] + '<|im_end|>\n<|im_start|>user\n'
                  + case['prompt'] + '<|im_end|>\n<|im_start|>assistant\n')
        assert native[case['id']]['prompt'] == prompt
        assert native[case['id']]['tokenIDs'] == tokenizer.encode(prompt, add_special_tokens=False).ids

    def validate(path, case_id):
        report = json.loads(path.read_text())
        validation = validate_report(report, profile)
        run = report['runs'][0]
        assert run['promptSHA256'] == text_hash(native[case_id]['prompt'])
        assert run['tokenIDsSHA256'] == text_hash(','.join(map(str, native[case_id]['tokenIDs'])))
        return {'validation': validation, 'outcome': run['outcome'], 'report_sha256': digest(path)}

    evidence = {item['id']: item for item in manifest['cases']}
    recovery = json.loads((run_dir / 'pause-state.json').read_text())['recovered_report']
    evidence[recovery['id']] = {'report_sha256': recovery['sha256'], 'exit_code': None}
    continuation_path = run_dir / 'continuation.json'
    if continuation_path.exists():
        continuation = json.loads(continuation_path.read_text())
        for item in continuation['cases']:
            if item.get('stop_reason') or item.get('exit_code') != 0 or item.get('validation_error'):
                raise ValueError('Prior interrupted/failed attempt requires explicit audit; no automatic retry')
            assert item['id'] not in evidence
            evidence[item['id']] = item
    else:
        continuation = {'original_manifest_sha256': digest(run_dir / 'manifest.json'),
                        'status': 'pending', 'preserved_cases': list(evidence), 'cases': [],
                        'qualification': 'Interrupted development run; manual quality grading required; timings not a controlled benchmark'}
    assert continuation['original_manifest_sha256'] == digest(run_dir / 'manifest.json')
    for case in suite['cases']:
        path = run_dir / (case['id'] + '.json')
        if case['id'] in evidence:
            assert digest(path) == evidence[case['id']]['report_sha256']
            assert validate(path, case['id'])['outcome'] == 'completed'
        elif path.exists():
            raise ValueError('Unrecorded output requires audit: ' + case['id'])
    free_bytes = lambda: shutil.disk_usage(HERE).free
    if free_bytes() < 8_000_000_000:
        raise ValueError('Need at least 8 GB free before resuming')

    def save():
        temporary = continuation_path.with_suffix('.json.tmp')
        temporary.write_text(json.dumps(continuation, indent=2) + '\n')
        temporary.replace(continuation_path)

    continuation['status'] = 'running'
    save()
    print('Verified frozen artifacts, 30 token sequences, and', len(evidence), 'preserved answers', flush=True)
    for case in suite['cases']:
        case_id = case['id']
        if case_id in evidence:
            continue
        if free_bytes() < 3 * 1024**3:
            continuation['status'] = 'paused_disk_reserve'
            save()
            raise SystemExit('Paused before next case: low disk space')
        prompt_path = run_dir / (case_id + '.prompt.txt')
        prompt_path.write_text(case['prompt'])
        path = run_dir / (case_id + '.json')
        entry = {'id': case_id, 'category': case['category']}
        with path.open('xb') as out, (run_dir / (case_id + '.stderr')).open('xb') as err:
            entry.update(guarded_run([str(binary), str(model), str(prompt_path)], out, err, free_bytes=free_bytes))
        try:
            entry.update(validate(path, case_id))
        except (ValueError, KeyError, TypeError, AssertionError) as error:
            entry['validation_error'] = repr(error)
        continuation['cases'].append(entry)
        save()
        print(case_id, entry.get('outcome', entry.get('validation_error')), 'free GiB:', round(free_bytes()/1024**3, 2), flush=True)
        if entry.get('stop_reason') or entry.get('exit_code') != 0 or entry.get('validation_error'):
            continuation['status'] = 'paused_requires_audit'
            save()
            raise SystemExit(1)
    continuation['status'] = 'generation_finished_manual_grading_pending'
    save()


if __name__ == '__main__':
    main()
