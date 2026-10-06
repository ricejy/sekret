"""Frozen one-variable controls, not a replacement for the failed quality screen."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
CASES = {'equal-shares': '7', 'member-exception': '0', 'embedded-location': 'North Gate', 'missing-phone': 'Not given.'}
CONTROLS = [
    ('metal', 'baseline', 'legacy'),
    ('metal', 'no-penalty', 'legacy'),
    ('metal', 'greedy', 'legacy'),
    ('cpu', 'baseline', 'legacy'),
    ('metal', 'baseline', 'ext'),
]

def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def main():
    suite_path = HERE.parent / 'model_comparison/broader-text-v1.json'
    suite = json.loads(suite_path.read_text())
    prompts = {case['id']: case['prompt'] for case in suite['cases']}
    binary = HERE / '.build/diagnostic/control'
    directory = Path(tempfile.mkdtemp(prefix='diagnostic-matrix-', dir=HERE / 'results'))
    manifest = {'suite_sha256': digest(suite_path), 'binary_sha256': digest(binary),
        'controls': CONTROLS, 'expected': CASES, 'qualification': 'diagnostic-not-quality-validation', 'runs': []}
    (directory / 'plan.json').write_text(json.dumps(manifest, indent=2))
    print(directory, flush=True)
    for case_id, expected in CASES.items():
        prompt = directory / f'{case_id}.txt'
        prompt.write_text(prompts[case_id])
        for backend, sampling, api in CONTROLS:
            name = f'{case_id}-{backend}-{sampling}-{api}'
            report = directory / f'{name}.json'
            entry = {'id': case_id, 'backend': backend, 'sampling': sampling, 'api': api, 'report': report.name}
            with report.open('wb') as out, (directory / f'{name}.stderr').open('wb') as err:
                try:
                    process = subprocess.run([str(binary), str(HERE / 'artifacts/LFM2.5-1.2B-Instruct-Q4_K_M.gguf'),
                        str(prompt), backend, sampling, api], stdout=out, stderr=err, timeout=120)
                    entry['exit_code'] = process.returncode
                except subprocess.TimeoutExpired:
                    entry['timeout'] = True
            try:
                result = json.loads(report.read_text())
                entry.update(response=result['response'], outcome=result['outcome'],
                    exact_answer_pass=result['outcome'] == 'completed' and result['response'].strip() == expected,
                    prompt_sha256=result['prompt_sha256'], token_ids_sha256=result['token_ids_sha256'])
            except (ValueError, KeyError):
                entry['invalid_report'] = True
            entry['report_sha256'] = digest(report)
            manifest['runs'].append(entry)
            (directory / 'manifest.json').write_text(json.dumps(manifest, indent=2))
            print(name, entry.get('response', 'ERROR'), flush=True)
    if any(run.get('exit_code') != 0 or run.get('invalid_report') for run in manifest['runs']):
        raise SystemExit(2)
    if not all(run['exact_answer_pass'] for run in manifest['runs']):
        raise SystemExit(1)

if __name__ == '__main__':
    main()
