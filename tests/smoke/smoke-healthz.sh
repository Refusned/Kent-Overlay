#!/usr/bin/env bash
# Verify gateway health endpoint responds
set -euo pipefail

if curl -sf --max-time 5 http://localhost:18789/healthz > /dev/null 2>&1; then
    exit 0
else
    echo "FAIL: Gateway healthz at localhost:18789 unreachable"
    exit 1
fi
