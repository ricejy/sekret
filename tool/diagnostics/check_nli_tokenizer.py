"""Offline parity check against the publisher's SentencePiece tokenizer path."""
import hashlib
import json
import sys
from pathlib import Path

from tokenizers import Tokenizer
from transformers import DebertaV2Tokenizer

assets = Path(sys.argv[1])
fixture = Path('eval/guardrails/fixed_verifier_development_v1.json').read_bytes()
suite = json.loads(fixture)
fast = Tokenizer.from_file(str(assets / 'tokenizer.json'))
fast.no_truncation()
fast.no_padding()
slow = DebertaV2Tokenizer.from_pretrained(str(assets), local_files_only=True)
results = []
for case in suite['cases']:
    premise = '\n\n'.join(p['text'] for p in case['evidence'])
    hypothesis = case['draft']
    encoded = fast.encode(premise, hypothesis)
    reference = slow(premise, hypothesis, truncation=False, padding=False)
    match = encoded.ids == reference['input_ids'] and encoded.attention_mask == reference['attention_mask']
    results.append(dict(caseID=case['id'], match=match, tokens=len(encoded.ids)))
report = dict(fixtureSha256=hashlib.sha256(fixture).hexdigest(), fictional=True,
              purpose='fixed-verifier-development-tokenizer-parity',
              method='Publisher tokenizer.json versus local DebertaV2Tokenizer/SentencePiece; no iOS tokenizer tested.',
              allMatch=all(r['match'] for r in results), results=results)
print(json.dumps(report, indent=2))
sys.exit(0 if report['allMatch'] else 1)
