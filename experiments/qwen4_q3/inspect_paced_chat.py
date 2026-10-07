"""Audit captured fictional inputs, history and exact publisher token hashes.

Template rendering is an independently written, manually audited subset of the
retained publisher Jinja: string messages, system first, alternating user and
assistant, no tools. This does not claim execution of the full Jinja template.
"""
import argparse
import hashlib
import json
from pathlib import Path
import statistics
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / 'liquid_text/artifacts/diagnostic-reference/python'))
from tokenizers import Tokenizer

def sha(text):
    return hashlib.sha256(text.encode()).hexdigest()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('reports', type=Path)
    parser.add_argument('--mode', choices=['paced', 'boundary', 'long-chat'], default='paced')
    args = parser.parse_args()
    root = args.reports.resolve()
    if not root.is_relative_to((HERE / 'results').resolve()):
        raise ValueError('Only isolated evaluation results may be audited')
    tokenizer = Tokenizer.from_file(str(HERE / 'artifacts/tokenizer.json'))
    results = []
    previous_input = None
    previous_response = None
    count = 2 if args.mode == 'boundary' else 8 if args.mode == 'long-chat' else 6
    for i in range(1, count + 1):
        name = f'{args.mode}-{i}'
        report_path = root / f'{name}.json'
        if not report_path.exists():
            break
        report = json.loads(report_path.read_text())
        messages = json.loads((root / f'{name}-input.json').read_text())
        result = report['result']
        expected_roles = ['system'] + ['user' if k % 2 else 'assistant' for k in range(1, len(messages))]
        assert len(messages) % 2 == 0 and [m['role'] for m in messages] == expected_roles
        if (args.mode == 'paced' and 2 <= i <= 4) or (args.mode == 'long-chat' and i >= 2):
            assert messages[:-1] == previous_input + [{'role': 'assistant', 'content': previous_response}], 'History mismatch'
        else:
            assert len(messages) == 2
        prompt = ''.join(f"<|im_start|>{m['role']}\n{m['content']}<|im_end|>\n" for m in messages) + '<|im_start|>assistant\n'
        ids = tokenizer.encode(prompt, add_special_tokens=False).ids
        assert result['promptSHA256'] == sha(prompt), 'Prompt mismatch'
        assert result['tokenIDsSHA256'] == sha(','.join(map(str, ids))), 'Publisher token mismatch'
        assert len(ids) == result['promptTokens']
        expected_context = 4096 if args.mode == 'boundary' and i == 2 else 2048
        assert len(ids) + result['outputCap'] <= result['actualContext'] == expected_context
        if args.mode == 'boundary':
            assert len(ids) == [1884, 3938][i-1]
        assert report['modelSHA256'] == '9c6e0763577125a994a9bea0bbd7a737ac4498b8a6a4e0f788727553af1806c9'
        expected_version = ('qwen3-4b-instruct-2507-alternating-chat-no-tools-v1' if len(messages) > 2
                            else 'qwen3-4b-instruct-2507-single-turn-no-tools-no-thinking-v1')
        assert report['templateVersion'] == expected_version
        results.append({'id': name, 'promptAndTokenParity': True,
                        'responseWordsWhitespaceSplit': len(result['response'].split()), **result})
        previous_input, previous_response = messages, result['response']
    summary = {'reports': results, 'mode': args.mode, 'allExpectedCompleted': len(results) == count and all(r['outcome'] == 'completed' for r in results),
               'thermalBelowSeriousAtEveryRecordedReturn': bool(results) and all(r['thermalState'] < 2 for r in results),
               'contentReview': 'Manual review required; token parity and native completion are not quality grades',
               'templateMethod': __doc__,
               'referenceHashes': {name: hashlib.sha256((HERE / 'artifacts' / name).read_bytes()).hexdigest()
                                   for name in ['tokenizer.json', 'tokenizer_config.json']}}
    if results:
        summary['peakSampledFootprintBytes'] = max(r['peakObservedFootprintBytes'] for r in results)
        summary['medianGenerationSeconds'] = statistics.median(r['elapsedSeconds'] for r in results)
    destination = root.parent.parent / 'paced-audit.json'
    with destination.open('x') as stream:
        json.dump(summary, stream, indent=2)
    print(json.dumps(summary, indent=2))

if __name__ == '__main__':
    main()
