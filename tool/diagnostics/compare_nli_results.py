"""Compare immutable first results, retaining repetitions; exit 1 on quality failure."""
import hashlib
import json
import sys
from pathlib import Path

left, right = [json.loads(Path(p).read_text()) for p in sys.argv[1:]]
fixture = Path('eval/guardrails/fixed_verifier_development_v1.json').read_bytes()
cases = {c['id']: c for c in json.loads(fixture)['cases']}
for report in [left, right]:
    assert report['complete'] and report['fictional']
    assert report['fixtureSha256'] == hashlib.sha256(fixture).hexdigest()
    expected_keys = {(case_id, repeat) for case_id in cases for repeat in [1, 2, 3]}
    assert len(report['results']) == len(expected_keys)
    assert {(r['caseID'], r['repeat']) for r in report['results']} == expected_keys
    for r in report['results']:
        c = cases[r['caseID']]
        assert r['premise'] == '\n\n'.join(p['text'] for p in c['evidence'])
        assert r['hypothesis'] == c['draft'] and r['expected'] == c['expectedVerdict']

right_rows = {(r['caseID'], r['repeat']): r for r in right['results']}
differences = []
for row in left['results']:
    other = right_rows[(row['caseID'], row['repeat'])]
    assert row['tokenIDsSha256'] == other['tokenIDsSha256']
    if row['output'] != other['output']:
        differences.append(dict(caseID=row['caseID'], repeat=row['repeat'],
                                fp32=row['output'], int8=other['output']))

def grades(report):
    rows = report['results']
    false_approvals = [r for r in rows if r['expected'] != 'SUPPORTED' and r['output'] == 'SUPPORTED']
    false_rejections = [r for r in rows if r['expected'] == 'SUPPORTED' and not r['failure'] and r['output'] != 'SUPPORTED']
    errors = [r for r in rows if r['failure']]
    return dict(falseApprovals=len(false_approvals), falseRejections=len(false_rejections),
                falseApprovalCaseIDs=sorted({r['caseID'] for r in false_approvals}),
                falseRejectionCaseIDs=sorted({r['caseID'] for r in false_rejections}),
                errors=len(errors), developmentTargetMet=not false_approvals and not errors and len(false_rejections) <= 4)

summary = dict(purpose='fixed-verifier-development-not-acceptance', fictional=True,
               fixtureSha256=hashlib.sha256(fixture).hexdigest(),
               fp32=grades(left), int8=grades(right), labelDifferences=differences,
               binaryAdmissionDifferences=sum((d['fp32'] == 'SUPPORTED') != (d['int8'] == 'SUPPORTED') for d in differences))
print(json.dumps(summary, indent=2))
sys.exit(0 if summary['fp32']['developmentTargetMet'] and summary['int8']['developmentTargetMet'] else 1)
