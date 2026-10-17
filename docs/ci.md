# CI 与发布链路（docs/ci.md）

本文说明 `dsh-companion` 的 GitHub Actions 构建/发布流程、`android/` 配置约束，以及本机
环境下的发布与排障方式。工作流文件：`.github/workflows/build.yml`；发布脚本：
`scripts/release.mjs`（PowerShell 包装：`scripts/release.ps1`）。

## 1. 触发方式

| 触发 | 条件 | 结果 |
| --- | --- | --- |
| `push` 到 `main` | 任意提交 | analyze + test + 构建 APK，上传 artifact（不发 Release） |
| `push` `v*` tag | tag 名形如 `v0.1.0` | 同上，且自动发布 Release（tag 名即版本） |
| 手动 `workflow_dispatch` | 输入 `release_tag`（如 `v0.1.0`） | 同上；填了 `release_tag` 才发布 Release |
| 手动 `workflow_dispatch` | `release_tag` 留空 | 只构建并上传 artifact，可用于日常冒烟 |

手动触发（本机 api.github.com 可用，github.com 不可达）：

```powershell
gh workflow run build.yml --repo youzhaiZhi/dsh-companion -f release_tag=v0.1.0
gh run list --repo youzhaiZhi/dsh-companion --limit 5
gh run watch <run-id> --repo youzhaiZhi/dsh-companion
```

更推荐用 `scripts/release.mjs`（见第 4 节），它会一条龙完成触发 → 轮询 → 下载 → 校验。

## 2. 工作流步骤

`build` job（`ubuntu-latest`，timeout 45 分钟）：

1. `actions/checkout@v4`
2. **修正 gradle wrapper 可执行位**：仓库通过 Git Data API 推送，所有文件都是 `100644`，
   `android/gradlew` 在 Linux runner 上需要 `chmod +x`（workflow 里兜底处理）。
3. `actions/setup-java@v4`：Temurin **JDK 17**
4. `subosito/flutter-action@v2`：**Flutter 3.47.7 / stable / cache**
5. `flutter pub get` → `flutter analyze` → `flutter test`
6. `flutter build apk --release --target-platform android-arm64`
7. **ABI 校验**：用 `unzip -Z1` 列出 `lib/<abi>/`，必须恰好只有 `arm64-v8a`，
   且 `lib/arm64-v8a/libflutter.so` 存在；然后复制为 `dist/dsh-companion-arm64.apk`。
8. **签名校验**：用 runner 自带 `apksigner verify --print-certs` 确认 APK 已签名可安装。
9. `actions/upload-artifact@v4`：artifact 名 `dsh-companion-arm64`，保留 30 天。

`release` job（仅 tag / 带 `release_tag` 的 dispatch）：

- 解析发布 tag（tag push 用 tag 名；dispatch 用 `release_tag` 输入），必须以 `v` 开头；
- 下载 artifact → `softprops/action-gh-release@v2` 发布
  `dist/dsh-companion-arm64.apk`，自动生成 release notes；
- 该 job 权限提升为 `contents: write`（工作流默认 `contents: read`）。

## 3. android/ 配置约束（本仓库约定）

- `applicationId = "com.youzhai.dsh_companion"`。
- `minSdk = 23`（Android 6.0+），`targetSdk` 用 Flutter 默认。
- `AndroidManifest.xml` 必须有 `<uses-permission android:name="android.permission.INTERNET"/>`
  （连 dsh-mobile 网关必需），`android:label="DSH 伴侣"`。
- release 构建用 **debug 签名**（`signingConfig = signingConfigs.getByName("debug")`），
  保证 CI 产物直接可安装；**不要提交任何 keystore/jks/key.properties**（`.gitignore`、
  推送脚本均已排除）。将来要正式签名时再单独配置 secrets。
- 只构建 `arm64-v8a`：`flutter build apk --target-platform android-arm64` +
  `android/app/build.gradle.kts` 里 `abiFilters += "arm64-v8a"` 双保险。

## 4. 发布脚本

Node 不在 PATH，用 DSH 自带 node 或 `scripts/release.ps1` 包装（自动找 node）：

```powershell
$node = 'C:\Users\youzhai\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe'
& $node scripts\release.mjs v0.1.0                 # 触发 CI → 等待 → 校验 Release → 下载 APK
& $node scripts\release.mjs v0.1.0 --download-only # 只下载已有 Release（验收用）
& $node scripts\release.mjs --status               # 看最近 10 次 run

# 或
powershell -ExecutionPolicy Bypass -File scripts\release.ps1 v0.1.0
```

脚本行为：

1. `gh workflow run build.yml -f release_tag=<tag>` 触发；
2. 轮询新 run，打印每个 job 的状态变化；
3. CI 失败时打印失败 job / 步骤名，并输出 `gh run view --log-failed` 尾部 200 行；
4. 成功后确认 Release、`gh release download` 到 `dist/`（失败则回退 `api.github.com`
   asset API 下载，绕开 github.com 不可达的问题）；
5. 打印 APK 路径、体积、SHA256、ABI 列表，并校验是否仅 `arm64-v8a`。

## 5. 版本号与 tag 约定

- `pubspec.yaml`：`version: 0.1.0+1`（`+` 后是 versionCode，每次发布递增）。
- Release tag：`v0.1.0`（与 pubspec 的版本号一致）。
- 发布顺序：改 `pubspec.yaml` 版本 → 推 `main`（Lead 用 `scripts/push_github.mjs`）→
  CI 绿 → `node scripts/release.mjs v0.1.0` 触发发布。

## 6. 排障

本机网络限制：`github.com:443` / `codeload` / `raw.githubusercontent.com` 不可达，
`api.github.com` 可用。因此**不要** `git push/clone/fetch`，一律 `gh api` / `gh run` /
`gh release`；代码推送由 Lead 用 `scripts/push_github.mjs`（Git Data API）完成。

常用命令：

```powershell
gh run list --repo youzhaiZhi/dsh-companion --limit 10
gh run view <run-id> --repo youzhaiZhi/dsh-companion --log-failed
gh run view <run-id> --repo youzhaiZhi/dsh-companion --json jobs
gh release list --repo youzhaiZhi/dsh-companion
gh api repos/youzhaiZhi/dsh-companion/actions/runs --jq '.workflow_runs[0] | {id,status,conclusion}'
```

常见失败与处理：

| 现象 | 原因 / 处理 |
| --- | --- |
| `flutter-action` 报找不到指定版本 | `FLUTTER_VERSION` 写错或该版本未发布；去 flutter releases 镜像确认后改 `env.FLUTTER_VERSION` |
| `flutter pub get` 失败 | `pubspec.yaml` 依赖/约束问题；本机先 `flutter pub get` 复现 |
| `flutter analyze` / `test` 失败 | 按 `--log-failed` 修代码；本地 `flutter analyze` / `flutter test` 先过 |
| Gradle 下载慢/失败 | runner 网络问题，重跑 run；本地无法复现 `flutter build`（本机无 Android SDK） |
| ABI 校验失败（出现 x86 等） | 构建命令丢了 `--target-platform android-arm64`，或插件带其他 ABI；检查 build 步骤 |
| `apksigner verify` 失败 | release 签名配置被改成了未签名的 release；检查 `build.gradle.kts` 的 `signingConfig` |
| Release job 403 | `permissions.contents: write` 被删或仓库 Actions 权限收紧 |
| `gh release download` 超时 | 脚本会自动回退 API asset 下载；仍失败时检查 `objects.githubusercontent.com` 可达性 |

## 7. 验收清单

- [ ] `push main` 的 run 绿，artifact `dsh-companion-arm64` 可下载，APK 仅 arm64-v8a。
- [ ] `node scripts/release.mjs v0.1.0` 成功，Release 页面有 `dsh-companion-arm64.apk`。
- [ ] `node scripts/release.mjs v0.1.0 --download-only` 能把 APK 下载到 `dist/` 并打印 SHA256/ABI。
- [ ] 手机安装 APK 可正常启动（后续真机联调阶段验证）。
