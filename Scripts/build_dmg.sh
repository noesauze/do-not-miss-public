#!/bin/bash

set -euo pipefail

log() {
  printf '[dmg] %s\n' "$1"
}

fail() {
  printf '[dmg] ERROR: %s\n' "$1" >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_PATH="${APP_PATH:-${REPO_ROOT}/build/export/Do Not Miss.app}"
DMG_ROOT="${DMG_ROOT:-${REPO_ROOT}/build/dmg}"
STAGING_DIR="${STAGING_DIR:-${DMG_ROOT}/staging}"
VOLUME_NAME="${VOLUME_NAME:-Do Not Miss}"
DMG_NAME="${DMG_NAME:-DoNotMiss-macOS}"
APP_ICONSET_PATH="${APP_ICONSET_PATH:-${REPO_ROOT}/Do Not Miss/Assets.xcassets/AppIcon.appiconset}"
FINAL_DMG_PATH="${FINAL_DMG_PATH:-${DMG_ROOT}/${DMG_NAME}.dmg}"
TEMP_DMG_PATH="${TEMP_DMG_PATH:-${DMG_ROOT}/${DMG_NAME}-temp.dmg}"
NOTARIZE_DMG="${NOTARIZE_DMG:-0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-YOUR_NOTARY_PROFILE}"
APPLE_ID="${APPLE_ID:-YOUR_APPLE_ID@example.com}"
APP_SPECIFIC_PASSWORD="${APP_SPECIFIC_PASSWORD:-YOUR_APP_SPECIFIC_PASSWORD}"
TEAM_ID="${TEAM_ID:-YOUR_TEAM_ID}"
REQUIRE_STAPLE="${REQUIRE_STAPLE:-auto}"

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

ensure_full_xcode() {
  local developer_dir
  developer_dir="$(xcode-select -p 2>/dev/null || true)"

  [[ -n "${developer_dir}" ]] || fail "xcode-select is not configured. Point it to the full Xcode app."
  [[ "${developer_dir}" != "/Library/Developer/CommandLineTools" ]] || fail "xcode-select currently points to CommandLineTools. Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
}

assert_path() {
  [[ -e "$1" ]] || fail "$2: $1"
}

is_placeholder() {
  [[ "$1" == YOUR_* ]]
}

build_notary_auth_args() {
  if ! is_placeholder "${NOTARY_PROFILE}"; then
    printf -- '--keychain-profile\0%s\0' "${NOTARY_PROFILE}"
    return 0
  fi

  if is_placeholder "${APPLE_ID}" || is_placeholder "${APP_SPECIFIC_PASSWORD}" || is_placeholder "${TEAM_ID}"; then
    fail "Configure either NOTARY_PROFILE or the APPLE_ID / APP_SPECIFIC_PASSWORD / TEAM_ID trio before DMG notarization."
  fi

  printf -- '--apple-id\0%s\0--password\0%s\0--team-id\0%s\0' "${APPLE_ID}" "${APP_SPECIFIC_PASSWORD}" "${TEAM_ID}"
}

require_command hdiutil
require_command xcrun
require_command xcode-select
require_command rsync
require_command plutil
require_command iconutil
ensure_full_xcode

assert_path "${APP_PATH}" "Stapled app not found"

mkdir -p "${DMG_ROOT}"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"
rm -f "${TEMP_DMG_PATH}" "${FINAL_DMG_PATH}"

log "Validating stapled app before packaging"
if [[ "${REQUIRE_STAPLE}" == "auto" ]]; then
  if [[ "${NOTARIZE_DMG}" == "1" ]]; then
    REQUIRE_STAPLE="1"
  else
    REQUIRE_STAPLE="0"
  fi
fi

if [[ "${REQUIRE_STAPLE}" == "1" ]]; then
  xcrun stapler validate "${APP_PATH}" || fail "The app is not stapled. Run Scripts/notarize_app.sh successfully before building the DMG, or use REQUIRE_STAPLE=0 for a local/GitHub test DMG."
else
  if xcrun stapler validate "${APP_PATH}" >/dev/null 2>&1; then
    log "Stapled ticket found on app"
  else
    log "No stapled ticket found on app; continuing because REQUIRE_STAPLE=${REQUIRE_STAPLE}"
  fi
fi

log "Preparing DMG staging folder"
rsync -a "${APP_PATH}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

log "Creating temporary writable DMG"
hdiutil create \
  -fs HFS+ \
  -srcfolder "${STAGING_DIR}" \
  -volname "${VOLUME_NAME}" \
  -format UDRW \
  "${TEMP_DMG_PATH}"

APP_ICON_ICNS="${APP_PATH}/Contents/Resources/AppIcon.icns"
GENERATED_ICONSET=""
GENERATED_VOLUME_ICON=""

if [[ ! -f "${APP_ICON_ICNS}" && -d "${APP_ICONSET_PATH}" ]]; then
  GENERATED_ICONSET="${DMG_ROOT}/volume-icon.iconset"
  GENERATED_VOLUME_ICON="${DMG_ROOT}/volume-icon.icns"
  rm -rf "${GENERATED_ICONSET}" "${GENERATED_VOLUME_ICON}"
  mkdir -p "${GENERATED_ICONSET}"
  rsync -a --include='*.png' --exclude='*' "${APP_ICONSET_PATH}/" "${GENERATED_ICONSET}/"
  iconutil -c icns "${GENERATED_ICONSET}" -o "${GENERATED_VOLUME_ICON}"
  APP_ICON_ICNS="${GENERATED_VOLUME_ICON}"
fi

if [[ -f "${APP_ICON_ICNS}" ]]; then
  log "Applying app icon to DMG volume"
  ATTACH_OUTPUT="$(hdiutil attach "${TEMP_DMG_PATH}" -readwrite -noverify)"
  DEVICE_NAME="$(printf '%s\n' "${ATTACH_OUTPUT}" | awk '/Apple_HFS/ { print $1; exit }')"
  MOUNT_POINT="$(printf '%s\n' "${ATTACH_OUTPUT}" | awk -F'\t' '/Volumes/ { print $NF; exit }')"

  if [[ -n "${DEVICE_NAME}" && -n "${MOUNT_POINT}" && -d "${MOUNT_POINT}" ]]; then
    cp "${APP_ICON_ICNS}" "${MOUNT_POINT}/.VolumeIcon.icns"
    SetFile -a C "${MOUNT_POINT}"
    hdiutil detach "${DEVICE_NAME}"
  else
    fail "Unable to determine mounted DMG device or mount point while applying icon."
  fi
else
  log "AppIcon.icns not found in app bundle; skipping DMG volume icon"
fi

log "Converting DMG to compressed read-only image"
hdiutil convert "${TEMP_DMG_PATH}" -format UDZO -o "${FINAL_DMG_PATH}"
rm -f "${TEMP_DMG_PATH}"

shasum -a 256 "${FINAL_DMG_PATH}" > "${FINAL_DMG_PATH}.sha256"

if [[ "${NOTARIZE_DMG}" == "1" ]]; then
  AUTH_ARGS_RAW="$(build_notary_auth_args)"
  IFS=$'\0' read -r -d '' -a AUTH_ARGS <<<"${AUTH_ARGS_RAW}"$'\0'
  DMG_SUBMIT_JSON="${DMG_ROOT}/dmg-submit-result.json"
  DMG_WAIT_JSON="${DMG_ROOT}/dmg-wait-result.json"
  DMG_LOG_JSON="${DMG_ROOT}/dmg-notary-log.json"

  rm -f "${DMG_SUBMIT_JSON}" "${DMG_WAIT_JSON}" "${DMG_LOG_JSON}"

  log "Submitting DMG for notarization"
  xcrun notarytool submit "${FINAL_DMG_PATH}" "${AUTH_ARGS[@]}" --output-format json > "${DMG_SUBMIT_JSON}"

  DMG_SUBMISSION_ID="$(plutil -extract id raw "${DMG_SUBMIT_JSON}")"
  [[ -n "${DMG_SUBMISSION_ID}" ]] || fail "Unable to extract DMG notarization submission ID."

  set +e
  xcrun notarytool wait "${DMG_SUBMISSION_ID}" "${AUTH_ARGS[@]}" --output-format json > "${DMG_WAIT_JSON}"
  WAIT_EXIT_CODE=$?
  set -e

  DMG_STATUS="$(plutil -extract status raw "${DMG_WAIT_JSON}" 2>/dev/null || true)"

  if [[ "${WAIT_EXIT_CODE}" -ne 0 || "${DMG_STATUS}" != "Accepted" ]]; then
    xcrun notarytool log "${DMG_SUBMISSION_ID}" "${AUTH_ARGS[@]}" > "${DMG_LOG_JSON}" || true
    fail "DMG notarization failed with status '${DMG_STATUS:-unknown}'. Inspect ${DMG_LOG_JSON}."
  fi

  log "Stapling notarization ticket to DMG"
  xcrun stapler staple "${FINAL_DMG_PATH}"
  xcrun stapler validate "${FINAL_DMG_PATH}"
fi

log "DMG ready: ${FINAL_DMG_PATH}"
log "SHA-256: ${FINAL_DMG_PATH}.sha256"
