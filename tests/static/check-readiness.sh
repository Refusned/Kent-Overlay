#!/usr/bin/env bash
# Verify READINESS.md exists and references match workspace/skills/
set -euo pipefail
ERRORS=0

if [[ ! -f "READINESS.md" ]]; then
    echo "FAIL: READINESS.md not found"
    exit 1
fi

# Check every skill directory is mentioned in READINESS.md
for dir in workspace/skills/*/; do
    [[ -d "$dir" ]] || continue
    skill="$(basename "$dir")"
    if ! grep -q "$skill" READINESS.md; then
        echo "FAIL: skill '$skill' exists in workspace/skills/ but not mentioned in READINESS.md"
        ERRORS=$((ERRORS + 1))
    fi
done

exit "$ERRORS"
