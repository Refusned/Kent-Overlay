#!/usr/bin/env bash
# Verify core workspace files exist and are non-empty
set -euo pipefail
ERRORS=0
WORKSPACE="${HOME}/.openclaw/workspace"

FILES=("SOUL.md" "SECURITY.md" "AGENTS.md")

for f in "${FILES[@]}"; do
    filepath="${WORKSPACE}/${f}"
    if [[ ! -f "$filepath" ]]; then
        echo "FAIL: ${f} not found in ${WORKSPACE}"
        ERRORS=$((ERRORS + 1))
    elif [[ ! -s "$filepath" ]]; then
        echo "FAIL: ${f} exists but is empty"
        ERRORS=$((ERRORS + 1))
    fi
done

exit "$ERRORS"
