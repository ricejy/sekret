"""Small offline red-capable loop; original executable/profile, no grading model."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--minimal', action='store_true')
    args = parser.parse_args()
    suite = json.loads((HERE.parent / 'model_comparison/broader-text-v1.json').read_text())
    original = next(case['prompt'] for case in suite['cases'] if case['id'] == 'equal-shares')
    prompt = 'What is 42 divided by 6? Reply with the number only.' if args.minimal else original
    directory = Path(tempfile.mkdtemp(prefix='diagnostic-repro-', dir=HERE / 'results'))
    prompt_path = directory / 'prompt.txt'
    prompt_path.write_text(prompt)
    passed = True
    for index in range(2):
        output = directory / f'run-{index}.json'
        with output.open('wb') as stdout, (directory / f'run-{index}.stderr').open('wb') as stderr:
            result = subprocess.run([str(HERE / '.build/release/LiquidCLI'),
                str(HERE / 'artifacts/LFM2.5-1.2B-Instruct-Q4_K_M.gguf'), str(prompt_path)],
                stdout=stdout, stderr=stderr, timeout=120)
        report = json.loads(output.read_text())
        run = report['runs'][0]
        ok = result.returncode == 0 and run['outcome'] == 'completed' and run['response'].strip() == '7'
        passed = passed and ok
        print(f'{"PASS" if ok else "FAIL"}: expected 7; got {run["response"]!r}', flush=True)
    print(directory, flush=True)
    raise SystemExit(0 if passed else 1)

if __name__ == '__main__':
    main()
