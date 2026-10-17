# DSH 伴侣（dsh-companion）

DeepSeek Harness 的 Flutter 轻量伴侣 Android App。

> 施工中。当前仓库还在搭建基础骨架，功能与文档随后补齐。

## 目标

给 DSH 配一个手机上用得顺手的「遥控器 / 仪表盘」，而不是再套一层 WebView：

- **会话列表**：看得到所有会话、标题、最近活动和运行状态
- **实时任务状态**：进行中 / 等待输入 / 已完成，流式刷新
- **通知**：任务完成、等待输入时推系统通知
- **远程审批**：工具调用、提问卡片，手机上直接批 / 拒 / 选
- **快速发消息**：选一个会话，发一句话让 Agent 继续干活

连接层复用已安装的 `dsh-mobile` 插件网关：局域网 HTTPS + 设备配对 + 私有 CA 固定，配一次就行，局域网/远程通道都能用。

## 构建

APK 由 GitHub Actions 构建（arm64-v8a），发布到本仓库 Release：

- 推送 `main`：跑 analyze / test / build，APK 作为 artifact
- 手动触发并填写 `release_tag`（或推 `v*` tag）：额外发布 Release

从 Release 下载：

```powershell
gh release download --repo youzhaiZhi/dsh-companion --pattern '*.apk'
```

## 开发

本机开发只需要 Flutter SDK（`flutter analyze` / `flutter test`），APK 交给 CI。
协议调研结论见 `docs/protocol.md`，代码结构见 `docs/app-architecture.md`。

## 许可

个人项目，未经许可请勿分发。
