#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
核对 data/gates.json 里各门曲目的顺序，是否符合游戏内的乐曲排序。

为什么需要这个脚本：顺序错了**肉眼很难发现** —— 一个门 30 首，
看起来"差不多有序"不代表真的对。之前就是靠眼睛数，数错了好几次
（16 vs 17 颗星那次）。所以顺序必须用脚本比对。

游戏里有两份排序表：
  condition/MusicSort.xml       常规乐曲排序
  condition/MusicSort_Mate.xml  「対戦相手（Mate）」相关的排序表

本脚本对每个门分别算「按 MusicSort 排」和「按 Mate 排」两种期望顺序，
再和实际顺序比对，从而判断这个门到底用的哪一份。

用法：
    python tools/check_music_order.py
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
GATES = ROOT / "data" / "gates.json"


def load_order(path: Path) -> list[int]:
    """读 MusicSort 类文件，返回文档顺序的 id 列表。

    结构：<SerializeSortData><SortList><StringID><id>N</id>...</StringID>
    文档顺序 = 游戏内顺序，所以直接按遍历顺序收集。
    """
    if not path.exists():
        return []
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


def ids_of(song_keys) -> list[int]:
    return [int(k.split(":")[1]) for k in song_keys]


def project(order: list[int], ids: list[int]) -> list[int]:
    """按 order 的顺序排列 ids 的子集。

    表里没有的曲目会被丢掉 —— 这里故意这样做：调用方要对比的是
    「实际顺序是否等于按该表排出来的顺序」，丢掉的曲目会让两边长度不等，
    从而暴露出来，而不是被静默忽略。
    """
    want = set(ids)
    return [i for i in order if i in want]


def main() -> int:
    ms = load_order(CONDITION / "MusicSort.xml")
    mate = load_order(CONDITION / "MusicSort_Mate.xml")

    if not ms:
        print("✗ 读不到 MusicSort.xml —— 无法核对")
        return 1

    print(f"MusicSort.xml      : {len(ms)} 首")
    print(f"MusicSort_Mate.xml : {len(mate)} 首")
    if mate:
        print(f"  两者顺序完全相同? {ms == mate}")
        print(f"  两者集合完全相同? {set(ms) == set(mate)}")
        only_ms = sorted(set(ms) - set(mate))
        only_mate = sorted(set(mate) - set(ms))
        print(f"  仅在 MusicSort : {len(only_ms)} 首 {only_ms[:15]}")
        print(f"  仅在 Mate      : {len(only_mate)} 首 {only_mate[:15]}")

    if not GATES.exists():
        print(f"✗ 找不到 {GATES}")
        return 1
    gates = json.loads(GATES.read_text(encoding="utf-8"))["gates"]

    print()
    print("=" * 92)
    print("各门曲目顺序核对")
    print("=" * 92)

    problems = 0
    for gate in gates:
        gid = gate.get("id")
        req = gate.get("requirement", {})
        rtype = req.get("type")

        if rtype == "playAll":
            got = ids_of(req["songKeys"])
            label = f"{len(got)} 首"
        elif rtype == "playAnyOfEach":
            # PARADISE：分组是按曲师的，组**之间**不重排，只比组内
            groups = req.get("groups", [])
            print(f"{gid:9} playAnyOfEach，{len(groups)} 组（只比组内顺序）")
            for grp in groups:
                got_g = ids_of(grp["songKeys"])
                exp_g = project(ms, got_g)
                ok = got_g == exp_g
                if not ok:
                    problems += 1
                print(f"    {grp.get('key',''):10} {len(got_g):2} 首  "
                      f"{'OK' if ok else '✗ 顺序不符'}"
                      + ("" if ok else f"\n        实际 {got_g}\n        期望 {exp_g}"))
            continue
        else:
            # clearAllPrev / items / manualConfirm / remainingHp —— 没有曲目列表
            continue

        exp_ms = project(ms, got)
        exp_mate = project(mate, got) if mate else []

        # 表里没有的曲目 = 期望列表比实际短
        missing_ms = [i for i in got if i not in set(ms)]
        missing_mate = [i for i in got if i not in set(mate)] if mate else []

        ok_ms = got == exp_ms
        ok_mate = bool(mate) and got == exp_mate

        verdict = []
        verdict.append("MusicSort✓" if ok_ms else "MusicSort✗")
        verdict.append("Mate✓" if ok_mate else "Mate✗")

        note = ""
        if ok_ms and not ok_mate:
            note = "  ← 只符合 MusicSort"
        elif ok_mate and not ok_ms:
            note = "  ← 只符合 Mate"
        elif not ok_ms and not ok_mate:
            note = "  ← 两个都不符合"
            problems += 1

        print(f"{gid:9} {label:>7}  {'  '.join(verdict)}{note}")
        if missing_ms:
            print(f"    不在 MusicSort.xml 里的曲目 {len(missing_ms)} 首: {missing_ms}")
        if not ok_ms and not ok_mate:
            print(f"    实际: {got}")
            print(f"    MS  : {exp_ms}")
            print(f"    Mate: {exp_mate}")

    print()
    print("=" * 92)
    if problems:
        print(f"✗ {problems} 处顺序不符")
        return 1
    print("✓ 所有有曲目列表的门，顺序都符合 MusicSort.xml")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
