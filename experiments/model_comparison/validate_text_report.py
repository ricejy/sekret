"""Fail closed on mismatched candidate reports; never assigns answer-quality scores."""


def validate_report(report, profile):
    """Compare a native report to an independently frozen candidate profile.

    profile must be prepared from verified candidate metadata before inference.
    A profile is not authorization to download, install, or approve a model.
    """
    for key in ('modelSHA256', 'runtimeTag', 'templateVersion', 'sampling'):
        expected = profile[key]
        if not isinstance(expected, str) or not expected:
            raise ValueError(f'Missing expected {key}')
        if report.get(key) != expected:
            raise ValueError(f'Candidate report differs from frozen {key}')
    runs = report.get('runs')
    if not isinstance(runs, list) or len(runs) != 1 or not isinstance(runs[0], dict):
        raise ValueError('Expected exactly one native result per request')
    run = runs[0]
    if run.get('configuredContext') != profile['context'] or run.get('outputCap') != profile['output_cap']:
        raise ValueError('Context/output budget differs from frozen suite profile')
    for key in ('promptTokens', 'outputTokens', 'actualContext'):
        if type(run.get(key)) is not int or run[key] < 0:
            raise ValueError(f'Invalid {key}')
    if run['actualContext'] < profile['context']:
        raise ValueError('Actual context below requested context')
    if run['promptTokens'] < 1 or run['promptTokens'] + profile['output_cap'] > min(profile['context'], run['actualContext']):
        raise ValueError('Input plus reserved output does not fit')
    if run['outputTokens'] > profile['output_cap']:
        raise ValueError('Output exceeds frozen budget')
    for key in ('promptSHA256', 'tokenIDsSHA256'):
        value = run.get(key)
        if not isinstance(value, str) or len(value) != 64 or any(c not in '0123456789abcdef' for c in value):
            raise ValueError(f'Invalid {key}')
    if not isinstance(run.get('response'), str):
        raise ValueError('Missing unedited response')
    if run.get('outcome') not in ('completed', 'output-limit', 'cancelled'):
        raise ValueError('Unknown or missing terminal outcome')
    # Incomplete outcomes are valid evidence, but must never be counted as completed.
    return {'complete': run['outcome'] == 'completed', 'quality': 'requires manual grading'}
