#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/upload_release_asset_safe.sh <tag> <file> [asset_name]

Behavior:
  1. Upload the file to the release under a temporary asset name with curl progress.
  2. Optionally delete the old asset of the target name.
  3. Rename the temporary asset to the final asset name.
  4. Verify the final asset exists on the release.

Why this exists:
  gh release upload --clobber deletes the old asset before uploading the new one.
  If the upload stalls or fails, the release can be left without that asset.

Environment overrides:
  GITHUB_REPO            Default: HardwareFuzz/cx-riscv-cores
  CURL_LOW_SPEED_BPS     Default: 10240   (10 KiB/s)
  CURL_LOW_SPEED_TIME    Default: 120     (seconds)
  CURL_CONNECT_TIMEOUT   Default: 15      (seconds)
  CURL_HTTP_VERSION      Default: --http1.1
  CURL_LIMIT_RATE        Optional. Example: 256k
  CURL_RESOLVE_ENTRY     Optional. Example: uploads.github.com:443:20.205.243.161
  UPLOAD_RETRIES         Default: 3
  UPLOAD_RETRY_DELAY     Default: 10      (seconds)
EOF
}

[[ $# -ge 2 && $# -le 3 ]] || { usage >&2; exit 1; }

TAG="$1"
FILE="$2"
ASSET_NAME="${3:-$(basename "$FILE")}"
REPO="${GITHUB_REPO:-HardwareFuzz/cx-riscv-cores}"
LOW_SPEED_BPS="${CURL_LOW_SPEED_BPS:-10240}"
LOW_SPEED_TIME="${CURL_LOW_SPEED_TIME:-120}"
CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-15}"
HTTP_VERSION_FLAG="${CURL_HTTP_VERSION:---http1.1}"
LIMIT_RATE="${CURL_LIMIT_RATE:-}"
RESOLVE_ENTRY="${CURL_RESOLVE_ENTRY:-}"
UPLOAD_RETRIES="${UPLOAD_RETRIES:-3}"
UPLOAD_RETRY_DELAY="${UPLOAD_RETRY_DELAY:-10}"

[[ -f "$FILE" ]] || { echo "ERROR: file not found: $FILE" >&2; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "ERROR: gh is required" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required" >&2; exit 1; }

RELEASE_JSON="$(gh api "repos/${REPO}/releases/tags/${TAG}")"
RELEASE_ID="$(python3 - <<'PY' "$RELEASE_JSON"
import json, sys
print(json.loads(sys.argv[1])["id"])
PY
)"
UPLOAD_URL="https://uploads.github.com/repos/${REPO}/releases/${RELEASE_ID}/assets"
TOKEN="$(gh auth token)"
TMP_RESP="$(mktemp)"
FILE_SIZE="$(stat -c '%s' "$FILE")"

cleanup() {
  rm -f "$TMP_RESP"
}
trap cleanup EXIT

echo "release=${TAG}"
echo "repo=${REPO}"
echo "file=${FILE}"
echo "target_name=${ASSET_NAME}"
echo "low_speed=${LOW_SPEED_BPS}B/s for ${LOW_SPEED_TIME}s"
[[ -n "${LIMIT_RATE}" ]] && echo "limit_rate=${LIMIT_RATE}"
[[ -n "${RESOLVE_ENTRY}" ]] && echo "resolve=${RESOLVE_ENTRY}"
echo "retries=${UPLOAD_RETRIES}"
echo

TMP_ASSET_ID=""
TMP_ASSET_SIZE=""
TMP_NAME=""
attempt=1

while (( attempt <= UPLOAD_RETRIES )); do
  TMP_NAME="${ASSET_NAME}.uploading.$(date +%Y%m%d%H%M%S).$$.${attempt}"
  echo "[1/4] Upload temp asset with live progress (attempt ${attempt}/${UPLOAD_RETRIES})"
  echo "temp_name=${TMP_NAME}"
  : > "$TMP_RESP"

  curl_args=(
    "$HTTP_VERSION_FLAG"
    ${RESOLVE_ENTRY:+--resolve "$RESOLVE_ENTRY"}
    --progress-bar
    --connect-timeout "$CONNECT_TIMEOUT"
    --speed-limit "$LOW_SPEED_BPS"
    --speed-time "$LOW_SPEED_TIME"
    --output "$TMP_RESP"
    --write-out '%{http_code}'
    -X POST
    -H "Authorization: Bearer ${TOKEN}"
    -H "Accept: application/vnd.github+json"
    -H "Content-Type: application/octet-stream"
    -H "Expect:"
    --data-binary @"$FILE"
    "${UPLOAD_URL}?name=${TMP_NAME}"
  )
  if [[ -n "${LIMIT_RATE}" ]]; then
    curl_args=(--limit-rate "${LIMIT_RATE}" "${curl_args[@]}")
  fi

  set +e
  CURL_HTTP_CODE="$(curl "${curl_args[@]}")"
  curl_status=$?
  set -e
  echo

  if [[ $curl_status -eq 0 && "$CURL_HTTP_CODE" == "201" ]]; then
    TMP_ASSET_ID="$(python3 - <<'PY' "$TMP_RESP"
import json, sys
obj = json.load(open(sys.argv[1]))
print(obj["id"])
PY
)"
    TMP_ASSET_SIZE="$(python3 - <<'PY' "$TMP_RESP"
import json, sys
obj = json.load(open(sys.argv[1]))
print(obj["size"])
PY
)"
    if [[ "$TMP_ASSET_SIZE" != "$FILE_SIZE" ]]; then
      echo "WARNING: uploaded temp asset size ${TMP_ASSET_SIZE} != local file size ${FILE_SIZE}" >&2
      gh api -X DELETE "repos/${REPO}/releases/assets/${TMP_ASSET_ID}" >/dev/null 2>&1 || true
    else
      break
    fi
  else
    echo "WARNING: upload attempt ${attempt} failed (curl_status=${curl_status}, http=${CURL_HTTP_CODE:-n/a})" >&2
    sed -n '1,40p' "$TMP_RESP" >&2 || true
  fi

  # If a partial temp asset somehow made it onto the release, remove it before retrying.
  partial_id="$(
    gh api "repos/${REPO}/releases/${RELEASE_ID}/assets" \
      --jq ".[] | select(.name == \"${TMP_NAME}\") | .id" 2>/dev/null || true
  )"
  if [[ -n "${partial_id}" ]]; then
    gh api -X DELETE "repos/${REPO}/releases/assets/${partial_id}" >/dev/null 2>&1 || true
  fi

  (( attempt++ ))
  if (( attempt <= UPLOAD_RETRIES )); then
    echo "Retrying in ${UPLOAD_RETRY_DELAY}s..."
    sleep "${UPLOAD_RETRY_DELAY}"
  fi
done

if [[ -z "${TMP_ASSET_ID}" || "${TMP_ASSET_SIZE}" != "${FILE_SIZE}" ]]; then
  echo "ERROR: upload failed after ${UPLOAD_RETRIES} attempt(s)" >&2
  exit 1
fi

echo "[2/4] Query old asset"
OLD_ASSET_ID="$(
  gh api "repos/${REPO}/releases/${RELEASE_ID}/assets" \
    --jq ".[] | select(.name == \"${ASSET_NAME}\") | .id" 2>/dev/null || true
)"

if [[ -n "${OLD_ASSET_ID}" ]]; then
  echo "Deleting old asset id=${OLD_ASSET_ID}"
  gh api \
    -X DELETE \
    "repos/${REPO}/releases/assets/${OLD_ASSET_ID}" >/dev/null
else
  echo "No existing asset named ${ASSET_NAME}"
fi

echo "[3/4] Rename temp asset to final name"
gh api \
  -X PATCH \
  "repos/${REPO}/releases/assets/${TMP_ASSET_ID}" \
  -f name="${ASSET_NAME}" >/dev/null

echo "[4/4] Verify final asset"
gh api "repos/${REPO}/releases/${RELEASE_ID}/assets" \
  --jq ".[] | select(.name == \"${ASSET_NAME}\") | [.name, .updated_at, (.size|tostring), .browser_download_url] | @tsv"
