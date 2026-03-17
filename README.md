# cx-riscv-cores

这个仓库用于**统一收集** HardwareFuzz 组织下多个 RISC-V 核的 `cx-*` 分支，并提供**一键构建脚本**把所有构建产物归档到一个统一输出目录。

目前纳入的实现（作为 submodule）：

- `picorv32`
- `kronos`
- `ibex`
- `VexRiscv`
- `cva6`
- `rocket-chip`
- `XiangShan`（默认不构建；需要显式打开）

## Quick start

```bash
git clone --recurse-submodules https://github.com/HardwareFuzz/cx-riscv-cores.git
cd cx-riscv-cores

# 统一输出目录（推荐）
export CX_OUT_DIR="$PWD/artifacts"

# 构建所有实现（默认：跳过香山）
./scripts/build_all.sh
```

构建结束后，产物会在 `artifacts/` 下，命名规则统一为：

`<core>_<isa>_<N>c[_cov|_cov_light]`

例如：`rocket-chip_rv64fd_2c`、`ibex_rv32imc_1c`、`cva6_rv32_1c`。

## 常用参数

```bash
# 只构建 1 核（cx-build）
./scripts/build_all.sh --cores 1

# 只构建 2 核（cx-2hart-build）
./scripts/build_all.sh --cores 2

# 同时构建 1 核 + 2 核（默认）
./scripts/build_all.sh --cores both

# 清理后构建
./scripts/build_all.sh --clean

# 指定输出目录（等价于设置 CX_OUT_DIR）
./scripts/build_all.sh --out-dir /abs/path/to/artifacts

# 开启覆盖率构建
./scripts/build_all.sh --coverage
./scripts/build_all.sh --coverage-light

# 包含香山（默认跳过）
./scripts/build_all.sh --with-xiangshan

# 只构建某些 core（逗号分隔；大小写不敏感）
./scripts/build_all.sh --only picorv32,kronos,ibex,vexriscv

# 只打印将要执行的命令，不实际执行
./scripts/build_all.sh --dry-run
```

## 依赖说明（简述）

不同核的构建依赖不同，常见包括：

- `verilator`
- `cmake` / `ninja`
- `python3`（`ibex` 会创建 venv 并安装依赖）
- `java17` / `sbt`（`VexRiscv`）
- `mill` / `firtool`（`rocket-chip`）

脚本不会帮你安装系统依赖，只会把每个子仓库的 `build.sh` 跑起来并统一归档产物。
