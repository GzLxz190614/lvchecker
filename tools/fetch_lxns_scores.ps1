# 从落雪查分器拉取成绩，并提取出 ORIGIN 门那 30 首。
#
# 用法（在仓库根目录）：
#     powershell -ExecutionPolicy Bypass -File tools\fetch_lxns_scores.ps1
#
# 它会：
#   1. 隐蔽地提示你输入个人 API 密钥（输入时屏幕上不显示，不进历史记录）
#   2. 调落雪个人 API 拿全部成绩，存成 scores_raw.json
#   3. 运行 tools/extract_lxns_origin.py，提取 ORIGIN 门那 30 首 -> lxns_origin.txt
#   4. 立刻清掉第 2 步的原始响应（里面有你全部成绩，不必留着）
#
# 两个文件都在 .gitignore 里（lxns_* / scores_raw*.json），不会被提交。
#
# 为什么用 curl.exe 而不是 Invoke-RestMethod：后者在 Windows PowerShell 5.1 下
# 可能给输出加 BOM 或改变编码，中文曲名会乱。curl.exe 是原生程序，直接落字节。

$ErrorActionPreference = 'Stop'

# 先给个失败初值：万一中途抛异常，最后不会读到未定义的变量。
$code = 1

$root = Split-Path -Parent $PSScriptRoot   # tools/ 的上一级 = 仓库根
Set-Location $root

$api = 'https://maimai.lxns.net/api/v0/user/chunithm/player/scores'
$raw = Join-Path $root 'scores_raw.json'

Write-Host ''
Write-Host '=== 落雪查分器：拉取成绩 ===' -ForegroundColor Cyan
Write-Host '密钥在查分器网页「账号详情」页生成，要的是【个人】密钥（X-User-Token）。'
Write-Host ''

$secure = Read-Host -Prompt '粘贴你的个人 API 密钥（输入时不显示）' -AsSecureString
$token = [System.Net.NetworkCredential]::new('', $secure).Password

if ([string]::IsNullOrWhiteSpace($token)) {
    Write-Host '没有输入密钥，已取消。' -ForegroundColor Yellow
    exit 1
}

Write-Host ''
Write-Host "正在请求…（密钥长度 $($token.Length)，不在屏幕上回显）"

try {
    & curl.exe -s -S --max-time 30 -H "X-User-Token: $token" -o $raw $api
    if ($LASTEXITCODE -ne 0) {
        # curl 的退出码 6 = 解析不了域名，7 = 连不上，28 = 超时
        Write-Host "请求失败（curl 退出码 $LASTEXITCODE）。检查网络。" -ForegroundColor Red
        exit 1
    }

    if (-not (Test-Path $raw)) {
        Write-Host '没有收到任何响应。' -ForegroundColor Red
        exit 1
    }

    $size = (Get-Item $raw).Length
    Write-Host "已收到 $size 字节" -ForegroundColor Green
    Write-Host ''

    & python tools\extract_lxns_origin.py $raw
    $code = $LASTEXITCODE
}
finally {
    # 原始响应包含你**全部**成绩，提取完就没必要留着
    if (Test-Path $raw) {
        Remove-Item $raw -Force
        Write-Host ''
        Write-Host '（已删除 scores_raw.json —— 它包含你的全部成绩）' -ForegroundColor DarkGray
    }
    # 清掉内存里的密钥
    $token = $null
    $secure = $null
}

if ($code -ne 0) { exit $code }

Write-Host ''
Write-Host '下一步：把 lxns_origin.txt 的内容发给我。' -ForegroundColor Cyan
Write-Host '它只包含 ORIGIN 门那 30 首，不包含你其它曲目的成绩。'
