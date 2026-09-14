#!/usr/bin/env python3
"""Check locale bundle parity and format placeholders."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
manifest = ROOT / "Resources/Localization/locale-manifest.json"
import json
locales = json.loads(manifest.read_text(encoding="utf-8"))["locales"]

ENTRY = re.compile(r'^\s*"((?:\\.|[^"\\])+)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;', re.MULTILINE)

def entries(path):
    return {key: value for key, value in ENTRY.findall(path.read_text(encoding="utf-8"))}

source = entries(ROOT / "Resources/en.lproj/Localizable.strings")
errors = []
localized_keys = set(source)
source_key_pattern = re.compile(r'(?:copy|AppLanguage\.text)\("([^"]+)"')
for swift_file in (ROOT / "Sources").rglob("*.swift"):
    for key in source_key_pattern.findall(swift_file.read_text(encoding="utf-8")):
        if "\\(" not in key and key not in localized_keys:
            errors.append(f"source uses missing localization key: {key} ({swift_file.relative_to(ROOT)})")

for locale in locales:
    path = ROOT / f"Resources/{locale}.lproj/Localizable.strings"
    if not path.exists():
        errors.append(f"missing bundle: {locale}")
        continue
    found = entries(path)
    if set(found) != set(source):
        errors.append(f"{locale}: missing={sorted(set(source)-set(found))} extra={sorted(set(found)-set(source))}")
    for key in set(source) & set(found):
        source_placeholders = re.findall(r'%(?:\d+\$)?[@dDuUxXfFeEgGcCsSpaAF]', source[key])
        found_placeholders = re.findall(r'%(?:\d+\$)?[@dDuUxXfFeEgGcCsSpaAF]', found[key])
        if source_placeholders != found_placeholders:
            errors.append(f"{locale}:{key}: placeholders {found_placeholders} != {source_placeholders}")
    if locale in {"zh-CN", "zh-TW"}:
        untranslated = sorted(key for key in source if found.get(key) == source[key])
        if untranslated:
            errors.append(f"{locale}: untranslated English values={untranslated}")
    if locale not in {"zh-CN", "zh-TW", "ja"}:
        contaminated = sorted(key for key, value in found.items() if re.search(r'[\u4e00-\u9fff]', value))
        if contaminated:
            errors.append(f"{locale}: unexpected Han characters in values={contaminated}")

if errors:
    print("Localization check failed:")
    print("\n".join(errors))
    sys.exit(1)
print(f"Localization check passed for {len(locales)} locales and {len(source)} keys with matching placeholders.")
