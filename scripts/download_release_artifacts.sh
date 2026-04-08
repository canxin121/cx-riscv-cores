#!/usr/bin/env bash
set -euo pipefail

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh CLI is required. Install https://cli.github.com/ and authenticate first." >&2
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${CX_OUT_DIR:-${ROOT_DIR}/artifacts}"
release_tag="${CX_RISCV_CORES_RELEASE_TAG:-"dev-release"}"
manifest_name="${CX_RISCV_CORES_RELEASE_MANIFEST:-"cx_riscv_cores_artifacts_manifest.json"}"

mkdir -p "${ARTIFACT_DIR}"

if [[ "$#" -eq 0 ]]; then
  gh release download "${release_tag}" --dir "${ARTIFACT_DIR}" --clobber
else
  for pattern in "$@"; do
    gh release download "${release_tag}" --pattern "${pattern}" --dir "${ARTIFACT_DIR}" --clobber
  done
fi

rm -f "${ARTIFACT_DIR}/${manifest_name}"
echo "Downloaded release artifacts into ${ARTIFACT_DIR}"
