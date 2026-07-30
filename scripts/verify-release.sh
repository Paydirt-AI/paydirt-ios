#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
sdk_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
cd "$sdk_root"

pod_version=$(sed -n "s/.*s\.version[[:space:]]*=[[:space:]]*'\([^']*\)'.*/\1/p" Paydirt.podspec)
source_version=$(sed -n 's/.*Paydirt SDK v\([0-9][0-9.]*\) configured.*/\1/p' Sources/Paydirt/Paydirt.swift)

if [ -z "$pod_version" ] || [ "$pod_version" != "$source_version" ]; then
  echo "Version mismatch: podspec=$pod_version source=$source_version" >&2
  exit 1
fi

if ! grep -q "from: \"$pod_version\"" README.md; then
  echo "README SwiftPM version does not match $pod_version" >&2
  exit 1
fi

release_cache="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/paydirt-release-contract"
mkdir -p "$release_cache/clang" "$release_cache/swiftpm"
CLANG_MODULE_CACHE_PATH="$release_cache/clang" \
SWIFTPM_MODULECACHE_OVERRIDE="$release_cache/swiftpm" \
  swift package dump-package >/dev/null
plutil -lint Sources/Paydirt/Resources/PrivacyInfo.xcprivacy >/dev/null

if grep -ERq 'hooks\.slack\.com/services/|sk-ant-|sk-proj-|xox[baprs]-' Sources IntegrationTemplates Example; then
  echo "A credential-like value is present in a public SDK directory" >&2
  exit 1
fi

echo "Release contract verified for Paydirt $pod_version"
