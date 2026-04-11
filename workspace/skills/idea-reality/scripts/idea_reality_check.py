#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import urllib.request

API_URL = 'https://idea-reality-mcp.onrender.com/api/check'


def main() -> int:
    if len(sys.argv) < 2:
        print('Usage: idea_reality_check.py "idea text" [quick|deep]', file=sys.stderr)
        return 2

    idea_text = sys.argv[1].strip()
    depth = (sys.argv[2].strip() if len(sys.argv) > 2 else 'quick') or 'quick'
    if depth not in {'quick', 'deep'}:
        print('depth must be quick or deep', file=sys.stderr)
        return 2

    payload = json.dumps({'idea_text': idea_text, 'depth': depth}).encode('utf-8')
    req = urllib.request.Request(
        API_URL,
        data=payload,
        headers={'Content-Type': 'application/json'},
        method='POST',
    )

    with urllib.request.urlopen(req, timeout=90) as resp:
        data = json.load(resp)

    print(json.dumps(data, ensure_ascii=False, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
