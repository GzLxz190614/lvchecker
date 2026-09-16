# 探查落雪 API 的收藏品端点（第二轮）。
#
# 第一轮 probe_lxns_collections.ps1 的结论有 bug：
#   * 它拿 `wear` / `avatar` 当 collection_type 去试 —— 但那两个**不是合法值**，
#     合法值只有 trophy|character|plate|icon。用必然 404 的路径证明「装扮查不到」，
#     这个证据是无效的（真正的依据是文档里这四种都不是衣服）。
#   * 它把 `/chunithm/character/24320` 和 `/user/chunithm/character/24320` 都判为
#     拿不到，但响应体是 Go 原生的 `404 page not found` —— 这是**路由没匹配**，
#     不是业务拒绝。说明路径写法不对，不能据此下"查不到"的结论。
#
# 读完文档后的正确路径（共 3 类收藏品端点）：
#   GET /api/v0/chunithm/{collection_type}/list                          全表，不需密钥
#   GET /api/v0/chunithm/{collection_type}/{collection_id}               单个定义，不需密钥
#   GET /api/v0/chunithm/player/{friend_code}/{collection_type}/{collection_id}  玩家进度
#
# 本轮要一次回答三个问题：
#   Q1 收藏品路由到底装没装？-> 打 4 个 /list + 一个故意写错的类型做对照
#   Q2 单个收藏品能不能查？  -> 用 Q1 拿到的真实 ID 打
#   Q3 AIR 门的缎带怎么读？  -> 打 /chunithm/player/{你的好友码} 看 class_emblem
#
# 关于好友码：Q3 需要好友码。好友码在上一轮的 01_player.json 里（你本地）。
# 那个文件会被读出来、并打印在屏幕上 —— 因为它本来就是你自己的数据、在你自己机器上，
# 而报告里没有它就没法判断 Q3。如果你不想看到它，脚本跑完删掉 .probe 即可。
# 本脚本**只查你自己的好友码**，不会去查别人。
#
# 用法（在仓库根目录）：
#     powershell -ExecutionPolicy Bypass -File tools\probe_lxns_collections2.ps1

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host '找不到 python，请先装好并加入 PATH。' -ForegroundColor Red
    exit 1
}

$base = 'https://maimai.lxns.net/api/v0'

# ---------------------------------------------------------------
# 先看能不能捡到上一轮的好友码，省得再问你一次
# ---------------------------------------------------------------
$friendCode = $null
$prevPlayer = Join-Path $root '.probe\01_player.json'
if (Test-Path $prevPlayer) {
    try {
        $prev = Get-Content $prevPlayer -Raw | ConvertFrom-Json
        if ($prev.data.friend_code) { $friendCode = [int]$prev.data.friend_code }
    } catch {
        Write-Host "（读上一轮的 01_player.json 失败：$($_.Exception.Message)）" -ForegroundColor DarkYellow
    }
}

Write-Host ''
Write-Host '=== 落雪 API 探查 第 2 轮：收藏品端点 ===' -ForegroundColor Cyan
Write-Host '只打只读接口。'
if ($friendCode) {
    Write-Host "已从上一轮的响应里读到你的好友码：$friendCode" -ForegroundColor DarkGray
} else {
    Write-Host '没找到上一轮的响应，Q3 会跳过。' -ForegroundColor DarkYellow
}
Write-Host ''

$secure = Read-Host -Prompt '粘贴你的个人 API 密钥（输入时不显示）' -AsSecureString
$token = [System.Net.NetworkCredential]::new('', $secure).Password
if ([string]::IsNullOrWhiteSpace($token)) {
    Write-Host '没有输入密钥，已取消。' -ForegroundColor Yellow
    exit 1
}

# ---------------------------------------------------------------
# 目标清单
# ---------------------------------------------------------------
$targets = @()

# --- Q1: 收藏品路由存在性。四种合法类型 + 一个故意的非法类型做对照 ---
foreach ($ct in @('character', 'trophy', 'plate', 'icon')) {
    $targets += @{ Group = 'Q1 列表'; Name = "$ct/list"; Path = "$base/chunithm/$ct/list" }
}
# 对照：类型名字故意写错。如果这个是**业务 JSON 错误**（而不是 raw 404），
# 就证明路由是通的、类型是在业务层校验的。
$targets += @{ Group = 'Q1 对照'; Name = 'zzznotatype/list'; Path = "$base/chunithm/zzznotatype/list" }

# 顺手确认 /chunithm/ 子路由整体可达（这个接口不需要密钥）
$targets += @{ Group = 'Q1 对照'; Name = 'song/list'; Path = "$base/chunithm/song/list" }

# --- Q2: 单个收藏品定义。先用真实已知 ID ---
$targets += @{ Group = 'Q2 单个'; Name = 'character/14520'; Path = "$base/chunithm/character/14520" }
$targets += @{ Group = 'Q2 单个'; Name = 'character/24320'; Path = "$base/chunithm/character/24320" }
# 装扮 ID 当角色打一次，作为「ID 不存在」的对照
$targets += @{ Group = 'Q2 单个'; Name = 'character/6104401'; Path = "$base/chunithm/character/6104401" }

# --- Q3: 公开玩家端点 + 你自己的收藏品进度 ---
if ($friendCode) {
    $targets += @{ Group = 'Q3 玩家'; Name = "player/$friendCode"; Path = "$base/chunithm/player/$friendCode" }
    $targets += @{ Group = 'Q3 玩家'; Name = "player/$friendCode/character/14520"; Path = "$base/chunithm/player/$friendCode/character/14520" }
    $targets += @{ Group = 'Q3 玩家'; Name = "player/$friendCode/character/24320"; Path = "$base/chunithm/player/$friendCode/character/24320" }
}

$dir = Join-Path $root '.probe2'
if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
New-Item -ItemType Directory -Path $dir | Out-Null

$results = @()

try {
    $i = 0
    foreach ($t in $targets) {
        $i++
        $out = Join-Path $dir ("{0:d2}_{1}.json" -f $i, ($t.Name -replace '[/\\()]', '_'))

        $http = & curl.exe -s -S --max-time 40 -w '%{http_code}' `
            -H "X-User-Token: $token" -o $out $t.Path 2>&1
        $curlCode = $LASTEXITCODE

        $size = if (Test-Path $out) { (Get-Item $out).Length } else { 0 }

        # 一眼看出是不是 Go 的 raw 404（路由没匹配）还是业务 JSON
        $kind = ''
        if ($size -gt 0 -and $size -lt 64) {
            $head = (Get-Content $out -Raw).Trim()
            if ($head -like '*page not found*') { $kind = '  <- 路由未匹配(raw 404)' }
        }
        if ($size -eq 0) { $kind = '  <- 空响应(通常=服务器拒绝且无 body)' }

        Write-Host ("[{0:d2}/{1:d2}] {2,-8} http={3}  {4,8} B  {5}{6}" -f `
            $i, $targets.Count, $t.Group, $http, $size, $t.Name, $kind)
        if ($curlCode -ne 0) {
            Write-Host "        （curl 退出码 $curlCode）" -ForegroundColor DarkYellow
        }

        $results += [pscustomobject]@{
            Group = $t.Group; Name = $t.Name; Path = $t.Path
            Http = "$http"; Bytes = $size; File = $out; Curl = $curlCode
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
& python tools\probe_lxns_report2.py $manifest
$code = $LASTEXITCODE

Write-Host ''
Write-Host '=== 完 ===' -ForegroundColor Cyan
Write-Host "原始响应在 $dir"
Write-Host '把上面整段输出发我。看完可以直接删掉 .probe2 目录。'

exit $code
