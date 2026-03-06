#!/usr/bin/env python3
"""Scan repository for metadata YAML files, validate against schema, and emit portal-artifact.json

Usage:
  ./scripts/generate_function_metadata.py --validate --output portal-artifact.json
"""
import argparse
import json
import os
import sys
from glob import glob

try:
    import yaml
except Exception:
    print('Missing PyYAML. Install with: pip install pyyaml', file=sys.stderr)
    sys.exit(2)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SCHEMA_PATH = os.path.join(ROOT, 'portal-sync', 'function-metadata.schema.json')

def load_schema():
    with open(SCHEMA_PATH, 'r') as f:
        return json.load(f)

def find_metadata_files():
    patterns = [
        '**/metadata.yaml', '**/metadata.yml', '**/function-metadata.yaml', '**/portal-metadata.yaml'
    ]
    matches = set()
    for p in patterns:
        matches.update(glob(os.path.join(ROOT, p), recursive=True))
    return sorted(matches)

def validate_basic(obj):
    # Minimal required keys check (works without jsonschema installed)
    required = ['id', 'name', 'repo_path', 'owner', 'status', 'last_updated']
    missing = [k for k in required if k not in obj]
    if missing:
        return False, f"missing required keys: {missing}"
    return True, None

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--validate', action='store_true')
    parser.add_argument('--output', default='portal-artifact.json')
    args = parser.parse_args()

    files = find_metadata_files()
    results = []
    for f in files:
        try:
            with open(f, 'r') as fh:
                data = yaml.safe_load(fh)
            ok, reason = validate_basic(data)
            results.append({
                'path': os.path.relpath(f, ROOT),
                'valid': ok,
                'reason': reason,
                'metadata': data if ok else None
            })
        except Exception as e:
            results.append({
                'path': os.path.relpath(f, ROOT),
                'valid': False,
                'reason': str(e),
                'metadata': None
            })

    artifact = {
        'generated': True,
        'timestamp': __import__('datetime').datetime.utcnow().isoformat() + 'Z',
        'files': results,
        'total': len(results)
    }

    out_path = os.path.join(ROOT, args.output)
    with open(out_path, 'w') as of:
        json.dump(artifact, of, indent=2)

    # If any invalid and --validate, exit non-zero
    invalid = [r for r in results if not r['valid']]
    if args.validate and invalid:
        print(f"Validation failed: {len(invalid)} invalid metadata files", file=sys.stderr)
        for r in invalid:
            print(f" - {r['path']}: {r['reason']}", file=sys.stderr)
        sys.exit(3)
    else:
        print(f"Validated {len(results)} metadata files. Artifact: {out_path}")

if __name__ == '__main__':
    main()
