#!/bin/bash

set -euo pipefail

log() {
  printf '[archive] %s\n' "$1"
}

fail() {
  printf '[archive] ERROR: %s\n' "$1" >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROJECT_PATH="${PROJECT_PATH:-${REPO_ROOT}/Do Not Miss.xcodeproj}"
SCHEME="${SCHEME:-Do Not Miss}"
CONFIGURATION="${CONFIGURATION:-Release}"
ARCHIVE_PATH="${ARCHIVE_PATH:-${REPO_ROOT}/build/archive/DoNotMiss.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-${REPO_ROOT}/build/export}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-${EXPORT_PATH}/ExportOptions.plist}"
EXPECTED_BUNDLE_ID="${EXPECTED_BUNDLE_ID:-sauzede.Do-Not-Miss}"
EXPECTED_TEAM_ID="${EXPECTED_TEAM_ID:-YOUR_TEAM_ID}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${REPO_ROOT}/build/DerivedData}"
EXPORT_MODE="${EXPORT_MODE:-developer-id}"

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

ensure_full_xcode() {
  local developer_dir
  developer_dir="$(xcode-select -p 2>/dev/null || true)"

  [[ -n "${developer_dir}" ]] || fail "xcode-select is not configured. Point it to the full Xcode app."
  [[ "${developer_dir}" != "/Library/Developer/CommandLineTools" ]] || fail "xcode-select currently points to CommandLineTools. Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
}

extract_plist_string() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

assert_path() {
  [[ -e "$1" ]] || fail "$2: $1"
}

assert_not_placeholder() {
  local value="$1"
  local label="$2"

  [[ -n "${value}" ]] || fail "${label} is empty"
  [[ "${value}" != YOUR_* ]] || fail "${label} still contains a placeholder value: ${value}"
}

require_command xcodebuild
require_command xcode-select
require_command /usr/libexec/PlistBuddy
ensure_full_xcode

assert_path "${PROJECT_PATH}" "Xcode project not found"

mkdir -p "$(dirname "${ARCHIVE_PATH}")" "${EXPORT_PATH}" "${DERIVED_DATA_PATH}"

[[ "${EXPORT_MODE}" == "developer-id" || "${EXPORT_MODE}" == "local" ]] || fail "EXPORT_MODE must be either 'developer-id' or 'local'."

if [[ "${EXPORT_MODE}" == "developer-id" ]]; then
  assert_path "${EXPORT_OPTIONS_PLIST}" "Export options plist not found"
fi

EXPORT_METHOD=""
EXPORT_TEAM_ID=""

if [[ "${EXPORT_MODE}" == "developer-id" ]]; then
  EXPORT_METHOD="$(extract_plist_string "${EXPORT_OPTIONS_PLIST}" "method")"
  EXPORT_TEAM_ID="$(extract_plist_string "${EXPORT_OPTIONS_PLIST}" "teamID")"
fi

[[ "${CONFIGURATION}" == "Release" ]] || fail "CONFIGURATION must be Release for production distribution. Current value: ${CONFIGURATION}"
if [[ "${EXPORT_MODE}" == "developer-id" ]]; then
  [[ "${EXPORT_METHOD}" == "developer-id" ]] || fail "ExportOptions.plist method must be 'developer-id' for outside-App-Store distribution."
fi

if [[ -n "${EXPORT_TEAM_ID}" ]]; then
  assert_not_placeholder "${EXPORT_TEAM_ID}" "ExportOptions.plist teamID"
fi

if [[ "${EXPECTED_TEAM_ID}" != "YOUR_TEAM_ID" ]]; then
  assert_not_placeholder "${EXPECTED_TEAM_ID}" "EXPECTED_TEAM_ID"
fi

log "Project: ${PROJECT_PATH}"
log "Scheme: ${SCHEME}"
log "Configuration: ${CONFIGURATION}"
log "Archive path: ${ARCHIVE_PATH}"
log "Export path: ${EXPORT_PATH}"
log "DerivedData path: ${DERIVED_DATA_PATH}"
log "Export mode: ${EXPORT_MODE}"

APP_IN_ARCHIVE="${ARCHIVE_PATH}/Products/Applications/${SCHEME}.app"
INFO_PLIST_IN_ARCHIVE="${APP_IN_ARCHIVE}/Contents/Info.plist"
EXPORTED_APP_PATH="${EXPORT_PATH}/${SCHEME}.app"

if [[ "${EXPORT_MODE}" == "developer-id" ]]; then
  xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    -archivePath "${ARCHIVE_PATH}" \
    clean archive

  assert_path "${APP_IN_ARCHIVE}" "Archived app not found"
  assert_path "${INFO_PLIST_IN_ARCHIVE}" "Archived app Info.plist not found"

  ARCHIVE_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${INFO_PLIST_IN_ARCHIVE}")"
  [[ "${ARCHIVE_BUNDLE_ID}" == "${EXPECTED_BUNDLE_ID}" ]] || fail "Bundle identifier mismatch. Expected '${EXPECTED_BUNDLE_ID}', got '${ARCHIVE_BUNDLE_ID}'."

  xcodebuild \
    -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_PATH}" \
    -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}"

  assert_path "${EXPORTED_APP_PATH}" "Exported app not found"

  log "Verifying code signature on exported app"
  codesign --verify --deep --strict --verbose=2 "${EXPORTED_APP_PATH}"
else
  xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -derivedDataPath "${DERIVED_DATA_PATH}" \
    -archivePath "${ARCHIVE_PATH}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    clean archive

  assert_path "${APP_IN_ARCHIVE}" "Archived app not found after local unsigned archive"
  assert_path "${INFO_PLIST_IN_ARCHIVE}" "Archived app Info.plist not found after local unsigned archive"

  ARCHIVE_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${INFO_PLIST_IN_ARCHIVE}")"
  [[ "${ARCHIVE_BUNDLE_ID}" == "${EXPECTED_BUNDLE_ID}" ]] || fail "Bundle identifier mismatch. Expected '${EXPECTED_BUNDLE_ID}', got '${ARCHIVE_BUNDLE_ID}'."

  log "Copying archived app to export folder for local distribution"
  rm -rf "${EXPORTED_APP_PATH}"
  ditto "${APP_IN_ARCHIVE}" "${EXPORTED_APP_PATH}"
  assert_path "${EXPORTED_APP_PATH}" "Exported app not found after local copy"

  log "Inspecting local app signature"
  codesign -dv --verbose=4 "${EXPORTED_APP_PATH}" >/dev/null 2>&1 || log "codesign inspection returned a non-fatal warning in local mode"
fi

log "Archive and export completed"
log "Exported app: ${EXPORTED_APP_PATH}"
