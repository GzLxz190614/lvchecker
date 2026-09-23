#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
校验 `ClassData.tierByOrdinal` 的映射表：落雪 `class_emblem.base` 序号 -> 我方的段位。

## 为什么需要这个检查

`base` 是 1-based 段位序号（Ⅰ=1 … Ⅴ=5、∞=6，实测：通关 CLASS Ⅲ 后 base=3）。
但 `ClassData.fromJson` 末尾有一段排序，把 `tiers` 重排成 **显示顺序**：

    [∞, Ⅴ, Ⅳ, Ⅲ, Ⅱ, Ⅰ]

—— 和序号顺序**完全相反**。所以 `tiers[base - 1]` 会 6/6 全错：
`base = 3` 取到 **Ⅳ** 而不是 **Ⅲ**，于是自动勾错段位，
而界面上看起来一切正常（最难查的那种 bug）。

## 这个脚本做什么

1. 用 Dart 的排序规则复现 `ClassData.fromJson` 的实际 tiers 顺序；
2. **从 `lib/models/class_course.dart` 源码里抠出映射表**（不手抄一份，
   否则源码改了这里不会跟着变，检查就失去意义）；
3. 逐条验证映射正确、且能在真实的 tiers 列表里找到对应段位。

用法：
    python tools/check_tier_order.py
退出码 0 = 映射正确，1 = 有问题。
"""

from __future__ import annotations

import json
import re
import sys
from functools import cmp_to_key
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = Path(__file__).resolve().parent.parent
DART = ROOT / "lib" / "models" / "class_course.dart"
CLASSES = ROOT / "data" / "classes.json"

# 期望的映射。和 Dart 源码里的 byOrdinal 对照。
EXPECTED = {1: "I", 2: "II", 3: "III", 4: "IV", 5: "V", 6: "∞"}


def dart_compare(a: dict, b: dict) -> int:
    """复现 ClassData.fromJson 里的 comparator（∞ 最前，然后 level 降序）。"""
    la, lb = a.get("level", 0), b.get("level", 0)
    if la == 0 and lb != 0:
        return -1
    if lb == 0 and la != 0:
        return 1
    return (lb > la) - (lb < la)


def parse_dart_map() -> dict[int, str] | None:
    """从 Dart 源码里抠出 byOrdinal 映射表。"""
    if not DART.exists():
        print(f"✗ 找不到 {DART}")
        return None
    src = DART.read_text(encoding="utf-8")

    m = re.search(r"byOrdinal\s*=\s*<int,\s*String>\s*\{(.*?)\}", src, re.S)
    if not m:
        print("✗ 在 class_course.dart 里找不到 byOrdinal 映射表")
        return None

    out: dict[int, str] = {}
    for km, vm in re.findall(r"(\d+)\s*:\s*'([^']*)'", m.group(1)):
        out[int(km)] = vm
    return out or None


def main() -> int:
    if not CLASSES.exists():
        print(f"✗ 找不到 {CLASSES}")
        return 1
    raw = json.loads(CLASSES.read_text(encoding="utf-8"))["classes"]

    # ---- 复现 Dart 的排序 ----
    tiers = sorted(raw, key=cmp_to_key(dart_compare))
    print("Dart fromJson 排序后（运行时真实的 tiers 顺序）：")
    for i, c in enumerate(tiers):
        print(f"  tiers[{i}] = {c['label']!r}")
    print()

    # ---- 顺带演示「下标当序号」是错的（回归证据）----
    print("如果用 tiers[ordinal - 1]（错误做法）：")
    wrong = 0
    for ordv, want in EXPECTED.items():
        idx = ordv - 1
        got = tiers[idx]["label"] if 0 <= idx < len(tiers) else "（越界）"
        if got != want:
            wrong += 1
    if wrong:
        print(f"  {wrong}/6 取错 -> 确认**不能**用下标（这正是当初写错的地方）")
    else:
        print("  居然全对？那说明排序行为变了，需要重新审视这段注释")
    print()

    # ---- 校验 Dart 里的映射表 ----
    dart_map = parse_dart_map()
    if dart_map is None:
        return 1

    print("从 class_course.dart 抠出的映射表（实际生效的那份）：")
    for k in sorted(dart_map):
        print(f"  {k} -> {dart_map[k]!r}")
    print()

    problems: list[str] = []

    if dart_map != EXPECTED:
        problems.append(f"映射表与期望不符：\n      Dart = {dart_map}\n      期望 = {EXPECTED}")

    # 每个映射值必须能在真实 tiers 里找到（否则 tierByOrdinal 会返回 null）
    tier_keys = {c["key"] for c in tiers}
    tier_labels = {c["label"] for c in tiers}
    print("逐条验证（映射值必须能在真实 tiers 里匹配到）：")
    for ordv in sorted(EXPECTED):
        want = dart_map.get(ordv)
        found = want in tier_keys or want in tier_labels
        mark = "OK" if found else "✗ 在 tiers 里找不到"
        print(f"  序号 {ordv} -> {want!r}   {mark}")
        if not found:
            problems.append(f"序号 {ordv} 映射到 {want!r}，但 tiers 里没有这个 key/label")

    # 反向：每个段位都应能被某个序号取到
    covered = {dart_map.get(o) for o in EXPECTED}
    missed = (tier_keys | tier_labels) - covered
    if missed:
        problems.append(f"这些段位没有任何序号能取到：{sorted(missed)}")

    # 全角字符陷阱：classRawName 用全角（Ⅲ = U+2162），key/label 用半角。
    # 映射表必须用半角。
    for ordv, v in dart_map.items():
        if any(0x2160 <= ord(ch) <= 0x217F for ch in v):
            problems.append(
                f"序号 {ordv} 的映射值 {v!r} 含**全角**罗马数字 —— "
                f"classes.json 的 key/label 是半角，匹配不上"
            )

    print()
    if problems:
        print(f"✗ 发现 {len(problems)} 个问题：")
        for p in problems:
            print(f"  - {p}")
        return 1

    print("✓ 映射表正确，且 6 个序号都能在真实 tiers 里匹配到")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
