#!/bin/bash
# 第二实例启动器：启动第二套 QQ 运行环境（独立虚拟机 + 独立磁盘）
# 原实现基于 NapCat + LD_PRELOAD；现改为 QEMU 虚拟机方案。
set -u

BASE_HOME="/root"
INSTANCE_HOME="$BASE_HOME/snowluma_instances/qq2_home"
INSTANCE_WORKDIR="$BASE_HOME/snowluma_instances/qq2_vm"
INSTANCE_DISPLAY="${QQ2_DISPLAY:-22}"
INSTANCE_WS_PORT="${QQ2_ONEBOT_WS_PORT:-6200}"

VM_DIR="$BASE_HOME/snowluma-vm"
GUEST_DIR="$VM_DIR/guest"
BASE_DISK="$VM_DIR/disk.img"
INSTANCE_DISK="$INSTANCE_WORKDIR/disk.img"

mkdir -p "$INSTANCE_HOME" "$INSTANCE_WORKDIR/logs" "$INSTANCE_WORKDIR/cache"

echo "[launcher2] 第二实例：QEMU 虚拟机方案"
echo "[launcher2] INSTANCE_WORKDIR=$INSTANCE_WORKDIR"
echo "[launcher2] INSTANCE_HOME=$INSTANCE_HOME"
echo "[launcher2] ONEBOT_WS_PORT=$INSTANCE_WS_PORT"

if [ ! -f "$GUEST_DIR/vmlinuz" ] || [ ! -f "$GUEST_DIR/initrd.img" ]; then
  echo "[launcher2] 错误：QQ 运行环境尚未安装，请先在应用内完成安装"
  exit 1
fi

if [ ! -f "$INSTANCE_DISK" ]; then
  if [ -f "$BASE_DISK" ]; then
    echo "[launcher2] 从主实例磁盘复制一份独立磁盘（首次较慢）"
    cp --sparse=always "$BASE_DISK" "$INSTANCE_DISK" || {
      echo "[launcher2] 复制磁盘失败"
      exit 1
    }
  else
    echo "[launcher2] 错误：主实例磁盘不存在，请先启动一次主实例"
    exit 1
  fi
fi

if [ -f "$INSTANCE_WORKDIR/qemu.pid" ]; then
  OLD=$(cat "$INSTANCE_WORKDIR/qemu.pid" 2>/dev/null || true)
  if [ -n "$OLD" ] && kill -0 "$OLD" 2>/dev/null; then
    echo "[launcher2] 第二实例已在运行（pid $OLD）"
    exit 0
  fi
  rm -f "$INSTANCE_WORKDIR/qemu.pid"
fi

FORWARDS="hostfwd=tcp::5109-:5099,hostfwd=tcp::6091-:6081,hostfwd=tcp::8899-:8889"
FORWARDS="$FORWARDS,hostfwd=tcp::${INSTANCE_WS_PORT}-:6199"

echo "[launcher2] 启动第二实例虚拟机（WebUI 5109 / 远程桌面 6091 / WS ${INSTANCE_WS_PORT}）"
setsid qemu-system-aarch64 \
  -M virt \
  -cpu cortex-a72 \
  -accel tcg,thread=multi,tb-size=512 \
  -m "${SNOWLUMA_VM_MEM:-2048}" -smp "${SNOWLUMA_VM_SMP:-2}" \
  -nographic -no-reboot \
  -nic "user,$FORWARDS" \
  -drive "file=$INSTANCE_DISK,if=virtio,format=raw,cache=writeback" \
  -kernel "$GUEST_DIR/vmlinuz" \
  -initrd "$GUEST_DIR/initrd.img" \
  -append "console=ttyAMA0 loglevel=4 snowluma.ws=6199" \
  > "$INSTANCE_WORKDIR/logs/vm.log" 2>&1 &

echo $! > "$INSTANCE_WORKDIR/qemu.pid"
sleep 2
if kill -0 "$(cat "$INSTANCE_WORKDIR/qemu.pid")" 2>/dev/null; then
  echo "[launcher2] 第二实例已启动（pid $(cat "$INSTANCE_WORKDIR/qemu.pid")）"
else
  echo "[launcher2] 第二实例启动失败，日志：$INSTANCE_WORKDIR/logs/vm.log"
  tail -n 30 "$INSTANCE_WORKDIR/logs/vm.log" 2>/dev/null || true
  exit 1
fi
