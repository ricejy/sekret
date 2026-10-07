"""Independent publisher-tokenizer comparison; no inference or network calls."""
import hashlib
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
REFERENCE = HERE / 'artifacts/diagnostic-reference'
sys.path.insert(0, str(REFERENCE / 'python'))
from tokenizers import Tokenizer, __version__

def sha(value):
    return hashlib.sha256(value).hexdigest()

def main():
    if len(sys.argv) != 2:
        raise SystemExit('usage: check_tokenizer_parity.py EXISTING_RAW_RUN_DIRECTORY')
    directory = Path(sys.argv[1])
    manifest = json.loads((directory / 'manifest.json').read_text())
    suite = json.loads((directory / 'suite.json').read_text())
    prompts = {case['id']: case['prompt'] for case in suite['cases']}
    tokenizer = Tokenizer.from_file(str(REFERENCE / 'tokenizer.json'))
    cases = []
    for case in manifest['cases']:
        name = case['id']
        native = json.loads((directory / f'{name}.json').read_text())['runs'][0]
        prompt = ('<|startoftext|><|im_start|>system\n' + suite['text_system'] +
                  '<|im_end|>\n<|im_start|>user\n' + prompts[name] +
                  '<|im_end|>\n<|im_start|>assistant\n')
        tokens = tokenizer.encode(prompt, add_special_tokens=False).ids
        token_hash = sha(','.join(map(str, tokens)).encode())
        cases.append({'id': name, 'prompt_matches': sha(prompt.encode()) == native['promptSHA256'],
                      'token_ids_match': token_hash == native['tokenIDsSHA256'],
                      'token_count_matches': len(tokens) == native['promptTokens'],
                      'token_sha256': token_hash, 'token_count': len(tokens)})
    result = {'tokenizers_version': __version__,
              'source_revision': '0f604ada3f766f9f257460c4c9f0b5d6f69d431b',
              'reference_sha256': {name: sha((REFERENCE / name).read_bytes()) for name in
                                  ['tokenizer.json', 'tokenizer_config.json', 'chat_template.jinja', 'simple.cpp']},
              'bos_id': tokenizer.token_to_id('<|startoftext|>'),
              'eos_id': tokenizer.token_to_id('<|im_end|>'), 'cases': cases}
    print(json.dumps(result, indent=2))
    if not all(case['prompt_matches'] and case['token_ids_match'] and case['token_count_matches'] for case in cases):
        raise SystemExit(1)

if __name__ == '__main__':
    main()
