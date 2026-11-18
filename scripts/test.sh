#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> validate"
bash tests/test_validate.sh

echo "==> lists dedupe"
bash tests/test_lists_dedupe.sh

echo "==> stats-ctl"
bash tests/test_stats_ctl.sh

echo "==> mock API"
python3 tests/test_mock_api.py

echo "==> package stage + measure"
bash scripts/measure-size.sh >/dev/null

echo "ALL TESTS PASSED"
