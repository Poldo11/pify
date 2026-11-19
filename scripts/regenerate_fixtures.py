#!/usr/bin/env python3
"""Rebuild test/fixtures.gleam from test/fixtures/*.json.

Each JSON file becomes one function that returns the compact JSON text. The
fixtures are hand-written from the Admin API shapes with placeholder people:
Maria Silva, maria@example.com, CPF 000.000.000-00. Never paste a real
customer's data into test/fixtures/.
"""

import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
FIXTURES = ROOT / "test" / "fixtures"
MODULE = ROOT / "test" / "fixtures.gleam"


def gleam_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    parts = [
        "//// Test fixtures as string constants. Regenerate with\n"
        "//// `python3 scripts/regenerate_fixtures.py` after editing test/fixtures/.\n"
    ]
    for path in sorted(FIXTURES.glob("*.json")):
        compact = json.dumps(
            json.loads(path.read_text()), separators=(",", ":"), ensure_ascii=False
        )
        parts.append(f"\npub fn {path.stem}() -> String {{\n  {gleam_string(compact)}\n}}\n")
    MODULE.write_text("".join(parts))


if __name__ == "__main__":
    main()
