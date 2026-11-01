# 星萤AstrBot（Android 应用）

在手机上本地运行 **AstrBot + SnowLuma** 的 Android 应用。

- 应用名：**星萤AstrBot**
- 包名：`com.firefiy99.astrbot_snow`
- 版本：`1.0.1-xingying.1`（versionCode 7）
- 作者：**小星萤** ｜ QQ **3010009516** ｜ [@firefiy99](https://github.com/firefiy99)

## 下载

到本仓库 **[Releases](../../releases)** 页面下载最新 APK：

| 文件 | 说明 |
|---|---|
| `星萤AstrBot-v1.0.1-xingying.1.apk` | 完整安装包（约 90 MB，V1/V2/V3 已签名） |

> 该 APK 使用自签证书，与任何官方/第三方版本签名不同，
> 因此是**独立应用**，不会覆盖手机上已有的同类应用。

## 它做什么

应用是一个「安装引导 + 服务面板」，本身不包含机器人运行时。
首次安装时它会：

1. 在应用私有目录创建一个 **PRoot Linux 环境**（Ubuntu/Debian rootfs）
2. 在其中安装 **AstrBot**（Python 聊天机器人框架）及其依赖
3. 安装 **QEMU** 与一个 **Debian 虚拟机系统包**
4. 在虚拟机内安装 **Linux 版 QQ** 与 **SnowLuma**（从官方渠道下载）
5. 启动后提供三个本地入口：

| 服务 | 地址 | 用途 |
|---|---|---|
| AstrBot WebUI | `http://127.0.0.1:6185` | 配置模型、插件、人设、查看日志 |
| SnowLuma WebUI | `http://127.0.0.1:5099` | 查看 QQ 连接状态、注入、OneBot 配置 |
| 远程桌面（noVNC） | `http://127.0.0.1:6081` | **扫码登录 QQ**、操作 QQ 窗口 |

## 使用流程

```
安装应用
  ↓
打开应用 → 点「安装」（首次约需下载 700 MB ~ 1 GB，建议 Wi-Fi）
  ↓
点「启动」→ 等待虚拟机拉起（约 30~60 秒）
  ↓
浏览器打开 127.0.0.1:6081（远程桌面）→ 在 QQ 窗口扫码登录
  ↓
登录成功后 SnowLuma 自动完成 hook 注入，状态变为 ready
  ↓
浏览器打开 127.0.0.1:6185（AstrBot）→ 配置模型 → 机器人上线
```

### 第一次一定要知道的几件事

1. **必须先注入、后扫码。** 应用已按正确时序启动（先起 QQ → 再起 SnowLuma 自动注入），
   所以正常流程下直接扫码即可。若你先手动登录再注入，会卡在 `awaiting readiness`。
2. **二维码过期不会自动刷新。** QQ 在无头环境不会自己换码。
   过期后请重启 QQ（应用内「重启 QQ」），或直接在远程桌面里点 QQ 的刷新按钮。
3. **不要同一账号同时跑两套实例**，会互相踢下线。
4. **SnowLuma 必须 ≥ 2.3.2。** 2.3.0 的 arm64 hook 有回归 bug，注入后 QQ 会崩溃。

## AstrBot 默认凭据

首次启动后在 AstrBot 日志中会打印初始账号密码，也可在 `127.0.0.1:6185` 直接查看。
如需重置：删除容器内 `AstrBot/data/cmd_config.json` 中的 dashboard 段后重启。

## 系统要求

- Android 9 及以上（实测 Android 16 / arm64）
- arm64 设备
- 至少 6 GB 可用存储、8 GB 内存体验较好
- **不需要 root，不需要解锁 BootLoader**

## 已知限制

- 虚拟机使用 QEMU 软件模拟（TCG），CPU 性能约为原生的 1/3；
  AstrBot 跑在 PRoot 内接近原生，只有 QQ + SnowLuma 受影响。
- 首次安装耗时较长（依赖网络，通常 10~30 分钟）。
- 后台常驻会持续耗电，建议在系统设置中为应用开启「允许后台运行」并关闭电池优化。

## 隐私与免责

- 应用**不收集任何设备信息、不上传日志、不含统计或广告 SDK**。
- 所有数据（配置、聊天、账号登录态）均保存在你自己的设备上。
- 使用第三方 QQ 客户端与消息桥接存在账号被限制或封禁的风险，请自行评估。
- 应用**不包含**腾讯公司的 QQ 客户端与 SnowLuma 二进制，二者在安装时由你的设备
  从官方渠道下载。

完整条款见 [privacy_policy.md](privacy_policy.md)。

## 相关仓库

- 部署脚本与虚拟机系统：[firefiy99/astrbot-snowluma-build](https://github.com/firefiy99/astrbot-snowluma-build)
