# 探查落雪 API 到底能拿到哪些字段（不改仓库数据，只打印结构）。
#
# 目的：网页端能看到「最后游玩时间」，但我们需要知道**用个人密钥**能不能
# 通过 API 拿到它。这个脚本打两个接口，只打印字段名和少量样本。
#
# 用法（在仓库根目录）：
#     powershell -ExecutionPolicy Bypass -File tools\probe_lxns_api.ps1
#
# 它不会把结果写进仓库 —— 输出只打在屏幕上，你把屏幕内容复制给我即可。

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host '找不到 python，请先装好并加入 PATH。' -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host '=== 落雪 API 探查 ===' -ForegroundColor Cyan
Write-Host '只打印字段结构和少量样本，不会写入仓库。'
Write-Host ''

$secure = Read-Host -Prompt '粘贴你的个人 API 密钥（输入时不显示）' -AsSecureString
$token = [System.Net.NetworkCredential]::new('', $secure).Password
if ([string]::IsNullOrWhiteSpace($token)) {
    Write-Host '没有输入密钥，已取消。' -ForegroundColor Yellow
    exit 1
}

$base = 'https://maimai.lxns.net/api/v0'

# 要探的接口：(名字, 路径, 是不是个人 API)
$targets = @(
    @{ Name = '玩家信息';        Path = "$base/user/chunithm/player" },
    @{ Name = '全部成绩';        Path = "$base/user/chunithm/player/scores" },
    @{ Name = 'Recent 50(试)';   Path = "$base/user/chunithm/player/recents" }
)

$tmp = Join-Path $root 'lxns_probe_raw.json'

try {
    foreach ($t in $targets) {
        Write-Host ''
        Write-Host ('=' * 60)
        Write-Host "接口：$($t.Name)" -ForegroundColor Yellow
        Write-Host "  $($t.Path)"

        & curl.exe -s -S --max-time 30 -H "X-User-Token: $token" -o $tmp $t.Path
        $curlCode = $LASTEXITCODE
        & python tools\probe_lxns_raw.py $tmp $t.Name
        Write-Host "  （curl 退出码 $curlCode）"
    }
}
finally {
    if (Test-Path $tmp) { Remove-Item $tmp -Force }
    $token = $null
    $secure = $null
}

Write-Host ''
Write-Host '=== 完 ===' -ForegroundColor Cyan
Write-Host '把上面「全部成绩」那段的字段列表 + 「Recent 50(试)」的结果发我。'
