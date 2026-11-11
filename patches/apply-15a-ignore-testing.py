#!/usr/bin/env python3
"""Keep test runtime files outside Git without changing other ignore rules."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
path = root / '.gitignore'
rule = '/storage/framework/testing/'
text = path.read_text() if path.exists() else ''
if rule not in text.splitlines():
    path.write_text(text.rstrip('\n') + '\n\n# Temporary files created by Laravel tests\n' + rule + '\n')
print('Служебные файлы Laravel-тестов исключены из Git. Сами файлы сохранены.')
