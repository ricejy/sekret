"""Frozen-prompt, bounded diagnostics; no changes to original evaluation evidence."""
import argparse
import json
from pathlib import Path
import shutil
import tempfile
from resume_evaluation import digest, guarded_run, validate_report

HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('stage', choices=['repro', 'controls', 'backend'])
    args = parser.parse_args()
    plan = json.loads((HERE / 'diagnostic-plan.json').read_text())
    suite_path = HERE.parent / 'model_comparison/broader-text-v1.json'
    assert digest(suite_path) == plan['suite_sha256']
    suite = json.loads(suite_path.read_text())
    cases = {x['id']: x for x in suite['cases']}
    profile = json.loads((HERE / 'profile.json').read_text())
    model = HERE / 'artifacts' / profile['modelFile']
    assert model.stat().st_size == profile['modelBytes'] and digest(model) == profile['modelSHA256']
    original_binary = HERE / '.build/release/QwenCLI'
    assert digest(original_binary) == plan['original_binary_sha256']
    binary = original_binary if args.stage == 'repro' else HERE / '.build/diagnostic/control'
    free_bytes = lambda: shutil.disk_usage(HERE).free
    if free_bytes() < 8_000_000_000:
        raise ValueError('Need 8 GB free before diagnostic')
    directory = Path(tempfile.mkdtemp(prefix='diagnostic-' + args.stage + '-', dir=HERE / 'results'))
    manifest = {'stage': args.stage, 'plan': plan, 'plan_sha256': digest(HERE / 'diagnostic-plan.json'),
                'binary_sha256': digest(binary), 'model_sha256': digest(model), 'cases': [],
                'qualification': 'Diagnostic only; original 26/30 unchanged'}
    if args.stage == 'backend':
        manifest['addendum'] = json.loads((HERE / 'diagnostic-backend-plan.json').read_text())
        manifest['addendum_sha256'] = digest(HERE / 'diagnostic-backend-plan.json')
    def save():
        (directory / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    save()
    print(directory, flush=True)
    jobs = [('packs-and-singles', 'original-' + str(i)) for i in range(2)] if args.stage == 'repro' else [
        (cid, mode) for cid in plan['cases'] for mode in ['baseline', 'greedy']]
    if args.stage == 'backend':
        jobs = [('packs-and-singles', mode) for mode in ['cpu-greedy', 'metal-greedy-ext']]
    all_passed = True
    for cid, mode in jobs:
        prompt = directory / (cid + '.prompt.txt')
        prompt.write_text(cases[cid]['prompt'])
        output = directory / (cid + '-' + mode + '.json')
        stderr = directory / (cid + '-' + mode + '.stderr')
        command = [str(binary), str(model), str(prompt)]
        backend, sampling, api = 'metal', mode, 'legacy'
        if args.stage == 'backend':
            backend, sampling, api = ('cpu', 'greedy', 'legacy') if mode == 'cpu-greedy' else ('metal', 'greedy', 'ext')
        if args.stage != 'repro':
            command.extend([backend, sampling, api])
        with output.open('xb') as out, stderr.open('xb') as err:
            entry = {'id': cid, 'mode': mode, **guarded_run(command, out, err, free_bytes=free_bytes)}
        entry['report_sha256'] = digest(output)
        manifest['cases'].append(entry)
        save()
        if entry.get('exit_code') != 0 or entry.get('stop_reason'):
            raise SystemExit('Native diagnostic stopped; inspect preserved evidence')
        report = json.loads(output.read_text())
        baseline = json.loads((HERE / 'results/broader-o6ogzahr' / (cid + '.json')).read_text())['runs'][0]
        if args.stage == 'repro':
            assert validate_report(report, profile)['complete']
            run = report['runs'][0]
            assert run['promptSHA256'] == baseline['promptSHA256']
            assert run['tokenIDsSHA256'] == baseline['tokenIDsSHA256']
            response = run['response']
            entry['answer_pass'] = response.strip() == '26'
            all_passed = all_passed and entry['answer_pass']
            print(('PASS' if entry['answer_pass'] else 'FAIL') + ': expected 26; got ' + repr(response), flush=True)
        else:
            assert report['prompt_sha256'] == baseline['promptSHA256']
            assert report['token_ids_sha256'] == baseline['tokenIDsSHA256']
            assert report['sampling'] == sampling and report['backend'] == backend
            assert report['decode_api'] == api
            assert report['outcome'] == 'completed'
            entry['response'] = report['response']
            entry['matches_original_response'] = report['response'] == baseline['response']
            print(cid, mode, repr(report['response']), flush=True)
        if backend == 'metal':
            assert 'offloaded 37/37 layers to GPU' in stderr.read_text()
        else:
            assert 'offloaded 0/37 layers to GPU' in stderr.read_text()
        save()
    manifest['status'] = 'finished'
    save()
    if args.stage == 'repro' and not all_passed:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
