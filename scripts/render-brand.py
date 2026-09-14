#!/usr/bin/env python3
"""Render the supplied Icon Composer document and generate macOS icon sizes."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]

subprocess.run([sys.executable, str(root / 'scripts/generate-icon.py')], check=True)
subprocess.run([
    'sips', '-s', 'format', 'pdf',
    str(root / 'Assets/AppIcon-Source.png'),
    '--out', str(root / 'Assets/CloudBridge-Vector.pdf'),
], check=True, stdout=subprocess.DEVNULL)
