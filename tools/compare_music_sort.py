#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
对比 MusicSort.xml 与 MusicSort_Mate.xml 在「各个门涉及的那批曲子」上
排出来的顺序是否**真的不同**。

为什么单写这个：Mate 是 MusicSort 的**严格超集**（Mate 多 92 首新曲，
且包含 MusicSort 全部 2247 首）。所以在 check_music_order.py 里，
只要某门曲目全在 MusicSort 覆盖范围内，`MusicSort✓` 和 `Mate✓` 会**同时为真** ——
这两个 ✓ 并不能说明这个门该用哪份表。

要判断"该用哪份"，唯一有意义的问法是：
    把同一批曲子分别按两份表排，结果是否不同？
如果不同，才能拿实际顺序当证据；如果相同，那这个门对两份表**不敏感**，
用什么表都一样，也就无从（也无需）区分。

用法：
    python tools/compare_music_sort.py
"""

from __future__ import annotations

import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = Path(__file__).resolve().parent.parent
CONDITION = ROOT / "condition"


def load_order(path: Path) -> list[int]:
    out: list[int] = []
    for el in ET.parse(path).getroot().iter():
        if el.tag.endswith("StringID"):
            for child in el:
                if child.tag.endswith("id") and child.text:
                    try:
                        out.append(int(child.text))
                    except ValueError:
                        pass
    return out


def main() -> int:
    ms = load_order(CONDITION / "MusicSort.xml")
    mate = load_order(CONDITION / "MusicSort_Mate.xml")

    pos_ms = {sid: n for n, sid in enumerate(ms)}
    pos_mate = {sid: n for n, sid in enumerate(mate)}

    gates = json.loads((ROOT / "data" / "gates.json").read_text(encoding="utf-8"))["gates"]

    # 先看两份表里「都有」的曲目，相对顺序是否一致。
    # 如果一致，那对任何曲子集合两者投影都相同 —— 这是最关键的判断。
    common = [s for s in ms if s in pos_mate]
    proj_ms = sorted(common, key=lambda s: pos_ms[s])
    proj_mate = sorted(common, key=lambda s: pos_mate[s])
    print(f"两份表共有的曲目：{len(common)} 首")
    if proj_ms == proj_mate:
        print("  ✓ 共有曲目的**相对顺序完全一致**")
        print("    -> 对任何只含共有曲目的集合，两份表投影必然相同。")
        print("       也就是说：这些门的顺序「对用哪份表不敏感」。")
    else:
        print("  ✗ 共有曲目的相对顺序**不一致** —— 存在能区分两份表的门")
        diffs = [(a, b) for a, b in zip(proj_ms, proj_mate) if a != b]
        print(f"    差异位置 {len(diffs)} 处，前 10 处：")
        for a, b in diffs[:10]:
            print(f"      MusicSort 里是 {a}，Mate 里该位是 {b}")

    print()
    print("=" * 92)
    print("各门：两份表的投影是否相同")
    print("=" * 92)

    any_differ = False
    for gate in gates:
        gid = gate.get("id")
        req = gate.get("requirement", {})
        rtype = req.get("type")

        if rtype == "playAll":
            batches = [(gid, [int(k.split(":")[1]) for k in req["songKeys"]])]
        elif rtype == "playAnyOfEach":
            batches = [(f"{gid}/{g.get('key','')}",
                        [int(k.split(":")[1]) for k in g["songKeys"]])
                       for g in req.get("groups", [])]
        else:
            continue

        for label, ids in batches:
            want = set(ids)
            a = [i for i in ms if i in want]
            b = [i for i in mate if i in want]
            same = (a == b)
            if not same:
                any_differ = True
            print(f"{label:22} {len(ids):2} 首  两份表投影{'相同' if same else '不同'}")
            if not same:
                print(f"    MusicSort: {a}")
                print(f"    Mate     : {b}")

    print()
    print("=" * 92)
    if any_differ:
        print("有门能被区分 -> 可以用实际顺序反推用的是哪份表")
    else:
        print("没有任何门能区分两份表 -> 现有数据无法判断（也不需要判断）")
        print("  含义：这些门无论按哪份表排，结果都一模一样。")
        print("  所以「应该用 Mate 还是 MusicSort」对这些门没有可观测差别。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
