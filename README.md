# cx-riscv-cores

`cx-riscv-cores` 是 HardwareFuzz 的统一 RISC-V core 构建仓库。

这个仓库只负责两件事：

- 构建、下载、上传各个 core 的 wrapper/runtime 产物
- 生成并永久安装 `CX_RISCV_CORES_*` 环境变量

`riscv-fuzz-test` 已经不再维护自己的 `riscv_impls_bins/`、wrapper 下载脚本、wrapper 上传脚本或旧的 `RISCV_WRAPPER_*` 环境变量。现在唯一的 bin/runtime 来源就是这个仓库。

## 这个仓库产出什么

统一产物目录是 `artifacts/`，默认命名规则是：

```text
<artifact basename> -> CX_RISCV_CORES_<UPPER_SNAKE_BASENAME>
```

例如：

- `cva6_rv32_1c` -> `CX_RISCV_CORES_CVA6_RV32_1C`
- `rocket-chip_rv64fd_2c` -> `CX_RISCV_CORES_ROCKET_CHIP_RV64FD_2C`
- `xiangshan_difftest_rv64_2c_so` -> `CX_RISCV_CORES_XIANGSHAN_DIFFTEST_RV64_2C_SO`

除了 wrapper 二进制，这个仓库还会把香山运行时依赖一并放进 `artifacts/`：

- `xiangshan_difftest_rv64_1c_so`
- `xiangshan_difftest_rv64_2c_so`

这样消费侧只需要依赖一个目录，不需要再去单独扫描 `ready-to-run/`。

## 快速开始：下载预构建 bin

如果你只是想拿到当前 release 的可用 bin，这是推荐流程。

### 1. 克隆仓库

```bash
git clone --recurse-submodules https://github.com/HardwareFuzz/cx-riscv-cores.git
cd cx-riscv-cores
```

### 2. 准备 GitHub CLI

下载 release 资产依赖 `gh`：

```bash
gh auth login
gh auth status
```

### 3. 下载 release 里的所有产物

```bash
./scripts/download_release_artifacts.sh
```

默认会下载 `dev-release` 的全部资产到：

- `./artifacts`

如果你只想下载部分模式：

```bash
./scripts/download_release_artifacts.sh 'rocket-chip_*' 'xiangshan_*'
```

如果你想改 release tag：

```bash
export CX_RISCV_CORES_RELEASE_TAG=my-tag
./scripts/download_release_artifacts.sh
```

### 4. 永久安装环境变量

```bash
./scripts/install_env.sh
source ~/.bashrc
```

这个脚本会：

- 生成 `~/.config/cx-riscv-cores/env.sh`
- 向 `~/.bashrc` 写入 source block
- 向 `~/.profile` 写入 source block
- 如果存在 `~/.zshrc`，也会写入 source block

### 5. 验证环境变量

```bash
env | rg '^CX_RISCV_CORES_' | sed -n '1,40p'
```

你应该能看到类似：

- `CX_RISCV_CORES_ARTIFACT_DIR=.../cx-riscv-cores/artifacts`
- `CX_RISCV_CORES_CVA6_RV64_2C=.../artifacts/cva6_rv64_2c`
- `CX_RISCV_CORES_ROCKET_CHIP_RV64FD_2C=.../artifacts/rocket-chip_rv64fd_2c`
- `CX_RISCV_CORES_XIANGSHAN_DIFFTEST_RV64_2C_SO=.../artifacts/xiangshan_difftest_rv64_2c_so`

## 快速开始：从源码构建 bin

如果你不想下载 release，而是希望自己重建 wrapper，可以这样做。

### 1. 克隆仓库

```bash
git clone --recurse-submodules https://github.com/HardwareFuzz/cx-riscv-cores.git
cd cx-riscv-cores
```

### 2. 配置统一输出目录

推荐显式设置 `CX_OUT_DIR`：

```bash
export CX_OUT_DIR="$PWD/artifacts"
```

### 3. 一键构建

```bash
./scripts/build_all.sh
```

脚本默认会：

- 统一切换各 submodule 到对应的 `cx-*` 构建分支
- 构建默认矩阵下的 1hart / 2hart wrapper
- 自动把香山 difftest `.so` stage 到 `artifacts/`

### 4. 永久安装环境变量

```bash
./scripts/install_env.sh
source ~/.bashrc
```

## 环境变量模型

这个仓库导出的环境变量有三类：

- `CX_RISCV_CORES_ROOT`
- `CX_RISCV_CORES_ARTIFACT_DIR`
- `CX_RISCV_CORES_<ARTIFACT_NAME>`

生成规则由 `./scripts/generate_env.sh` 实现。这个脚本本身不修改 shell 配置，只是把 `export ...` 打到 stdout：

```bash
./scripts/generate_env.sh
./scripts/generate_env.sh --artifact-dir /abs/path/to/artifacts
```

如果你只想在当前 shell 临时生效：

```bash
source ~/.config/cx-riscv-cores/env.sh
```

如果你想改用别的产物目录：

```bash
./scripts/install_env.sh --artifact-dir /abs/path/to/artifacts
source ~/.bashrc
```

注意：

- 这里不保留任何 `RISCV_WRAPPER_*` 兼容
- `CX_RISCV_CORES_SPIKE` 不由本仓库构建产出
- `install_env.sh` / `generate_env.sh` 会尝试从 `PATH` 解析 `spike`
- 如果系统里没有 `spike`，这个变量不会被导出

## 下载、上传、发布

这个仓库是 release 资产的唯一管理入口。

### 下载

```bash
./scripts/download_release_artifacts.sh
./scripts/download_release_artifacts.sh 'ibex_*' 'kronos_*'
```

### 上传

```bash
./scripts/upload_release_artifacts.sh
```

上传脚本会：

- 先把香山 runtime support stage 到 `artifacts/`
- 计算每个资产的 sha256
- 维护 `cx_riscv_cores_artifacts_manifest.json`
- 只上传发生变化的文件

可用的发布环境变量：

- `CX_RISCV_CORES_RELEASE_TAG`
- `CX_RISCV_CORES_RELEASE_TITLE`
- `CX_RISCV_CORES_RELEASE_NOTES`
- `CX_RISCV_CORES_RELEASE_MANIFEST`

## 常用构建命令

### 全量默认构建

```bash
./scripts/build_all.sh
```

### 只构建 1hart

```bash
./scripts/build_all.sh --cores 1
```

### 只构建 2hart

```bash
./scripts/build_all.sh --cores 2
```

### 同时构建 1hart 和 2hart

```bash
./scripts/build_all.sh --cores both
```

### 只构建部分 core

```bash
./scripts/build_all.sh --only picorv32,kronos,ibex,vexriscv
```

### 只构建香山

```bash
./scripts/build_all.sh --only xiangshan --xiangshan-preset both
```

### 指定输出目录

```bash
./scripts/build_all.sh --out-dir /abs/path/to/artifacts
```

### 开启覆盖构建

```bash
./scripts/build_all.sh --coverage
./scripts/build_all.sh --coverage-light
```

### 只打印命令，不实际执行

```bash
./scripts/build_all.sh --dry-run
```

## 构建依赖

如果你只下载 release bin，可以只安装：

- `git`
- `gh`
- `bash`

如果你要从源码完整构建，通常还需要：

- `make`
- `gcc` / `g++`
- `clang` / `clang++`
- `cmake`
- `ninja`
- `python3`
- `java`
- `verilator`
- `mill`
- `firtool`
- RISC-V toolchain

不同 core 自身还可能带有额外依赖；顶层仓库只负责统一调度和产物归档。

## 故障排除

### 下载或构建后看不到新的环境变量

重新执行：

```bash
./scripts/install_env.sh
source ~/.bashrc
```

### 仓库路径变了

`install_env.sh` 生成的是绝对路径导出。只要你移动了仓库目录，就应该重新执行一次：

```bash
./scripts/install_env.sh
source ~/.bashrc
```

### 想确认当前 shell 实际吃到的是哪个 env 文件

```bash
ls -l ~/.config/cx-riscv-cores/env.sh
grep -n "cx-riscv-cores" ~/.bashrc ~/.profile ~/.zshrc 2>/dev/null
```

### `CX_RISCV_CORES_SPIKE` 没有出现

先确认系统里有 `spike`：

```bash
command -v spike
```

如果没有，就先把 `spike` 装到 `PATH` 里，再重新执行：

```bash
./scripts/install_env.sh
source ~/.bashrc
```
