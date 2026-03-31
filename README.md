# cx-riscv-cores

这个仓库用于**统一收集** HardwareFuzz 组织下多个 RISC-V 核的 `cx-*` 分支，并提供**一键构建脚本**把所有构建产物归档到一个统一输出目录。

目前纳入的实现（作为 submodule）：

- `picorv32`
- `kronos`
- `ibex`
- `VexRiscv`
- `cva6`
- `rocket-chip`
- `XiangShan`

## Submodule 的 `cx-*` 分支设计

这个仓库的一级 submodule 都来自 `HardwareFuzz/*` fork。顶层仓库负责 pin 每个 submodule 的具体 commit，保证 clone 后的状态可复现；而各 submodule 自身则约定维护一组配套的 `cx-*` 分支，用来承载不同阶段/目标的构建适配。

约定中的三个核心分支是：

- `cx-log`：最早的统一化/日志化基线，作为后续构建分支的共同祖先
- `cx-build`：1 核构建分支，也是 `.gitmodules` 中为所有一级 submodule 配置的默认 `branch`
- `cx-2hart-build`：2 核构建分支，供双核构建路径使用

这套设计的含义是：

- 顶层仓库的 submodule commit 才是“当前版本”的最终定义；`.gitmodules` 里的 `branch = cx-build` 只是默认远端跟踪分支，不代表仓库只支持 `cx-build`
- `git submodule update --remote` 默认只会沿着 `cx-build` 前进，因此它适合更新 1 核默认基线，不适合作为“切到 2 核版本”的方法
- 1 核/2 核的构建差异尽量收敛在各个 core 自己的 `cx-build` / `cx-2hart-build` 中，顶层脚本只负责统一 checkout、调用 `build.sh`、归档产物

当前一级 submodule 的分支拓扑约定是：

- `picorv32`、`kronos`、`ibex`、`VexRiscv`、`cva6`、`rocket-chip` 目前基本都是线性继承：`cx-log -> cx-build -> cx-2hart-build`
- `XiangShan` 不是简单线性关系：`cx-log` 仍然是共同祖先，但 `cx-build` 和 `cx-2hart-build` 是从共享的 build 基线分叉出来的兄弟分支，而不是前者 fast-forward 到后者

这对使用 `scripts/build_all.sh` 的影响是：

- `--cores 1`：会把每个一级 submodule checkout 到 `origin/cx-build`
- `--cores 2`：会把每个一级 submodule checkout 到 `origin/cx-2hart-build`
- `--cores both`：会先跑 `cx-build`，再跑 `cx-2hart-build`，因此脚本结束后本地 submodule 工作树通常停在 `cx-2hart-build`
- 脚本内部使用 `git checkout -B <branch> origin/<branch>`；如果 submodule 里有未提交修改且与切换冲突，构建会失败，需要先处理本地改动

## Quick start

```bash
git clone --recurse-submodules https://github.com/HardwareFuzz/cx-riscv-cores.git
cd cx-riscv-cores

# 统一输出目录（推荐）
export CX_OUT_DIR="$PWD/artifacts"

# 构建所有实现（默认包含香山；默认矩阵为 minimal）
./scripts/build_all.sh
```

构建结束后，产物会在 `artifacts/` 下，命名规则统一为：

`<core>_<isa>[_<tag>]_<N>c[_cov|_cov_light]`

例如：`rocket-chip_rv64fd_2c`、`ibex_rv32imc_1c`、`cva6_rv32_1c`。
香山会额外带可选的 `tag`（例如 `aligned/unaligned`）：`xiangshan_rv64_unaligned_1c`。

## 常用参数

```bash
# 只构建 1 核（cx-build）
./scripts/build_all.sh --cores 1

# 只构建 2 核（cx-2hart-build）
./scripts/build_all.sh --cores 2

# 同时构建 1 核 + 2 核（默认）
./scripts/build_all.sh --cores both

# 构建“全组合矩阵”（所有 core 支持的 ISA / 香山 preset 组合）
./scripts/build_all.sh --matrix all

# 清理后构建
./scripts/build_all.sh --clean

# 指定输出目录（等价于设置 CX_OUT_DIR）
./scripts/build_all.sh --out-dir /abs/path/to/artifacts

# 开启覆盖率构建
./scripts/build_all.sh --coverage
./scripts/build_all.sh --coverage-light

# 跳过香山（默认构建）
./scripts/build_all.sh --skip-xiangshan

# 只构建某些 core（逗号分隔；大小写不敏感）
./scripts/build_all.sh --only picorv32,kronos,ibex,vexriscv

# 只构建指定 ISA（支持 shell glob；注意要加引号）
./scripts/build_all.sh --matrix all --isa rv64fd
./scripts/build_all.sh --matrix all --isa 'rv32*'

# 香山 preset 选择
./scripts/build_all.sh --only xiangshan --xiangshan-preset both

# 只打印将要执行的命令，不实际执行
./scripts/build_all.sh --dry-run
```

## 依赖说明（简述）

> 说明：这里列的是**用于运行各子仓库 `build.sh` 的依赖**（主要是 Verilator 仿真器/emu 产物）。
> 不包含“跑完整回归/跑 FPGA/跑 Linux 镜像”等更重的上游依赖集合。

### 版本基线（本仓库开发机已验证）

下面这些版本组合在本机上跑通过（仅供你对齐环境时参考）：

- OS：Ubuntu 24.04（x86_64）
- `git` 2.43.0
- `bash` 5.2.21
- `make` 4.3
- `gcc/g++` 13.3.0
- `clang/clang++` 18.1.3
- `cmake` 3.28.3
- `ninja` 1.11.1
- `python3` 3.12.3
- `java` OpenJDK 21.0.10
- `verilator` 5.040
- `mill` 0.11.13
- `firtool` (CIRCT) 1.56.1（LLVM 18）
- RISC-V toolchain（用于部分 repo）：`riscv64-unknown-elf-gcc` 15.1.0

### 通用依赖（所有/大部分 core 都会用到）

- `git`（建议 ≥ 2.25）：用于 clone / submodule / fetch
- `bash`（建议 ≥ 4.0）：构建脚本
- C/C++ 构建工具链：`make` + `gcc/g++`（或等价 clang）
- `verilator`：多个 core 都是 Verilator 仿真可执行体
  - 若要用 `--coverage` / `--coverage-light`，需要 Verilator 启用 coverage 支持并支持对应参数
- 足够的磁盘/内存：`--matrix all` 会拉起多个重编译，缓存（Scala/Coursier、Verilator obj）会占用较多空间

### 各实现依赖（按 core 拆分）

#### `picorv32`

- 依赖：`verilator`、`make`、`g++`
- 备注：仅支持 `--isa rv32`

#### `kronos`

- 依赖：`cmake`（脚本中声明需要 ≥ 3.10）、`verilator`、`make`、`g++`
- 额外：RISC-V GCC toolchain（至少要有其一）
  - `riscv32-unknown-elf-gcc` 或 `riscv64-unknown-elf-gcc`
  - 仅安装了 `riscv64-unknown-elf-*` 时，脚本会在 build 目录创建 `riscv32-unknown-elf-*` 的 shim

#### `ibex`

- 依赖：`python3`（含 `venv`）、`pip`、`verilator`、`make`、`g++`
- Python 包：脚本会创建 `./.venv`，并安装 `python-requirements.txt` 中的依赖
  - 其中 `fusesoc == 2.4.3` 是显式 pin 的版本（见 `ibex/python-requirements.txt`）
- 备注：首次构建可能会用到网络（pip 下载依赖）

#### `VexRiscv`

- 依赖：`java`（建议用 JDK 17+；本机用 JDK 21 验证）、`verilator`、`make`、`g++`
- Scala/SBT：
  - repo pin 的 sbt 版本：`sbt.version=1.6.0`（见 `VexRiscv/project/build.properties`）
  - `build.sh` 默认会下载一个 `sbt-extras` wrapper 到 `./.sbtw`（需要 `curl` + 网络），并通过 Maven 拉依赖（需要网络）

#### `cva6`

- 依赖：`verilator`、`make`、`g++`
- 备注：上游 README 里有更完整的 toolchain/Spike/Verilator 固定版本流程；我们这里的 `build.sh` 只覆盖“生成可执行仿真器”这条轻量路径

#### `rocket-chip`

- 依赖：`mill`、`java`、`verilator`、`firtool`、`cmake`、`ninja`、`clang/clang++`
  - `mill`：上游 README 的 BSP 示例里出现过 `millVersion: 0.10.9`；本机用 `mill 0.11.13` 验证通过
  - `verilator`：本机用 5.040 验证；仓库内 `verilator.hash` 记录了 `4.226`（用于 Nix 环境 pin）
  - `firtool`：需要 CIRCT 的 `firtool`（本机 `firtool-1.56.1`）
- 环境变量：需要能找到 `fesvr` 头文件/库（脚本提示 `RISCV` 或 `SPIKE_ROOT`）
- 备注：这是最“重”的一类构建；建议预留较长时间和足够磁盘

#### `XiangShan`

- 依赖：`mill`、`java`、`verilator`、`make`、`g++`
  - `mill`：仓库内有 `.mill-version`，当前为 `0.12.15`（建议安装/使用能尊重 `.mill-version` 的 mill launcher/wrapper）
- 备注：首次构建会通过 Coursier 拉 Scala 依赖（需要网络）

### 常用版本检查命令

```bash
verilator --version
mill --version
firtool --version | head -n 5
java -version
python3 --version
cmake --version
ninja --version
```

脚本不会帮你安装系统依赖，只会把每个子仓库的 `build.sh` 跑起来并统一归档产物。
