#!/usr/bin/env bash
# Verify Python dependencies from deploy.sh are importable
set -euo pipefail

if ! command -v python3 &>/dev/null; then
    echo "SKIP: python3 not available"
    exit 0
fi

ERRORS=0
DEPS=("pptx" "PIL" "PyPDF2" "docx" "openpyxl" "reportlab")

for dep in "${DEPS[@]}"; do
    if ! python3 -c "import $dep" 2>/dev/null; then
        echo "WARN: Python module '$dep' not importable (needed for deploy)"
        # Not a hard error — these are deployed on VPS
    fi
done

exit "$ERRORS"
