#!/bin/bash
set -euo pipefail
widget_repo="$(cd "$(dirname "$0")/.." && pwd)"
widget_tests="$(mktemp -d /tmp/cliperx-widget-ai-test.XXXXXX)"
trap 'rm -rf "$widget_tests"' EXIT
xcrun swiftc -parse-as-library -module-cache-path "$widget_tests/module-cache" \
  "$widget_repo/host/WorkshopContract.swift" \
  "$widget_repo/host/integration/WorkshopAICore.swift" \
  "$widget_repo/tests/native-ai-smoke.swift" -o "$widget_tests/smoke"
"$widget_tests/smoke"
