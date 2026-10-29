# DeepSeek Harness 离线安装包

面向**内网麒麟 V10 桌面（arm64）**的 DeepSeek Harness Web 版一键离线部署包。

- **免联网**：Node.js、dsh、pnpm 与 Python 环境全部内置，安装过程不访问外网。
- **免 sudo**：全部安装在当前用户目录，不修改系统文件。
- **开箱即用**：安装后桌面会出现「DeepSeek Harness」图标，双击即可启动并打开浏览器。
- **自带 Python 3.11**：预装文档处理、数据分析、绘图、数据库等常用库，开箱即可运行 Python 工具。

| 组件 | 版本 |
| --- | --- |
| Node.js | v26.2.0（linux-arm64） |
| dsh（`@deepseek-ai/dsh`） | 0.2.1-rc.2 |
| pnpm | 12.16.1 |
| Python | 3.11.16（uv 托管，独立于系统 Python） |

---

## 一、包内容

| 文件 | 大小 | 说明 |
| --- | --- | --- |
| `deepseek-harness-user-offline.tar.gz` | 约 760 MB | 自包含运行时包（解压后约 2.7 GB），含 Node.js + dsh + pnpm + Python 3.11 环境 + 桌面图标 |
| `install-on-target.sh` | 6 KB | **目标机**上执行的安装脚本（免 sudo） |
| `make-offline.sh` | 15 KB | 在**联网打包机**上重新生成离线包的脚本 |
| `node-v26.2.0-linux-arm64.tar.xz` | 31 MB | Node.js 官方预编译包，仅打包时需要，目标机不需要 |
| `uv-aarch64-unknown-linux-gnu.tar.gz` | 18 MB | uv 独立二进制，用于创建 Python 3.11 环境，仅打包时需要 |
| `icon.jpeg` | 5 KB | 桌面启动图标 |
| `README.md` / `README_EN.md` | — | 中文 / 英文说明 |

> 目标机只需要 **`deepseek-harness-user-offline.tar.gz` + `install-on-target.sh`** 两个文件即可完成安装；其余文件可留在打包机上。

---

## 二、环境要求

- 操作系统：麒麟 V10（`aarch64`），glibc ≥ 2.28（V10 自带 2.31，满足要求）。
- 磁盘空间：安装目录约需 2.7 GB（Node/dsh 约 1.4 GB + Python 运行时约 95 MB + 预装依赖约 1.2 GB）；拷贝与解压期间建议预留 4 GB。
- 权限：普通用户即可，**无需 root / sudo**。
- 桌面环境：GNOME / MATE / UKUI 等支持 `.desktop` 快捷方式的桌面均可。

> **x86_64 机器**：本包内置的是 arm64 版 Node.js，不能在 x86_64 上运行。请参考[第七节](#七从联网机器重新打包)把 `ARCH` 改为 `x64` 后重新打包。

---

## 三、快速开始（目标机）

### 1. 拷贝文件

把 `deepseek-harness-user-offline.tar.gz` 和 `install-on-target.sh` 拷贝到麒麟机的**同一目录**，例如 `~/下载/dsh-offline/`。

### 2. 执行安装

```bash
cd ~/下载/dsh-offline        # 必须进入该目录：脚本按相对路径查找 tar 包
bash install-on-target.sh
```

看到 `✓ 安装完成。` 即表示成功。整个过程约 2–5 分钟，主要耗时在解压约 2.7 GB 的运行时。

### 3. 启动

- **推荐**：双击桌面上的 **「DeepSeek Harness」** 图标。
- 或在终端执行：

```bash
dsh-web        # 等价于 dsh web，额外参数会原样透传
```

启动后会弹出一个终端窗口，提示“请不要关闭此窗口”，随后自动打开浏览器访问：

```
http://127.0.0.1:3080
```

> 该终端窗口就是 dsh 服务的宿主进程。关闭窗口或按 `Ctrl+C` 都会停止服务，浏览器随即无法访问。

### 4. 配置模型

首次使用需要在 Web 界面里接入模型：

1. 打开 **设置（Settings）→ Models**；
2. 添加一个**自定义提供方（Custom Provider）**；
3. 填入内网 OpenAI 兼容端点，例如 `http://10.0.0.5:8000/v1`，以及 API Key 和模型名；
4. 保存后即可在会话中选择该模型。

---

## 四、安装器做了什么

安装脚本只改动当前用户目录：

| 动作 | 位置 |
| --- | --- |
| 解压运行时（去掉顶层目录） | `~/.local/opt/deepseek-harness/` |
| 创建命令软链接 `dsh` / `node` / `pnpm` | `~/.local/bin/` |
| 若 `~/.local/bin` 不在 `PATH`，追加到 | `~/.profile` |
| 初始化 web profile，并追加离线必需的 pnpm 配置 | `~/.dsh/profiles/web/pnpm-workspace.yaml` |
| 修正 Python 环境路径，创建 `dsh-python` / `dsh-pip` | `~/.local/opt/deepseek-harness/python-venv/`、`~/.local/bin/` |
| 生成启动脚本（打印提示后执行 `dsh web`） | `~/.local/bin/dsh-web` |
| 安装桌面图标 | `~/.local/share/icons/deepseek-harness.jpeg` |
| 创建桌面快捷方式并标记为可信 | `~/桌面/dsh-web.desktop`（无中文桌面目录时为 `~/Desktop/`） |

其中写入 `pnpm-workspace.yaml` 的两行配置用于**离线安装插件**：

```yaml
minimumReleaseAge: 0            # 关闭 pnpm>=11 的供应链延迟检查
dangerouslyAllowAllBuilds: true # 放行插件构建脚本
```

安装后的目录结构：

```
~/.local/opt/deepseek-harness/
├── node/                     # Node.js 运行时
│   ├── bin/{node,npm,npx,pnpm,dsh}
│   └── lib/node_modules/     # 全局包：@deepseek-ai/dsh、pnpm
├── python/                   # uv 托管的 Python 3.11 运行时
├── python-venv/              # 预装全部依赖的虚拟环境
│   └── PYTHON_ENV.txt        # 构建时间、Python/uv 版本与 pip freeze 清单
├── python-requirements.txt   # 可读的依赖清单（构建时生成）
├── uv/                       # 随包内置的 uv（可复用）
└── dsh-web-icon.jpeg         # 桌面图标源文件

~/.local/bin/dsh-web          # 启动脚本
~/.local/bin/dsh-python       # Python 3.11（venv）快捷方式
~/.local/bin/dsh-pip          # 对应 venv 的 pip
~/.dsh/                       # 用户数据与配置（与安装包分离，升级不覆盖）
```

### Python 3.11 环境

安装包内置由 [uv](https://github.com/astral-sh/uv) 托管的独立 Python 3.11.16，位于 `python/`，不会覆盖或影响系统自带的 Python。`python-venv/` 中已预先安装以下库（合并为一次 `uv pip install` 完成）：

| 类别 | 软件包 |
| --- | --- |
| 文档 / Office | `markitdown[pptx]` `Pillow` `defusedxml` `lxml` `python-pptx` `python-docx` `openpyxl` `xlrd` `xlsxwriter` `python-calamine` `olefile` `PyMuPDF` `pdfplumber` `pytesseract` `pypandoc` `docxtpl` |
| 数据 / 科学计算 | `pandas` `numpy` `scipy` `chardet` `python-magic` `xlsx2csv` `unstructured` `matplotlib` `seaborn` `plotly` `kaleido` `pygame` |
| 流程图 / 思维导图 | `graphviz` `pygraphviz` `diagrams` `networkx` `xmind` `xmindparser` |
| 数据库 | `psycopg2-binary` `pymongo` `redis` `sqlalchemy` `pymysql` `sqlcipher3` `oracledb` `dmPython`（安装失败不阻断打包） |
| 常用工具 | `requests` `pyyaml` `jinja2` `tabulate` `tqdm` |

使用方式：

```bash
dsh-python -V                    # Python 3.11.16
dsh-python -m pip list           # 查看已安装包
dsh-python your_script.py        # 直接运行脚本
dsh-pip install <package>        # 仅在有内网 PyPI 源时可用

# 或激活虚拟环境
source ~/.local/opt/deepseek-harness/python-venv/bin/activate
```

- dsh 的终端工具默认能通过 `PATH` 找到 `dsh-python`，可直接让 Agent 调用。
- `python/` 与 `python-venv/` 使用 `--relocatable` 构建，安装脚本会在目标机重写 venv 的 `pyvenv.cfg` 与解释器链接，因此换用户名/家目录后仍可用。
- `pytesseract`、`pypandoc`、`graphviz`/`diagrams` 的**渲染**还依赖系统可执行文件 `tesseract`、`pandoc`、`dot`（Graphviz）。这些不属于 pip 包，需在目标机另行安装；仅调用 Python API 时不受影响。
- 环境完全离线，`dsh-pip install` 默认无法访问公网；如需扩充依赖，请先在内网搭建 PyPI 镜像或提前下载 wheel。

---

## 五、日常使用

```bash
dsh-web                 # 启动 Web 服务并打开浏览器
dsh web                 # 同上（dsh-web 的底层命令）
dsh --version           # 查看版本
dsh --profile web --dump-config   # 查看 web profile 的最终配置
```

- 服务默认监听 `127.0.0.1:3080`，仅本机可访问。
- 用户数据（会话、配置、插件）都在 `~/.dsh/`，删除安装目录不会丢失数据，但删除 `~/.dsh/` 会清空所有配置。
- 插件市场在离线环境下无法访问公共 registry；如需安装插件，请提前把 tarball 放入内网源或本地目录后再用 pnpm 安装。

---

## 六、升级与卸载

### 升级

直接用新版 `deepseek-harness-user-offline.tar.gz` 重新执行一遍 `install-on-target.sh` 即可。脚本会覆盖 `~/.local/opt/deepseek-harness/` 中的运行时，**不会**改动 `~/.dsh/` 中的用户数据。

### 卸载

```bash
# 1. 删除运行时与命令
rm -rf ~/.local/opt/deepseek-harness
rm -f  ~/.local/bin/dsh ~/.local/bin/node ~/.local/bin/pnpm ~/.local/bin/dsh-web
rm -f  ~/.local/bin/dsh-python ~/.local/bin/dsh-pip

# 2. 删除桌面快捷方式与图标
rm -f  ~/桌面/dsh-web.desktop ~/Desktop/dsh-web.desktop
rm -f  ~/.local/share/icons/deepseek-harness.jpeg

# 3. 如确认不再需要个人数据（会话、配置、插件），再删除：
# rm -rf ~/.dsh
```

`~/.profile` 中由脚本追加的 `PATH` 行可保留，不影响系统。

---

## 七、从联网机器重新打包

适用于升级版本、切换架构（arm64 → x64）或更换内网镜像源。

### 前置条件

1. 一台**与目标机同架构**、可联网的 Linux 机器；
2. 安装好 `npm`、`tar`、`xz`；
3. 准备 Node.js 官方预编译包，例如 `node-v26.2.0-linux-arm64.tar.xz`（[下载地址](https://nodejs.org/dist/v26.2.0/)）；
4. 准备 uv 独立二进制包，例如 `uv-aarch64-unknown-linux-gnu.tar.gz`（[下载地址](https://github.com/astral-sh/uv/releases)）；若打包机已安装 `uv` 可跳过；
5. 准备 `icon.jpeg`，与脚本放在同一目录；
6. 能访问 PyPI 镜像（默认清华源，可用 `PIP_INDEX_URL` 覆盖），用于下载 Python 包。

### 打包步骤

```bash
# 按需修改架构：arm64 / x64
sed -i 's/^ARCH=.*/ARCH="x64"/' make-offline.sh

# 可选：改用其他 PyPI 镜像
export PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple

bash make-offline.sh
```

脚本会依次：部署 Node.js → 全局安装 `@deepseek-ai/dsh` 和 `pnpm` → 用 uv 安装独立 Python 3.11 并创建可迁移 venv → **一次 `uv pip install` 合并安装全部依赖** → Python/Web 冒烟测试 → 生成 `install-on-target.sh` → 打包出 `deepseek-harness-user-offline.tar.gz`。

> ⚠️ **注意**：打包脚本会把运行时安装到**当前用户的** `~/.local/opt/deepseek-harness`，会覆盖该目录下的旧版本；冒烟测试使用临时 `DSH_HOME`，不会读写你的 `~/.dsh`。建议在一台干净的打包机（或专用容器）上执行。
>
> Python 环境解压后约 1.3 GB，打包过程需要额外 3–4 GB 临时空间，并会从 PyPI 下载数百 MB 的 wheel；首次打包建议预留 15–30 分钟。

打包完成后，把新的 `deepseek-harness-user-offline.tar.gz` 与 `install-on-target.sh` 一起拷到目标机即可。

---

## 八、常见问题

**双击桌面图标没反应**

```bash
chmod +x ~/桌面/dsh-web.desktop
gio set ~/桌面/dsh-web.desktop metadata::trusted true
```

部分桌面还需要右键图标选择「允许启动」。

**终端提示 `dsh: command not found`**

`~/.local/bin` 不在当前 `PATH` 中。重新登录，或执行：

```bash
source ~/.profile
# 或临时：
export PATH="$HOME/.local/bin:$PATH"
```

**`dsh-python: command not found`**

同样检查 `~/.local/bin` 是否在 `PATH`；若该文件不存在，说明安装时未找到随包的 Python 环境，可重新执行 `install-on-target.sh`。也可直接使用绝对路径：

```bash
~/.local/opt/deepseek-harness/python-venv/bin/python -V
```

**Python 报 `No module named 'encodings'` 或 venv 路径错误**

通常是安装目录被移动、或没有通过 `install-on-target.sh` 解压。重新执行安装脚本即可重写 `pyvenv.cfg` 和解释器链接：

```bash
bash install-on-target.sh
```

**matplotlib 提示配置目录只读 / 无法写入缓存**

目标机的家目录若被限制写入，可指定缓存目录：

```bash
export MPLCONFIGDIR="$HOME/.cache/matplotlib"
```

**`pytesseract` / `pypandoc` / `graphviz` 运行时报找不到可执行文件**

这些库只提供 Python 封装，仍需系统安装 `tesseract`、`pandoc`、`dot`（Graphviz）。离线环境请用目标机对应的 RPM/DEB 安装包部署。

**`dsh-pip install` 无法联网**

这是预期行为：安装包不带公网访问能力。请配置内网 PyPI 镜像（`PIP_INDEX_URL`），或提前下载 wheel 后用 `dsh-pip install --no-index --find-links <目录>` 安装。

**安装插件时 pnpm 报 `minimumReleaseAge` / 构建脚本被拦截**

确认 `~/.dsh/profiles/web/pnpm-workspace.yaml` 中已包含：

```yaml
minimumReleaseAge: 0
dangerouslyAllowAllBuilds: true
```

缺少时手动追加后重启 `dsh-web`。

**端口 3080 被占用**

```bash
ss -ltnp | grep 3080
# 找到进程后结束；或临时改用其他端口：
dsh --profile web --port 3081
# 也可以让启动脚本透传参数：
dsh-web --port 3081
```

**启动报 `Exec format error` 或 `cannot execute binary file`**

目标机架构与包内 Node.js 不一致（例如把 arm64 包装到了 x86_64 机器）。按第七节用 `ARCH="x64"` 重新打包。

**启动报 `GLIBC_2.28 not found`**

系统 glibc 过旧，不满足 Node.js 官方预编译包要求。需升级系统，或改用自行编译的 Node.js。

**浏览器没有自动打开**

在浏览器中手动访问 <http://127.0.0.1:3080>。无桌面环境 / 无默认浏览器时不会自动拉起。

**桌面图标显示为通用图标**

图标文件缺失或路径不可读。确认 `~/.local/share/icons/deepseek-harness.jpeg` 存在，或重新执行安装脚本。

**首次启动较慢**

首次启动需要初始化 profile 和插件目录，通常 10–30 秒，之后会明显加快。

---

## 九、安全说明

- 服务默认仅监听回环地址 `127.0.0.1`，请勿将其转发或暴露到不可信网络。
- 包内为 Node.js 官方预编译二进制、Python 独立运行时、npm/PyPI 公共包，建议拷贝前后用 `sha256sum` 校验一致性。
- 安装脚本不执行 `sudo`，不写入系统目录；所有变更均可用第六节命令完整回滚。
