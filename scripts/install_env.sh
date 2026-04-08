#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${CX_OUT_DIR:-${ROOT_DIR}/artifacts}"
CONFIG_DIR="${HOME}/.config/cx-riscv-cores"
ENV_FILE="${CONFIG_DIR}/env.sh"

usage() {
  cat <<'EOF'
Usage: ./scripts/install_env.sh [--artifact-dir DIR]

Generate a permanent cx-riscv-cores env file under ~/.config/cx-riscv-cores/env.sh
and make common shell startup files source it.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact-dir)
      [[ $# -ge 2 ]] || { echo "ERROR: --artifact-dir requires a value" >&2; exit 1; }
      ARTIFACT_DIR="$2"
      shift 2
      ;;
    --artifact-dir=*)
      ARTIFACT_DIR="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

mkdir -p "${CONFIG_DIR}"
"${ROOT_DIR}/scripts/generate_env.sh" --artifact-dir "${ARTIFACT_DIR}" > "${ENV_FILE}"

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
  echo "[install] updated ${rc_file}"
}

ensure_source_block "${HOME}/.bashrc"
ensure_source_block "${HOME}/.profile"
if [[ -f "${HOME}/.zshrc" ]]; then
  ensure_source_block "${HOME}/.zshrc"
fi

echo
echo "Installed permanent cx-riscv-cores environment:"
echo "  ${ENV_FILE}"
echo
echo "Reload your shell now to apply it in the current session:"
echo "  source ~/.bashrc"
