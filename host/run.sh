#!/usr/bin/env bash
# Start local UI + mock API on http://127.0.0.1:8765/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$ROOT/host/mock_server.py"
