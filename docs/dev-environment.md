# 本机开发环境与协作规范

## 机器现状（别重复探测）

- 工作目录：`C:\Users\youzhai\Desktop\插件开发\dsh-companion`（仓库）。
- OS：Windows，C 盘剩余约 72GB。
- **没有** Android SDK / JDK / Visual Studio；**不要**尝试本地跑 `flutter build apk`，APK 一律由 GitHub Actions 构建。
- 已装：Git、GitHub CLI（`gh`，已登录 `youzhaiZhi`）、adb（`C:\Users\youzhai\AppData\Local\Microsoft\WinGet\Packages\Google.PlatformTools...\platform-tools\adb.exe`）。
- Node（DSH 自带，勿装）：`C:\Users\youzhai\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe`。`node` 不在 PATH，脚本里用绝对路径。
- Flutter SDK：安装在 `C:\Users\youzhai\flutter`（本机只装了 SDK，用于 `flutter analyze` / `flutter test`；Android 工具链不装）。用 `C:\Users\youzhai\flutter\bin\flutter.bat` 调用。
- 环境变量（本机 Flutter 下载依赖）：`FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`、`PUB_HOSTED_URL=https://pub.flutter-io.cn`。

## 网络：为什么不能用 git push

- `github.com:443`、`codeload.github.com`、`raw.githubusercontent.com` 全部超时；`api.github.com` 正常。
- 因此**不要**用 `git push` / `git clone` / `git fetch` 与 GitHub 交互。用：
  - `node scripts/push_github.mjs "commit message"` —— 把当前工作区快照成一个 commit 推到 `main`（Git Data API，全量快照，删除文件会同步删除）。
  - `gh api ...` / `gh run ...` / `gh release ...` —— 走 api.github.com，可用。
- 仓库：`youzhaiZhi/dsh-companion`（public，默认分支 main）。

## 常用命令

```powershell
$flutter = 'C:\Users\youzhai\flutter\bin\flutter.bat'
$node    = 'C:\Users\youzhai\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe'

# 依赖 / 静态检查 / 单测（本地）
& $flutter pub get
& $flutter analyze
& $flutter test

# 推送代码（替代 git push）
& $node scripts\push_github.mjs "feat: xxxx"

# 触发/查看 CI（api.github.com 可用）
gh workflow run build.yml --repo youzhaiZhi/dsh-companion
gh run list --repo youzhaiZhi/dsh-companion --limit 5
gh run view <run-id> --repo youzhaiZhi/dsh-companion --log-failed
gh run watch <run-id> --repo youzhaiZhi/dsh-companion

# 手动发布 Release（触发器里填 release_tag，或推 v* tag 后由 workflow 发布）
gh release list --repo youzhaiZhi/dsh-companion
gh release download --repo youzhaiZhi/dsh-companion --pattern '*.apk' --dir "$env:TEMP\apk"
```

## 推送节奏（避免互相覆盖工作区）

- **Lead 统一负责推 GitHub**，其他人不要自己跑 `push_github.mjs`（会扫全工作区，可能把别人未完成的改动一起推）。
- 各目录所有者见 `docs/app-architecture.md` 第 3 节；不要改别人的目录。
- Flutter 本地命令（pub get）可能并发冲突；同一时间只由一个人跑 `flutter pub get`，Lead 会在需要时统一跑。

## 真机 / DSH 侧现状（联调参考）

- DSH Desktop `0.2.1-rc.2`，profile `desktop`；已装 `dsh-mobile` 0.6.2，正在运行。
- 网关当前监听：`192.168.0.198:3443`（WLAN，托管私有 CA TLS）；`$DSH_HOME\mobile-access\` 下有 setup/设备记录/CA 证书。
- 已注册一台设备 label `DeepSeek Harness Android`（token 摘要不可逆，不能用它当测试凭据）。
- 联调需要用户配合：在 DSH「设置 → 移动访问 → 局域网 → 创建配对密钥/链接」，把链接贴给我们；或由协议同学先用 mock 网关自测。
- DSH Web 本机服务：`http://127.0.0.1:56806`（需要 `dsh web` 打印的 token，直接访问 401）；不要试图绕过认证。
- 不要修改、重启、卸载 dsh-mobile 插件或 DSH 本身；只读可以参考其代码：
  `C:\Users\youzhai\.dsh\profiles\desktop\node_modules\dsh-mobile\lib\index.mjs`（可读的编译产物，含 native-pair 等实现）。
