#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从 condition/class/course/*/Course.xml 里抽出**段位编号映射表**：
    游戏内部 difficulty.id  <->  CLASS 标签（Ⅰ/Ⅱ/Ⅲ/Ⅳ/Ⅴ/∞）

为什么要这个：
    落雪 API 的 `class_emblem.base` 通关后是 3（你通的是 CLASS Ⅲ）。
    而 Course.xml 里 CLASS Ⅲ 的 `difficulty.id` 是 **12** —— 两套编号不同。
    所以不能假设 base 就是游戏内部 ID，也不能假设它等于「序号」或
    「classes.json 里的 level」。必须把三套编号都列出来对照。

    （`classes.json` 里的 `level` 字段是我们自己定的，用于排序显示，
      从来不是从游戏里读出来的 —— 拿它当证据是循环论证。）

用法：
    python tools/class_id_map.py
"""

from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = Path(__file__).resolve().parent.parent
COURSE_DIR = ROOT / "condition" / "class" / "course"

# 罗马数字 / 全角罗马数字 -> 我们的序号
# 游戏里用的是 Ⅰ Ⅱ Ⅲ Ⅳ Ⅴ（U+2160 起，全角）和 ∞
ROMAN = {
    "Ⅰ": 1, "Ⅱ": 2, "Ⅲ": 3, "Ⅳ": 4, "Ⅴ": 5,
    "I": 1, "II": 2, "III": 3, "IV": 4, "V": 5,
    "∞": 6,
}


def parse_label(data_text: str) -> str | None:
    """从 'CLASS Ⅲ' / 'CLASS ∞' / 'CLASS Extra' 里取出段位标签。"""
    m = re.search(r"CLASS\s*(\S+)", data_text or "")
    return m.group(1) if m else None


def main() -> int:
    if not COURSE_DIR.exists():
        print(f"✗ 找不到 {COURSE_DIR}")
        print("  （condition/ 是 gitignore 的，这个脚本只能在有游戏数据的机器上跑）")
        return 1

    # difficulty.id -> {标签集合, course 列表}
    by_id: dict[int, set[str]] = defaultdict(set)
    courses_of: dict[int, list[str]] = defaultdict(list)
    unparsed: list[str] = []

    for d in sorted(p for p in COURSE_DIR.iterdir() if p.is_dir()):
        cx = d / "Course.xml"
        if not cx.exists():
            continue
        root = ET.parse(cx).getroot()
        diff = root.find("difficulty")
        if diff is None:
            unparsed.append(f"{d.name}: 没有 <difficulty>")
            continue
        id_el = diff.find("id")
        data_el = diff.find("data")
        if id_el is None or id_el.text is None:
            unparsed.append(f"{d.name}: difficulty 没有 <id>")
            continue
        did = int(id_el.text)
        label = parse_label(data_el.text if data_el is not None else "")
        if label is None:
            unparsed.append(f"{d.name}: 解析不出 CLASS 标签（data={data_el.text if data_el is not None else None!r}）")
            continue
        by_id[did].add(label)
        courses_of[did].append(d.name)

    if not by_id:
        print("✗ 一个段位都没解析出来")
        return 1

    print(f"解析了 {sum(len(v) for v in courses_of.values())} 个组曲，"
          f"覆盖 {len(by_id)} 个内部 difficulty.id")
    if unparsed:
        print(f"\n⚠ {len(unparsed)} 个无法解析：")
        for u in unparsed[:10]:
            print(f"    {u}")

    print()
    print("=" * 76)
    print("三套编号对照")
    print("=" * 76)
    print(f"  {'标签':<6} {'游戏内部 id':>10} {'罗马序号':>8} {'组曲数':>6}")
    print("  " + "-" * 72)

    rows = []
    for did in sorted(by_id):
        labels = by_id[did]
        if len(labels) > 1:
            print(f"  ⚠ id={did} 对应多个标签：{sorted(labels)}")
        label = sorted(labels)[0]
        seq = ROMAN.get(label)
        rows.append((label, did, seq, len(courses_of[did])))
        print(f"  {label:<6} {did:>10} {str(seq):>8} {len(courses_of[did]):>6}")

    print()
    print("=" * 76)
    print("关键：内部 id 和序号是什么关系？")
    print("=" * 76)

    with_seq = [(l, d, s) for l, d, s, _ in rows if s is not None]
    if with_seq:
        diffs = sorted({d - s for _, d, s in with_seq})
        print(f"  内部 id - 罗马序号 的差值集合: {diffs}")
        if len(diffs) == 1:
            print(f"  -> 恒为 {diffs[0]}，说明 id = 序号 + {diffs[0]}（一一对应）")
        else:
            print("  -> 差值不固定，两套编号不是简单平移")

    # 核心判断：base=3 能不能对上
    print()
    print("=" * 76)
    print("落雪 base=3（你通的是 CLASS Ⅲ）对得上哪一套？")
    print("=" * 76)
    base = 3
    hit_seq = [l for l, _, s in with_seq if s == base]
    hit_id = [l for l, d, _ in with_seq if d == base]
    print(f"  按「罗马序号」解释: {'匹配 CLASS ' + '、'.join(hit_seq) if hit_seq else '无匹配'}")
    print(f"  按「内部 id」解释 : {'匹配 CLASS ' + '、'.join(hit_id) if hit_id else '无匹配'}")
    print()
    print("  你的实际情况是通了 CLASS Ⅲ。所以：")
    if base in hit_seq:
        print("    ✓ base 和「CLASS Ⅲ 的罗马序号 3」一致")
    if base in hit_id:
        print("    ✓ base 和「CLASS Ⅲ 的内部 id」一致")
    if base not in hit_id and base in hit_seq:
        print("    -> base **不是**游戏内部 id，更像「段位序号」（Ⅰ=1…Ⅴ=5）")
        print("       也可能就是「最高已通关段位的序号」或「最近通关段位的序号」。")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
