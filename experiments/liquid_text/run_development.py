"""Run a frozen fictional text suite; no downloads or builds or automatic grading."""
import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import time
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
SUITE = ROOT / 'experiments/model_comparison/development-v1.json'
MODEL = HERE / 'artifacts/LFM2.5-1.2B-Instruct-Q4_K_M.gguf'
EXPECTED = 'b1b3de114215d9507409a662a501a631095a479a419584e8a2ded6304b19b4f5'

def digest(path):
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', type=pathlib.Path, default=SUITE)
    args = parser.parse_args()
    suite_path = args.suite.resolve()
    suite_bytes = suite_path.read_bytes()
    suite = json.loads(suite_bytes)
    if suite['context'] != 2048 or suite['output_cap'] != 128:
        raise ValueError('Suite settings differ from the compiled adapter')
    if suite['text_system'] != "You are a concise on-device assistant. Answer the user's request directly. This is an evaluation using fictional data.":
        raise ValueError('Suite system instruction differs from the adapter')
    cases = [case for case in suite['cases'] if case['modality'] == 'text']
    names = [case['id'] for case in cases]
    if not cases or len(set(names)) != len(names):
        raise ValueError('Expected nonempty suite with unique text case IDs')
    if any(not name or any(c not in 'abcdefghijklmnopqrstuvwxyz0123456789-' for c in name) for name in names):
        raise ValueError('Unsafe case ID')
    if MODEL.stat().st_size != 730895168 or digest(MODEL) != EXPECTED:
        raise ValueError('Candidate artifact size/SHA mismatch')
    if shutil.disk_usage(HERE).free <= 1.5 * 1024 ** 3:
        raise ValueError('Required 1.5 GiB disk reserve unavailable')
    binary = HERE / '.build/release/LiquidCLI'
    (HERE / 'results').mkdir(exist_ok=True)
    output = pathlib.Path(tempfile.mkdtemp(prefix='development-', dir=HERE / 'results'))
    (output / 'suite.json').write_bytes(suite_bytes)
    manifest = {'suite_sha256': hashlib.sha256(suite_bytes).hexdigest(), 'binary_sha256': digest(binary),
                'model_sha256': EXPECTED, 'qualification': suite['qualification'], 'cases': []}
    print(output, flush=True)
    for case in cases:
        name = case['id']
        prompt = output / (name + '.prompt.txt')
        prompt.write_text(case['prompt'])
        started = time.monotonic()
        with (output / (name + '.json')).open('wb') as stdout, (output / (name + '.stderr.log')).open('wb') as stderr:
            try:
                result = subprocess.run([str(binary), str(MODEL), str(prompt)], stdout=stdout, stderr=stderr, timeout=120)
                status = result.returncode
            except subprocess.TimeoutExpired:
                status = 'timeout'
            except OSError as error:
                status = 'launch-error: ' + str(error)
        report_path = output / (name + '.json')
        try:
            report = json.loads(report_path.read_text())
            valid_report = len(report['runs']) == 1 and isinstance(report['runs'][0]['response'], str)
            outcome = report['runs'][0]['outcome']
        except (OSError, ValueError, KeyError, TypeError, IndexError):
            valid_report = False
            outcome = None
        manifest['cases'].append({'id': name, 'status': status, 'process_seconds': time.monotonic() - started,
                                  'valid_report': valid_report, 'outcome': outcome,
                                  'report_sha256': digest(report_path),
                                  'prompt_sha256': digest(prompt), 'required': case['required'], 'forbidden': case['forbidden']})
        (output / 'manifest.json').write_text(json.dumps(manifest, indent=2))
        print(name, status, flush=True)
    print(output, flush=True)
    if any(case['status'] != 0 or not case['valid_report'] or case['outcome'] != 'completed' for case in manifest['cases']):
        raise SystemExit(1)

if __name__ == '__main__':
    main()
