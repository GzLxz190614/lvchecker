# 探查落雪 API 的「段位（CLASS）缎带」数据。**第二轮：你已通关 AIR 之后。**
#
# 背景：
#   AIR 门的解锁条件是「获得一个段位缎带」（任一 CLASS 内所有组曲通关）。
#   官方文档里 Player.class_emblem 是：
#       base  (int) 缎带（通关该组别全部课题组），默认值为 0
#       medal (int) 勋章（通关任意一组），默认值为 0
#
#   第一轮探查（你还没通关时）拿到的是 {"base": 0, "medal": 0} —— 无法区分
#   「没拿缎带」和「它其实是布尔量」。现在你通关了，这个值应该不再是 0，
#   于是能一次性回答：
#       Q1 base 到底是布尔量(0/1)还是段位序号？
#       Q2 它对应的是哪个 CLASS？
#       Q3 能不能用它自动判定 AIR 门？
#
# 这个脚本会自动做一件事：读 data/classes.json，把 base 的取值和
# 「哪个 CLASS 已通关」对应起来算一遍，而不是让你自己去猜。
#
# 用法（在仓库根目录）：
#     powershell -ExecutionPolicy Bypass -File tools\probe_lxns_class.ps1

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host '找不到 python，请先装好并加入 PATH。' -ForegroundColor Red
    exit 1
}

# 从第一轮的响应里捡好友码，省得你再输（也能顺带验证它还在不在）
$friendCode = $null
foreach ($f in @('.probe\01_player.json', '.probe2\01_player.json', '.probe3\01_player.json')) {
    $p = Join-Path $root $f
    if (-not (Test-Path $p)) { continue }
    try {
        $j = Get-Content $p -Raw | ConvertFrom-Json
        $fc = $j.data.friend_code
        if ($null -eq $fc) {
            Write-Host "（$f 里没有 friend_code 字段）" -ForegroundColor DarkYellow
            continue
        }
        # 必须用 [long]：好友码是 15 位数字（例如 100888340152545），
        # 超出 Int32 上限 2147483647。用 [int] 会抛异常，
        # 而上一版把异常吞掉了，于是只报「没找到好友码」——
        # 文件明明在、也能解析，讯息却误导。
        $friendCode = [long]$fc
        Write-Host "(已从 $f 读到好友码，$($fc.ToString().Length) 位)" -ForegroundColor DarkGray
        break
    } catch {
        # 不能静默吞掉：这个 bug 就是被吞掉才没发现的
        Write-Host "（读 $f 失败：$($_.Exception.Message)）" -ForegroundColor DarkYellow
    }
}

Write-Host ''
Write-Host '=== 落雪 API 探查：段位（CLASS）缎带 ===' -ForegroundColor Cyan
Write-Host '只打只读接口。'
Write-Host ''

$base = 'https://maimai.lxns.net/api/v0'

# 要探的路径。顺序：先拿最重要的玩家信息。
$targets = @(
    # Q1/Q2：玩家信息里的 class_emblem —— 这是核心
    @{ Name = 'player'; Path = "$base/user/chunithm/player" }

    # 公开的玩家端点（需要 allow_third_party_fetch_player 权限）。
    # 如果这个能返回，说明能从**公开**端点读缎带；
    # 如果不行，那就只能用个人端点 —— 两者对 App 的实现方式差别很大。
    @{ Name = 'player_friendcode'; Path = $null }
)

if ($friendCode) {
    $targets[1].Path = "$base/chunithm/player/$friendCode"
} else {
    $targets = @($targets[0])
    Write-Host '（没找到上一轮响应里的好友码，公开玩家端点那项跳过）' -ForegroundColor DarkYellow
}

$dir = Join-Path $root '.probe3'
if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
New-Item -ItemType Directory -Path $dir | Out-Null

Write-Host '在查分器网页「账号详情」生成/复制的【个人】密钥粘进来。'
$secure = Read-Host -Prompt '个人 API 密钥（输入时不显示）' -AsSecureString
$token = [System.Net.NetworkCredential]::new('', $secure).Password
if ([string]::IsNullOrWhiteSpace($token)) {
    Write-Host '没有输入密钥，已取消。' -ForegroundColor Yellow
    exit 1
}

$results = @()

try {
    $i = 0
    foreach ($t in $targets) {
        $i++
        $out = Join-Path $dir ("{0:d2}_{1}.json" -f $i, $t.Name)
        $http = & curl.exe -s -S --max-time 40 -w '%{http_code}' `
            -H "X-User-Token: $token" -o $out $t.Path 2>&1
        $curlCode = $LASTEXITCODE
        $size = if (Test-Path $out) { (Get-Item $out).Length } else { 0 }

        $kind = ''
        if ($size -gt 0 -and $size -lt 64) {
            $head = (Get-Content $out -Raw).Trim()
            if ($head -like '*page not found*') { $kind = '  <- 路由未匹配' }
        }
        if ($size -eq 0) { $kind = '  <- 空响应' }

        Write-Host ("[{0}/{1}] http={2}  {3,7} B  {4}{5}" -f `
            $i, $targets.Count, $http, $size, $t.Name, $kind)
        if ($curlCode -ne 0) { Write-Host "      （curl 退出码 $curlCode）" -ForegroundColor DarkYellow }

        $results += [pscustomobject]@{
            Name = $t.Name; Path = $t.Path; Http = "$http"; Bytes = $size; File = $out
        }
        Start-Sleep -Milliseconds 350
    }
}
finally {
    $token = $null
    $secure = $null
}

$manifest = Join-Path $dir 'manifest.json'
$results | ConvertTo-Json -Depth 4 | Out-File -FilePath $manifest -Encoding utf8

Write-Host ''
& python tools\probe_lxns_class_report.py $manifest
$code = $LASTEXITCODE

Write-Host ''
Write-Host '=== 完 ===' -ForegroundColor Cyan
Write-Host "原始响应在 $dir（里面有你的好友码，看完可删）"
Write-Host '把上面整段输出发我。'

exit $code
