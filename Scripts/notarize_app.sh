#!/bin/bash

set -euo pipefail

log() {
  printf '[notarize] %s\n' "$1"
}

fail() {
  printf '[notarize] ERROR: %s\n' "$1" >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

APP_PATH="${APP_PATH:-${REPO_ROOT}/build/export/Do Not Miss.app}"
WORK_DIR="${WORK_DIR:-${REPO_ROOT}/build/notarization}"
ZIP_PATH="${ZIP_PATH:-${WORK_DIR}/DoNotMiss-notarization.zip}"
NOTARY_PROFILE="${NOTARY_PROFILE:-YOUR_NOTARY_PROFILE}"
APPLE_ID="${APPLE_ID:-YOUR_APPLE_ID@example.com}"
APP_SPECIFIC_PASSWORD="${APP_SPECIFIC_PASSWORD:-YOUR_APP_SPECIFIC_PASSWORD}"
TEAM_ID="${TEAM_ID:-YOUR_TEAM_ID}"

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
    fail "Configure either NOTARY_PROFILE or the APPLE_ID / APP_SPECIFIC_PASSWORD / TEAM_ID trio before notarization."
  fi

  printf -- '--apple-id\0%s\0--password\0%s\0--team-id\0%s\0' "${APPLE_ID}" "${APP_SPECIFIC_PASSWORD}" "${TEAM_ID}"
}

require_command xcrun
require_command xcode-select
require_command ditto
require_command plutil
require_command spctl
require_command codesign
ensure_full_xcode

assert_path "${APP_PATH}" "Exported app not found"

mkdir -p "${WORK_DIR}"

AUTH_ARGS_RAW="$(build_notary_auth_args)"
IFS=$'\0' read -r -d '' -a AUTH_ARGS <<<"${AUTH_ARGS_RAW}"$'\0'

SUBMIT_JSON="${WORK_DIR}/submit-result.json"
WAIT_JSON="${WORK_DIR}/wait-result.json"
LOG_JSON="${WORK_DIR}/notary-log.json"

rm -f "${ZIP_PATH}" "${SUBMIT_JSON}" "${WAIT_JSON}" "${LOG_JSON}"

log "Verifying code signature before notarization"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

log "Creating ZIP for notarization"
ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"

log "Submitting ZIP to Apple notarization service"
xcrun notarytool submit "${ZIP_PATH}" "${AUTH_ARGS[@]}" --output-format json > "${SUBMIT_JSON}"

SUBMISSION_ID="$(plutil -extract id raw "${SUBMIT_JSON}")"
[[ -n "${SUBMISSION_ID}" ]] || fail "Unable to extract notarization submission ID."

log "Submission ID: ${SUBMISSION_ID}"
log "Waiting for notarization result"

set +e
xcrun notarytool wait "${SUBMISSION_ID}" "${AUTH_ARGS[@]}" --output-format json > "${WAIT_JSON}"
WAIT_EXIT_CODE=$?
set -e

STATUS="$(plutil -extract status raw "${WAIT_JSON}" 2>/dev/null || true)"

if [[ "${WAIT_EXIT_CODE}" -ne 0 || "${STATUS}" != "Accepted" ]]; then
  log "Fetching notarization log"
  xcrun notarytool log "${SUBMISSION_ID}" "${AUTH_ARGS[@]}" > "${LOG_JSON}" || true
  fail "Notarization failed with status '${STATUS:-unknown}'. Inspect ${LOG_JSON} for Apple diagnostics."
fi

log "Stapling notarization ticket to app"
xcrun stapler staple "${APP_PATH}"

log "Validating stapled ticket"
xcrun stapler validate "${APP_PATH}"

log "Assessing app with Gatekeeper"
spctl --assess --type execute --verbose=4 "${APP_PATH}"

log "Notarization and stapling completed"
log "Submission log: ${WAIT_JSON}"
