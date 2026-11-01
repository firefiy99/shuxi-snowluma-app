#!/bin/bash
# guest 首次配置：安装 X 运行环境、Linux 版 QQ、SnowLuma 运行时
# 说明：Linux QQ 与 SnowLuma 均为第三方版权软件，由本脚本在设备本地从官方渠道下载，
#      不在本项目中分发。下载即表示您同意其各自的许可协议。
set -u

export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root

LOG=/var/log/provision.log
: > "$LOG"
exec >> "$LOG" 2>&1

log(){ echo "[provision] $*"; }
fail(){ echo "[provision] ERROR: $*"; exit 1; }

GH_PROXY="${SNOWLUMA_GH_PROXY:-https://ghfast.top}"
SL_VER="${SNOWLUMA_VERSION:-2.3.2}"

log "start $(date -u '+%F %T') UTC"

# ---------- 1. 基础依赖 ----------
log "apt-get update"
apt-get update -o Acquire::ForceIPv4=true || log "WARN apt update failed"

log "installing X / capture / tools"
BASE_PKGS="ca-certificates curl xz-utils procps psmisc iproute2 util-linux \
xvfb fluxbox x11-utils x11-xserver-utils xdotool imagemagick zbar-tools qrencode \
fonts-noto-cjk fonts-dejavu-core dbus-x11 x11vnc novnc websockify libnss3 libnspr4 libgbm1 libdrm2 \
libxkbcommon0 libxcomposite1 libxdamage1 libxrandr2 libxtst6 libatk1.0-0 \
libatk-bridge2.0-0 libpango-1.0-0 libcairo2 libcups2 libxshmfence1 libexpat1"

apt-get install -y --no-install-recommends $BASE_PKGS -o Acquire::ForceIPv4=true 2>/dev/null \
  || apt-get install -y --no-install-recommends $BASE_PKGS -o Acquire::ForceIPv4=true \
  || log "WARN some packages failed to install"

for p in libasound2t64 libasound2; do
  apt-get install -y --no-install-recommends "$p" -o Acquire::ForceIPv4=true >/dev/null 2>&1 && break
done

# ---------- 2. Linux 版 QQ ----------
if [ ! -x /opt/QQ/qq ]; then
  log "resolving official Linux QQ download url"
  QQ_URL="${QQ_DEB_URL:-}"
  if [ -z "$QQ_URL" ] && [ -f /opt/qq_arm64.deb ]; then
    QQ_URL="file:///opt/qq_arm64.deb"
  fi
  if [ -z "$QQ_URL" ]; then
    CFG=$(curl -sk --connect-timeout 15 --max-time 40 \
      "https://cdn-go.cn/qq-web/im.qq.com_new/latest/rainbow/linuxConfig.js" || true)
    QQ_URL=$(printf '%s' "$CFG" | grep -oE 'https://[^"'"'"'\\ ]*arm64\.deb' | head -n 1 || true)
  fi
  if [ -z "$QQ_URL" ]; then
    QQ_URL="https://qqdl.gtimg.cn/qqfile/QQNT/9.9.33/beta/3f89efc5/linuxqq_3.2.32-52194_arm64.deb"
  fi
  log "QQ url: $QQ_URL"
  rm -f /tmp/qq_arm64.deb
  case "$QQ_URL" in
    file://*) cp "${QQ_URL#file://}" /tmp/qq_arm64.deb ;;
    *) curl -fL --connect-timeout 20 --retry 3 -o /tmp/qq_arm64.deb "$QQ_URL" || log "WARN QQ download failed" ;;
  esac
  if [ -s /tmp/qq_arm64.deb ]; then
    log "installing Linux QQ"
    apt-get install -y /tmp/qq_arm64.deb -o Acquire::ForceIPv4=true \
      || (dpkg -i /tmp/qq_arm64.deb; apt-get install -y -f -o Acquire::ForceIPv4=true) \
      || log "WARN QQ install failed"
    rm -f /tmp/qq_arm64.deb
  fi
fi

if [ -x /opt/QQ/qq ]; then
  log "Linux QQ installed: ok"
else
  log "WARN Linux QQ not installed; QQ will be unavailable"
fi

# ---------- 3. SnowLuma 运行时 ----------
SL_DIR=/opt/snowluma
if [ ! -f "$SL_DIR/index.mjs" ] && [ -f /opt/snowluma_local.tar.gz ]; then
  log "installing SnowLuma from local package"
  mkdir -p "$SL_DIR"
  tar -xzf /opt/snowluma_local.tar.gz -C "$SL_DIR" --strip-components=1 2>/dev/null \
    || tar -xzf /opt/snowluma_local.tar.gz -C "$SL_DIR"
fi

if [ ! -f "$SL_DIR/index.mjs" ]; then
  SL_URL="${SNOWLUMA_PKG_URL:-https://github.com/SnowLuma/SnowLuma/releases/download/v${SL_VER}/SnowLuma-v${SL_VER}-linux-arm64.tar.gz}"
  log "downloading SnowLuma: $SL_URL"
  rm -f /tmp/sl.tar.gz
  if ! curl -fL --connect-timeout 20 --retry 3 -o /tmp/sl.tar.gz "$SL_URL"; then
    log "direct download failed, trying proxy"
    curl -fL --connect-timeout 20 --retry 3 -o /tmp/sl.tar.gz \
      "${GH_PROXY}/${SL_URL}" || log "WARN SnowLuma download failed"
  fi
  if [ -s /tmp/sl.tar.gz ]; then
    mkdir -p "$SL_DIR"
    tar -xzf /tmp/sl.tar.gz -C "$SL_DIR" --strip-components=1 2>/dev/null \
      || tar -xzf /tmp/sl.tar.gz -C "$SL_DIR"
    rm -f /tmp/sl.tar.gz
  fi
fi

if [ -f "$SL_DIR/index.mjs" ]; then
  log "SnowLuma installed: ok"
  chmod +x "$SL_DIR/node" 2>/dev/null || true
  chmod +x "$SL_DIR/launcher.sh" 2>/dev/null || true
else
  log "WARN SnowLuma not installed; WebUI will be unavailable"
fi

# ---------- 4. SnowLuma 配置 ----------
# 注入时序：必须在登录前加载 hook（hookAutoLoad=true），
# 否则会停在 awaiting readiness，永远无法就绪。
mkdir -p "$SL_DIR/config"
cat > "$SL_DIR/config/runtime.json" <<'EOF'
{
  "hookAutoLoad": true
}
EOF

WS_TOKEN="kasdkfljsadhlskdjhasdlkfshdlafksjdhf"
cat > "$SL_DIR/config/onebot.json" <<EOF
{
  "networks": {
    "httpServers": [],
    "wsServers": [],
    "httpClients": [],
    "wsClients": [
      {
        "name": "astrbot",
        "url": "ws://10.0.2.2:6199/ws?access_token=${WS_TOKEN}",
        "role": "client",
        "messageFormat": "array",
        "reportSelfMessage": false,
        "reconnectIntervalMs": 5000
      }
    ]
  }
}
EOF
chmod 600 "$SL_DIR/config/onebot.json"
log "onebot config written"

# ---------- 5. QQ 运行目录 ----------
mkdir -p /root/qqhome
mkdir -p /tmp/www /tmp/xdg

touch /opt/.provisioned
log "done $(date -u '+%F %T') UTC"
