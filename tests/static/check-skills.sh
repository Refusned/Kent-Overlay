#!/usr/bin/env bash
# Verify every skill directory has SKILL.md with name: in frontmatter
set -euo pipefail
SKILLS_DIR="workspace/skills"
ERRORS=0

for dir in "$SKILLS_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    skill="$(basename "$dir")"

    if [[ ! -f "$dir/SKILL.md" ]]; then
        echo "FAIL: $skill missing SKILL.md"
        ERRORS=$((ERRORS + 1))
        continue
    fi

    if ! grep -q '^name:' "$dir/SKILL.md"; then
        echo "FAIL: $skill SKILL.md missing 'name:' in frontmatter"
        ERRORS=$((ERRORS + 1))
    fi

    if ! grep -q '^emoji:' "$dir/SKILL.md"; then
        echo "WARN: $skill SKILL.md missing 'emoji:' in frontmatter"
    fi
done

exit "$ERRORS"
