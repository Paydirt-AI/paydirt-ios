#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
sdk_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
fixture_sources="$sdk_root/IntegrationSmoke/Sources/PaydirtIntegrationSmoke"
derived_data="${RUNNER_TEMP:-/tmp}/paydirt-integration-derived"

cp "$sdk_root/IntegrationTemplates/PaydirtRevenueCatAdapter.swift" "$fixture_sources/"
cp "$sdk_root/IntegrationTemplates/PaydirtSuperwallAdapter.swift" "$fixture_sources/"

cd "$sdk_root/IntegrationSmoke"
xcodebuild \
  -scheme PaydirtIntegrationSmoke \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  build
