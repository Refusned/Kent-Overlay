#!/usr/bin/env bash
# Verify pptx_tool.py is functional
set -euo pipefail

TOOL="${HOME}/.openclaw/workspace/tools/pptx_tool.py"

if [[ ! -f "$TOOL" ]]; then
    # Try overlay path
    TOOL="workspace/tools/pptx_tool.py"
fi

if [[ ! -f "$TOOL" ]]; then
    echo "FAIL: pptx_tool.py not found"
    exit 1
fi

if python3 "$TOOL" --help > /dev/null 2>&1; then
    exit 0
else
    echo "FAIL: pptx_tool.py --help failed"
    exit 1
fi
