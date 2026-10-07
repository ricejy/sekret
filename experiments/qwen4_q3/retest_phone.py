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
    parser.add_argument('--probe', choices=sorted(EXPECTED))
    parser.add_argument('--count', type=int, choices=range(1, 21))
    parser.add_argument('--mixed-contexts', action='store_true')
    parser.add_argument('--paced-chat', action='store_true')
    parser.add_argument('--context-boundary', action='store_true')
    parser.add_argument('--long-chat', action='store_true')
    parser.add_argument('--power-profile', action='store_true')
    parser.add_argument('--power-matched', choices=['baseline-first', 'workload-first'])
    args = parser.parse_args()
    if args.power_profile and not args.long_chat: parser.error('--power-profile requires --long-chat')
    if args.power_matched and not args.power_profile: parser.error('--power-matched requires --power-profile')
    expected = {args.probe} if args.probe else EXPECTED
    conversation_suite = args.paced_chat or args.context_boundary or args.long_chat
    if conversation_suite:
        if sum([args.paced_chat, args.context_boundary, args.long_chat]) != 1 or args.probe or args.count or args.mixed_contexts:
            parser.error('Choose one conversation suite without other replay selectors')
        prefix, count = ('boundary', 2) if args.context_boundary else ('long-chat', 8) if args.long_chat else ('paced', 6)
        expected = {f'{prefix}-{i}' for i in range(1, count + 1)}
    if args.count:
        if args.probe: parser.error('--count and --probe are mutually exclusive')
        expected = {f'memory-replay-{i}' for i in range(1, args.count + 1)}
    root = Path(tempfile.mkdtemp(prefix='repeated-phone-', dir=ROOT / 'results'))
    def inventory(subdirectory):
        destination = root / 'inventory.json'
        device('info', 'files', '--device', args.device, '--subdirectory', subdirectory,
               '--no-recurse', '--domain-type', 'appDataContainer', '--domain-identifier', BUNDLE,
               '--json-output', str(destination), '--quiet')
        return {item['name'] for item in json.loads(destination.read_text())['result']['files']}
    remote = 'Documents/Qwen4Q3Reports'
    prior = inventory(remote)
    device('process', 'launch', '--device', args.device, '--terminate-existing', BUNDLE,
           '--context-boundary' if args.context_boundary else '--long-chat' if args.long_chat else '--paced-chat' if args.paced_chat else '--evaluation-suite', *([f'--probe={args.probe}'] if args.probe else []),
           *([f'--memory-replay-count={args.count}'] if args.count else []),
           *(['--power-profile'] if args.power_profile else []),
           *([f'--power-matched={args.power_matched}'] if args.power_matched else []),
           *(['--mixed-contexts'] if args.mixed_contexts else []))
    deadline = time.monotonic() + (1080 if args.power_matched else 960 if args.power_profile else 720 if args.long_chat else 480 if conversation_suite else 240)
    last_count = -1
    while time.monotonic() < deadline:
        # Matched battery pairs use the same quiet polling cadence in both phases.
        time.sleep(15 if args.power_matched else 2)
        fresh = sorted(inventory(remote) - prior)
        if len(fresh) > 1:
            raise RuntimeError('Ambiguous new report directories; refusing to merge runs.')
        if not fresh:
            continue
        names = inventory(remote + '/' + fresh[0])
        if args.power_profile and last_count == -1:
            print(f'Power capture gate: {remote}/{fresh[0]}/capture-ready.json. '
                  'Attach Instruments first; release with matching runID and captureReady=true only after recording is confirmed.', flush=True)
        recorded = sum(name + '.json' in names for name in expected)
        if recorded != last_count:
            print(f'Recorded {recorded}/{len(expected)} terminal probe reports.', flush=True)
            last_count = recorded
        if not {'suite-complete.json', 'suite-failed.json'} & names:
            continue
        run = root / 'reports' / fresh[0]
        device('copy', 'from', '--device', args.device, '--source', remote + '/' + fresh[0],
               '--destination', str(run), '--domain-type', 'appDataContainer', '--domain-identifier', BUNDLE)
        reports = {p.stem: json.loads(p.read_text()) for p in run.glob('*.json')
                   if p.stem in expected}
        valid = not (run / 'suite-failed.json').exists() and set(reports) == expected and all(
            r['result']['outcome'] == ('cancelled' if name == 'phone-cancel-8' else 'completed')
            and (name != 'phone-cancel-8' or r['result']['outputTokens'] == 8)
            for name, r in reports.items())
        failure = json.loads((run / 'suite-failed.json').read_text()) if (run / 'suite-failed.json').exists() else None
        summary = {'pass': valid, 'reports': sorted(reports), 'failure': failure,
                   'evidence': str(run), 'criterion': f'All {len(expected)} fixed probes reach expected outcomes in one process.'}
        (root / 'verdict.json').write_text(json.dumps(summary, indent=2) + '\n')
        print(json.dumps(summary, indent=2), flush=True)
        return 0 if valid else 1
    raise RuntimeError(f'No terminal result within deadline. Evidence: {root}')

if __name__ == '__main__':
    raise SystemExit(replay())
