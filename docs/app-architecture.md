# DSH 伴侣 — 应用架构与协作契约

本文件是团队的**唯一架构契约**。改动架构、新增依赖、修改 `lib/core/contracts.dart` 前先在这里更新，并在 Team 任务里同步。

## 1. 产品范围（MVP）

目标：给 DeepSeek Harness 一个手机端「遥控器 + 仪表盘」，不是 WebView 套壳。

**做（MVP）**

1. **配对与设备管理**：粘贴 dsh-mobile 配对链接（或手动填地址 + 配对码），配一次记住；设备列表支持连接 / 删除 / 重命名。
2. **会话列表**：标题、工作区、模型、状态（进行中 / 等待输入 / 空闲 / 完成）、最近活动时间；下拉刷新；实时更新。
3. **会话详情**：流式事件（用户消息、assistant 文本、工具调用、状态变化）；工具调用以卡片显示（名称、参数摘要、状态）。
4. **审批 / 提问**：待批准的工具调用、提问卡片，手机上直接「允许 / 拒绝 / 选一个选项」。
5. **通知**：应用在前台/后台存活时，任务完成、等待输入 → 系统本地通知；设置里可开关。
6. **快速发消息**：详情页输入框发一句话让 Agent 继续（支持多行输入）。

**不做（MVP 之后）**

- 二维码相机扫码（先用「粘贴链接」；第二阶段加扫码）
- 图片/文件附件上传、语音、Markdown 全量渲染（先做纯文本 + 代码块等简版）
- 远程推送（FCM）、多账号、iOS、Windows 桌面
- 修改 dsh-mobile 插件本身（它是外部依赖，不改源码）

## 2. 连接层（已确认可行）

```
┌──────────────┐  HTTPS/WSS (局域网或远程)   ┌────────────────────┐  loopback   ┌──────────────┐
│ Flutter App  │ ──────────────────────────▶ │ dsh-mobile 网关     │ ──────────▶ │ DSH Web 服务  │
│ (dsh-companion)│  设备令牌 / 会话 Cookie    │ (已安装, 0.6.2)     │  带认证     │ (RPC + WS)   │
└──────────────┘                             └────────────────────┘             └──────────────┘
```

关键事实（已从本机 `dsh-mobile` 0.6.2 代码确认）：

- 网关当前监听 `192.168.0.198:3443`，TLS 为托管私有 CA；配对令牌格式见 `docs/protocol.md`。
- **Native 配对 API**（不需要 WebView）：
  - `POST /mobile-access/auth/native-pair` `{token, label?}` → `201 {instanceId, deviceId, deviceToken, deviceExpiresAt, sessionToken, csrfToken, sessionExpiresAt}`
  - `POST /mobile-access/auth/native-renew` `{deviceToken}` → `200 {instanceId, deviceId, sessionToken, csrfToken, sessionExpiresAt}`
  - `POST /mobile-access/auth/native-probe` `{deviceToken}` → `200 {instanceId, deviceId, deviceExpiresAt}`
- 会话凭据通过 Cookie 携带（名称/细节见 `docs/protocol.md`），写操作可能需要 CSRF 头。
- 之后 App 通过网关访问 DSH Web 的 RPC：一元调用 `POST /api`（JSON 信封 `{type:'client-request', rpcId, method, payload}`），流式事件走 WebSocket `/api/remote.mux`（信封见 `@deepseek-ai/dsh-client-connection` 的 `rpc.d.ts`）。
- 局域网自签证书需要固定 CA：配对链接里带 CA 指纹/证书，App 用自定义 `HttpClient.badCertificateCallback` 校验指纹（不要全局忽略证书）。

> 协议细节以 `docs/protocol.md`（protocol-scout 产出）为准；本文件只锁架构。

## 3. 代码结构

```
lib/
  main.dart                      # 入口：runApp(DshCompanionApp())
  app.dart                       # MaterialApp、主题、路由表、Provider 注入（flutter-core 拥有）
  core/
    contracts.dart               # ★ 架构契约：模型 + CompanionController 抽象 + CompanionGateway 抽象（Lead 拥有）
    models/                      # 如需拆分模型（flutter-core 拥有）
    gateway/                     # 配对、认证、RPC、WS 实现（flutter-core 拥有）
    storage/                     # 设备记录安全存储、设置存储（flutter-core 拥有）
    state/                       # CompanionControllerImpl、SessionFeed 实现（flutter-core 拥有）
    util/                        # 日志、错误类型等（flutter-core 拥有）
  ui/
    screens/                     # devices / pair / sessions / session_detail / settings（flutter-ui 拥有）
    widgets/                     # 事件卡片、审批卡片、状态徽章、空状态等（flutter-ui 拥有）
    theme.dart                   # 颜色、排版、深色/浅色（flutter-ui 拥有）
test/
  core/                          # 单测：协议编解码、cookie/CSRF、重连、状态机（flutter-core）
  ui/                            # widget 测试：用 FakeCompanionController（flutter-ui）
  fixtures/                      # 共享测试数据、fake 控制器（flutter-ui 建，core 可复用）
docs/
  protocol.md                    # 协议调研（protocol-scout）
  app-architecture.md            # 本文件
  dev-environment.md             # 本机环境与协作规范（Lead）
tools/
  mock-gateway/                  # Node 模拟网关，供单测/联调（protocol-scout）
scripts/
  push_github.mjs                # GitHub API 推送（不能用 git push）
.github/workflows/build.yml      # CI：analyze + test + build APK + Release
```

**依赖方向（硬约束）**

- `ui/` 只允许 import：`core/contracts.dart`、`ui/` 内部、Flutter/第三方包。**不得** import `core/gateway`、`core/state` 的实现文件。
- `core/` 不 import `ui/`。
- 两边都不得改对方的目录；跨目录需求发消息给 Lead 协调。

## 4. 数据模型与控制器契约

以 `lib/core/contracts.dart` 为准（Lead 维护，任何改动先同步）。要点：

- `DeviceRecord`：`instanceId, label, origin, deviceToken(secret), caFingerprint?, kind(lan/remote), expiresAt, lastConnectedAt`
- `SessionSummary`：`id, title, workspace?, model?, status(SessionStatus), updatedAt, lastActivity?`
- `SessionEvent`：sealed 概念上的事件（message / tool / approval / status / usage），用 `enum SessionEventKind` + 工厂构造，便于 JSON 扩展
- `ApprovalRequest`：`id, sessionId, kind(tool/question), title, detail, options[], allowMultiple, createdAt`
- `CompanionGateway`：`pair()`, `renew()`, `listSessions()`, `watchSession()`, `sendPrompt()`, `respondApproval()`, `pendingApprovals()`, `logout()`
- `CompanionController extends ChangeNotifier`：UI 唯一状态入口（devices/sessions/activeSession/connection/load*/pair*/connect*/refresh*/send*/decide*/remove*）
- `SessionFeed extends ChangeNotifier`：单个会话的事件列表 + 连接状态
- `AppSettings`：`notificationsEnabled, notifyOnComplete, notifyOnWaiting, themeMode`
- 失败统一 `CompanionException(code, message, {details})`，UI 只展示 `message`，日志记 `code`。

## 5. UI 结构

- 启动：`DevicesScreen`（无设备时显示「配对第一台电脑」空状态）
- 配对：`PairScreen`（粘贴链接 / 手动地址 + 配对码；成功后回设备列表）
- 会话：`SessionsScreen`（列表 + 状态徽章 + 下拉刷新 + 连接状态条）
- 详情：`SessionDetailScreen`（事件流 + 底部输入 + 审批卡片内联 + 自动滚动）
- 设置：`SettingsScreen`（通知开关、设备管理、诊断日志、版本）
- 中文为主界面；文案集中放 `ui/strings.dart`（便于以后 i18n）

## 6. 测试策略

- **core**：协议编解码单测（fixture JSON）、cookie/CSRF 处理、配对流程（对 `tools/mock-gateway` 或本地 HttpServer 打桩）、WS 事件解析与重连、控制器状态机。
- **ui**：widget 测试全部用 `FakeCompanionController`（`test/fixtures/`），覆盖：空状态、会话列表渲染、事件流渲染、审批交互、错误态。
- CI 必跑：`flutter analyze` + `flutter test`；本地同样命令，必须 0 warning / 全绿。

## 7. 交付与验收

- CI 绿（analyze/test/build APK），Release 能下载到 arm64 APK。
- 真机/局域网：手机装 APK → 粘贴配对链接 → 看到会话 → 打开会话看到实时事件 → 发一句话 → 任务完成收到通知 → 审批卡片能操作。
- 首版版本号 `0.1.0+1`，tag `v0.1.0`。

## 8. 里程碑

1. **M0 基础设施**（Lead）：仓库、CI、推送脚本、Flutter SDK 本机安装、空工程 analyze/test 绿。
2. **M1 协议**（protocol-scout）：`docs/protocol.md` + mock 网关 + 一份真实抓包验证记录。
3. **M2 核心层**（flutter-core）：模型/网关/存储/控制器 + 单测。
4. **M3 UI**（flutter-ui）：五个页面 + Fake 控制器 widget 测试。
5. **M4 集成**（Lead + 全员）：真机端到端，修问题，发 `v0.1.0`。
