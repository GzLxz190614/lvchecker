# 探查落雪 API 能否拿到「段位缎带 / 角色等级 / 装扮」这三类记录。
#
# 背景：Linked VERSE 有三个门靠这三样东西判定，现在只能手动打勾。
#   AIR  门 = 段位缎带（通关该组别全部课题组）-> 猜 Player.class_emblem.base
#   STAR 门 = 角色 RANK 15                    -> 猜 Collection.level (collection_type=character)
#   NEW  门 = 企鹅装扮（wear/head/back）      -> 文档里**没有**任何对应 collection_type
#
# 这个脚本只做一件事：把候选路径全打一遍，**记录 HTTP 状态码**，区分三种结果：
#   200 + data   -> 拿到了
#   4xx 带业务 message -> 路径对、但没权限或 ID 不对
#   404          -> 路径压根不存在
#
# 为什么不复用 probe_lxns_api.ps1：那个脚本只打 3 个路径、不记状态码，
# 而且它的输出会**隐去** class_emblem / character / trophy —— 恰好就是这次要看的。
# 这里改成「只隐去身份字段」（好友码/昵称/QQ），游戏进度字段全部保留。
#
# 用法（在仓库根目录）：
#     powershell -ExecutionPolicy Bypass -File tools\probe_lxns_collections.ps1
#
# 输出在屏幕上（含原始响应存在 .probe/ 里，脚本结束会留下，方便你自己再看）。
# 密钥不进历史、不回显、不落盘。

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Host '找不到 python，请先装好并加入 PATH。' -ForegroundColor Red
    exit 1
}

$base = 'https://maimai.lxns.net/api/v0'

# 要探的路径。顺序有意为之：先打最重要的「玩家信息」——
# 它一个响应就能回答「class_emblem 到底长什么样」，后面的才需要继续。
$targets = @(
    # --- 第一组：玩家信息，看 class_emblem / character / 有没有装扮字段 ---
    @{ Group = '玩家信息'; Name = 'player';            Path = "$base/user/chunithm/player" }

    # --- 第二组：角色等级（STAR 门）。24320 = 観音寺 にこる ---
    @{ Group = '角色等级'; Name = 'user/character/24320'; Path = "$base/user/chunithm/character/24320" }
    @{ Group = '角色等级'; Name = 'character/24320';      Path = "$base/chunithm/character/24320" }

    # --- 第三组：装扮（NEW 门）。四种猜法各试一遍 ---
    #   猜法 A：套用 collection_type 命名，但类型叫 wear
    @{ Group = '装扮(wear)'; Name = 'user/wear/6104401';  Path = "$base/user/chunithm/wear/6104401" }
    @{ Group = '装扮(wear)'; Name = 'wear/6104401';       Path = "$base/chunithm/wear/6104401" }
    #   猜法 B：游戏资源分类叫 avatar
    @{ Group = '装扮(avatar)'; Name = 'user/avatar/6104401'; Path = "$base/user/chunithm/avatar/6104401" }
    @{ Group = '装扮(avatar)'; Name = 'avatar/6104401';      Path = "$base/chunithm/avatar/6104401" }
    #   猜法 C：去掉首位分类位（6104401 -> 104401）
    @{ Group = '装扮(短ID)'; Name = 'wear/104401';        Path = "$base/chunithm/wear/104401" }
    @{ Group = '装扮(短ID)'; Name = 'avatar/104401';      Path = "$base/chunithm/avatar/104401" }
    #   猜法 D：也许装扮被塞进了 icon 类（玩家端口能看到的头像）
    @{ Group = '装扮(icon)'; Name = 'user/icon/6104401';  Path = "$base/user/chunithm/icon/6104401" }
)

$dir = Join-Path $root '.probe'
if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
New-Item -ItemType Directory -Path $dir | Out-Null

Write-Host ''
Write-Host '=== 落雪 API 探查：段位 / 角色等级 / 装扮 ===' -ForegroundColor Cyan
Write-Host '只打只读接口，不改你账号里的任何东西。'
Write-Host ''

$secure = Read-Host -Prompt '粘贴你的个人 API 密钥（输入时不显示）' -AsSecureString
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
        $out = Join-Path $dir ("{0:d2}_{1}.json" -f $i, ($t.Name -replace '[/\\]', '_'))

        # -w 把状态码单独打到 stdout（-o 落 body），这样两者不会混在一起。
        # -s 静默进度条；-S 但保留错误信息。
        $http = & curl.exe -s -S --max-time 30 -w '%{http_code}' `
            -H "X-User-Token: $token" -o $out $t.Path 2>&1
        $curlCode = $LASTEXITCODE

        $size = if (Test-Path $out) { (Get-Item $out).Length } else { 0 }
        Write-Host ("[{0:d2}/{1:d2}] {2,-9} http={3}  {4,7} B  {5}" -f `
            $i, $targets.Count, $t.Group, $http, $size, $t.Name)
        if ($curlCode -ne 0) {
            Write-Host "        （curl 退出码 $curlCode）" -ForegroundColor DarkYellow
        }

        $results += [pscustomobject]@{
            Group  = $t.Group
            Name   = $t.Name
            Path   = $t.Path
            Http   = "$http"
            Bytes  = $size
            File   = $out
            Curl   = $curlCode
        }

        # 对服务器客气一点，也避免触发频控
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
& python tools\probe_lxns_report.py $manifest
$code = $LASTEXITCODE

Write-Host ''
Write-Host '=== 完 ===' -ForegroundColor Cyan
Write-Host "原始响应留在 .probe\ 里了（$dir）。"
Write-Host '把上面整段输出发我即可 —— 报告里不含你的好友码/昵称/QQ。'
Write-Host '看完可以直接删掉 .probe 目录。'

exit $code
