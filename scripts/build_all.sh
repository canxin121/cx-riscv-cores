#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: ./scripts/build_all.sh [options]

Options:
  --out-dir DIR         Unified output directory for final artifacts.
                        Default: $CX_OUT_DIR if set, else ./artifacts
  --log-dir DIR         Log directory (default: ./logs/<YYYYMMDD>)
  --cores <1|2|both>    Build 1-core, 2-core, or both (default: both)
  --only a,b,c          Only build selected cores (comma-separated, case-insensitive).
                        Supported: picorv32,kronos,ibex,vexriscv,cva6,rocket-chip,xiangshan
  --with-xiangshan      Include XiangShan (default: skip)
  --clean               Forward --clean to sub-build scripts
  --coverage            Forward --coverage to sub-build scripts
  --coverage-light      Forward --coverage-light to sub-build scripts
  --no-coverage         Forward --no-coverage to sub-build scripts (default)
  --dry-run             Print commands without executing
  --help, -h            Show this help

Notes:
  - This repo uses git submodules under ./cores/.
  - Each core repo is expected to provide a compatible ./build.sh.
  - Intermediate build dirs stay inside each submodule repo; only final binaries
    are copied into <out-dir> with unified names.
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

OUT_DIR_OPT=""
LOG_DIR_OPT=""
CORES_MODE="both" # 1|2|both
ONLY_LIST=""
WITH_XIANGSHAN=0
CLEAN=0
COV_MODE="none" # none|full|light
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out-dir)
      [[ $# -ge 2 ]] || die "--out-dir requires a value"
      OUT_DIR_OPT="$2"; shift 2 ;;
    --out-dir=*)
      OUT_DIR_OPT="${1#*=}"; shift ;;
    --log-dir)
      [[ $# -ge 2 ]] || die "--log-dir requires a value"
      LOG_DIR_OPT="$2"; shift 2 ;;
    --cores)
      [[ $# -ge 2 ]] || die "--cores requires a value"
      CORES_MODE="$2"; shift 2 ;;
    --cores=*)
      CORES_MODE="${1#*=}"; shift ;;
    --only)
      [[ $# -ge 2 ]] || die "--only requires a value"
      ONLY_LIST="$2"; shift 2 ;;
    --only=*)
      ONLY_LIST="${1#*=}"; shift ;;
    --with-xiangshan) WITH_XIANGSHAN=1; shift ;;
    --skip-xiangshan) WITH_XIANGSHAN=0; shift ;;
    --clean) CLEAN=1; shift ;;
    --coverage) COV_MODE="full"; shift ;;
    --coverage-light) COV_MODE="light"; shift ;;
    --no-coverage) COV_MODE="none"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

case "${CORES_MODE}" in
  1|2|both) ;;
  *) die "--cores must be one of: 1, 2, both (got: ${CORES_MODE})" ;;
esac

DATE_TAG="$(date +%Y%m%d)"
OUT_DIR_DEFAULT="${ROOT_DIR}/artifacts"
OUT_DIR="${OUT_DIR_OPT:-${CX_OUT_DIR:-${OUT_DIR_DEFAULT}}}"
LOG_DIR="${LOG_DIR_OPT:-${ROOT_DIR}/logs/${DATE_TAG}}"

mkdir -p "${OUT_DIR}" "${LOG_DIR}"

run() {
  if (( DRY_RUN )); then
    printf '+'
    printf ' %q' "$@"
    echo
    return 0
  fi
  "$@"
}

contains_core() {
  local core="$1"
  if [[ -z "${ONLY_LIST}" ]]; then
    return 0
  fi
  # Case-insensitive comma-separated list matching.
  local only_lc="${ONLY_LIST,,}"
  only_lc="${only_lc//[[:space:]]/}"
  local core_lc="${core,,}"
  [[ ",${only_lc}," == *",${core_lc},"* ]]
}

ensure_submodule() {
  local relpath="$1"
  run git -C "${ROOT_DIR}" submodule update --init --recursive "${relpath}"
}

checkout_branch() {
  local repo_dir="$1"
  local branch="$2"
  run git -C "${repo_dir}" fetch origin --prune
  run git -C "${repo_dir}" checkout -q -B "${branch}" "origin/${branch}"
}

build_in_repo() {
  local name="$1"
  local branch="$2"
  shift 2
  local repo_dir="${ROOT_DIR}/cores/${name}"

  ensure_submodule "cores/${name}"
  checkout_branch "${repo_dir}" "${branch}"

  local build_cmd=("./build.sh")
  build_cmd+=("$@")
  build_cmd+=("--out-dir" "${OUT_DIR}")

  if (( CLEAN )); then
    build_cmd+=("--clean")
  fi

  case "${COV_MODE}" in
    none) build_cmd+=("--no-coverage") ;;
    full) build_cmd+=("--coverage") ;;
    light) build_cmd+=("--coverage-light") ;;
    *) die "internal: unknown coverage mode ${COV_MODE}" ;;
  esac

  local log_file="${LOG_DIR}/${name}_${branch}.log"
  echo "[build] ${name} (${branch}) -> ${OUT_DIR}"

  if (( DRY_RUN )); then
    echo "+ (cd ${repo_dir} && CX_OUT_DIR=${OUT_DIR} ${build_cmd[*]}) | tee ${log_file}"
    return 0
  fi

  (
    cd "${repo_dir}"
    export CX_OUT_DIR="${OUT_DIR}"
    "${build_cmd[@]}" 2>&1 | tee "${log_file}"
  )
}

build_picorv32() {
  local branch="$1"
  local cores="$2"
  build_in_repo picorv32 "${branch}" --isa rv32 --cores "${cores}"
}

build_kronos() {
  local branch="$1"
  local cores="$2"
  build_in_repo kronos "${branch}" --isa rv32 --cores "${cores}"
}

build_ibex() {
  local branch="$1"
  local cores="$2"
  build_in_repo ibex "${branch}" --isa rv32imc --cores "${cores}"
}

build_vexriscv() {
  local branch="$1"
  local cores="$2"
  # Default to rv32fd for maximum feature coverage (and 2-core support).
  build_in_repo VexRiscv "${branch}" --isa rv32fd --cores "${cores}"
}

build_cva6() {
  local branch="$1"
  local cores="$2"
  # Build both rv64 and rv32 binaries.
  build_in_repo cva6 "${branch}" --isa rv64 --isa rv32 --cores "${cores}"
}

build_rocket_chip() {
  local branch="$1"
  local cores="$2"
  # Build both rv64fd and rv32 emulators.
  build_in_repo rocket-chip "${branch}" --isa rv64fd --isa rv32 --cores "${cores}"
}

build_xiangshan() {
  local branch="$1"
  local cores="$2"
  # XiangShan is optional; its build script and presets evolve quickly. Keep this
  # minimal and let the repo decide defaults.
  build_in_repo XiangShan "${branch}" --cores "${cores}"
}

build_set() {
  local branch="$1"
  local cores="$2"

  contains_core picorv32 && build_picorv32 "${branch}" "${cores}"
  contains_core kronos && build_kronos "${branch}" "${cores}"
  contains_core ibex && build_ibex "${branch}" "${cores}"
  contains_core VexRiscv && build_vexriscv "${branch}" "${cores}"
  contains_core cva6 && build_cva6 "${branch}" "${cores}"
  contains_core rocket-chip && build_rocket_chip "${branch}" "${cores}"
  if (( WITH_XIANGSHAN )); then
    contains_core XiangShan && build_xiangshan "${branch}" "${cores}"
  fi
}

echo "OUT_DIR=${OUT_DIR}"
echo "LOG_DIR=${LOG_DIR}"
echo "CORES=${CORES_MODE}"
echo "ONLY=${ONLY_LIST:-<all>}"
echo "COVERAGE=${COV_MODE}"
echo "XIANGSHAN=$([[ ${WITH_XIANGSHAN} -eq 1 ]] && echo on || echo off)"
echo

if [[ "${CORES_MODE}" == "1" || "${CORES_MODE}" == "both" ]]; then
  build_set "cx-build" "1"
fi

if [[ "${CORES_MODE}" == "2" || "${CORES_MODE}" == "both" ]]; then
  build_set "cx-2hart-build" "2"
fi

echo
echo "Artifacts:"
ls -1 "${OUT_DIR}" | sed -n '1,200p'
