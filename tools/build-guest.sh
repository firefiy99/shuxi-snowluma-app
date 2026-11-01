#!/bin/bash
# 构建 guest 系统包 snowluma-guest-v<VER>.tar.xz
#
# 产物结构（tar.xz 内）：
#   vmlinuz        guest 内核
#   initrd.img     initramfs（busybox + ext4/virtio 模块 + /init）
#   rootfs.tar     Debian guest 根文件系统
#
# 用法：
#   ./tools/build-guest.sh --rootfs /path/to/debian-rootfs.tar \
#                          --kernel /path/to/vmlinuz-6.12-arm64 \
#                          --modules /path/to/lib/modules/6.12.0-arm64 \
#                          [--out snowluma-guest-v1.0.0.tar.xz]
#
# 说明：
#   * rootfs 需为 aarch64 的 Debian/Ubuntu 根文件系统 tar（可由
#     `docker export $(docker create debian:trixie-slim)` 得到）
#   * 本脚本不下载 QQ 与 SnowLuma（版权软件），它们由 guest 首次
#     启动时从官方渠道下载安装
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

ROOTFS_TAR=""
KERNEL=""
MODULES=""
OUT=""
VER="1.0.0"
WORK="build"

while [ $# -gt 0 ]; do
  case "$1" in
    --rootfs) ROOTFS_TAR="$2"; shift 2 ;;
    --kernel) KERNEL="$2"; shift 2 ;;
    --modules) MODULES="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --version) VER="$2"; shift 2 ;;
    --work) WORK="$2"; shift 2 ;;
    *) echo "未知参数: $1"; exit 2 ;;
  esac
done

[ -n "$OUT" ] || OUT="snowluma-guest-v${VER}.tar.xz"

die(){ echo "ERROR: $*" >&2; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "缺少命令：$1"; }

for c in tar xz cpio mke2fs sha256sum; do need "$c"; done

[ -n "$ROOTFS_TAR" ] || die "必须用 --rootfs 指定 Debian aarch64 根文件系统 tar"
[ -f "$ROOTFS_TAR" ] || die "rootfs 不存在：$ROOTFS_TAR"
[ -n "$KERNEL" ] || die "必须用 --kernel 指定 aarch64 内核"
[ -f "$KERNEL" ] || die "内核不存在：$KERNEL"
[ -n "$MODULES" ] || die "必须用 --modules 指定内核模块目录（lib/modules/<ver>）"
[ -d "$MODULES" ] || die "模块目录不存在：$MODULES"

mkdir -p "$WORK"
STAGE="$WORK/guest"
rm -rf "$STAGE"
mkdir -p "$STAGE"

echo "==> 1/4 展开 rootfs"
RFS="$WORK/rootfs"
rm -rf "$RFS"; mkdir -p "$RFS"
tar -xf "$ROOTFS_TAR" -C "$RFS"

echo "==> 2/4 注入 guest 脚本"
mkdir -p "$RFS/opt" "$RFS/var/log" "$RFS/dev/shm" "$RFS/tmp" "$RFS/run" \
         "$RFS/proc" "$RFS/sys" "$RFS/root/qqhome"
install -m 755 guest/boot.sh          "$RFS/opt/boot.sh"
install -m 755 guest/provision.sh     "$RFS/opt/provision.sh"
install -m 755 guest/start-services.sh "$RFS/opt/start-services.sh"
install -m 644 guest/onebot.json      "$RFS/opt/onebot.json" 2>/dev/null || true
mkdir -p "$RFS/tmp/www" "$RFS/tmp/xdg"
chmod 1777 "$RFS/tmp" "$RFS/dev/shm"

# busybox 静态二进制（供 provision 之前的网络配置使用）
BB=$(command -v busybox || true)
if [ -n "$BB" ] && file "$BB" 2>/dev/null | grep -q 'statically linked'; then
  install -m 755 "$BB" "$RFS/opt/busybox"
  echo "    已内置静态 busybox"
fi

echo "==> 3/4 生成 initramfs"
IR="$WORK/initramfs"
rm -rf "$IR"; mkdir -p "$IR/bin" "$IR/sbin" "$IR/proc" "$IR/sys" "$IR/dev" "$IR/newroot" "$IR/lib"
[ -n "$BB" ] || die "缺少 busybox（请安装 busybox-static）"
install -m 755 "$BB" "$IR/bin/busybox"
for a in sh mount umount mknod sleep cat ls mkdir echo exec chroot poweroff; do
  ln -sf /bin/busybox "$IR/bin/$a"
done
install -m 755 guest/init "$IR/init"
chmod 755 "$IR/init"

# 内核模块（ext4 + virtio）
KVER="$(basename "$MODULES")"
for m in kernel/fs/ext4/ext4.ko.* kernel/fs/jbd2/jbd2.ko.* kernel/fs/mbcache.ko.* \
         kernel/lib/crc16.ko.* kernel/lib/libcrc32c.ko.* kernel/lib/crc32c_generic.ko.* \
         kernel/drivers/block/virtio_blk.ko.* kernel/net/core/failover.ko.* \
         kernel/drivers/net/net_failover.ko.* kernel/drivers/net/virtio_net.ko.*; do
  f=$(ls "$MODULES"/$m 2>/dev/null | head -n 1 || true)
  [ -n "$f" ] || continue
  rel="${f#$MODULES/}"
  mkdir -p "$IR/lib/modules/$KVER/$(dirname "$rel")"
  cp "$f" "$IR/lib/modules/$KVER/$rel"
done

( cd "$IR" && find . -print0 | cpio -- -ov --format=newc 2>/dev/null | gzip -9 ) > "$STAGE/initrd.img"
echo "    initrd.img: $(du -h "$STAGE/initrd.img" | cut -f1)"

echo "==> 4/4 打包"
install -m 644 "$KERNEL" "$STAGE/vmlinuz"
( cd "$RFS" && tar -cf - . ) > "$WORK/rootfs.tar"
mv "$WORK/rootfs.tar" "$STAGE/rootfs.tar"
echo "    rootfs.tar: $(du -h "$STAGE/rootfs.tar" | cut -f1)"

( cd "$STAGE" && tar -cJf "$ROOT/$OUT" vmlinuz initrd.img rootfs.tar )

echo ""
echo "完成：$OUT"
ls -lh "$OUT"
echo "sha256: $(sha256sum "$OUT" | awk '{print $1}')"
echo ""
echo "上传到 GitHub Release（firefiy99/astrbot-snowluma-build）："
echo "  gh release upload v${VER} \"$OUT\" --clobber"
echo "或使用网页上传："
echo "  https://github.com/firefiy99/astrbot-snowluma-build/releases/new?tag=v${VER}"
