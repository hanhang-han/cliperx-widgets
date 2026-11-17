#!/bin/bash
set -euo pipefail
widget_repo="$(cd "$(dirname "$0")/.." && pwd)"
widget_tests="$(mktemp -d /tmp/cliperx-widget-task-test.XXXXXX)"
trap 'rm -rf "$widget_tests"' EXIT
xcrun swiftc -parse-as-library -module-cache-path "$widget_tests/module-cache" \
  "$widget_repo/host/WorkshopContract.swift" \
  "$widget_repo/tests/native-task-smoke.swift" -o "$widget_tests/task-smoke"
"$widget_tests/task-smoke" "$widget_repo/examples/bug-report/manifest.json"
