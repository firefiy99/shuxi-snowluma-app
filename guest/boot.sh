#!/bin/bash
# guest 引导入口（由 initramfs 的 init chroot 调用）
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
export LANG=C.UTF-8
export TERM=linux

LOG=/var/log/boot.log
mkdir -p /var/log /tmp /run /dev/shm /dev/pts
: > "$LOG"
# 输出到控制台（避免进程替换在受限环境失败）
exec >> /dev/console 2>&1

echo "[boot] $(date -u '+%F %T') UTC starting"

# ---------- 网络（QEMU slirp 用户网络） ----------
ip link set lo up 2>/dev/null || true
for n in eth0 ens3 enp0s1; do
  if [ -e "/sys/class/net/$n" ]; then
    ip link set "$n" up 2>/dev/null || true
    ip addr add 10.0.2.15/24 dev "$n" 2>/dev/null || true
    ip route add default via 10.0.2.2 dev "$n" 2>/dev/null || true
    echo "[boot] network $n configured"
    break
  fi
done
printf 'nameserver 223.5.5.5\nnameserver 119.29.29.29\n' > /etc/resolv.conf

# ---------- 首次配置 ----------
if [ ! -f /opt/.provisioned ]; then
  echo "[boot] first run, provisioning ..."
  /opt/provision.sh || echo "[boot] WARN provisioning failed (see /var/log/provision.log)"
fi

# ---------- 启动服务 ----------
/opt/start-services.sh

# ---------- 保活 ----------
while true; do
  sleep 30
done
