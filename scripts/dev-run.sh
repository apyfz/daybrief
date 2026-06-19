#!/usr/bin/env bash
#
# Local dev build + run for Daybrief, signed with a STABLE "Apple Development"
# identity so macOS Keychain "Always Allow" persists across rebuilds.
#
# Why: the default Debug signing is ad-hoc ("Sign to Run Locally"), whose code
# signature changes on every build. macOS ties Keychain trust to the signature, so
# ad-hoc builds re-prompt for every secret (the LLM key + each connector token) on
# every launch. Signing with a real cert gives a stable, identity-based designated
# requirement, so "Always Allow" sticks. The identity is auto-detected — nothing
# machine-specific is hard-coded.
#
# Usage:  ./scripts/dev-run.sh
set -euo pipefail

cd "$(dirname "$0")/.."

IDENTITY=$(security find-identity -p codesigning -v | grep "Apple Development" | head -1 | awk '{print $2}')
if [ -z "${IDENTITY:-}" ]; then
  echo "No 'Apple Development' code-signing identity found."
  echo "Create one in Xcode → Settings → Accounts (add your Apple ID, then 'Manage Certificates')."
  exit 1
fi
echo "Signing with Apple Development identity: $IDENTITY"

xcodebuild -project Daybrief.xcodeproj -scheme Daybrief -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES \
  build

APP_PATH=$(xcodebuild -project Daybrief.xcodeproj -scheme Daybrief -configuration Debug \
  -showBuildSettings 2>/dev/null \
  | awk '/ BUILT_PRODUCTS_DIR /{dir=$3} / FULL_PRODUCT_NAME /{name=$3} END{print dir"/"name}')

pkill -x Daybrief 2>/dev/null || true
sleep 1
open "$APP_PATH"
echo "Launched: $APP_PATH"
