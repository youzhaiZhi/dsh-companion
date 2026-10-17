# dsh-companion release helper -- PowerShell wrapper around release.mjs.
#
# The DSH-bundled node is not on PATH, so this wrapper locates it first.
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts\release.ps1 v0.1.0
#   powershell -ExecutionPolicy Bypass -File scripts\release.ps1 v0.1.0 --download-only
#   powershell -ExecutionPolicy Bypass -File scripts\release.ps1 --status
#
# NOTE: keep this file ASCII-only. Windows PowerShell 5.1 reads BOM-less .ps1
# files as ANSI, and some UTF-8 Chinese bytes decode into smart-quote characters
# that break the parser.
$ErrorActionPreference = 'Stop'

$candidates = @(
    'C:\Users\youzhai\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\node\bin\node.exe',
    (Get-Command node -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue)
)

$node = $null
foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) {
        $node = $candidate
        break
    }
}

if (-not $node) {
    Write-Error 'node.exe not found (neither in the DSH runtime dir nor on PATH). Run scripts/release.mjs with an absolute node path instead.'
    exit 1
}

$script = Join-Path $PSScriptRoot 'release.mjs'
& $node $script @args
exit $LASTEXITCODE
