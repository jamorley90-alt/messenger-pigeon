#!/usr/bin/env bash
set -euo pipefail
destination="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/pigeon-xcodegen-2.44.1"
mkdir -p "$destination"
curl --fail --location --proto '=https' --tlsv1.2 \
  'https://github.com/yonaskolb/XcodeGen/releases/download/2.44.1/xcodegen.zip' \
  --output "$destination/xcodegen.zip"
printf '%s  %s\n' 'a2e905fb68446e9bb4008cdfe2e13e3f176d0cbcca828b71770f8e53fca91b73' "$destination/xcodegen.zip" | shasum -a 256 --check
unzip -q -o "$destination/xcodegen.zip" -d "$destination"
binary="$(find "$destination" -type f -name xcodegen | head -n 1)"
test -n "$binary"
chmod +x "$binary"
"$binary" --version
if [[ -n "${GITHUB_PATH:-}" ]]; then
  dirname "$binary" >> "$GITHUB_PATH"
else
  printf 'Add this directory to PATH: %s\n' "$(dirname "$binary")"
fi

