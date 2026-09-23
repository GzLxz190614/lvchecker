#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
查各门里有没有「同一首歌出现多次」或「多个 key 指向同一个 song_id」。

背景（用户报告）：
    从落雪同步乐曲时，ORIGIN 门里出现了**两个「怒槌」**。
    而且手动勾完 30 首后再同步，会提示「怒槌没勾」；把 30 首全取消再同步，
    多出来的那个怒槌就消失了。

    听起来像「同一首歌在门里有两个不同 key」，于是：
      * 界面渲染两张卡（都叫怒槌）；
      * 用户只勾了其中一张，另一张仍显示未勾；
      * 落雪同步按 songId 匹配，一条成绩会同时命中两个 key，
        于是给「另一张」也提建议 —— 但用户看到的却是「我明明勾了」。

    为什么会有两个 key 指向同一首歌：`meta.json` 的 key 是 `music:<id>`，
    而曲目 id 在不同版本/难度体系里可能是不同的（例如 WORLD'S END 用的
    是 8xxx 段的 id，但也可能是同一首歌在 mega39 / 通常谱面里两条记录）。

用法：
    python tools/check_duplicate_songs.py
退出码 0 = 没有重复，1 = 发现重复。
"""

from __future__ import annotations

import json
import sys
from collections import defaultdict
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    gates = json.loads((ROOT / "data" / "gates.json").read_text(encoding="utf-8"))["gates"]
    meta = json.loads((ROOT / "data" / "meta.json").read_text(encoding="utf-8"))["entries"]

    problems = 0

    # ---- 1. 同一个门里 key 重复 ----
    print("=" * 78)
    print("① 同一个门里 key 重复")
    print("=" * 78)
    print("  （itemsInSteps 的顶层 itemKeys 与 steps[].itemKeys 是**故意冗余**，跳过）")
    any_dup_key = False
    for gate in gates:
        req = gate.get("requirement", {})
        rtype = req.get("type")
        # itemsInSteps：顶层 itemKeys 是 steps 的平铺副本，必然「重复」。
        # 那是设计如此（老版本 App 只读 itemKeys），由 check_gates_schema.py
        # 校验两者一致，不在这里当成 bug。
        if rtype == "itemsInSteps":
            continue

        keys: list[str] = []
        keys.extend(req.get("songKeys") or [])
        keys.extend(req.get("itemKeys") or [])
        for g in req.get("groups") or []:
            keys.extend(g.get("songKeys") or [])
            keys.extend(g.get("itemKeys") or [])

        seen = defaultdict(int)
        for k in keys:
            seen[k] += 1
        dups = {k: n for k, n in seen.items() if n > 1}
        if dups:
            any_dup_key = True
            problems += 1
            print(f"  ✗ {gate['id']}: {dups}")
    if not any_dup_key:
        print("  ✓ 没有（每个 key 在门里只出现一次）")

    # ---- 2. 同一个门里，多个 key 指向同一个曲名 ----
    print()
    print("=" * 78)
    print("② 同一个门里，多个 key 指向同一个**曲名**（「两个怒槌」就是这个）")
    print("=" * 78)
    any_dup_title = False
    for gate in gates:
        req = gate.get("requirement", {})
        keys: list[str] = []
        keys.extend(req.get("songKeys") or [])
        for g in req.get("groups") or []:
            keys.extend(g.get("songKeys") or [])

        by_title: dict[str, list[str]] = defaultdict(list)
        for k in keys:
            e = meta.get(k)
            if not e:
                continue
            title = (e.get("title") or "").strip()
            if title:
                by_title[title].append(k)

        for title, ks in by_title.items():
            if len(ks) > 1:
                any_dup_title = True
                problems += 1
                print(f"  ✗ {gate['id']}: 「{title}」出现 {len(ks)} 次 -> {ks}")
                for k in ks:
                    e = meta.get(k, {})
                    print(f"        {k}: id={e.get('id')} works={e.get('works')!r} "
                          f"genre={e.get('genre')!r}")
    if not any_dup_title:
        print("  ✓ 没有（没有门收录同名曲目两次）")

    # ---- 3. 全库里「id 不同但曲名相同」的曲目 ----
    print()
    print("=" * 78)
    print("③ 全库里「曲名相同但 id 不同」的曲目（不限门）")
    print("=" * 78)
    by_title_all: dict[str, list[str]] = defaultdict(list)
    for k, e in meta.items():
        if e.get("type") != "music":
            continue
        title = (e.get("title") or "").strip()
        if title:
            by_title_all[title].append(k)
    dup_titles = {t: ks for t, ks in by_title_all.items() if len(ks) > 1}
    if dup_titles:
        print(f"  共 {len(dup_titles)} 组同名曲目：")
        for t, ks in sorted(dup_titles.items()):
            print(f"    「{t}」")
            for k in sorted(ks):
                e = meta[k]
                print(f"        {k}: id={e.get('id')} works={e.get('works')!r}")
    else:
        print("  ✓ 没有")

    # ---- 4. 怒槌 专项 ----
    print()
    print("=" * 78)
    print("④ 「怒槌」专项")
    print("=" * 78)
    hits = [(k, e) for k, e in meta.items()
            if e.get("type") == "music" and "怒槌" in (e.get("title") or "")]
    if not hits:
        print("  meta.json 里没有曲名含「怒槌」的条目")
    for k, e in hits:
        print(f"  {k}: title={e.get('title')!r} id={e.get('id')} "
              f"works={e.get('works')!r} image={e.get('image')!r}")
        # 它出现在哪些门
        for gate in gates:
            req = gate.get("requirement", {})
            ks = list(req.get("songKeys") or [])
            for g in req.get("groups") or []:
                ks.extend(g.get("songKeys") or [])
            if k in ks:
                print(f"        -> 在门 {gate['id']} 里")

    print()
    if problems:
        print(f"✗ 发现 {problems} 处重复")
        return 1
    print("✓ 没有发现重复")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
