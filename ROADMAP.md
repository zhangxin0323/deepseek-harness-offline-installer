# ROADMAP

本文档记录 DeepSeek Harness 离线安装包的演进计划。

当前版本：**0.2.1-rc.2**（对应标签 `0.2.1-rc.2`）

> 版本约定：本项目不单独编号。Release 标签、包文件名、`manifest.json` 中的版本均直接使用 DeepSeek Harness（dsh）的版本，例如 `0.2.1-rc.2`。

---

## 一、当前状态

- 仅支持 **arm64（aarch64）麒麟 V10**，包内 Node.js、uv、Python 3.11 均为 arm64 构建。
- 打包脚本中 `ARCH="arm64"` 为硬编码，切换到 x86_64 需要手工修改 `make-offline.sh`。
- 产物文件名固定为 `deepseek-harness-user-offline.tar.gz`，安装脚本按固定文件名查找。
- 已内置：Node.js v26.2.0、dsh 0.2.1-rc.2、pnpm、`pptxgenjs@3.12.0`、Python 3.11.16 及预装依赖。
- 已通过 GitHub Release 发布 tar 包与 `install-on-target.sh`。

---

## 二、下一里程碑：按 CPU 架构区分安装包

### 2.1 目标

同一套脚本在 arm64 和 x86_64 上都能：

1. **自动识别**构建机/目标机架构，不再手工改 `ARCH`；
2. 生成**文件名带架构**的压缩包，避免把错误架构的包拷到目标机；
3. 安装脚本自动选择匹配当前机器架构的包；
4. 架构不匹配时**在解压前明确报错**，不污染安装目录。

### 2.2 命名规范

| 目标架构 | `uname -m` | Node 标识 | uv/Python 标识 | 包名 |
| --- | --- | --- | --- | --- |
| ARM64 | `aarch64` / `arm64` | `arm64` | `aarch64` | `deepseek-harness-user-offline-linux-arm64.tar.gz` |
| x86_64 | `x86_64` / `amd64` | `x64` | `x86_64` | `deepseek-harness-user-offline-linux-x86_64.tar.gz` |

可选：在文件名中加入版本号，例如：

```text
deepseek-harness-user-offline-0.2.1-rc.2-linux-arm64.tar.gz
deepseek-harness-user-offline-0.2.1-rc.2-linux-x86_64.tar.gz
```

版本号直接取 dsh 版本（与 Git 标签一致），由 `DSH_VERSION` 变量注入，不维护独立的包版本；若希望文件名保持稳定，可只保留架构后缀，版本以 Release 标签区分。

### 2.3 自动识别逻辑

**打包脚本 `make-offline.sh`**

1. 新增 `TARGET_ARCH`，默认取 `uname -m`：
   ```bash
   TARGET_ARCH="${TARGET_ARCH:-$(uname -m)}"
   ```
2. 归一化：
   - `aarch64` / `arm64` → `arm64`
   - `x86_64` / `amd64` → `x86_64`
3. 分别映射到各组件命名：
   - Node：`arm64` 或 `x64`
   - uv：`aarch64` 或 `x86_64`
   - 包名：`arm64` 或 `x86_64`
4. 检测交叉构建：当 `TARGET_ARCH` 与 `uname -m` 不一致时给出警告。由于 Python wheel、Node 预编译包和 uv 都按架构分发，**默认只支持本机构建**；跨架构需使用对应架构的构建机或容器。
5. 输出文件自动带架构后缀，并生成对应的 `SHA256SUMS`。

**安装脚本 `install-on-target.sh`**

1. 用 `uname -m` 做同样的归一化，得到 `PKG_ARCH`。
2. 按优先级查找安装包：
   ```text
   deepseek-harness-user-offline-linux-${PKG_ARCH}.tar.gz
   deepseek-harness-user-offline-${PKG_ARCH}.tar.gz
   deepseek-harness-user-offline.tar.gz          # 旧包，兼容一个版本
   ```
3. 若同目录存在多个架构的包，只选择与当前架构匹配的那一个。
4. 支持 `--arch <arm64|x86_64>` 或 `TARGET_ARCH` 覆盖自动识别（用于特殊场景）。
5. 找不到匹配包时，列出当前目录中检测到的包名与架构，提示用户下载正确版本。

### 2.4 包内架构清单

在包根目录新增 `manifest.json`，安装前读取校验：

```json
{
  "schema": 1,
  "dsh_version": "0.2.1-rc.2",
  "target_arch": "arm64",
  "built_at": "2026-10-29T12:35:14+08:00",
  "node": "v26.2.0",
  "python": "3.11.16",
  "python_venv": "python-venv"
}
```

安装脚本校验 `manifest.target_arch` 与当前机器一致后才解压；不一致直接退出，并提示应下载的包名。

### 2.5 验收标准

- [ ] 在 arm64 机器执行 `bash make-offline.sh`，生成 `deepseek-harness-user-offline-linux-arm64.tar.gz`。
- [ ] 在 x86_64 机器执行同一脚本，生成 `deepseek-harness-user-offline-linux-x86_64.tar.gz`，无需手工改代码。
- [ ] 两种包分别能在同架构目标机完成安装，`dsh web` 与 Python 环境冒烟测试通过。
- [ ] 把 arm64 包拷到 x86_64 机器执行安装脚本，脚本在**解压前**报错，安装目录保持不变。
- [ ] 安装脚本能自动选择同目录中与当前架构匹配的包。
- [ ] Release 同时上传两个架构的包及各自校验和，README 说明下载哪一个。
- [ ] 旧文件名 `deepseek-harness-user-offline.tar.gz` 仍可安装，但打印弃用提示。

### 2.6 任务拆解

- [ ] 抽出架构归一化与组件映射函数，供打包、安装脚本共用（可生成一段共享 shell 片段）。
- [ ] `make-offline.sh`：用 `TARGET_ARCH` 替换硬编码 `ARCH`，产物名带架构。
- [ ] 生成 `manifest.json`，写入包根目录并随包发布。
- [ ] `install-on-target.sh`：自动识别架构、按架构查找包、校验 manifest。
- [ ] 错误提示：列出目录中现有包及其架构，给出正确下载链接。
- [ ] `SHA256SUMS` 按架构生成，作为 Release 资产上传。
- [ ] README / README_EN 增加“下载哪个包”的架构选择说明。
- [ ] Release 流程改为一次构建两个架构并上传 4 个资产（2 包 + 2 校验文件）。

---

## 三、后续 Backlog

- **CI 构建矩阵**：arm64 / x86_64 runner 自动构建、冒烟测试并发布 Release，避免手工打包。
- **依赖锁定**：用 `uv.lock` 或带哈希的 requirements 固定 Python 包版本，保证可复现构建。
- **系统依赖可选包**：将 `tesseract`、`pandoc`、Graphviz 等系统可执行文件做成可选离线依赖包，或提供 `dsh-doctor` 自检命令。
- **包体拆分**：把 Python 环境拆成可选组件（基础包 / 数据科学包），减小主包体积。
- **安装自检**：安装后自动执行 Python 导入、`dsh --version`、端口可用性检查，并输出诊断报告。
- **升级与回滚**：保留上一版本运行时目录，支持 `dsh-web --rollback`。
- **校验与签名**：Release 资产提供 SHA256 与 GPG/minisign 签名。
- **文档国际化**：ROADMAP 提供英文版本，与 README_EN 同步。

---

## 四、非目标

- 不引入需要 root/sudo 的安装步骤。
- 不要求目标机联网；所有依赖仍随包提供。
- 不在目标机现场编译 Python 包或 Node 原生模块。
