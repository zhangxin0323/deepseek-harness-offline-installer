#!/bin/bash
set -e
# =============================================================================
# make-dsh-offline-package.sh
# 在【联网机器】上执行（CPU 架构必须与目标麒麟机一致，默认 arm64），
# 生成自包含离线包 deepseek-harness-user-offline.tar.gz。
#
# 用法：把本脚本和 Node tar 包放同一目录，然后 bash make-dsh-offline-package.sh
#   依赖文件：node-v26.2.0-linux-arm64.tar.xz  （https://nodejs.org/dist/v26.2.0/）
#   依赖文件：icon.jpeg（桌面启动图标，必须与脚本同目录）
#
# 目标机要求：麒麟 V10（内核 5.4 / glibc 2.31 均满足 Node 官方预编译包要求）
# 安装位置：~/.local/opt/deepseek-harness（用户级，免 sudo）
# 数据目录：保持 dsh 默认 ~/.dsh（按用户隔离，不进安装包）
# =============================================================================

OFFLINE_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.local/opt/deepseek-harness"
NODE_VERSION="v26.2.0"
ARCH="arm64"                       # 若目标机是 x86_64 麒麟，改成 "x64"
NODE_TARBALL="node-${NODE_VERSION}-linux-${ARCH}.tar.xz"

echo "=== 步骤0：前置检查 ==="
[ -f "$OFFLINE_DIR/$NODE_TARBALL" ] || { echo "✗ 缺少 $NODE_TARBALL，请先从 nodejs.org 下载"; exit 1; }
[ -f "$OFFLINE_DIR/icon.jpeg" ] || { echo "✗ 缺少 icon.jpeg（桌面启动图标），请放到脚本同目录"; exit 1; }
GLIBC_VER=$(ldd --version 2>/dev/null | head -1 | grep -oP '2\.\d+' | head -1)
echo "打包机 glibc: $GLIBC_VER（Node 官方包要求 >= 2.28）"

echo "=== 步骤1：创建安装目录 ==="
mkdir -p "$INSTALL_DIR"

echo "=== 步骤2：统一环境变量（内外网路径一致）==="
export npm_config_prefix="$INSTALL_DIR/node" # npm 全局包全部装进 INSTALL_DIR
export PATH="$INSTALL_DIR/node/bin:$PATH"
npm config set registry https://registry.npmmirror.com

echo "=== 步骤3：部署 Node.js ==="
cd "$INSTALL_DIR"
tar xf "$OFFLINE_DIR/$NODE_TARBALL" -C .
mv "node-${NODE_VERSION}-linux-${ARCH}" node
npm install -g npm@latest

echo "=== 步骤4：联网安装 dsh 与 pnpm ==="
npm install -g @deepseek-ai/dsh --loglevel=http --progress=true \
  --fetch-timeout=600000 --fetch-retries=5
npm install -g pnpm@latest --loglevel=http

dsh --version

echo "=== 步骤5：冒烟测试（本机临时拉起 web 服务）==="
( dsh web & )
sleep 10
node -e 'fetch("http://127.0.0.1:3080").then(r=>{console.log("smoke:",r.status);process.exit(r.ok||r.status<500?0:1)}).catch(e=>{console.error("smoke failed:",e.message);process.exit(1)})' \
  && echo "✓ web 服务可访问" || echo "！smoke 未通过（建议排查后再打包）"
pkill -f "dsh" 2>/dev/null || true
sleep 2
# 清理冒烟测试产生的个人数据（不进安装包）
rm -rf "$HOME/.dsh" 2>/dev/null || true

echo "=== 步骤6：生成目标机安装脚本 ==="
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

# 确保 ~/.local/bin 在 PATH（麒麟 V10 桌面默认已包含，缺则写入 ~/.profile）
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
  grep -q '.local/bin' "$HOME/.profile" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.profile"
  echo "已写入 ~/.profile，重新登录后生效"
fi

# 初始化 profile 并写入离线必需的 pnpm 配置
dsh --profile web --dump-config > /dev/null 2>&1 || true
PW="$HOME/.dsh/profiles/web/pnpm-workspace.yaml"
if [ -f "$PW" ] && ! grep -q minimumReleaseAge "$PW"; then
  printf '\nminimumReleaseAge: 0            # 离线装插件必需：关闭 pnpm>=11 供应链延迟\ndangerouslyAllowAllBuilds: true # 离线装插件放行构建脚本\n' >> "$PW"
  echo "已写入离线 pnpm 配置: $PW"
else
  echo "！未找到 $PW，请首次运行 dsh web 后手动追加 minimumReleaseAge: 0"
fi

# ---------------- 桌面启动脚本 ----------------
# 先打印“请勿关闭窗口”的提示，再启动 dsh web
LAUNCHER="$HOME/.local/bin/dsh-web"
cat > "$LAUNCHER" <<LAUNCHER_EOF
#!/bin/sh
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

echo "=== 步骤6.5：内置桌面图标 ==="
if [ -f "$OFFLINE_DIR/icon.jpeg" ]; then
  cp -f "$OFFLINE_DIR/icon.jpeg" "$INSTALL_DIR/dsh-web-icon.jpeg"
  echo "✓ 已内置图标: icon.jpeg"
else
  echo "！未找到 $OFFLINE_DIR/icon.jpeg，目标机将回退使用 dsh 自带 favicon"
fi

echo "=== 步骤7：打包 ==="
cd "$HOME/.local/opt"
tar czvf "$OFFLINE_DIR/deepseek-harness-user-offline.tar.gz" deepseek-harness/

echo "✓ 打包完成: $OFFLINE_DIR/deepseek-harness-user-offline.tar.gz"
du -sh "$OFFLINE_DIR/deepseek-harness-user-offline.tar.gz"
echo "  把 tar 包 + install-on-target.sh 一起拷贝到内网麒麟机即可"
