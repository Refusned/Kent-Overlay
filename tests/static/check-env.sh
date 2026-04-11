#!/usr/bin/env bash
# Verify all ${VAR} references in openclaw.json exist in .env.example
set -euo pipefail
ERRORS=0

while IFS= read -r var; do
    if ! grep -q "^${var}=" .env.example 2>/dev/null; then
        echo "FAIL: ${var} referenced in openclaw.json but missing from .env.example"
        ERRORS=$((ERRORS + 1))
    fi
done < <(grep -oP '\$\{([A-Z_]+)\}' config/openclaw.json | sed 's/[${}]//g' | sort -u)

exit "$ERRORS"
