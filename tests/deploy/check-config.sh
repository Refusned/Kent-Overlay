#!/usr/bin/env bash
# Verify openclaw.json parses (JSON5 with comments)
set -euo pipefail

if [[ ! -f "config/openclaw.json" ]]; then
    echo "FAIL: config/openclaw.json not found"
    exit 1
fi

# Strip comments and try JSON parse (strict=False for control chars like emoji)
if python3 -c "
import re, json, sys
with open('config/openclaw.json', encoding='utf-8') as f:
    text = f.read()
# Remove // comments (but not inside strings)
text = re.sub(r'^\s*//.*$', '', text, flags=re.MULTILINE)
text = re.sub(r'(?<=,)\s*//.*$', '', text, flags=re.MULTILINE)
# Remove trailing commas before } or ]
text = re.sub(r',(\s*[\]}])', r'\1', text)
json.loads(text, strict=False)
" 2>/dev/null; then
    exit 0
else
    echo "FAIL: config/openclaw.json does not parse as JSON5"
    exit 1
fi
