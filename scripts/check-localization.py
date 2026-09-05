#!/usr/bin/env python3
"""Check locale bundle parity and format placeholders."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
manifest = ROOT / "Resources/Localization/locale-manifest.json"
import json
locales = json.loads(manifest.read_text(encoding="utf-8"))["locales"]

def keys(path):
    return set(re.findall(r'^\s*"((?:\\.|[^"\\])+)"\s*=', path.read_text(encoding="utf-8"), re.MULTILINE))

source = keys(ROOT / "Resources/en.lproj/Localizable.strings")
errors = []
for locale in locales:
    path = ROOT / f"Resources/{locale}.lproj/Localizable.strings"
    if not path.exists():
        errors.append(f"missing bundle: {locale}")
        continue
    found = keys(path)
    if found != source:
        errors.append(f"{locale}: missing={sorted(source-found)} extra={sorted(found-source)}")

if errors:
    print("Localization check failed:")
    print("\n".join(errors))
    sys.exit(1)
print(f"Localization check passed for {len(locales)} locales and {len(source)} keys.")
