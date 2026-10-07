"""Bounded offline diagnostic; all prompts fictional, fresh process per probe.

Default exits nonzero when the original refusal symptom is reproduced.
The flag is a narrow diagnostic, never an automatic answer-quality grade.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import sys
import tempfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'qwen4_text'))
from resume_evaluation import guarded_run

PROMPTS = {
    'original': 'Write a long fictional story about a robot organizing imaginary seeds, continuing until the output limit. This is a Stop-button test, not a quality benchmark.',
    'no-test-language': 'Write a long fictional story about a robot organizing imaginary seeds, continuing until the output limit.',
    'no-limit-language': 'Write a long fictional story about a robot organizing imaginary seeds. This is a Stop-button test, not a quality benchmark.',
    'plain-long': 'Write a long fictional story about a robot organizing imaginary seeds.',
    'bounded-story': 'Write a 180-word fictional story about a robot organizing imaginary seeds. Give it a beginning, a small problem, and a happy ending.',
    'everyday-draft': 'Write a friendly email of about 120 words inviting fictional neighbors to a seed exchange on Saturday at 10 am in Cedar Hall. Ask them to label their seed packets. Do not invent a registration link or fee.',
}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--case', choices=PROMPTS, default='original')
    parser.add_argument('--repeat', type=int, choices=[1, 2], default=1)
    args = parser.parse_args()
    root = Path(tempfile.mkdtemp(prefix='refusal-', dir=HERE / 'results'))
    binary = HERE / '.build/release/QwenCLI'
    model = HERE / 'artifacts/Qwen3-4B-Instruct-2507-Q3_K_M.gguf'
    prompt = root / 'prompt.txt'
    prompt.write_text(PROMPTS[args.case])
    summary = {'case': args.case, 'prompt': PROMPTS[args.case],
               'binarySHA256': hashlib.sha256(binary.read_bytes()).hexdigest(),
               'scope': 'Mac diagnostic, not phone qualification or general accuracy', 'runs': []}
    print(root, flush=True)
    for i in range(args.repeat):
        report = root / f'run-{i+1}.json'
        with report.open('xb') as out, (root / f'run-{i+1}.stderr').open('xb') as err:
            process = guarded_run([str(binary), str(model), str(prompt), '--output-512'],
                out, err, free_bytes=lambda: shutil.disk_usage(HERE).free, timeout=90)
        if process.get('stop_reason') or process['exit_code'] != 0:
            raise RuntimeError(process)
        result = json.loads(report.read_text())['runs'][0]
        refusal = bool(re.search(r"\b(?:can't|cannot|unable to)\b|exceeds the output limit", result['response'], re.I))
        entry = dict(process, result=result, refusalSymptom=refusal)
        summary['runs'].append(entry)
        (root / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        print(json.dumps(entry), flush=True)
        if result['thermalState'] >= 2:
            raise RuntimeError('Stopping additional Mac probes: serious/critical thermal state')
    return int(any(x['refusalSymptom'] for x in summary['runs']))

if __name__ == '__main__':
    raise SystemExit(main())
