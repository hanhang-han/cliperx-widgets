#!/bin/bash
set -euo pipefail
widget_repo="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$widget_repo/dist"
xcrun swiftc -O -parse-as-library -swift-version 5 \
  "$widget_repo/host/WorkshopContract.swift" "$widget_repo/host/WorkshopRunner.swift" \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$widget_repo/host/WorkshopRunner-Info.plist" \
  -o "$widget_repo/dist/CliperXWidgetRunner"
codesign --force --options runtime --identifier com.cliperx.widget-runner \
  --entitlements "$widget_repo/host/WorkshopRunner.entitlements" \
  --sign "${CLIPERX_WIDGET_SIGN_IDENTITY:--}" "$widget_repo/dist/CliperXWidgetRunner"
