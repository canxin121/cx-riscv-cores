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
  --matrix <minimal|all>
                        Variant matrix to build (default: minimal)
                        - minimal: fast defaults per core
                        - all: build all supported ISA/preset combinations
  --isa PATTERN         Limit ISA tags to build. May be specified multiple times.
                        Supports shell globs (quote if needed), e.g. --isa 'rv32*'
  --only a,b,c          Only build selected cores (comma-separated, case-insensitive).
                        Supported: picorv32,kronos,ibex,vexriscv,cva6,rocket-chip,xiangshan
  --skip-xiangshan      Skip XiangShan (default: build)
  --with-xiangshan      (legacy) Include XiangShan (default: build)
  --xiangshan-preset <default|aligned|unaligned|both|all>
                        XiangShan preset selection (default: auto from --matrix)
                        - default: no preset (TLConfig)
                        - aligned / unaligned: build that preset only
                        - both: aligned + unaligned
                        - all: default + aligned + unaligned
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
MATRIX_MODE="minimal" # minimal|all
ISA_FILTERS=()
ONLY_LIST=""
WITH_XIANGSHAN=1
XIANGSHAN_PRESET_MODE="auto" # auto|default|aligned|unaligned|both|all
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
    --matrix)
      [[ $# -ge 2 ]] || die "--matrix requires a value"
      MATRIX_MODE="$2"; shift 2 ;;
    --matrix=*)
      MATRIX_MODE="${1#*=}"; shift ;;
    --all)
      MATRIX_MODE="all"; shift ;;
    --isa)
      [[ $# -ge 2 ]] || die "--isa requires a value"
      IFS=',' read -r -a _tmp_isas <<<"$2"
      for _isa in "${_tmp_isas[@]}"; do
        _isa="${_isa,,}"
        _isa="${_isa//[[:space:]]/}"
        [[ -n "$_isa" ]] && ISA_FILTERS+=("$_isa")
      done
      shift 2 ;;
    --isa=*)
      _val="${1#*=}"
      IFS=',' read -r -a _tmp_isas <<<"$_val"
      for _isa in "${_tmp_isas[@]}"; do
        _isa="${_isa,,}"
        _isa="${_isa//[[:space:]]/}"
        [[ -n "$_isa" ]] && ISA_FILTERS+=("$_isa")
      done
      shift ;;
    --skip-xiangshan) WITH_XIANGSHAN=0; shift ;;
    --with-xiangshan) WITH_XIANGSHAN=1; shift ;;
    --xiangshan-preset)
      [[ $# -ge 2 ]] || die "--xiangshan-preset requires a value"
      XIANGSHAN_PRESET_MODE="${2,,}"; shift 2 ;;
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

case "${MATRIX_MODE}" in
  minimal|all) ;;
  *) die "--matrix must be one of: minimal, all (got: ${MATRIX_MODE})" ;;
esac

case "${XIANGSHAN_PRESET_MODE}" in
  auto|default|aligned|unaligned|both|all) ;;
  *) die "--xiangshan-preset must be one of: auto, default, aligned, unaligned, both, all (got: ${XIANGSHAN_PRESET_MODE})" ;;
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

cov_suffix() {
  case "${COV_MODE}" in
    none) echo "" ;;
    full) echo "_cov" ;;
    light) echo "_cov_light" ;;
    *) die "internal: unknown coverage mode ${COV_MODE}" ;;
  esac
}

log_tag_from_args() {
  local -a args=("$@")
  local -a isas=()
  local preset=""
  local cores=""

  for ((i=0; i<${#args[@]}; i++)); do
    case "${args[$i]}" in
      --isa)
        if (( i + 1 < ${#args[@]} )); then
          isas+=("${args[$((i+1))],,}")
          ((i++))
        fi
        ;;
      --preset)
        if (( i + 1 < ${#args[@]} )); then
          preset="${args[$((i+1))],,}"
          ((i++))
        fi
        ;;
      --cores)
        if (( i + 1 < ${#args[@]} )); then
          cores="${args[$((i+1))]}"
          ((i++))
        fi
        ;;
    esac
  done

  local tag=""
  if [[ -n "${cores}" ]]; then
    tag+="cores-${cores}"
  fi
  if (( ${#isas[@]} > 0 )); then
    [[ -n "${tag}" ]] && tag+="_"
    tag+="isa-$(IFS=+; echo "${isas[*]}")"
  fi
  if [[ -n "${preset}" ]]; then
    [[ -n "${tag}" ]] && tag+="_"
    tag+="preset-${preset}"
  fi
  [[ -n "${tag}" ]] || tag="default"

  tag="${tag// /_}"
  tag="${tag//\//_}"
  tag="${tag//:/_}"
  echo "${tag}"
}

isa_aliases_for_core() {
  local core="$1"
  local isa="${2,,}"
  case "${core}" in
    # CVA6 treats rv64fd as an alias of rv64; accept both in filters.
    cva6)
      case "${isa}" in
        rv64) printf '%s\n' rv64 rv64fd ;;
        *) printf '%s\n' "${isa}" ;;
      esac
      ;;
    *)
      printf '%s\n' "${isa}"
      ;;
  esac
}

isa_selected() {
  local core="$1"
  local isa="$2"

  if (( ${#ISA_FILTERS[@]} == 0 )); then
    return 0
  fi

  local pattern a
  local -a _aliases=()
  mapfile -t _aliases < <(isa_aliases_for_core "${core}" "${isa}")
  for pattern in "${ISA_FILTERS[@]}"; do
    for a in "${_aliases[@]}"; do
      if [[ "${a}" == ${pattern} ]]; then
        return 0
      fi
    done
  done
  return 1
}

filter_isas() {
  local core="$1"
  shift
  local -a candidates=("$@")
  local -a out=()
  for isa in "${candidates[@]}"; do
    if isa_selected "${core}" "${isa}"; then
      out+=("${isa}")
    fi
  done
  printf '%s\n' "${out[@]}"
}

xiangshan_presets() {
  local mode="${XIANGSHAN_PRESET_MODE}"
  if [[ "${mode}" == "auto" ]]; then
    mode="${MATRIX_MODE}"
  fi
  case "${mode}" in
    minimal|default) printf '%s\n' default ;;
    aligned) printf '%s\n' aligned ;;
    unaligned) printf '%s\n' unaligned ;;
    both) printf '%s\n' aligned unaligned ;;
    all) printf '%s\n' default aligned unaligned ;;
    *)
      die "internal: unexpected xiangshan preset mode '${mode}'"
      ;;
  esac
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

  local log_tag
  log_tag="$(log_tag_from_args "$@")"
  local log_file="${LOG_DIR}/${name}_${branch}_${log_tag}.log"
  echo "[build] ${name} (${branch}) ${log_tag} -> ${OUT_DIR}"

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
  local -a candidates=(rv32)
  mapfile -t candidates < <(filter_isas picorv32 "${candidates[@]}")
  if (( ${#candidates[@]} == 0 )); then
    echo "[skip] picorv32: no ISA matches --isa filter"
    return 0
  fi
  build_in_repo picorv32 "${branch}" --isa "${candidates[0]}" --cores "${cores}"
}

build_kronos() {
  local branch="$1"
  local cores="$2"
  local -a candidates=(rv32)
  mapfile -t candidates < <(filter_isas kronos "${candidates[@]}")
  if (( ${#candidates[@]} == 0 )); then
    echo "[skip] kronos: no ISA matches --isa filter"
    return 0
  fi
  build_in_repo kronos "${branch}" --isa "${candidates[0]}" --cores "${cores}"
}

build_ibex() {
  local branch="$1"
  local cores="$2"
  local -a candidates=(rv32imc)
  mapfile -t candidates < <(filter_isas ibex "${candidates[@]}")
  if (( ${#candidates[@]} == 0 )); then
    echo "[skip] ibex: no ISA matches --isa filter"
    return 0
  fi
  build_in_repo ibex "${branch}" --isa "${candidates[0]}" --cores "${cores}"
}

build_vexriscv() {
  local branch="$1"
  local cores="$2"
  local -a candidates=()
  if [[ "${MATRIX_MODE}" == "all" || ${#ISA_FILTERS[@]} -gt 0 ]]; then
    if [[ "${cores}" == "1" ]]; then
      candidates=(rv32 rv32f rv32fd)
    else
      candidates=(rv32 rv32fd)
    fi
  else
    # Default to rv32fd for maximum feature coverage (and 2-core support).
    candidates=(rv32fd)
  fi

  mapfile -t candidates < <(filter_isas VexRiscv "${candidates[@]}")
  if (( ${#candidates[@]} == 0 )); then
    echo "[skip] VexRiscv: no ISA matches --isa filter"
    return 0
  fi
  for isa in "${candidates[@]}"; do
    build_in_repo VexRiscv "${branch}" --isa "${isa}" --cores "${cores}"
  done
}

build_cva6() {
  local branch="$1"
  local cores="$2"
  local -a candidates=()
  if [[ "${MATRIX_MODE}" == "all" || ${#ISA_FILTERS[@]} -gt 0 ]]; then
    candidates=(rv64 rv32 rv32f)
  else
    # Default: build both rv64 and rv32 binaries.
    candidates=(rv64 rv32)
  fi

  mapfile -t candidates < <(filter_isas cva6 "${candidates[@]}")
  if (( ${#candidates[@]} == 0 )); then
    echo "[skip] cva6: no ISA matches --isa filter"
    return 0
  fi

  local -a args=()
  for isa in "${candidates[@]}"; do
    args+=(--isa "${isa}")
  done
  args+=(--cores "${cores}")
  build_in_repo cva6 "${branch}" "${args[@]}"
}

build_rocket_chip() {
  local branch="$1"
  local cores="$2"
  local -a candidates=()
  if [[ "${MATRIX_MODE}" == "all" || ${#ISA_FILTERS[@]} -gt 0 ]]; then
    candidates=(rv64fd rv64f rv64 rv32fd rv32f rv32)
  else
    # Default: build both rv64fd and rv32 emulators.
    candidates=(rv64fd rv32)
  fi

  mapfile -t candidates < <(filter_isas rocket-chip "${candidates[@]}")
  if (( ${#candidates[@]} == 0 )); then
    echo "[skip] rocket-chip: no ISA matches --isa filter"
    return 0
  fi

  local -a args=()
  for isa in "${candidates[@]}"; do
    args+=(--isa "${isa}")
  done
  args+=(--cores "${cores}")
  build_in_repo rocket-chip "${branch}" "${args[@]}"
}

build_xiangshan() {
  local branch="$1"
  local cores="$2"
  local -a isas=()
  if [[ "${MATRIX_MODE}" == "all" || ${#ISA_FILTERS[@]} -gt 0 ]]; then
    isas=(rv64 rv64f rv64fd)
  else
    isas=(rv64)
  fi

  mapfile -t isas < <(filter_isas XiangShan "${isas[@]}")
  if (( ${#isas[@]} == 0 )); then
    echo "[skip] XiangShan: no ISA matches --isa filter"
    return 0
  fi

  local -a presets=()
  mapfile -t presets < <(xiangshan_presets)
  local cov_suf
  cov_suf="$(cov_suffix)"

  for preset in "${presets[@]}"; do
    # Build XiangShan once per preset+core-count, then (optionally) duplicate the
    # resulting binary under additional ISA tags. XiangShan's build.sh documents
    # that --isa currently affects naming only.
    local primary_isa="${isas[0]}"
    local -a args=(--isa "${primary_isa}" --cores "${cores}")
    local preset_tag=""
    if [[ "${preset}" != "default" ]]; then
      args+=(--preset "${preset}")
      preset_tag="_${preset}"
    fi

    if (( CLEAN )); then
      for isa in "${isas[@]}"; do
        local dst="${OUT_DIR}/xiangshan_${isa}${preset_tag}_${cores}c${cov_suf}"
        run rm -f "${dst}"
      done
    fi

    build_in_repo XiangShan "${branch}" "${args[@]}"

    local src="${OUT_DIR}/xiangshan_${primary_isa}${preset_tag}_${cores}c${cov_suf}"
    for isa in "${isas[@]}"; do
      local dst="${OUT_DIR}/xiangshan_${isa}${preset_tag}_${cores}c${cov_suf}"
      if [[ "${dst}" == "${src}" ]]; then
        continue
      fi
      if (( DRY_RUN )); then
        echo "+ cp -f ${src} ${dst}"
      else
        cp -f "${src}" "${dst}"
      fi
    done
  done
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
echo "MATRIX=${MATRIX_MODE}"
echo "ONLY=${ONLY_LIST:-<all>}"
echo "ISA_FILTER=$([[ ${#ISA_FILTERS[@]} -gt 0 ]] && (IFS=,; echo "${ISA_FILTERS[*]}") || echo "<all>")"
echo "COVERAGE=${COV_MODE}"
echo "XIANGSHAN=$([[ ${WITH_XIANGSHAN} -eq 1 ]] && echo on || echo off)"
echo "XIANGSHAN_PRESET=${XIANGSHAN_PRESET_MODE}"
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
