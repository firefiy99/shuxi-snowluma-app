# 星萤AstrBot（Android 应用 + 部署资产）

在手机上本地运行 **AstrBot + SnowLuma** 的完整方案，**应用与部署资产在同一个仓库**。

- 应用名：**星萤AstrBot**
- 包名：`com.firefiy99.astrbot_snow`
- 当前版本：`1.0.6-xingying.1`（versionCode 12）
- 作者：**小星萤** ｜ QQ **3010009516** ｜ [@firefiy99](https://github.com/firefiy99)

## 下载

到本仓库 **[Releases](../../releases)** 页面，一个 release 里包含全部所需文件：

| 资产 | 用途 |
|---|---|
| `xingying-astrbot-v1.0.6-xingying.1.apk` | **Android 安装包**（约 90 MB，V1/V2/V3 已签名） |
| `astrbot-installer-v1.1.0.tar.gz` | 安装脚本包（Ed25519 验签） |
| `manifest.json` / `manifest.sig` | 清单与签名 |
| `snowluma-guest-v1.0.0.tar.xz` | 虚拟机系统包（内核 + initramfs + rootfs，约 93 MB） |

> APK 使用自签证书，与任何官方/第三方版本签名不同，因此是**独立应用**，不会覆盖手机上已有的同类应用。

## 它做什么

应用是「安装引导 + 服务面板」，本身不含机器人运行时。首次安装时它会：

1. 在应用私有目录创建 **PRoot Linux 环境**
2. 在其中安装 **AstrBot** 及其依赖
3. 安装 **QEMU** 并解出 **Debian/Ubuntu 虚拟机系统包**
4. 虚拟机内安装 **Linux 版 QQ** 与 **SnowLuma**（从官方渠道下载）
5. 启动后提供三个本地入口：

| 服务 | 地址 | 用途 |
|---|---|---|
| AstrBot WebUI | `http://127.0.0.1:6185` | 配置模型、插件、人设、看日志 |
| SnowLuma WebUI | `http://127.0.0.1:5099` | QQ 连接状态、注入、OneBot 配置 |
| 远程桌面（noVNC） | `http://127.0.0.1:6081` | **扫码登录 QQ**、操作 QQ 窗口 |

## 使用流程

```
安装应用 → 点「安装」（首次约 700 MB ~ 1 GB，建议 Wi-Fi）
        → 点「启动」，等虚拟机拉起（30~60 秒）
        → 打开 127.0.0.1:6081 扫码登录 QQ
        → SnowLuma 自动注入，状态变 ready
        → 打开 127.0.0.1:6185 配置模型，机器人上线
```

### 需要注意

1. **必须先注入、后扫码。** 应用已按正确时序启动（先起 QQ → 再起 SnowLuma 自动注入）。
   若先登录后注入，会卡在 `awaiting readiness`。
2. **二维码过期不会自动刷新。** 过期后重启 QQ 出新码，或在远程桌面里点刷新。
3. **不要同一账号同时跑两套实例**，会互相踢下线。
4. **SnowLuma 必须 ≥ 2.3.2。** 2.3.0 的 arm64 hook 有回归 bug，注入后 QQ 会崩溃。

## 系统要求

- Android 9 及以上（实测 Android 16 / arm64）
- arm64 设备，至少 6 GB 可用存储、8 GB 内存体验较好
- **不需要 root，不需要解锁 BootLoader**

## 仓库内容

| 路径 | 说明 |
|---|---|
| `README.md` | 应用介绍与使用流程（本文件） |
| `DEPLOY.md` | 技术细节：架构、安装脚本、构建与发布 |
| `astrbot-startup.sh` | 安装/启动主脚本（PRoot 内执行） |
| `astrbot-installer-bootstrap.sh` | Ed25519 验签的在线更新引导器 |
| `launcher2.sh` | 第二实例启动器（QEMU 方案） |
| `guest/` | 虚拟机内部脚本：`init` / `boot.sh` / `provision.sh` / `start-services.sh` / `onebot.json` |
| `tools/` | `build-guest.sh`（构建系统包）、`make-release.sh`（签名打包） |
| `privacy_policy.md` | 隐私政策与免责声明（应用内展示） |

## 隐私与免责

- 应用**不收集设备信息、不上传日志、不含统计或广告 SDK**。
- 所有数据（配置、聊天、登录态）都保存在你自己的设备上。
- 使用第三方 QQ 客户端与消息桥接存在账号被限制或封禁的风险，请自行评估。
- 应用**不包含**腾讯公司的 QQ 客户端与 SnowLuma 二进制，
  二者在安装时由你的设备从官方渠道下载。

完整条款见 [privacy_policy.md](privacy_policy.md)。
