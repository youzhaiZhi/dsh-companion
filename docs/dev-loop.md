# 本地开发反馈环

本机没有 Android SDK/JDK，**APK 只能由 GitHub Actions 构建**。但“改完立刻知道有没有写错”是能做到秒级的。

## 一条命令

```powershell
pwsh scripts/dev-check.ps1            # 格式 + 全量 analyze + 单测（约 5 分钟，本机偏慢）
pwsh scripts/dev-check.ps1 -Fast      # 只跑格式 + analyze（约 30s）
pwsh scripts/dev-check.ps1 -Files lib/core/gateway/events.dart   # 只分析改动的文件（约 20s）
```

## 实测耗时（这台机器）

| 命令 | 耗时 | 说明 |
| --- | --- | --- |
| `dart analyze <单个文件>` | ~20s | 改一处逻辑时最划算 |
| `flutter analyze`（全量） | ~30s，偶发 OOM | 内存只有 3.9GB，analysis server 可能被系统杀掉 |
| `flutter test`（全量） | ~270s | 慢，但能跑通；测试失败会指出文件与用例名 |
| 推 CI（GitHub Actions） | ~4.5min | 唯一能出 APK 的路径，且环境干净（16GB） |

## 为什么不装 Android SDK 做热重载

热重载本身是 1-3 秒，但需要 Gradle 守护进程 + Dart 编译同时跑在一片可用内存只有 0.6GB 的机器上。判断是大概率 OOM，收益不抵风险。

**真正快的路径**：把逻辑写成纯 Dart（协议解析、状态机都是），用 `-Files` 只分析改动文件；UI 改动再走 CI。

## 已验证可用的下载源

- Android 命令行工具：`dl.google.com/android/repository/commandlinetools-win-*.zip`（146MB，200 OK）
- Gradle：`services.gradle.org/distributions/gradle-8.9-bin.zip`（130MB，200 OK）
- JDK：`winget install Microsoft.OpenJDK.17`

需要时再装，装之前先确认内存。
