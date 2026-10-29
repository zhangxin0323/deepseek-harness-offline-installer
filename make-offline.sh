#!/bin/bash
set -e
# =============================================================================
# make-dsh-offline-package.sh
# 在【联网机器】上执行（CPU 架构必须与目标麒麟机一致，默认 arm64），
# 生成自包含离线包 deepseek-harness-user-offline.tar.gz。
#
# 用法：把本脚本、Node tar 包、uv tar 包放同一目录，然后 bash make-offline.sh
#   依赖文件：node-v26.2.0-linux-arm64.tar.xz  （https://nodejs.org/dist/v26.2.0/）
#   依赖文件：uv-aarch64-unknown-linux-gnu.tar.gz（https://github.com/astral-sh/uv/releases）
#   依赖文件：icon.jpeg（桌面启动图标，必须与脚本同目录）
#
# 目标机要求：麒麟 V10（内核 5.4 / glibc 2.31 均满足 Node 官方预编译包要求）
# 安装位置：~/.local/opt/deepseek-harness（用户级，免 sudo）
# 数据目录：保持 dsh 默认 ~/.dsh（按用户隔离，不进安装包）
#
# 除 Node.js/dsh 外，本脚本还会用 uv 创建 Python 3.11 虚拟环境，
# 预装文档、数据科学、绘图、数据库等常用库（见步骤 5 的包清单）。
# =============================================================================

OFFLINE_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/opt/deepseek-harness}"
NODE_VERSION="v26.2.0"
ARCH="arm64"                       # 若目标机是 x86_64 麒麟，改成 "x64"
NODE_TARBALL="node-${NODE_VERSION}-linux-${ARCH}.tar.xz"

# ---------------- Python 3.11 环境 ----------------
PYTHON_VERSION="3.11"
# 打包机可访问的 PyPI 镜像；可用 PIP_INDEX_URL 覆盖
PIP_INDEX_URL="${PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"
PYTHON_DIR="$INSTALL_DIR/python"          # uv 托管的独立 Python 运行时
VENV_DIR="$INSTALL_DIR/python-venv"       # 预装好全部依赖的虚拟环境
UV_DIR="$INSTALL_DIR/uv"                  # 随包内置的 uv（离线可复用）
if [ "$ARCH" = "arm64" ]; then
  UV_ARCH="aarch64"
else
  UV_ARCH="x86_64"
fi
UV_TARBALL="uv-${UV_ARCH}-unknown-linux-gnu.tar.gz"
# uv 缓存放在包外，避免被打进安装包
UV_CACHE_DIR="$OFFLINE_DIR/.uv-cache"

echo "=== 步骤0：前置检查 ==="
[ -f "$OFFLINE_DIR/$NODE_TARBALL" ] || { echo "✗ 缺少 $NODE_TARBALL，请先从 nodejs.org 下载"; exit 1; }
[ -f "$OFFLINE_DIR/icon.jpeg" ] || { echo "✗ 缺少 icon.jpeg（桌面启动图标），请放到脚本同目录"; exit 1; }
if ! command -v uv >/dev/null 2>&1; then
  [ -f "$OFFLINE_DIR/$UV_TARBALL" ] || { echo "✗ 缺少 $UV_TARBALL（或系统未安装 uv），请从 https://github.com/astral-sh/uv/releases 下载"; exit 1; }
fi
GLIBC_VER=$(ldd --version 2>/dev/null | head -1 | grep -oP '2\.\d+' | head -1)
echo "打包机 glibc: $GLIBC_VER（Node 官方包要求 >= 2.28）"

echo "=== 步骤1：创建安装目录 ==="
mkdir -p "$INSTALL_DIR"

echo "=== 步骤2：统一环境变量（内外网路径一致）==="
export npm_config_prefix="$INSTALL_DIR/node" # npm 全局包全部装进 INSTALL_DIR
export PATH="$INSTALL_DIR/node/bin:$PATH"
npm config set registry https://registry.npmmirror.com
# uv 配置固定到包内，避免受打包机用户级配置影响，也避免写入 ~/.cache
mkdir -p "$UV_CACHE_DIR"
export UV_CACHE_DIR
export UV_PYTHON_INSTALL_DIR="$PYTHON_DIR"
export UV_NO_CONFIG=1

echo "=== 步骤3：部署 Node.js ==="
cd "$INSTALL_DIR"
tar xf "$OFFLINE_DIR/$NODE_TARBALL" -C .
mv "node-${NODE_VERSION}-linux-${ARCH}" node
npm install -g npm@latest

echo "=== 步骤4：联网安装 dsh 与 pnpm ==="
npm install -g @deepseek-ai/dsh --loglevel=http --progress=true \
  --fetch-timeout=600000 --fetch-retries=5
npm install -g pnpm@latest --loglevel=http
# PPTX 生成（Node 包，与 Python 无关）
npm install -g pptxgenjs@3.12.0 --loglevel=http
npm cache clean --force || true

dsh --version

echo "=== 步骤5：创建 Python ${PYTHON_VERSION} 虚拟环境（uv） ==="
if command -v uv >/dev/null 2>&1; then
  UV_BIN="$(command -v uv)"
  echo "使用系统 uv: $UV_BIN"
else
  mkdir -p "$UV_DIR"
  tar xzf "$OFFLINE_DIR/$UV_TARBALL" -C "$UV_DIR" --strip-components=1
  UV_BIN="$UV_DIR/uv"
  echo "使用内置 uv: $UV_BIN"
fi
# 统一在安装目录保留一份 uv，目标机也可离线复用
if [ "$UV_BIN" != "$UV_DIR/uv" ]; then
  mkdir -p "$UV_DIR"
  cp -f "$UV_BIN" "$UV_DIR/uv"
  chmod +x "$UV_DIR/uv"
fi

# 下载/安装独立 Python 运行时（不写入 ~/.local/bin，避免污染打包机）
"$UV_BIN" python install "$PYTHON_VERSION" --no-bin --install-dir "$PYTHON_DIR"
BASE_PY="$(ls -1 "$PYTHON_DIR"/cpython-${PYTHON_VERSION}*/bin/python${PYTHON_VERSION} 2>/dev/null | head -1)"
[ -n "$BASE_PY" ] || { echo "✗ 未找到 uv 安装的 Python $PYTHON_VERSION"; exit 1; }
echo "Python 运行时: $BASE_PY"

# --relocatable 让整个安装目录搬到目标机后仍可用；安装脚本会再修正一次路径
rm -rf "$VENV_DIR"
"$UV_BIN" venv --python "$BASE_PY" --relocatable --seed "$VENV_DIR"

# uv 会留一个指向绝对路径的 Python 版本别名，打包到目标机后会断链。
# 改为同目录内的相对链接，安装脚本再据此修正 venv。
PY_ALIAS="$PYTHON_DIR/cpython-${PYTHON_VERSION}-linux-${UV_ARCH}-gnu"
PY_VERSIONED="$(ls -d "$PYTHON_DIR"/cpython-${PYTHON_VERSION}.*-linux-* 2>/dev/null | head -1)"
if [ -L "$PY_ALIAS" ] && [ -n "$PY_VERSIONED" ]; then
  ln -sfn "$(basename "$PY_VERSIONED")" "$PY_ALIAS"
fi

cat > "$INSTALL_DIR/python-requirements.txt" <<'REQ'
# Office / 文档处理
markitdown[pptx]
Pillow
defusedxml
lxml
python-pptx
python-docx
openpyxl
xlrd
xlsxwriter
python-calamine
olefile
PyMuPDF
pdfplumber
pytesseract
pypandoc
docxtpl
# 数据处理 / 科学计算 / 可视化
pandas
numpy
scipy
chardet
python-magic
xlsx2csv
unstructured
matplotlib
seaborn
plotly
kaleido
pygame
# 流程图 / 思维导图
graphviz
pygraphviz
diagrams
networkx
xmind
xmindparser
# 数据库（通用 + 国产/Oracle）
psycopg2-binary
pymongo
redis
sqlalchemy
pymysql
sqlcipher3
oracledb
# Web / 地理计算
Flask
geographiclib
# 常用工具库
requests
pyyaml
jinja2
tabulate
tqdm
REQ

echo "合并安装 Python 依赖（单次 uv pip install，镜像: $PIP_INDEX_URL）..."
"$UV_BIN" pip install --python "$VENV_DIR/bin/python" \
  --index-url "$PIP_INDEX_URL" --no-cache \
  -r "$INSTALL_DIR/python-requirements.txt"

# 达梦驱动：部分镜像/架构可能缺失，失败不中断打包
"$UV_BIN" pip install --python "$VENV_DIR/bin/python" \
  --index-url "$PIP_INDEX_URL" --no-cache dmPython \
  || echo "⚠ WARNING: dmPython 安装失败，可稍后从达梦安装介质手动安装"

# 记录环境清单，便于目标机核对
{
  echo "# Built by make-offline.sh on $(date -Iseconds)"
  echo "# $("$VENV_DIR/bin/python" -V 2>&1)"
  echo "# $("$UV_BIN" --version 2>&1)"
  echo
  "$UV_BIN" pip freeze --python "$VENV_DIR/bin/python"
} > "$VENV_DIR/PYTHON_ENV.txt"

"$VENV_DIR/bin/python" - <<'PY'
import sys
import numpy, pandas, matplotlib, requests, sqlalchemy
import docx, pptx, openpyxl, fitz
print("✓ Python 环境可用:", sys.version.split()[0])
PY

echo "=== 步骤6：冒烟测试（本机临时拉起 web 服务）==="
# 用临时 DSH_HOME，避免读取或清除打包机上已有的 ~/.dsh 数据
export DSH_HOME="$OFFLINE_DIR/.smoke-dsh-home"
rm -rf "$DSH_HOME"
dsh web >/dev/null 2>&1 &
SMOKE_PID=$!
sleep 10
node -e 'fetch("http://127.0.0.1:3080").then(r=>{console.log("smoke:",r.status);process.exit(r.ok||r.status<500?0:1)}).catch(e=>{console.error("smoke failed:",e.message);process.exit(1)})' \
  && echo "✓ web 服务可访问" || echo "！smoke 未通过（建议排查后再打包）"
kill "$SMOKE_PID" 2>/dev/null || true
wait "$SMOKE_PID" 2>/dev/null || true
# 清理冒烟测试产生的临时数据（不进安装包）
rm -rf "$DSH_HOME"

echo "=== 步骤7：生成目标机安装脚本 ==="
cat > "$OFFLINE_DIR/install-on-target.sh" <<'EOF'
#!/bin/bash
# 在【离线麒麟机】上执行：bash install-on-target.sh（免 sudo）
set -e
TAR="deepseek-harness-user-offline.tar.gz"
[ -f "$TAR" ] || { echo "缺少 $TAR，请与 install-on-target.sh 放同一目录"; exit 1; }

INSTALL_DIR="$HOME/.local/opt/deepseek-harness"
echo "解压到 $INSTALL_DIR ..."
mkdir -p "$INSTALL_DIR"
tar xzf "$TAR" -C "$INSTALL_DIR" --strip-components=1
mkdir -p "$HOME/.local/bin"
ln -sf "$INSTALL_DIR/node/bin/dsh"   "$HOME/.local/bin/dsh"
ln -sf "$INSTALL_DIR/node/bin/node"  "$HOME/.local/bin/node"
ln -sf "$INSTALL_DIR/node/bin/pnpm"  "$HOME/.local/bin/pnpm"
export PATH="$INSTALL_DIR/node/bin:$HOME/.local/bin:$PATH"
# 固定 dsh 数据目录，避免 passwd 家目录与 $HOME 不一致时写错位置
export DSH_HOME="${DSH_HOME:-$HOME/.dsh}"

# 确保 ~/.local/bin 在 PATH（麒麟 V10 桌面默认已包含，缺则写入 ~/.profile）
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
  grep -q '.local/bin' "$HOME/.profile" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.profile"
  echo "已写入 ~/.profile，重新登录后生效"
fi

# 初始化 profile 并写入离线必需的 pnpm 配置
dsh --profile web --dump-config > /dev/null 2>&1 || true
PW="$DSH_HOME/profiles/web/pnpm-workspace.yaml"
if [ -f "$PW" ] && ! grep -q minimumReleaseAge "$PW"; then
  printf '\nminimumReleaseAge: 0            # 离线装插件必需：关闭 pnpm>=11 供应链延迟\ndangerouslyAllowAllBuilds: true # 离线装插件放行构建脚本\n' >> "$PW"
  echo "已写入离线 pnpm 配置: $PW"
else
  echo "！未找到 $PW，请首次运行 dsh web 后手动追加 minimumReleaseAge: 0"
fi

# ---------------- Python 3.11 虚拟环境 ----------------
# venv 以 --relocatable 构建，但仍会记录打包机上的绝对路径。
# 解压到目标用户目录后，重新指向随包的 Python 并修正 pyvenv.cfg。
PYROOT="$INSTALL_DIR/python"
VENV="$INSTALL_DIR/python-venv"
if [ -d "$VENV" ] && [ -d "$PYROOT" ]; then
  BASE_PY="$(ls -1 "$PYROOT"/cpython-*/bin/python3.* 2>/dev/null | head -1)"
  if [ -n "$BASE_PY" ] && [ -f "$BASE_PY" ] && [ -f "$VENV/pyvenv.cfg" ]; then
    BASE_BIN="$(dirname "$BASE_PY")"
    ln -sfn "$BASE_PY" "$VENV/bin/python"
    awk -v h="$BASE_BIN" '
      /^home[[:space:]]*=/ && !done { print "home = " h; done=1; next }
      { print }
    ' "$VENV/pyvenv.cfg" > "$VENV/pyvenv.cfg.tmp"
    mv -f "$VENV/pyvenv.cfg.tmp" "$VENV/pyvenv.cfg"
    # 用包装脚本而非符号链接：多级符号链接会让 Python 误判 sys.prefix
    rm -f "$HOME/.local/bin/dsh-python" "$HOME/.local/bin/dsh-pip"
    cat > "$HOME/.local/bin/dsh-python" <<DSH_PY
#!/bin/sh
exec "$VENV/bin/python" "\$@"
DSH_PY
    cat > "$HOME/.local/bin/dsh-pip" <<DSH_PIP
#!/bin/sh
exec "$VENV/bin/pip" "\$@"
DSH_PIP
    chmod +x "$HOME/.local/bin/dsh-python" "$HOME/.local/bin/dsh-pip"
    echo "✓ Python 环境: $VENV"
    "$VENV/bin/python" -V 2>&1 | sed 's/^/  /'
  else
    echo "！未找到随包的 Python 运行时，Python 环境不可用"
  fi
else
  echo "！未找到随包的 Python 环境，跳过"
fi

# ---------------- 桌面启动脚本 ----------------
# 先打印“请勿关闭窗口”的提示，再启动 dsh web
LAUNCHER="$HOME/.local/bin/dsh-web"
cat > "$LAUNCHER" <<LAUNCHER_EOF
#!/bin/sh
# 让 dsh 的 Node 脚本能 require 全局包（如 pptxgenjs）
export NODE_PATH="$INSTALL_DIR/node/lib/node_modules${NODE_PATH:+:$NODE_PATH}"
# 默认让 dsh 的终端工具直接使用包内 Python 3.11
# （设置 DSH_NO_PYTHON_PATH=1 可恢复系统默认 Python）
if [ "\${DSH_NO_PYTHON_PATH:-0}" != "1" ]; then
  export PATH="$INSTALL_DIR/python-venv/bin:\$PATH"
fi
export PATH="$INSTALL_DIR/node/bin:$HOME/.local/bin:\$PATH"

echo '============================================================'
echo '  DeepSeek Harness  -  dsh web 服务'
echo '------------------------------------------------------------'
echo '  正在启动，请稍候...'
echo '  注意：请不要关闭此终端窗口！关闭窗口会停止 dsh 服务。'
echo '  启动完成后，浏览器会自动打开 http://127.0.0.1:3080'
echo '  如需停止服务，请在此窗口按 Ctrl+C。'
echo '============================================================'

exec "$INSTALL_DIR/node/bin/dsh" web "\$@"
LAUNCHER_EOF
chmod +x "$LAUNCHER"
echo "✓ 已创建启动脚本: $LAUNCHER"

# ---------------- 桌面启动图标 ----------------
# 使用随包内置的 icon.jpeg 作为桌面图标
ICON_SRC="$INSTALL_DIR/dsh-web-icon.jpeg"
ICON_DST="$HOME/.local/share/icons/deepseek-harness.jpeg"
mkdir -p "$HOME/.local/share/icons"
if [ -f "$ICON_SRC" ]; then
  cp -f "$ICON_SRC" "$ICON_DST"
  ICON_VALUE="$ICON_DST"
  echo "已安装图标: $ICON_DST"
else
  ICON_VALUE="applications-internet"
  echo "！未找到 icon.jpeg，改用系统图标: $ICON_VALUE"
fi

# 桌面目录：优先使用 xdg-user-dir（中文系统通常为 ~/桌面）
DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || true)"
case "$DESKTOP_DIR" in
  ""|"$HOME")
    if [ -d "$HOME/桌面" ]; then DESKTOP_DIR="$HOME/桌面"
    else DESKTOP_DIR="$HOME/Desktop"; fi ;;
esac
mkdir -p "$DESKTOP_DIR"
DESKTOP_FILE="$DESKTOP_DIR/dsh-web.desktop"
cat > "$DESKTOP_FILE" <<DESKTOP_EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=DeepSeek Harness
Name[zh_CN]=DeepSeek Harness
GenericName=dsh Web Service
GenericName[zh_CN]=dsh Web 服务
Comment=Start the dsh web service and open it in the browser
Comment[zh_CN]=启动 dsh web 服务并在浏览器中打开
Exec="$HOME/.local/bin/dsh-web"
Icon=$ICON_VALUE
Terminal=true
StartupNotify=true
Categories=Development;
Keywords=dsh;DeepSeek;Harness;AI;
DESKTOP_EOF
chmod +x "$DESKTOP_FILE"
# 部分桌面（GNOME/MATE 系）需要标记为可信才能双击运行
if command -v gio >/dev/null 2>&1; then
  gio set "$DESKTOP_FILE" metadata::trusted true 2>/dev/null || true
fi
echo "✓ 已创建桌面启动图标: $DESKTOP_FILE"

echo "✓ 安装完成。"
echo ""
echo "▶ 请双击桌面上的 “DeepSeek Harness” 图标启动 dsh 服务；"
echo "  启动后的终端窗口会提示“请不要关闭此窗口”，请保持其运行。"
echo "  服务启动后会自动打开浏览器 http://127.0.0.1:3080"
echo "  也可以在终端执行：dsh-web  （或 dsh web）"
echo ""
echo "  模型配置：设置 → Models → 添加自定义提供方，填内网 OpenAI 兼容端点"
EOF
chmod +x "$OFFLINE_DIR/install-on-target.sh"

echo "=== 步骤8：内置桌面图标 ==="
if [ -f "$OFFLINE_DIR/icon.jpeg" ]; then
  cp -f "$OFFLINE_DIR/icon.jpeg" "$INSTALL_DIR/dsh-web-icon.jpeg"
  echo "✓ 已内置图标: icon.jpeg"
else
  echo "！未找到 $OFFLINE_DIR/icon.jpeg，目标机将回退使用 dsh 自带 favicon"
fi

echo "=== 步骤9：打包 ==="
cd "$HOME/.local/opt"
tar czvf "$OFFLINE_DIR/deepseek-harness-user-offline.tar.gz" deepseek-harness/

echo "✓ 打包完成: $OFFLINE_DIR/deepseek-harness-user-offline.tar.gz"
du -sh "$OFFLINE_DIR/deepseek-harness-user-offline.tar.gz"
echo "  把 tar 包 + install-on-target.sh 一起拷贝到内网麒麟机即可"
