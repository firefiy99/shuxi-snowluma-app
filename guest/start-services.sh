#!/bin/bash
# guest 内启动：Xvfb → 桌面 → QQ → SnowLuma → 远程桌面
# 注入时序（关键）：SnowLuma 必须在用户扫码登录【之前】加载 hook，
# 因此这里先起 QQ，再起 SnowLuma（hookAutoLoad=true 自动扫描并注入）。
set -u

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
export DISPLAY=:1
export SNOWLUMA_HOOK_RUNTIME_DIR=/tmp/xdg
export XDG_RUNTIME_DIR=/tmp/xdg

LOG=/var/log/services.log
: > "$LOG"
exec >> "$LOG" 2>&1

log(){ echo "[svc] $(date -u '+%H:%M:%S') $*"; }

mkdir -p /tmp/xdg /tmp/www /var/log /root/qqhome /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix 2>/dev/null || true

# ---------- Xvfb ----------
if ! pgrep -f "Xvfb :1" >/dev/null 2>&1; then
  log "starting Xvfb"
  rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true
  Xvfb :1 -screen 0 1280x800x24 -nolisten tcp > /var/log/xvfb.log 2>&1 &
  for i in $(seq 1 60); do
    [ -S /tmp/.X11-unix/X1 ] && break
    sleep 0.2
  done
fi
if [ -S /tmp/.X11-unix/X1 ]; then
  log "Xvfb ready"
else
  log "WARN Xvfb not ready"
fi

# ---------- 桌面（会话管理，便于远程操作） ----------
if command -v fluxbox >/dev/null 2>&1 && ! pgrep -x fluxbox >/dev/null 2>&1; then
  log "starting fluxbox"
  fluxbox > /var/log/fluxbox.log 2>&1 &
fi

# ---------- Linux QQ ----------
if [ -x /opt/QQ/qq ]; then
  if ! pgrep -f "/opt/QQ/qq" >/dev/null 2>&1; then
    log "starting Linux QQ"
    HOME=/root/qqhome setsid /opt/QQ/qq \
      --no-sandbox \
      --disable-gpu \
      --enable-unsafe-swiftshader \
      --disable-dev-shm-usage \
      > /var/log/qq.log 2>&1 &
    sleep 8
  else
    log "QQ already running"
  fi
else
  log "WARN /opt/QQ/qq missing, QQ not started"
fi

# ---------- SnowLuma ----------
if [ -f /opt/snowluma/index.mjs ]; then
  if ! pgrep -f "snowluma/index.mjs" >/dev/null 2>&1; then
    log "starting SnowLuma"
    cd /opt/snowluma || exit 1
    SNOWLUMA_ACCEPT_EULA=1 SNOWLUMA_ACCEPT_PRIVACY=1 \
      setsid ./node ./index.mjs > /var/log/snowluma.log 2>&1 &
    sleep 5
  else
    log "SnowLuma already running"
  fi
else
  log "WARN /opt/snowluma/index.mjs missing, SnowLuma not started"
fi

# ---------- 远程桌面（x11vnc + noVNC） ----------
if command -v x11vnc >/dev/null 2>&1 && ! pgrep -x x11vnc >/dev/null 2>&1; then
  log "starting x11vnc"
  x11vnc -display :1 -rfbport 5900 -forever -shared -nopw -ping 5 -noxdamage \
    -repeat > /var/log/x11vnc.log 2>&1 &
  sleep 1
fi

if command -v websockify >/dev/null 2>&1 && ! pgrep -f "websockify" >/dev/null 2>&1; then
  WEBROOT=""
  for d in /usr/share/novnc /usr/share/webapps/novnc; do
    [ -d "$d" ] && WEBROOT="$d" && break
  done
  if [ -n "$WEBROOT" ]; then
    log "starting websockify on 6081 (webroot=$WEBROOT)"
    websockify --web "$WEBROOT" 6081 127.0.0.1:5900 > /var/log/websockify.log 2>&1 &
    sleep 1
  fi
fi

# ---------- 状态汇总 ----------
sleep 3
log "=== status ==="
log "qq pid : $(pgrep -f '/opt/QQ/qq' | head -1)"
log "sl pid : $(pgrep -f 'snowluma/index.mjs' | head -1)"
log "webui  : $(curl -s -o /dev/null -w '%{http_code}' -m 5 http://127.0.0.1:5099/ 2>/dev/null)"
log "pidlist: $(curl -s -m 5 http://127.0.0.1:5099/api/processes 2>/dev/null | head -c 300)"
log "done"
