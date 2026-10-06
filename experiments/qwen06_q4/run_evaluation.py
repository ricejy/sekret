"""Offline compact-model screens after independent token-parity admission."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE.parent / 'model_comparison'))
from validate_text_report import validate_report
sys.path.insert(0, str(HERE.parent / 'liquid_text/artifacts/diagnostic-reference/python'))
from tokenizers import Tokenizer, __version__ as tokenizer_version
sys.path.insert(0, str(HERE.parent / 'qwen4_text'))
from resume_evaluation import guarded_run
from types import SimpleNamespace

def run_native(command, *, stdout, stderr, timeout):
    result = guarded_run(command, stdout, stderr, timeout=timeout,
                         free_bytes=lambda: shutil.disk_usage(HERE).free)
    if result.get('stop_reason'):
        raise RuntimeError('Resource guard stopped native process: ' + result['stop_reason'])
    return SimpleNamespace(returncode=result['exit_code'])

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def text_hash(value):
    return hashlib.sha256(value.encode()).hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--suite', choices=['broader', 'original'], default='broader')
    args = parser.parse_args()
    filename, expected_hash = {
        'broader': ('broader-text-v1.json', 'd3cfa3104a58a512bd7354ea71cff11f4ecc88353861fa6e88534572f4dc87c4'),
        'original': ('development-v1.json', 'f4d4adc3eb0547e7a0463b453bec293ba208810c3155081872f7d6413699843c'),
    }[args.suite]
    suite_path = HERE.parent / 'model_comparison' / filename
    suite_bytes = suite_path.read_bytes()
    if hashlib.sha256(suite_bytes).hexdigest() != expected_hash:
        raise ValueError('Frozen suite changed')
    suite = json.loads(suite_bytes)
    suite['cases'] = [case for case in suite['cases'] if case['modality'] == 'text']
    case_count = len(suite['cases'])
    profile = json.loads((HERE / 'profile.json').read_text())
    if (suite['context'], suite['output_cap']) != (profile['context'], profile['output_cap']):
        raise ValueError('Suite/profile budget mismatch')
    model = HERE / 'artifacts' / profile['modelFile']
    if model.stat().st_size != profile['modelBytes'] or digest(model) != profile['modelSHA256']:
        raise ValueError('Artifact size/SHA mismatch')
    if shutil.disk_usage(HERE).free < 8_000_000_000:
        raise ValueError('Insufficient operational disk reserve')
    binary = HERE / '.build/release/QwenCLI'
    (HERE / 'results').mkdir(exist_ok=True)
    run_dir = Path(tempfile.mkdtemp(prefix=args.suite + '-', dir=HERE / 'results'))
    (run_dir / 'suite.json').write_bytes(suite_bytes)
    (run_dir / 'profile.json').write_text(json.dumps(profile, indent=2))
    manifest = {'suite_sha256': digest(suite_path), 'profile_sha256': digest(HERE / 'profile.json'),
                'binary_sha256': digest(binary), 'model_sha256': profile['modelSHA256'],
                'reference_sha256': {name: digest(HERE / 'artifacts' / name) for name in
                                    ['tokenizer.json', 'tokenizer_config.json', 'generation_config.json', 'config.json', 'LICENSE']},
                'tokenizer_version': tokenizer_version, 'preflight': 'pending', 'cases': []}
    def save():
        (run_dir / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    save()
    print(run_dir, flush=True)
    with (run_dir / 'native-tokens.json').open('wb') as out, (run_dir / 'preflight.stderr').open('wb') as err:
        try:
            result = run_native([str(binary), str(model), str(suite_path), '--tokens-suite'],
                                    stdout=out, stderr=err, timeout=120)
            if result.returncode != 0:
                raise ValueError(f'Native admission failed: {result.returncode}')
            native_records = json.loads((run_dir / 'native-tokens.json').read_text())
            native = {item['id']: item for item in native_records}
            expected_ids = {case['id'] for case in suite['cases']}
            if len(native_records) != case_count or len(native) != case_count or set(native) != expected_ids:
                raise ValueError('Incomplete/duplicate token preflight cases')
            tokenizer = Tokenizer.from_file(str(HERE / 'artifacts/tokenizer.json'))
            for case in suite['cases']:
                expected_prompt = ('<|im_start|>system\n' + suite['text_system'] + '<|im_end|>\n<|im_start|>user\n' +
                                   case['prompt'] + '<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n')
                item = native[case['id']]
                if item['prompt'] != expected_prompt or item['tokenIDs'] != tokenizer.encode(expected_prompt, add_special_tokens=False).ids:
                    raise ValueError(f'Publisher token parity mismatch: {case["id"]}')
            manifest['preflight'] = f'{case_count}/{case_count} native/publisher prompt and token-ID matches'
        except Exception as error:
            manifest['preflight'] = 'failed: ' + str(error)
            save()
            raise
    save()
    print(manifest['preflight'], flush=True)
    for case in suite['cases']:
        case_id = case['id']
        prompt = run_dir / (case_id + '.prompt.txt')
        prompt.write_text(case['prompt'])
        report_path = run_dir / (case_id + '.json')
        entry = {'id': case_id, 'category': case.get('category', 'original-development')}
        started = time.monotonic()
        with report_path.open('wb') as out, (run_dir / (case_id + '.stderr')).open('wb') as err:
            try:
                result = run_native([str(binary), str(model), str(prompt)], stdout=out, stderr=err, timeout=120)
                entry['exit_code'] = result.returncode
            except subprocess.TimeoutExpired:
                entry['timeout'] = True
            except OSError as error:
                entry['launch_error'] = str(error)
            except RuntimeError as error:
                entry['resource_stop'] = str(error)
        entry['process_seconds'] = time.monotonic() - started
        entry['report_sha256'] = digest(report_path)
        try:
            report = json.loads(report_path.read_text())
            entry['validation'] = validate_report(report, profile)
            item = native[case_id]
            if report['runs'][0]['promptSHA256'] != text_hash(item['prompt']) or report['runs'][0]['tokenIDsSHA256'] != text_hash(','.join(map(str, item['tokenIDs']))):
                raise ValueError('Generation prompt/token IDs differ from admitted preflight')
            entry['outcome'] = report['runs'][0]['outcome']
        except (ValueError, KeyError, TypeError) as error:
            entry['validation_error'] = str(error)
        manifest['cases'].append(entry)
        save()
        print(case_id, entry.get('outcome', entry.get('validation_error', 'failed')), flush=True)
        if entry.get('resource_stop'):
            raise SystemExit('Resource guard stopped the screen; inspect preserved output before any resume')
    if any(item.get('exit_code') != 0 or item.get('validation_error') or item.get('outcome') != 'completed' for item in manifest['cases']):
        raise SystemExit(1)

if __name__ == '__main__':
    main()
