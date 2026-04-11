#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo 'Usage: youtube_summarize.sh <youtube-url> [output-dir]' >&2
  exit 2
fi

URL="$1"
OUTDIR="${2:-/root/.openclaw/workspace/summaries}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER_BIN="$SCRIPT_DIR/bin"
mkdir -p "$OUTDIR"

PATH="$WRAPPER_BIN:$PATH" summarizely "$URL" --provider codex-cli --output-dir "$OUTDIR"
