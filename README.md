# DSH 伴侣（dsh-companion）

DeepSeek Harness 的 Flutter 轻量伴侣 Android App —— 手机上查看会话、盯着任务跑、远程审批、随手发一句话让 Agent 继续。

![status](https://img.shields.io/badge/status-v0.2.0-4D6BFE)

## 现在能做什么

- **配对电脑**：粘贴 dsh-mobile 网关的配对链接（`https://<电脑IP>:3443/mobile-access/pair#instance=...&token=...`），配对一次长期记住；设备令牌与固定 CA 存在 Android Keystore 里。
- **会话列表**：标题、工作区、状态、最近活动时间，下拉刷新。
- **会话详情**：`session/follow` 实时事件流（用户/assistant 消息、工具调用卡片、轮次开始/结束、错误）。
- **任务通知**：任务完成、等待输入时发 Android 系统通知（可在设置里分别关闭；锁屏文本只显示会话标题）。
- **快速发消息**：底部输入栏，`session/prompt` 直接发给当前会话。
- **设置 / 诊断**：主题、通知开关、协议诊断日志（脱敏，不含令牌）。

连接层复用已安装的 [`dsh-mobile`](https://github.com/saya-ch/dsh-mobile) 插件网关：局域网 HTTPS + 私有 CA 固定 + 设备配对，**不修改 DSH / dsh-mobile 源码**。

## 下载安装

APK 由 GitHub Actions 构建（arm64-v8a），发布在 [Releases](https://github.com/youzhaiZhi/dsh-companion/releases/latest)：

```powershell
gh release download --repo youzhaiZhi/dsh-companion --pattern '*.apk'
```

电脑侧准备：DSH → 设置 → 移动访问 → 局域网 → 创建配对密钥 / 复制配对链接（几分钟内有效）。
手机安装 APK → 点「配对电脑」→ 粘贴链接。

## 当前限制（v0.2.0）

- **通知只在 App 进程存活时触发**：依赖 `session/follow` 事件流，没有后台常驻服务，也没有 FCM 推送。切到后台后系统可能回收进程，此时收不到提醒。
- **审批/提问应答尚未接通**：DSH 的审批走 `$events` 瀑布事件（不是普通 RPC），正确链路已在 `docs/protocol.md` 第 6 节写清，App 侧的事件订阅重构还没做；当前点击会明确提示「接入中」。
- 二维码扫码：暂用「粘贴链接」，相机扫码后续加。
- `session/list` / `session/follow` 的字段名做了宽松解析，个别字段（模型、预览）可能为空，等真机联调回填。

## 开发

本机只需要 Flutter SDK 做静态检查；**APK 一律交给 GitHub Actions**（本机没有 Android SDK/JDK）：

```powershell
# 本地检查（可选，机器内存小，analyze 可能 OOM）
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
C:\Users\youzhai\flutter\bin\flutter.bat analyze

# 推送代码（本机 github.com:443 不可达，用 Git Data API 推送）
node scripts\push_github.mjs "feat: ..."

# 触发发布
gh workflow run build.yml -R youzhaiZhi/dsh-companion -f release_tag=v0.1.1
```

## 目录

```
lib/
  core/contracts.dart          # UI ↔ 核心层契约（模型 + 控制器抽象）
  core/gateway/pairing.dart    # 配对链接解析、CA 固定、native-pair/renew/probe
  core/gateway/rpc.dart        # 一元 RPC（POST /api）+ WS mux（/api/remote.mux）
  core/gateway/companion_gateway_impl.dart  # DSH 返回 → 领域模型映射
  core/state/                  # CompanionControllerImpl / SessionFeedImpl / 诊断日志
  core/storage/                # 设备记录（Keystore）/ 设置（SharedPreferences）
  ui/screens/                  # 设备、配对、会话、详情、设置
docs/
  protocol.md                  # ★ 网关协议（配对/认证/RPC/WS + 置信度标注）
  app-architecture.md          # 架构与团队协作契约
  dev-environment.md           # 本机环境与推送/构建方式
.github/workflows/build.yml    # analyze + test + arm64 APK + Release
scripts/push_github.mjs        # Git Data API 推送（替代 git push）
```

## 许可

个人项目，未经许可请勿分发。
