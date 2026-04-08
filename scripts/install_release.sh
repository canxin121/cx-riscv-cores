#!/usr/bin/env bash
set -euo pipefail

REPO="${CX_RISCV_CORES_RELEASE_REPO:-HardwareFuzz/cx-riscv-cores}"
RELEASE_TAG="${CX_RISCV_CORES_RELEASE_TAG:-dev-release}"
MANIFEST_NAME="${CX_RISCV_CORES_RELEASE_MANIFEST:-cx_riscv_cores_artifacts_manifest.json}"

INSTALL_DIR="${CX_RISCV_CORES_INSTALL_DIR:-${HOME}/.local/share/cx-riscv-cores}"
ARTIFACT_DIR="${INSTALL_DIR}/artifacts"
CONFIG_DIR="${CX_RISCV_CORES_CONFIG_DIR:-${HOME}/.config/cx-riscv-cores}"
ENV_FILE="${CX_RISCV_CORES_ENV_FILE:-${CONFIG_DIR}/env.sh}"

INSTALL_DIR_EXPLICIT=0
ARTIFACT_DIR_EXPLICIT=0
DOWNLOAD_ONLY=0
NO_PROFILE=0
LIST_ONLY=0

declare -a ONLY_PATTERNS=()
declare -a SKIP_PATTERNS=()

usage() {
  cat <<'EOF'
Usage: ./scripts/install_release.sh [options]

Download cx-riscv-cores release artifacts into a local directory, generate a
stable env.sh, and optionally install shell startup hooks.

This script is intentionally standalone so it can be used as:

  curl -fsSL https://raw.githubusercontent.com/HardwareFuzz/cx-riscv-cores/main/scripts/install_release.sh | bash

Common examples:

  # Install all release artifacts into ~/.local/share/cx-riscv-cores
  curl -fsSL https://raw.githubusercontent.com/HardwareFuzz/cx-riscv-cores/main/scripts/install_release.sh | bash

  # Install all artifacts into a custom root
  curl -fsSL https://raw.githubusercontent.com/HardwareFuzz/cx-riscv-cores/main/scripts/install_release.sh | \
    bash -s -- --dir /opt/cx-riscv-cores

  # Install only part of the release into a specific artifact directory
  curl -fsSL https://raw.githubusercontent.com/HardwareFuzz/cx-riscv-cores/main/scripts/install_release.sh | \
    bash -s -- --artifact-dir /data/cx-riscv-cores --only 'rocket-chip_*' --only 'xiangshan_*unaligned*'

Options:
  --dir DIR             Install root. Artifacts go to DIR/artifacts by default.
  --artifact-dir DIR    Store artifacts directly in DIR.
  --env-file FILE       Write generated exports to FILE.
  --release TAG         GitHub release tag (default: dev-release).
  --repo OWNER/REPO     GitHub repo (default: HardwareFuzz/cx-riscv-cores).
  --only GLOB[,GLOB]    Download only assets matching any shell-style glob.
                        Repeatable. Quote patterns so your shell does not expand them.
  --skip GLOB[,GLOB]    Exclude assets matching any shell-style glob.
                        Repeatable.
  --list                List the selected asset names and exit.
  --download-only       Download files only. Do not write env.sh or shell rc files.
  --no-profile          Write env.sh but do not touch ~/.bashrc, ~/.profile, or ~/.zshrc.
  -h, --help            Show this help.
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

log() {
  echo "[install-release] $*" >&2
}

require_cmd() {
  local name="$1"
  command -v "${name}" >/dev/null 2>&1 || die "required command not found: ${name}"
}

download_file() {
  local url="$1"
  local output_path="$2"
  local label="$3"
  local attempt
  local rc=0

  for attempt in 1 2 3; do
    if curl --fail --location --silent --show-error --output "${output_path}" "${url}"; then
      return 0
    fi
    rc=$?
    rm -f "${output_path}"
    if [[ "${attempt}" -lt 3 ]]; then
      log "retrying ${label} after transient download failure (${attempt}/3)"
      sleep 2
    fi
  done

  return "${rc}"
}

detect_python() {
  if command -v python3 >/dev/null 2>&1; then
    echo python3
  elif command -v python >/dev/null 2>&1; then
    echo python
  else
    die "python3 (or python) is required"
  fi
}

split_csv_patterns() {
  local raw="$1"
  local item
  IFS=',' read -r -a items <<<"${raw}"
  for item in "${items[@]}"; do
    [[ -n "${item}" ]] || continue
    printf '%s\n' "${item}"
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      [[ $# -ge 2 ]] || die "--dir requires a value"
      INSTALL_DIR="$2"
      INSTALL_DIR_EXPLICIT=1
      if [[ "${ARTIFACT_DIR_EXPLICIT}" -eq 0 ]]; then
        ARTIFACT_DIR="${INSTALL_DIR}/artifacts"
      fi
      shift 2
      ;;
    --dir=*)
      INSTALL_DIR="${1#*=}"
      INSTALL_DIR_EXPLICIT=1
      if [[ "${ARTIFACT_DIR_EXPLICIT}" -eq 0 ]]; then
        ARTIFACT_DIR="${INSTALL_DIR}/artifacts"
      fi
      shift
      ;;
    --artifact-dir)
      [[ $# -ge 2 ]] || die "--artifact-dir requires a value"
      ARTIFACT_DIR="$2"
      ARTIFACT_DIR_EXPLICIT=1
      if [[ "${INSTALL_DIR_EXPLICIT}" -eq 0 ]]; then
        INSTALL_DIR="${ARTIFACT_DIR}"
      fi
      shift 2
      ;;
    --artifact-dir=*)
      ARTIFACT_DIR="${1#*=}"
      ARTIFACT_DIR_EXPLICIT=1
      if [[ "${INSTALL_DIR_EXPLICIT}" -eq 0 ]]; then
        INSTALL_DIR="${ARTIFACT_DIR}"
      fi
      shift
      ;;
    --env-file)
      [[ $# -ge 2 ]] || die "--env-file requires a value"
      ENV_FILE="$2"
      shift 2
      ;;
    --env-file=*)
      ENV_FILE="${1#*=}"
      shift
      ;;
    --release)
      [[ $# -ge 2 ]] || die "--release requires a value"
      RELEASE_TAG="$2"
      shift 2
      ;;
    --release=*)
      RELEASE_TAG="${1#*=}"
      shift
      ;;
    --repo)
      [[ $# -ge 2 ]] || die "--repo requires a value"
      REPO="$2"
      shift 2
      ;;
    --repo=*)
      REPO="${1#*=}"
      shift
      ;;
    --only)
      [[ $# -ge 2 ]] || die "--only requires a value"
      while IFS= read -r pattern; do
        ONLY_PATTERNS+=("${pattern}")
      done < <(split_csv_patterns "$2")
      shift 2
      ;;
    --only=*)
      while IFS= read -r pattern; do
        ONLY_PATTERNS+=("${pattern}")
      done < <(split_csv_patterns "${1#*=}")
      shift
      ;;
    --skip)
      [[ $# -ge 2 ]] || die "--skip requires a value"
      while IFS= read -r pattern; do
        SKIP_PATTERNS+=("${pattern}")
      done < <(split_csv_patterns "$2")
      shift 2
      ;;
    --skip=*)
      while IFS= read -r pattern; do
        SKIP_PATTERNS+=("${pattern}")
      done < <(split_csv_patterns "${1#*=}")
      shift
      ;;
    --download-only)
      DOWNLOAD_ONLY=1
      shift
      ;;
    --no-profile)
      NO_PROFILE=1
      shift
      ;;
    --list)
      LIST_ONLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

require_cmd curl
PYTHON_BIN="$(detect_python)"

mkdir -p "${ARTIFACT_DIR}"
mkdir -p "$(dirname "${ENV_FILE}")"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

MANIFEST_PATH="${TMP_DIR}/${MANIFEST_NAME}"
ONLY_PATTERNS_FILE="${TMP_DIR}/only_patterns.txt"
SKIP_PATTERNS_FILE="${TMP_DIR}/skip_patterns.txt"
SELECTED_TSV="${TMP_DIR}/selected.tsv"

printf '%s\n' "${ONLY_PATTERNS[@]}" > "${ONLY_PATTERNS_FILE}"
printf '%s\n' "${SKIP_PATTERNS[@]}" > "${SKIP_PATTERNS_FILE}"

MANIFEST_URL="https://github.com/${REPO}/releases/download/${RELEASE_TAG}/${MANIFEST_NAME}"
log "fetching manifest ${MANIFEST_NAME} from ${REPO}@${RELEASE_TAG}"
download_file "${MANIFEST_URL}" "${MANIFEST_PATH}" "${MANIFEST_NAME}"

"${PYTHON_BIN}" - "${MANIFEST_PATH}" "${ONLY_PATTERNS_FILE}" "${SKIP_PATTERNS_FILE}" > "${SELECTED_TSV}" <<'PY'
import fnmatch
import json
import os
import sys

manifest_path, only_path, skip_path = sys.argv[1:4]

with open(manifest_path, encoding="utf-8") as f:
    manifest = json.load(f)

if not isinstance(manifest, dict):
    print("manifest is not a JSON object", file=sys.stderr)
    raise SystemExit(2)

def load_patterns(path):
    if not os.path.exists(path):
        return []
    out = []
    with open(path, encoding="utf-8") as f:
        for raw in f:
            item = raw.strip()
            if item:
                out.append(item)
    return out

def matches(name, patterns):
    return any(fnmatch.fnmatchcase(name, pattern) for pattern in patterns)

only_patterns = load_patterns(only_path)
skip_patterns = load_patterns(skip_path)

selected = []
for name in sorted(manifest):
    if only_patterns and not matches(name, only_patterns):
        continue
    if skip_patterns and matches(name, skip_patterns):
        continue
    selected.append((name, manifest[name]))

if not selected:
    print("no release assets matched the requested filters", file=sys.stderr)
    raise SystemExit(3)

for name, checksum in selected:
    print(f"{name}\t{checksum}")
PY

if [[ "${LIST_ONLY}" -eq 1 ]]; then
  cut -f1 "${SELECTED_TSV}"
  exit 0
fi

sha256_file() {
  local path="$1"
  "${PYTHON_BIN}" - "${path}" <<'PY'
import hashlib
import sys

path = sys.argv[1]
digest = hashlib.sha256()
with open(path, "rb") as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b""):
        digest.update(chunk)
print(digest.hexdigest())
PY
}

emit_export() {
  local name="$1"
  local value="$2"
  printf 'export %s=%q\n' "${name}" "${value}"
}

artifact_env_name() {
  local name="$1"
  name="${name^^}"
  name="${name//-/_}"
  name="${name//./_}"
  printf 'CX_RISCV_CORES_%s\n' "${name}"
}

ensure_source_block() {
  local rc_file="$1"
  local start="# >>> cx-riscv-cores >>>"
  local end="# <<< cx-riscv-cores <<<"
  local source_line="[ -f \"${ENV_FILE}\" ] && . \"${ENV_FILE}\""
  local tmp

  [[ -f "${rc_file}" ]] || : > "${rc_file}"

  tmp="$(mktemp)"
  awk -v start="${start}" -v end="${end}" '
    $0 == start { skip=1; next }
    $0 == end { skip=0; next }
    !skip { print }
  ' "${rc_file}" > "${tmp}"

  {
    cat "${tmp}"
    if [[ -s "${tmp}" ]]; then
      printf '\n'
    fi
    printf '%s\n' "${start}"
    printf '%s\n' "${source_line}"
    printf '%s\n' "${end}"
  } > "${rc_file}"

  rm -f "${tmp}"
  log "updated ${rc_file}"
}

selected_count=0
downloaded_count=0
skipped_count=0

while IFS=$'\t' read -r asset_name expected_checksum; do
  [[ -n "${asset_name}" ]] || continue
  selected_count=$((selected_count + 1))
  dst="${ARTIFACT_DIR}/${asset_name}"

  if [[ -f "${dst}" ]]; then
    actual_checksum="$(sha256_file "${dst}")"
    if [[ "${actual_checksum}" == "${expected_checksum}" ]]; then
      log "skip ${asset_name}; checksum already matches"
      skipped_count=$((skipped_count + 1))
      continue
    fi
    log "re-download ${asset_name}; checksum mismatch"
  fi

  tmp_dst="${dst}.partial.$$"
  rm -f "${tmp_dst}"
  url="https://github.com/${REPO}/releases/download/${RELEASE_TAG}/${asset_name}"
  log "download ${asset_name}"
  download_file "${url}" "${tmp_dst}" "${asset_name}"

  actual_checksum="$(sha256_file "${tmp_dst}")"
  [[ "${actual_checksum}" == "${expected_checksum}" ]] || {
    rm -f "${tmp_dst}"
    die "checksum mismatch for ${asset_name}: expected ${expected_checksum}, got ${actual_checksum}"
  }

  mv -f "${tmp_dst}" "${dst}"
  chmod 755 "${dst}" || true
  downloaded_count=$((downloaded_count + 1))
done < "${SELECTED_TSV}"

if [[ "${DOWNLOAD_ONLY}" -eq 1 ]]; then
  log "downloaded ${downloaded_count} file(s), skipped ${skipped_count}, artifact dir: ${ARTIFACT_DIR}"
  exit 0
fi

{
  printf '# Generated by cx-riscv-cores install_release.sh\n'
  emit_export "CX_RISCV_CORES_ROOT" "${INSTALL_DIR}"
  emit_export "CX_RISCV_CORES_ARTIFACT_DIR" "${ARTIFACT_DIR}"

  mapfile -d '' artifact_paths < <(find "${ARTIFACT_DIR}" -maxdepth 1 -type f ! -name '*.json' ! -name '*.partial.*' -print0 | sort -z)
  for path in "${artifact_paths[@]}"; do
    [[ -n "${path}" ]] || continue
    base="$(basename "${path}")"
    emit_export "$(artifact_env_name "${base}")" "${path}"
  done

  if [[ -f "${ARTIFACT_DIR}/spike" ]]; then
    emit_export "CX_RISCV_CORES_SPIKE" "${ARTIFACT_DIR}/spike"
  else
    spike_path="$(command -v spike || true)"
    if [[ -n "${spike_path}" ]]; then
      emit_export "CX_RISCV_CORES_SPIKE" "${spike_path}"
    fi
  fi
} > "${ENV_FILE}"

log "wrote ${ENV_FILE}"

if [[ "${NO_PROFILE}" -eq 0 ]]; then
  mkdir -p "${CONFIG_DIR}"
  ensure_source_block "${HOME}/.bashrc"
  ensure_source_block "${HOME}/.profile"
  if [[ -f "${HOME}/.zshrc" ]]; then
    ensure_source_block "${HOME}/.zshrc"
  fi
fi

echo
echo "Install summary"
echo "  Selected assets : ${selected_count}"
echo "  Downloaded      : ${downloaded_count}"
echo "  Reused existing : ${skipped_count}"
echo "  Install root    : ${INSTALL_DIR}"
echo "  Artifact dir    : ${ARTIFACT_DIR}"
echo "  Env file        : ${ENV_FILE}"
echo
echo "To apply it in your current shell now:"
echo "  . \"${ENV_FILE}\""
