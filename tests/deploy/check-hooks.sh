#!/usr/bin/env bash
# Verify all 4 required hooks are enabled in config
set -euo pipefail
ERRORS=0
REQUIRED_HOOKS=("boot-md" "bootstrap-extra-files" "command-logger" "session-memory")

for hook in "${REQUIRED_HOOKS[@]}"; do
    if ! grep -q "\"$hook\"" config/openclaw.json; then
        echo "FAIL: Hook '$hook' not found in openclaw.json"
        ERRORS=$((ERRORS + 1))
    fi
done

exit "$ERRORS"
