#!/bin/bash

ASTRBOT_APP_VERSION="{{VERSION}}"

# 自定义 Git Clone 命令（为空时使用默认逻辑）
CUSTOM_GIT_CLONE=""

# 重装插件依赖标记（1表示需要重装，执行后自动清除）
REINSTALL_PLUGINS_FLAG=0

# GitHub 代理选择：auto 自动测试；direct 直连；其他值视为代理 URL
ASTRBOT_GITHUB_PROXY="${ASTRBOT_GITHUB_PROXY:-auto}"
ASTRBOT_FORCE_REINSTALL_STEP="${ASTRBOT_FORCE_REINSTALL_STEP:-}"

# ============================================================
# SnowLuma 手机部署方案常量
# ============================================================
# 说明：QQ 与 SnowLuma 均包含腾讯/上游版权，不随应用分发，
#      由本脚本在设备本地从官方渠道下载。
ASTRBOT_ONEBOT_WS_PORT="${ASTRBOT_ONEBOT_WS_PORT:-6199}"
ASTRBOT_ONEBOT_WS_TOKEN="${ASTRBOT_ONEBOT_WS_TOKEN:-kasdkfljsadhlskdjhasdlkfshdlafksjdhf}"

VM_DIR="$HOME/snowluma-vm"
GUEST_DIR="$VM_DIR/guest"
DISK_IMG="$VM_DIR/disk.img"
GUEST_SET="snowluma-guest-v1.0.0"
ASSET_BASE="${ASTRBOT_ASSET_BASE:-https://github.com/firefiy99/shuxi-snowluma-app/releases/latest/download}"

export UV_LINK_MODE=copy
export UV_DEFAULT_INDEX="https://pypi.tuna.tsinghua.edu.cn/simple"
export UV_PYTHON_INSTALL_MIRROR="https://ghfast.top/https://github.com/astral-sh/python-build-standalone/releases/download"

if [ -z "$TMPDIR" ]; then
  echo "错误：未检测到 TMPDIR，请在挂载共享目录时传入 TMPDIR"
  exit 1
fi

if [ ! -d "$TMPDIR" ]; then
  echo "错误：临时目录 $TMPDIR 不存在，请确认挂载已经完成"
  exit 1
fi

progress_echo(){
  echo -e "\033[31m- $@\033[0m"
  echo "$@" > "$TMPDIR/progress_des"
}

prepare_reinstall_step(){
  case "$1" in
    uv)
      progress_echo "uv 重装准备中"
      rm -f "$HOME/.local/bin/uv" "$HOME/.local/bin/uvx"
      ;;
    napcat)
      # 兼容旧步骤名：本方案的 "napcat" 步骤 = QQ 运行环境（QEMU + SnowLuma）
      progress_echo "QQ 运行环境重装准备中"
      stop_vm
      rm -rf "$VM_DIR/guest" "$DISK_IMG" "$VM_DIR/qq-home" "$VM_DIR/snowluma"
      ;;
    astrbot)
      progress_echo "AstrBot 重装准备中"
      killall uv 2>/dev/null || true
      rm -rf "$HOME/AstrBot_data_reinstall_backup"
      if [ -d "$HOME/AstrBot/data" ]; then
        cp -r "$HOME/AstrBot/data" "$HOME/AstrBot_data_reinstall_backup"
      fi
      rm -rf "$HOME/AstrBot" "$HOME/AstrBot_tmp"
      ;;
  esac
}

maybe_prepare_reinstall(){
  if [ "$ASTRBOT_FORCE_REINSTALL_STEP" = "$1" ]; then
    prepare_reinstall_step "$1"
  fi
}

bump_progress(){
  current=0
  if [ -f "$TMPDIR/progress" ]; then
    current=$(cat "$TMPDIR/progress" 2>/dev/null || echo 0)
  fi
  next=$((current + 1))
  printf "$next" > "$TMPDIR/progress"
}

install_sudo_curl_git(){
  missing=()
  for cmd in sudo git curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if [ ${#missing[@]} -eq 0 ]; then
    progress_echo "基础命令已安装"
    return 0
  fi

  progress_echo "基础命令缺失: ${missing[*]}, 开始安装..."

  export DEBIAN_FRONTEND=noninteractive
  apt_opts="-o Acquire::ForceIPv4=true"

  if ! apt-get $apt_opts update; then
    echo "apt-get update 失败，继续尝试安装..."
  fi

  if ! apt-get $apt_opts install -y sudo git curl; then
    echo "基础命令安装失败"
    return 1
  fi

  for cmd in sudo git curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "基础命令安装后仍缺少: $cmd"
      return 1
    fi
  done

  progress_echo "基础命令安装完成"
}

network_test() {
    local timeout=10
    local status=0
    local found=0
    target_proxy=""
    echo "开始网络测试: Github..."

    if [ "$ASTRBOT_GITHUB_PROXY" = "direct" ]; then
        echo "已选择 Github 直连"
        target_proxy=""
        return 0
    fi

    if [ -n "$ASTRBOT_GITHUB_PROXY" ] && [ "$ASTRBOT_GITHUB_PROXY" != "auto" ]; then
        target_proxy="$ASTRBOT_GITHUB_PROXY"
        echo "已选择 Github 代理: $target_proxy"
        return 0
    fi

    proxy_arr=("https://ghfast.top" "https://gh-proxy.com" "https://ghproxy.net" "https://ghproxy.cc" "https://gh.dpik.top" "https://gh.monlor.com" "https://gh.chjina.com" "https://github.boki.moe" "https://gh.jasonzeng.dev" "https://gh.geekertao.top" "https://gh.nxnow.top" "https://down.npee.cn")
    check_url="https://raw.githubusercontent.com/astral-sh/uv/main/README.md"

    for proxy in "${proxy_arr[@]}"; do
        echo "测试代理: ${proxy}"
        status=$(curl -fL --connect-timeout ${timeout} --max-time $((timeout*2)) -o /dev/null -s -w "%{http_code}" "${proxy}/${check_url}")
        curl_exit=$?
        if [ $curl_exit -ne 0 ]; then
            echo "代理 ${proxy} 测试失败或超时，错误码: $curl_exit"
            continue
        fi
        if [ "${status}" = "200" ]; then
            found=1
            target_proxy="${proxy}"
            echo "将使用Github代理: ${proxy}"
            break
        fi
    done

    if [ ${found} -eq 0 ]; then
        echo "警告: 无法找到可用的Github代理，将尝试直连..."
        status=$(curl -fL --connect-timeout ${timeout} --max-time $((timeout*2)) -o /dev/null -s -w "%{http_code}" "${check_url}")
        if [ $? -eq 0 ] && [ "${status}" = "200" ]; then
            echo "直连Github成功，将不使用代理"
            target_proxy=""
        else
            echo "警告: 无法连接到Github，请检查网络。将继续尝试安装，但可能会失败。"
        fi
    fi
}

install_uv(){
  local INSTALL_DIR="$HOME/.local/bin"
  if [ -x "$INSTALL_DIR/uv" ]; then
    progress_echo "uv 已安装"
    return 0
  fi

  progress_echo "uv 未安装，正在安装..."
  [ -z "${target_proxy+x}" ] && network_test
  local APP_VERSION="0.9.9"
  local ARCHIVE_FILE="uv-aarch64-unknown-linux-gnu.tar.gz"
  local DOWNLOAD_URL="${target_proxy:+${target_proxy}/}https://github.com/astral-sh/uv/releases/download/${APP_VERSION}/${ARCHIVE_FILE}"
  local TMP_UV
  TMP_UV="$(mktemp -d)"

  if ! curl -fL --connect-timeout 20 --retry 3 --retry-delay 2 -o "$TMP_UV/$ARCHIVE_FILE" "$DOWNLOAD_URL"; then
    echo "uv 下载失败: $DOWNLOAD_URL"
    rm -rf "$TMP_UV"
    exit 1
  fi

  if ! tar -xzf "$TMP_UV/$ARCHIVE_FILE" -C "$TMP_UV"; then
    echo "uv 解压失败"
    rm -rf "$TMP_UV"
    exit 1
  fi

  mkdir -p "$INSTALL_DIR"
  local uvbin
  uvbin="$(ls "$TMP_UV"/*/uv 2>/dev/null | head -n 1)"
  if [ -z "$uvbin" ]; then
    uvbin="$(ls "$TMP_UV"/uv 2>/dev/null | head -n 1)"
  fi
  if [ -z "$uvbin" ] || [ ! -f "$uvbin" ]; then
    echo "uv 解压后未找到可执行文件"
    rm -rf "$TMP_UV"
    exit 1
  fi

  cp "$uvbin" "$INSTALL_DIR/uv"
  chmod +x "$INSTALL_DIR/uv"
  rm -rf "$TMP_UV"

  if ! "$INSTALL_DIR/uv" --version >/dev/null 2>&1; then
    echo "uv 安装校验失败"
    exit 1
  fi
  progress_echo "uv 安装完成"
}

# ============================================================
# QQ 运行环境：QEMU 虚拟机 + Debian guest
# ============================================================
apt_ensure(){
  export DEBIAN_FRONTEND=noninteractive
  local pkgs=("$@")
  local need=()
  for p in "${pkgs[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || need+=("$p")
  done
  if [ ${#need[@]} -eq 0 ]; then
    return 0
  fi
  echo "安装依赖: ${need[*]}"
  apt-get -o Acquire::ForceIPv4=true update || true
  apt-get -o Acquire::ForceIPv4=true install -y "${need[@]}" || return 1
  return 0
}

stop_vm(){
  if [ -f "$VM_DIR/qemu.pid" ]; then
    local p
    p=$(cat "$VM_DIR/qemu.pid" 2>/dev/null || true)
    if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
      kill -9 "$p" 2>/dev/null || true
    fi
    rm -f "$VM_DIR/qemu.pid"
  fi
  # 清理残留的 qemu 进程（精确匹配本目录）
  local qp
  for qp in $(ps -eo pid,args 2>/dev/null | grep -F "$DISK_IMG" | grep -v grep | awk '{print $1}'); do
    kill -9 "$qp" 2>/dev/null || true
  done
}

check_vm_ready(){
  [ -f "$GUEST_DIR/vmlinuz" ] || return 1
  [ -f "$GUEST_DIR/initrd.img" ] || return 1
  [ -f "$DISK_IMG" ] || return 1
  command -v qemu-system-aarch64 >/dev/null 2>&1 || return 1
  return 0
}

fetch_guest_system(){
  local asset="$GUEST_SET.tar.xz"
  local url="${target_proxy:+${target_proxy}/}${ASSET_BASE}/${asset}"
  local out="$VM_DIR/$asset"

  if [ -f "$GUEST_DIR/vmlinuz" ] && [ -f "$GUEST_DIR/initrd.img" ] && [ -f "$GUEST_DIR/rootfs.tar" ]; then
    echo "guest 系统文件已存在，跳过下载"
    return 0
  fi

  mkdir -p "$VM_DIR"
  progress_echo "下载 QQ 运行环境系统镜像（约 250MB）"
  echo "下载地址: $url"

  if ! curl -fL --connect-timeout 20 --retry 3 --retry-delay 3 -o "$out" "$url"; then
    echo "系统镜像下载失败。请检查网络，或设置 ASTRBOT_ASSET_BASE 指向可用镜像。"
    return 1
  fi

  progress_echo "解压系统镜像"
  rm -rf "$GUEST_DIR"
  mkdir -p "$GUEST_DIR"
  if ! tar -xJf "$out" -C "$GUEST_DIR"; then
    echo "系统镜像解压失败"
    return 1
  fi
  rm -f "$out"

  if [ ! -f "$GUEST_DIR/vmlinuz" ] || [ ! -f "$GUEST_DIR/rootfs.tar" ]; then
    echo "系统镜像内容不完整"
    return 1
  fi
  progress_echo "系统镜像就绪"
}

build_disk(){
  if [ -f "$DISK_IMG" ]; then
    echo "磁盘镜像已存在，跳过创建"
    return 0
  fi
  progress_echo "创建 QQ 运行环境磁盘（首次约需 1-3 分钟）"
  local size="${SNOWLUMA_DISK_SIZE:-6G}"
  if ! truncate -s "$size" "$DISK_IMG" 2>/dev/null; then
    dd if=/dev/zero of="$DISK_IMG" bs=1M count=0 seek=6144 2>/dev/null || return 1
  fi
  local rfs="$VM_DIR/rfs"
  rm -rf "$rfs"
  mkdir -p "$rfs"
  if ! tar -xf "$GUEST_DIR/rootfs.tar" -C "$rfs"; then
    echo "解压 rootfs 失败"
    return 1
  fi
  if ! mke2fs -q -t ext4 -F -L snowluma -d "$rfs" "$DISK_IMG" >/dev/null 2>&1; then
    echo "创建 ext4 磁盘失败（mke2fs）"
    return 1
  fi
  rm -rf "$rfs"
  progress_echo "磁盘创建完成"
}

write_vm_launcher(){
  mkdir -p "$VM_DIR"
  cat > "$VM_DIR/run-vm.sh" <<'VMEOF'
#!/bin/bash
# SnowLuma 手机虚拟机启动脚本（由安装器生成）
set -u
VM_DIR="$(cd "$(dirname "$0")" && pwd)"
GUEST_DIR="$VM_DIR/guest"
DISK_IMG="$VM_DIR/disk.img"
LOG="$VM_DIR/vm.log"
PIDF="$VM_DIR/qemu.pid"

MEM="${SNOWLUMA_VM_MEM:-2560}"
SMP="${SNOWLUMA_VM_SMP:-2}"
WS="${ASTRBOT_ONEBOT_WS_PORT:-6199}"

FORWARDS="hostfwd=tcp::5099-:5099,hostfwd=tcp::6081-:6081,hostfwd=tcp::8889-:8889"
[ -n "$WS" ] && FORWARDS="$FORWARDS,hostfwd=tcp::${WS}-:${WS}"

exec qemu-system-aarch64 \
  -M virt \
  -cpu cortex-a72 \
  -accel tcg,thread=multi,tb-size=512 \
  -m "$MEM" -smp "$SMP" \
  -nographic -no-reboot \
  -nic "user,$FORWARDS" \
  -drive "file=$DISK_IMG,if=virtio,format=raw,cache=writeback" \
  -kernel "$GUEST_DIR/vmlinuz" \
  -initrd "$GUEST_DIR/initrd.img" \
  -append "console=ttyAMA0 loglevel=4 snowluma.ws=$WS" \
  >> "$LOG" 2>&1
VMEOF
  chmod +x "$VM_DIR/run-vm.sh"
}

install_snowluma(){
  maybe_prepare_reinstall napcat

  progress_echo "准备 QQ 运行环境（QEMU）"
  if ! apt_ensure qemu-system-arm busybox-static cpio e2fsprogs xz-utils zstd kmod; then
    echo "QEMU 依赖安装失败，请检查网络后重试"
    exit 1
  fi

  [ -z "${target_proxy+x}" ] && network_test

  fetch_guest_system || exit 1
  build_disk || exit 1
  write_vm_launcher

  progress_echo "QQ 运行环境准备完成"
}

# ============================================================
# AstrBot
# ============================================================
check_astrbot_ready(){
  local d="$HOME/AstrBot"
  [ -d "$d" ] || { echo "[AstrBot] 目录不存在: $d"; return 1; }
  [ -f "$d/main.py" ] || { echo "[AstrBot] main.py 缺失"; return 1; }
  [ -x "$HOME/.local/bin/uv" ] || { echo "[AstrBot] uv 缺失"; return 1; }
  [ -x "$d/.venv/bin/python" ] || { echo "[AstrBot] Python 虚拟环境缺失"; return 1; }
  return 0
}

install_astrbot(){
  local INSTALL_DIR="$HOME/AstrBot"

  if check_astrbot_ready >/dev/null 2>&1; then
    progress_echo "AstrBot 已安装"
    return 0
  fi

  [ -z "${target_proxy+x}" ] && network_test
  install_uv || exit 1

  if [ ! -f "$INSTALL_DIR/main.py" ]; then
    progress_echo "下载 AstrBot 源码"
    rm -rf "$HOME/AstrBot_tmp"
    if [ -n "$CUSTOM_GIT_CLONE" ]; then
      progress_echo "执行自定义克隆命令"
      if ! eval "$CUSTOM_GIT_CLONE"; then
        echo "自定义克隆命令执行失败"
        exit 1
      fi
      if [ -d "$HOME/AstrBot_tmp" ] && [ ! -d "$INSTALL_DIR" ]; then
        mv "$HOME/AstrBot_tmp" "$INSTALL_DIR"
      fi
    else
      local git_url="${target_proxy:+${target_proxy}/}https://github.com/AstrBotDevs/AstrBot.git"
      if ! git clone --depth=1 "$git_url" "$HOME/AstrBot_tmp"; then
        echo "git clone 失败，尝试使用 API 打包下载"
        rm -rf "$HOME/AstrBot_tmp" "$HOME/AstrBot.zip"
        local tar_url="${target_proxy:+${target_proxy}/}https://api.github.com/repos/AstrBotDevs/AstrBot/tarball/master"
        if ! curl -fL --connect-timeout 20 --retry 3 -o "$HOME/AstrBot.tar.gz" "$tar_url"; then
          echo "AstrBot 源码下载失败"
          exit 1
        fi
        mkdir -p "$HOME/AstrBot_tmp"
        if ! tar -xzf "$HOME/AstrBot.tar.gz" -C "$HOME/AstrBot_tmp" --strip-components=1; then
          echo "AstrBot 源码解压失败"
          exit 1
        fi
        rm -f "$HOME/AstrBot.tar.gz"
      fi
      if [ -d "$HOME/AstrBot_tmp" ] && [ ! -d "$INSTALL_DIR" ]; then
        mv "$HOME/AstrBot_tmp" "$INSTALL_DIR"
      fi
    fi
    rm -rf "$HOME/AstrBot_tmp"
  fi

  if [ ! -f "$INSTALL_DIR/main.py" ]; then
    echo "AstrBot 源码获取失败"
    exit 1
  fi

  cd "$INSTALL_DIR" || exit 1

  if [ ! -x ".venv/bin/python" ]; then
    progress_echo "创建 Python 虚拟环境"
    if ! "$HOME/.local/bin/uv" venv .venv --python 3.12; then
      echo "创建虚拟环境失败"
      exit 1
    fi
  fi

  if [ -f "requirements.txt" ]; then
    progress_echo "安装 AstrBot 依赖（首次约需 5-15 分钟）"
    if ! "$HOME/.local/bin/uv" pip install -r requirements.txt; then
      echo "AstrBot 依赖安装失败"
      exit 1
    fi
  fi

  if ! check_astrbot_ready; then
    echo "AstrBot 安装不完整，请查看上方错误后重试"
    exit 1
  fi

  progress_echo "AstrBot 安装完成"
}

# ============================================================
# 启动
# ============================================================
start_vm(){
  if ! check_vm_ready; then
    echo "[VM] QQ 运行环境未安装完整，请先执行安装"
    return 1
  fi

  if [ -f "$VM_DIR/qemu.pid" ]; then
    local oldp
    oldp=$(cat "$VM_DIR/qemu.pid" 2>/dev/null || true)
    if [ -n "$oldp" ] && kill -0 "$oldp" 2>/dev/null; then
      echo "[VM] 虚拟机已在运行（pid $oldp）"
      return 0
    fi
    rm -f "$VM_DIR/qemu.pid"
  fi

  mkdir -p "$VM_DIR"
  : > "$VM_DIR/vm.log"
  setsid nohup "$VM_DIR/run-vm.sh" >/dev/null 2>&1 &
  local pid=$!
  echo "$pid" > "$VM_DIR/qemu.pid"
  sleep 1
  if kill -0 "$pid" 2>/dev/null; then
    echo "[VM] 虚拟机启动中（pid $pid），日志：$VM_DIR/vm.log"
    return 0
  fi
  echo "[VM] 虚拟机启动失败，日志如下："
  tail -n 40 "$VM_DIR/vm.log" 2>/dev/null || true
  return 1
}

launch_astrbot(){
  local INSTALL_DIR="$HOME/AstrBot"

  if ! check_astrbot_ready; then
    return 1
  fi

  start_vm || echo "[VM] 警告：QQ 运行环境未能启动，本次仅启动 AstrBot"

  cd "$INSTALL_DIR"
  if [ ! -x "$HOME/.local/bin/uv" ]; then
    echo "uv 未找到"
    exit 1
  fi

  progress_echo "AstrBot 启动中"

  if ! "$HOME/.local/bin/uv" run --no-sync main.py; then
    echo "AstrBot 启动失败"
    exit 1
  fi
}

run_step(){
  case "$1" in
    start)
      launch_astrbot
      ;;
    base)
      maybe_prepare_reinstall base
      install_sudo_curl_git
      ;;
    uv)
      maybe_prepare_reinstall uv
      install_sudo_curl_git
      install_uv
      ;;
    napcat)
      maybe_prepare_reinstall napcat
      install_sudo_curl_git
      install_snowluma
      ;;
    astrbot)
      maybe_prepare_reinstall astrbot
      install_sudo_curl_git
      install_uv
      install_astrbot
      ;;
    all|"")
      install_sudo_curl_git
      bump_progress
      bump_progress
      install_uv
      bump_progress
      install_snowluma
      bump_progress
      bump_progress
      bump_progress
      install_astrbot
      ;;
    *)
      echo "未知步骤: $1"
      echo "可用步骤: base uv napcat astrbot all"
      exit 1
      ;;
  esac
}

if [ "$1" = "--step" ]; then
  run_step "$2"
else
  run_step start
fi
