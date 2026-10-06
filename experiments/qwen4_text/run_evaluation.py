"""Offline, one frozen Qwen4 screen after independent token-parity admission."""
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

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def text_hash(value):
    return hashlib.sha256(value.encode()).hexdigest()

def main():
    suite_path = HERE.parent / 'model_comparison/broader-text-v1.json'
    suite_bytes = suite_path.read_bytes()
    if hashlib.sha256(suite_bytes).hexdigest() != 'd3cfa3104a58a512bd7354ea71cff11f4ecc88353861fa6e88534572f4dc87c4':
        raise ValueError('Frozen suite changed')
    suite = json.loads(suite_bytes)
    profile = json.loads((HERE / 'profile.json').read_text())
    if (suite['context'], suite['output_cap']) != (profile['context'], profile['output_cap']):
        raise ValueError('Suite/profile budget mismatch')
    model = HERE / 'artifacts' / profile['modelFile']
    if model.stat().st_size != profile['modelBytes'] or digest(model) != profile['modelSHA256']:
        raise ValueError('Artifact size/SHA mismatch')
    if shutil.disk_usage(HERE).free < 1.5 * 1024**3:
        raise ValueError('Insufficient operational disk reserve')
    binary = HERE / '.build/release/QwenCLI'
    (HERE / 'results').mkdir(exist_ok=True)
    run_dir = Path(tempfile.mkdtemp(prefix='broader-', dir=HERE / 'results'))
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
            result = subprocess.run([str(binary), str(model), str(suite_path), '--tokens-suite'],
                                    stdout=out, stderr=err, timeout=120)
            if result.returncode != 0:
                raise ValueError(f'Native admission failed: {result.returncode}')
            native_records = json.loads((run_dir / 'native-tokens.json').read_text())
            native = {item['id']: item for item in native_records}
            expected_ids = {case['id'] for case in suite['cases']}
            if len(native_records) != 30 or set(native) != expected_ids:
                raise ValueError('Incomplete/duplicate token preflight cases')
            tokenizer = Tokenizer.from_file(str(HERE / 'artifacts/tokenizer.json'))
            for case in suite['cases']:
                expected_prompt = ('<|im_start|>system\n' + suite['text_system'] + '<|im_end|>\n<|im_start|>user\n' +
                                   case['prompt'] + '<|im_end|>\n<|im_start|>assistant\n')
                item = native[case['id']]
                if item['prompt'] != expected_prompt or item['tokenIDs'] != tokenizer.encode(expected_prompt, add_special_tokens=False).ids:
                    raise ValueError(f'Publisher token parity mismatch: {case["id"]}')
            manifest['preflight'] = '30/30 native/publisher prompt and token-ID matches'
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
        entry = {'id': case_id, 'category': case['category']}
        started = time.monotonic()
        with report_path.open('wb') as out, (run_dir / (case_id + '.stderr')).open('wb') as err:
            try:
                result = subprocess.run([str(binary), str(model), str(prompt)], stdout=out, stderr=err, timeout=120)
                entry['exit_code'] = result.returncode
            except subprocess.TimeoutExpired:
                entry['timeout'] = True
            except OSError as error:
                entry['launch_error'] = str(error)
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
    if any(item.get('exit_code') != 0 or item.get('validation_error') or item.get('outcome') != 'completed' for item in manifest['cases']):
        raise SystemExit(1)

if __name__ == '__main__':
    main()
