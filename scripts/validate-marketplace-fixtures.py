#!/usr/bin/env python3
"""Validate marketplace.schema.json and the spec/marketplace fixtures.

Fixtures named invalid-*.json must fail schema validation; every other
fixture must pass. Host-level rules (duplicate and reserved tool IDs) are
covered by Swift tests, so host-invalid-*.json fixtures are schema-valid.
"""

import glob
import json
import os
import sys

import jsonschema

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main() -> int:
    with open(os.path.join(ROOT, "marketplace.schema.json")) as fh:
        schema = json.load(fh)
    jsonschema.Draft202012Validator.check_schema(schema)
    validator = jsonschema.Draft202012Validator(schema)

    for example in schema.get("examples", []):
        errors = list(validator.iter_errors(example))
        if errors:
            print(f"FAIL schema example: {errors[0].message}")
            return 1

    failures = 0
    for path in sorted(glob.glob(os.path.join(ROOT, "spec/marketplace/*.json"))):
        name = os.path.basename(path)
        with open(path) as fh:
            document = json.load(fh)
        errors = list(validator.iter_errors(document))
        expect_invalid = name.startswith("invalid-")
        ok = bool(errors) == expect_invalid
        print(f"{'PASS' if ok else 'FAIL'} {name}")
        if not ok:
            failures += 1
            if errors:
                print(f"  unexpected error: {errors[0].message}")
            else:
                print("  expected schema validation to fail, but it passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
