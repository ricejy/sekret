#!/usr/bin/env python3
"""Debug-only physical-device replay. Copies only this harness's fictional reports."""
import json
import argparse
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent
BUNDLE = 'com.ricejy.sekret.localeval'
EXPECTED = {'phone-2k-1', 'phone-2k-2', 'phone-4k-1', 'phone-4k-2',
            'phone-fictional-facts', 'phone-unicode', 'phone-cancel-8'}

def device(*args):
    result = subprocess.run(['xcrun', 'devicectl', 'device', *args],
                            capture_output=True, text=True, timeout=45)
    if result.returncode:
        raise RuntimeError(result.stderr or result.stdout)

def replay():
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', required=True,
                        help='CoreDevice identifier for the explicitly selected test phone')
    parser.add_argument('--count', type=int, choices=range(1, 21))
    args = parser.parse_args()
    expected = {f'memory-replay-{i}' for i in range(1, args.count + 1)} if args.count else EXPECTED
    root = Path(tempfile.mkdtemp(prefix='repeated-phone-', dir=ROOT / 'results'))
    def inventory(subdirectory):
        destination = root / 'inventory.json'
        device('info', 'files', '--device', args.device, '--subdirectory', subdirectory,
               '--no-recurse', '--domain-type', 'appDataContainer', '--domain-identifier', BUNDLE,
               '--json-output', str(destination), '--quiet')
        return {item['name'] for item in json.loads(destination.read_text())['result']['files']}
    remote = 'Documents/Qwen06Q4Reports'
    prior = inventory(remote)
    device('process', 'launch', '--device', args.device, '--terminate-existing', BUNDLE,
           '--evaluation-suite', *([f'--memory-replay-count={args.count}'] if args.count else []))
    deadline = time.monotonic() + 60
    while time.monotonic() < deadline:
        time.sleep(2)
        fresh = sorted(inventory(remote) - prior)
        if len(fresh) > 1:
            raise RuntimeError('Ambiguous new report directories; refusing to merge runs.')
        if not fresh:
            continue
        names = inventory(remote + '/' + fresh[0])
        if not {'suite-complete.json', 'suite-failed.json'} & names:
            continue
        run = root / 'reports' / fresh[0]
        device('copy', 'from', '--device', args.device, '--source', remote + '/' + fresh[0],
               '--destination', str(run), '--domain-type', 'appDataContainer', '--domain-identifier', BUNDLE)
        reports = {p.stem: json.loads(p.read_text()) for p in run.glob('*.json')
                   if p.stem in expected}
        valid = set(reports) == expected and all(
            r['result']['outcome'] == ('cancelled' if name == 'phone-cancel-8' else 'completed')
            and (name != 'phone-cancel-8' or r['result']['outputTokens'] == 8)
            for name, r in reports.items())
        failure = json.loads((run / 'suite-failed.json').read_text()) if (run / 'suite-failed.json').exists() else None
        summary = {'pass': valid, 'reports': sorted(reports), 'failure': failure,
                   'evidence': str(run), 'criterion': f'All {len(expected)} fixed probes reach expected outcomes in one process.'}
        (root / 'verdict.json').write_text(json.dumps(summary, indent=2) + '\n')
        print(json.dumps(summary, indent=2), flush=True)
        return 0 if valid else 1
    raise RuntimeError(f'No terminal result within 60 seconds. Evidence: {root}')

if __name__ == '__main__':
    raise SystemExit(replay())
