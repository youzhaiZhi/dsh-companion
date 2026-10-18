# 一条命令做本地检查（格式 + 静态分析 + 单测）。
#
# 本机没有 Android SDK/JDK，不能本地出 APK；APK 一律由 GitHub Actions 构建。
# 这个脚本只负责“改完代码立刻知道有没有写错”。
#
# 用法：
#   pwsh scripts/dev-check.ps1            # 格式 + analyze + test
#   pwsh scripts/dev-check.ps1 -Fast      # 只跑格式 + analyze（约 30s）
#   pwsh scripts/dev-check.ps1 -Files lib/core/gateway/events.dart   # 只分析指定文件

param(
    [switch]$Fast,
    [string[]]$Files = @()
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$flutter = 'C:\Users\youzhai\flutter\bin\flutter.bat'
$dart = 'C:\Users\youzhai\flutter\bin\cache\dart-sdk\bin\dart.exe'

if (-not (Test-Path $flutter)) {
    Write-Error "找不到 Flutter SDK：$flutter（见 docs/dev-environment.md）"
}

$env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
Push-Location $root
$failed = @()
try {
    Write-Host '== 1/3 格式检查 ==' -ForegroundColor Cyan
    & $dart format --output=none --set-exit-if-changed lib test
    if ($LASTEXITCODE -ne 0) {
        $failed += 'format'
        Write-Host '  格式不符：运行 dart format lib test 自动修复' -ForegroundColor Yellow
    }

    Write-Host '== 2/3 静态分析 ==' -ForegroundColor Cyan
    if ($Files.Count -gt 0) {
        # 只分析指定文件：改一个文件时反馈最快。
        & $dart analyze @Files
    } else {
        & $flutter analyze
    }
    if ($LASTEXITCODE -ne 0) {
        $failed += 'analyze'
    }

    if (-not $Fast) {
        Write-Host '== 3/3 单元测试 ==' -ForegroundColor Cyan
        & $flutter test
        if ($LASTEXITCODE -ne 0) {
            $failed += 'test'
        }
    } else {
        Write-Host '== 3/3 单测已跳过（-Fast）==' -ForegroundColor DarkGray
    }
}
finally {
    Pop-Location
}

if ($failed.Count -gt 0) {
    Write-Host ''
    Write-Host ("本地检查失败：" + ($failed -join ', ')) -ForegroundColor Red
    exit 1
}
Write-Host ''
Write-Host '本地检查通过。推送：node scripts/push_github.mjs "feat: ..."' -ForegroundColor Green
