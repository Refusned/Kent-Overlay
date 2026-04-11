#!/usr/bin/env bash
# Verify docker-compose.yml is valid YAML
set -euo pipefail

if [[ ! -f "docker/docker-compose.yml" ]]; then
    echo "FAIL: docker/docker-compose.yml not found"
    exit 1
fi

# Check YAML validity with python
if command -v python3 &>/dev/null; then
    if python3 -c "import yaml; yaml.safe_load(open('docker/docker-compose.yml'))" 2>/dev/null; then
        exit 0
    else
        echo "FAIL: docker-compose.yml is not valid YAML"
        exit 1
    fi
fi

# Fallback: basic structure check
if grep -q "^services:" docker/docker-compose.yml; then
    exit 0
else
    echo "FAIL: docker-compose.yml missing 'services:' section"
    exit 1
fi
