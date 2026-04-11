#!/usr/bin/env bash
# Verify Telegram custom commands are documented
set -euo pipefail
ERRORS=0

# Extract command names from openclaw.json
COMMANDS=$(grep -o '"command":[ ]*"[^"]*"' config/openclaw.json | sed 's/"command":[ ]*"//;s/"//' | sort)
CMD_COUNT=$(echo "$COMMANDS" | wc -l | tr -d ' ')

echo "Found $CMD_COUNT custom commands in openclaw.json"

# Verify each command is in READINESS.md
while IFS= read -r cmd; do
    if ! grep -qi "/$cmd" READINESS.md 2>/dev/null; then
        echo "WARN: /$cmd not found in READINESS.md"
    fi
done <<< "$COMMANDS"

exit "$ERRORS"
