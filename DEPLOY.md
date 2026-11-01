# 星枢 · 手机本地部署版

在 **Android 手机上本地运行 AstrBot + SnowLuma** 的完整部署方案（含配套 Android 应用）。

不需要 root，不需要解锁 BootLoader，不需要电脑。全部运行在手机本地，
消息与账号数据不出设备。

作者：**小星萤** ｜ QQ：**3010009516** ｜ GitHub：**[@firefiy99](https://github.com/firefiy99)**

---

## 这个项目解决什么问题

想在手机上挂 QQ 机器人，通常只有三条路，都有硬伤：

| 路线 | 结果 |
|---|---|
| 直接用 NapCat / LLOneBot | Android 上没有可用的启动方式 |
| 在 PRoot / Termux 里跑 SnowLuma | SnowLuma 依赖 `ptrace` 注入，**PRoot 会把 `PTRACE_GETREGSET` 伪成功**（返回 0 但不写缓冲区），注入必然失败 |
| 云服务器 | 要花钱，账号在别人的机器上 |

本项目用 **QEMU 软件模拟的真内核虚拟机**在手机内跑一个完整 Linux，
`ptrace` 在虚拟机内是真实可用的，因此 SnowLuma 能正常注入。

实测数据（vivo PD2546 / Android 16 / arm64）：

- 虚拟机内对真实 QQ 进程 `PTRACE_SEIZE` → `INTERRUPT` → `GETREGSET`（len=272，pc/sp 真实）→ `SETREGSET` → `PEEKDATA` 全部成功
- CPU 性能约为原生的 **1 / 3.15**（300M 次整数运算：原生 0.488s vs 虚拟机 1.538s）
- SnowLuma 注入成功后可识别账号并进入 ready

---

## 架构

```
┌──────────────────────────────────────────────────────────┐
│ Android 应用（Flutter，包名 com.firefiy99.astrbot_snow） │
│  · 安装引导 / 进度显示 / 日志                            │
│  · 内置 WebView 打开本机 6185、5099、6081               │
└───────────────┬──────────────────────────────────────────┘
                │
    ┌───────────▼────────────┐   ┌─────────────────────────────┐
    │ PRoot Linux 用户空间   │   │ QEMU 虚拟机（真内核，TCG）  │
    │                        │   │                             │
    │  AstrBot v4.x          │◄──┤  Xvfb + fluxbox             │
    │  WebUI  :6185          │WS │  Linux 版 QQ                │
    │  aiocqhttp: :6199      │   │  SnowLuma  :5099 (WebUI)    │
    │                        │   │  x11vnc/noVNC :6081         │
    │  QEMU 进程宿主         │   │  Debian aarch64             │
    └────────────────────────┘   └─────────────────────────────┘
```

连接方式：**SnowLuma 作为 WebSocket 客户端** 主动连
`ws://10.0.2.2:6199/ws`（`10.0.2.2` 是 QEMU slirp 的宿主网关）。
AstrBot 侧 `aiocqhttp` 是反向 WS 服务端，因此必须由 bot 端发起连接。

---

## 目录结构

```
.
├── astrbot-startup.sh              # 安装/启动主脚本（在 PRoot 内执行）
├── astrbot-installer-bootstrap.sh  # Ed25519 验签的在线更新引导器
├── guest/                          # 虚拟机内部脚本（打包装进 guest 镜像）
│   ├── init                        # initramfs 的 init：挂载磁盘并 chroot
│   ├── boot.sh                     # guest 引导：网络 → 首次配置 → 起服务
│   ├── provision.sh                # guest 首次配置：装 X、Linux QQ、SnowLuma
│   ├── start-services.sh           # 启动 Xvfb / QQ / SnowLuma / 远程桌面
│   └── onebot.json                 # SnowLuma 的 OneBot 连接配置
├── tools/
│   ├── build-guest.sh              # 构建 guest 系统包（vmlinuz+initrd+rootfs）
│   └── make-release.sh             # 生成签名安装包与 manifest
├── privacy_policy.md               # 隐私政策与免责声明（应用内展示）
└── LICENSE
```

---

## 安装流程（应用内）

应用点「安装」时依次调用：

```
astrbot-installer-bootstrap.sh --prepare          # 检查 curl/openssl/CA
astrbot-startup.sh --step base                    # 基础命令
astrbot-startup.sh --step uv                      # 安装 uv
astrbot-startup.sh --step napcat                  # ★ QQ 运行环境（QEMU + guest 系统）
astrbot-startup.sh --step astrbot                 # AstrBot 源码 + venv + 依赖
astrbot-startup.sh                                # 启动：先起虚拟机，再起 AstrBot
```

> `--step napcat` 这个步骤名是为兼容应用界面而保留的，
> 内部实现已经换成 **QEMU + SnowLuma**，不再安装 NapCat。

首次安装会下载：

| 内容 | 约体积 | 来源 |
|---|---|---|
| guest 系统包（内核 + initramfs + Debian rootfs） | ~250 MB | 本仓库 Release |
| uv 运行时 | ~15 MB | astral-sh/uv Release |
| AstrBot 源码 + Python 依赖 | ~500 MB | AstrBotDevs/AstrBot + PyPI 镜像 |

虚拟机首次启动时，guest 内部再自行下载：

| 内容 | 约体积 | 来源 |
|---|---|---|
| Linux 版 QQ（arm64 deb） | ~200 MB | 腾讯官方 CDN |
| SnowLuma 运行时 | ~52 MB | SnowLuma/SnowLuma Release |

---

## 构建 guest 系统包

```bash
# 1. 准备 Debian aarch64 根文件系统
docker create --name deb13 --platform linux/arm64 debian:trixie-slim
docker export deb13 > debian13-arm64.tar

# 2. 准备内核与模块（Debian 官方 arm64 内核）
apt-get download linux-image-6.12.0-XX-arm64
dpkg-deb -x linux-image-*.deb /tmp/kernel

# 3. 构建
./tools/build-guest.sh \
  --rootfs  debian13-arm64.tar \
  --kernel  /tmp/kernel/boot/vmlinuz-6.12.0-XX-arm64 \
  --modules /tmp/kernel/lib/modules/6.12.0-XX-arm64 \
  --out     snowluma-guest-v1.0.0.tar.xz
```

## 发布签名安装包

```bash
# 首次：生成安装器签名密钥（Ed25519）
mkdir -p tools/keys
openssl genpkey -algorithm ed25519 -out tools/keys/installer-key.pem
openssl pkey -in tools/keys/installer-key.pem -pubout -out tools/keys/installer-public.pem
# 把 installer-public.pem 的内容替换进 astrbot-installer-bootstrap.sh 的公钥块

# 打包 + 签名 + 自校验
./tools/make-release.sh 1.0.0
```

产物：`release/astrbot-installer-v1.0.0.tar.gz`、`manifest.json`、`manifest.sig`
—— 上传到本仓库 Release 即可被应用内更新器识别。

---

## 踩过的坑（都已内建到脚本里）

1. **PRoot 下 `ptrace` 被伪成功** —— 这就是必须用 QEMU 的根本原因。
2. **guest 内必须先 `ip link set lo up`** —— 否则 `127.0.0.1` 不通，WebUI 看起来像卡死。
3. **guest 网络必须手配** —— `ip addr add 10.0.2.15/24`、`ip route add default via 10.0.2.2`，
   DNS 用 `223.5.5.5`（QEMU slirp 的 `10.0.2.3` 在部分网络下不可达）。
4. **必须挂 `/dev/shm`** —— 容器内不挂 tmpfs 会导致 QQ 渲染与登录异常。
5. **`-cpu max` 会 soft lockup** —— 改用 `-cpu cortex-a72`。
6. **注入时序：先注入、后扫码** —— SnowLuma 要在登录前加载 hook；
   若先登录再注入会永远停在 `login identity discovered ... awaiting readiness`。
7. **SnowLuma 2.3.0 的 arm64 hook 有回归 bug** —— 注入成功但 QQ 数秒内崩溃，
   2.3.2 已修复，请勿使用 2.3.0。
8. **QQ 在无头环境不会自动刷新登录二维码** —— 过期即蒙版，需重启 QQ 出新码。
9. **镜像被强杀后会脏** —— 操作前必须 `e2fsck -f -y`。
10. **QEMU 在 `-nographic` 下可能忽略 SIGTERM** —— 需要 `kill -9`。

---

## 常见问题

**Q：手机上会不会很卡？**
AstrBot 跑在 PRoot 里（接近原生速度），只有 QQ + SnowLuma 在虚拟机内（约 3 倍慢）。
日常挂机器人是够用的。

**Q：需要多少存储和内存？**
约 4–6 GB 存储（含镜像与依赖），建议虚拟机分配 2.5 GB 内存，
设备至少 8 GB RAM 体验较好。

**Q：扫码一直提示"二维码已过期"？**
QQ 在无头环境不会自动刷新二维码。请重新启动 QQ 生成新码，
或用应用内的远程桌面（6081）直接操作 QQ 窗口登录。

**Q：能换回 NapCat 吗？**
可以，但 PRoot 下 NapCat 走 `LD_PRELOAD` 方案，需要单独适配；
本项目聚焦 SnowLuma。

---

## 合规声明

- 本项目**不包含、不分发**腾讯公司的 Linux 版 QQ 客户端，也不分发 SnowLuma 二进制。
  它们由安装脚本在**用户自己的设备上**从官方渠道下载，用户需自行同意其许可协议。
- 本项目的原创代码以开源方式提供；第三方组件版权归各自权利人所有。
- 使用非官方客户端 / 自动化消息桥接存在账号被限制或封禁的风险，请自行评估，
  并遵守《腾讯 QQ 软件许可及服务协议》与所在地法律法规。
- 本项目与腾讯公司、AstrBot 官方团队、SnowLuma 项目组均无隶属或合作关系。

完整条款见 [privacy_policy.md](privacy_policy.md)。

---

## 致谢

- [AstrBot](https://github.com/AstrBotDevs/AstrBot) —— 聊天机器人框架
- [SnowLuma](https://github.com/SnowLuma/SnowLuma) —— QQ 互操作运行时（OneBot v11）
- [linux-qq / QQ NT](https://im.qq.com/) —— 官方 Linux 客户端
- [QEMU](https://www.qemu.org/) —— 虚拟机监控器
- 上游 Android 应用骨架与安装器设计（基于开源项目的重构版）
