# DSH 伴侣 ↔ dsh-mobile 网关协议（实测 + 源码推导）

> 本文档是 App 连接层的依据。**置信度**标注：
> ✅ 源码/实测确认；🟡 源码推导、未经真机实测；🔴 未确认（需要真机抓包）。
> 源码依据：本机 `dsh-mobile` 0.6.2（`~/.dsh/profiles/desktop/node_modules/dsh-mobile/lib/index.mjs`，含 TS 源码）与 DSH 0.2.1-rc.2 的 `@deepseek-ai/*` 包（app.asar 内含原始 TS）。

## 1. 连接拓扑

```
Flutter App ──HTTPS/WSS──▶ dsh-mobile 网关(192.168.x.x:3443, 私有 CA TLS) ──loopback──▶ DSH Web(RPC + WS)
```

网关对外只暴露：`/mobile-access/*`（配对/认证/页面）、`/ca.cer`（公开 CA）、`/api`（一元 RPC 代理）、`/api/remote.mux`（WS 流代理，受白名单保护）。

## 2. 配对与认证 ✅

### 2.1 配对链接

```
https://<host>:<port>/mobile-access/pair#instance=<64hex>&token=<one-time 43字符>
```

- `instance`：网关安装标识，**等于私有 CA 证书 DER 的 SHA-256 指纹**（实测 `GET /mobile-access/discovery` 与 `GET /ca.cer` 一致）✅
- `token`：一次性配对码，**10 分钟量级 TTL，用一次即失效**，重复使用返回 `401 authentication_failed` ✅

### 2.2 固定 CA（防中间人）

1. `GET /ca.cer`（无需认证，返回 DER，359 字节）✅
2. `sha256(der) == instance`，不一致必须中止配对 ✅
3. 之后所有请求只信任该 CA（Dart：`SecurityContext(withTrustedRoots:false)..setTrustedCertificatesBytes(pem)`）。

### 2.3 Native 认证端点 ✅

| 方法 | 路径 | 请求体 | 响应 |
| --- | --- | --- | --- |
| POST | `/mobile-access/auth/native-pair` | `{token, label?}` | `201 {instanceId, deviceId, deviceToken, deviceExpiresAt, sessionToken, csrfToken, sessionExpiresAt}` |
| POST | `/mobile-access/auth/native-renew` | `{deviceToken}` | `200 {instanceId, deviceId, sessionToken, csrfToken, sessionExpiresAt}` |
| POST | `/mobile-access/auth/native-probe` | `{deviceToken}` | `200 {instanceId, deviceId, deviceExpiresAt}` |
| POST | `/mobile-access/auth/logout` | `{}` + 会话 Cookie + CSRF | `200` |

- 设备令牌有效期约 180 天；会话凭据短期有效，App 启动/401 时用 native-renew 续期。
- 失败：`401 authentication_failed`（配对码过期/令牌无效）、`429 rate_limited`（限流）、`400 bad_request`。

### 2.4 会话凭据在请求里怎么带 ✅

TLS 网关使用 `__Host-` 前缀 Cookie（源码 `browser-auth-cookies.ts`）：

```
Cookie: __Host-dsh_ma_session=<sessionToken>; __Host-dsh_ma_csrf=<csrfToken>
x-dsh-mobile-csrf: <csrfToken>        # 仅非 GET/HEAD 请求需要
```

（明文 HTTP 部署时 Cookie 名为 `dsh_ma_session` / `dsh_ma_csrf`，本 App 只走 HTTPS。）

## 3. 一元 RPC ✅

```
POST /api
Content-Type: application/json
Cookie: __Host-dsh_ma_session=...; __Host-dsh_ma_csrf=...
x-dsh-mobile-csrf: ...

{"type":"client-request","rpcId":"<随机 id>","method":"session/list","payload":{"args":{...}}}
```

响应：

```
{"type":"server-response","rpcId":"<同一个 id>",
 "result":{"ok":true,"value": ...}}                    // 成功
  或 {"ok":false,"error":{"code":"session/not-found","message":"...","details":{...}}}
```

- `method` 是 `<namespace>/<method>`（如 `session/list`）。
- `payload` **必须且只能有 `args` 一个字段**，且 `args` 是普通对象（源码 `remoteRequest()` 强校验）。
- 错误码示例：`session/not-found`、`session/agent-busy`、`session/writer-held`、`gateway/input-invalid`、`remote-access/denied`、`gateway/*`。

## 4. 流式 RPC（WS `/api/remote.mux`）✅

与浏览器客户端使用同一个端点，帧格式来自 `@deepseek-ai/dsh-api-gateway` 的 `stream-protocol`：

```
ws(s)://<origin>/api/remote.mux
Cookie: __Host-dsh_ma_session=...; __Host-dsh_ma_csrf=...

client → host:
  {"type":"open","streamId":"<uuid>","endpoint":"session/follow","payload":{"args":{...}}}
  {"type":"item","streamId":"...","value":...}      // 上行（多数流不需要）
  {"type":"end","streamId":"..."}                   // 半关闭上行
  {"type":"cancel","streamId":"..."}                // 取消

host → client:
  {"type":"item","streamId":"...","value":...}      // 下行项（第一条是 opening/baseline）
  {"type":"end","streamId":"..."}
  {"type":"error","streamId":"...","error":{"code":"...","message":"..."}}
```

- Host 每 2s 发 WS Ping；连续两个周期无活动会断开 → App 侧需要重连（退化后可重开流）。
- 后台任务完成/等待输入通知走 Host 事件（`$events` 流 + SSE），**离线不重放**。

## 5. MVP 使用的 endpoint

| 用途 | 端点 | args | 返回/事件 | 置信度 |
| --- | --- | --- | --- | --- |
| 会话列表 | `session/list` | `{}` | `{rows:[{sessionId,title,cwd,updatedAt,formatStatus,agentAvailable,...}]}` | 🟡 行结构按源码推断，字段名可能不同 |
| 会话事件流 | `session/follow`（stream） | `{sessionId}` | opening 快照 + `{type:'event', event:{type,data,seq}}` | 🟡 args 名待确认 |
| 发消息 | `session/prompt` | `{sessionId, requestId, content:[{type:'text',text}]}` | 接受结果 | 🟡 结构按 `session/prompt` 源码 |
| 审批应答 | `$events/result`（一元 RPC） | `{clientId, eventId, outcome:{kind:'result', value:'allowed-once'\|'rejected'}}` | — | ✅ 源码确认（见下方专节） |
| 事件名 | — | — | `turn/start`,`turn/end`,`user/message`,`assistant/message`,`tool/call`,`tool/result`,`approval/asked`,`approval/decided`,`job/registered`,`job/settled`,`session/title` | ✅ `SessionEventMap` |

## 6. 审批 / 提问：走 `$events` 瀑布，不是普通 RPC ✅

⚠️ **重要纠正**：早期以为审批是 `approval/decide` 这类普通 RPC，**这是错的**。
`approval/asked` 与 `approval/decided` 只是写入会话日志的审计事件（`dsh-user-approval` 源码：*Both are log-only*）。
真正「人怎么作答」走的是 **Client 事件瀑布（waterfall）**：

### 6.1 订阅

```
WS /api/remote.mux
client → host: {"type":"open","streamId":"...","endpoint":"$events","payload":{"args":{}}}
host → client: {"type":"item","streamId":"...","value":{"type":"ready","clientId":"<id>","host":{"home":"..."}}}
```

`clientId` 之后每次应答都要带上。

### 6.2 审批帧

```
host → client: {"type":"item","streamId":"...","value":{
  "type":"event",
  "event":"approval/request",      // 提问卡片对应 dsh-user-questions 的事件名
  "eventId":"<id>",
  "agentId":"<id>",
  "request":{ ...具体请求，按事件类型... }   // 不含 agent / signal
}}
```

客户端 UI 的等价实现（`dsh-client-ui-approval`）：
`ctx.remote.$on("approval/request", (request, next) => answerApproval(...))`，
用户点按钮后 `pending.answer("allowed-once" | "rejected")`。

### 6.3 应答

```
POST /api
{"type":"client-request","rpcId":"...","method":"$events/result","payload":{"args":{
  "clientId":"<ready 帧里的 clientId>",
  "eventId":"<事件帧里的 eventId>",
  "outcome":{"kind":"result","value":"allowed-once"}     // 或 "rejected"
}}}
```

- `outcome.kind` 只能是 `next`（交给下个监听者）/ `result` / `rejected`（带 error）。
- 只有持有 `$events` 流、且 `interactions === 'answer'` 的 Peer 才能应答。
- Host 可能发送 `{"type":"cancel","eventId":"..."}` 撤回请求，此时不应再应答。

> 结论：**审批必须挂在同一条 `$events` 长连上**，因此 App 的事件模型要从「每会话开一条 `session/follow`」调整为「一条 `$events` + 按 agentId/sessionId 分发」。这是下一轮重构的重点。

## 7. 通知与状态折叠（App 侧逻辑）

App 不做协议层的额外订阅，只把 `session/follow` 的事件折叠成列表状态，再据此发系统通知：

| 事件 | 列表状态 | 通知 |
| --- | --- | --- |
| `turn/start` | running | 无 |
| `turn/end` | idle | 「DSH 任务已完成」（`notifyOnComplete`） |
| `approval/asked` | waitingInput | 「DSH 等待你的输入」（`notifyOnWaiting`） |
| `error` | idle | 无 |

- 只在**状态真的变化**时触发，避免同一状态多次提醒。
- 通知总开关与分类开关都在设置页，存 `SharedPreferences`。
- 通知依赖 App 进程存活（没有后台常驻/FCM），进程被回收后收不到。

## 8. 已知不确定项（下一步真机验证）

1. `session/list` 的实际行字段（标题取 `title` 还是 `displayTitle`；运行状态字段名）。
2. `session/follow` 的 args 形态（`sessionId` / `address.sessionId` / `address:{kind,sessionId}`）与 opening 快照结构。
3. 审批/提问的应答端点与字段（`approval/decide` 还是 `ui/approvals` 之类）。
4. 任务完成/等待输入事件的可靠来源（`$events` vs 每会话 `session/follow`）。

验证方法：本地 `tools/mock-gateway`（进行中）+ 真机配对后用 `scripts/probe` 发只读请求，把实际 JSON 回填到本文档。

## 9. 参考源码位置

- dsh-mobile 网关：`~/.dsh/profiles/desktop/node_modules/dsh-mobile/lib/index.mjs`（TS 源码在 sourcemap 中）
- DSH 客户端包（`@deepseek-ai/dsh-api-gateway`、`dsh-client-connection`、`dsh-api-session-controller`、`dsh-client-ui-*`）：`tools/mock-gateway/.scratch/dsh-pkgs/`（本地研究用，不入库）
