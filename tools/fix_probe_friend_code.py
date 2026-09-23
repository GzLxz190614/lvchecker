#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
修 tools/probe_lxns_class.ps1 里读好友码的 bug。

## bug

`friend_code` 是 15 位数字（例如 100888340152545），**超出 Int32 上限**
（2147483647）。而脚本里写的是：

    if ($j.data.friend_code) { $friendCode = [int]$j.data.friend_code; break }

`[int]` 转换直接抛异常：

    Cannot convert value "100888340152545" to type "System.Int32".

外面套的是 `catch { }` —— **空的**，异常被静默吞掉，`$friendCode` 保持 `$null`，
于是「公开玩家端点」那一项被跳过，只在屏幕上留一句「没找到上一轮响应里的好友码」。
文件明明在、也能解析，却报「没找到」—— 这种误导性的错误信息比直接报错更难查。

## 修法

1. `[int]` -> `[long]`（Int64，够放 15 位）。
2. **不再吞异常**：读失败就打印原因。吞异常让这个 bug 藏了一轮才发现。
3. 顺带在读到之后把好友码长度也打出来，便于确认解析对了。

用法：
    python tools/fix_probe_friend_code.py            # 改
    python tools/fix_probe_friend_code.py --dry-run  # 只看
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / "tools" / "probe_lxns_class.ps1"

OLD_BLOCK = """foreach ($f in @('.probe\\01_player.json', '.probe2\\01_player.json')) {
    $p = Join-Path $root $f
    if (Test-Path $p) {
        try {
            $j = Get-Content $p -Raw | ConvertFrom-Json
            if ($j.data.friend_code) { $friendCode = [int]$j.data.friend_code; break }
        } catch { }
    }
}"""

NEW_BLOCK = """foreach ($f in @('.probe\\01_player.json', '.probe2\\01_player.json', '.probe3\\01_player.json')) {
    $p = Join-Path $root $f
    if (-not (Test-Path $p)) { continue }
    try {
        $j = Get-Content $p -Raw | ConvertFrom-Json
        $fc = $j.data.friend_code
        if ($null -eq $fc) {
            Write-Host "（$f \u91cc\u6ca1\u6709 friend_code \u5b57\u6bb5\uff09" -ForegroundColor DarkYellow
            continue
        }
        # \u5fc5\u987b\u7528 [long]\uff1a\u597d\u53cb\u7801\u662f 15 \u4f4d\u6570\u5b57\uff08\u4f8b\u5982 100888340152545\uff09\uff0c
        # \u8d85\u51fa Int32 \u4e0a\u9650 2147483647\u3002\u7528 [int] \u4f1a\u629b\u5f02\u5e38\uff0c
        # \u800c\u4e0a\u4e00\u7248\u628a\u5f02\u5e38\u541e\u6389\u4e86\uff0c\u4e8e\u662f\u53ea\u62a5\u300c\u6ca1\u627e\u5230\u597d\u53cb\u7801\u300d\u2014\u2014
        # \u6587\u4ef6\u660e\u660e\u5728\u3001\u4e5f\u80fd\u89e3\u6790\uff0c\u8baf\u606f\u5374\u8bef\u5bfc\u3002
        $friendCode = [long]$fc
        Write-Host "(\u5df2\u4ece $f \u8bfb\u5230\u597d\u53cb\u7801\uff0c$($fc.ToString().Length) \u4f4d)" -ForegroundColor DarkGray
        break
    } catch {
        # \u4e0d\u80fd\u9759\u9ed8\u541e\u6389\uff1a\u8fd9\u4e2a bug \u5c31\u662f\u88ab\u541e\u6389\u624d\u6ca1\u53d1\u73b0\u7684
        Write-Host "\uff08\u8bfb $f \u5931\u8d25\uff1a$($_.Exception.Message)\uff09" -ForegroundColor DarkYellow
    }
}"""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if not TARGET.exists():
        print(f"✗ 找不到 {TARGET}")
        return 1

    src = TARGET.read_text(encoding="utf-8-sig")
    if NEW_BLOCK in src:
        print("（已经是修好的版本，无需改动）")
        return 0
    if OLD_BLOCK not in src:
        print("✗ 找不到要替换的代码块 —— 文件可能已被手工改过，请人工确认")
        return 1

    new = src.replace(OLD_BLOCK, NEW_BLOCK)
    print("将做以下改动：")
    print("  1. [int] -> [long]（好友码 15 位，超出 Int32）")
    print("  2. 空的 catch { } -> 打印异常信息（不再静默吞掉）")
    print("  3. 多扫一个 .probe3/01_player.json")
    print("  4. 读到后打印位数，便于确认解析正确")

    if args.dry_run:
        print("\n（--dry-run，没有写入）")
        return 0

    # BOM 必须保留：PS 5.1 读无 BOM 的 .ps1 会按 GBK 解析，中文变乱码
    TARGET.write_text(new, encoding="utf-8-sig", newline="\n")
    print(f"\n✓ 已写入 {TARGET.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
