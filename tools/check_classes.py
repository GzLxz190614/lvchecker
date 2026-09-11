#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
校验 classes.json（段位课程）里的引用是否都存在于 meta.json。

背景：段位课程是占位数据，可能手填了 meta.json 里没有的 linkId。
那样 app 里会渲染出「无图」卡片，看起来像 bug，实际是数据不一致。
这个脚本把它挡在前面。

用法：
    python tools/check_classes.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass


def main() -> int:
    meta = json.loads((ROOT / "data" / "meta.json").read_text(encoding="utf-8"))["entries"]
    cls = json.loads((ROOT / "data" / "classes.json").read_text(encoding="utf-8"))

    print(f"meta 条目 {len(meta)} 个；段位等级 {len(cls.get('classes', []))} 个")
    if cls.get("placeholder"):
        print("⚠️ classes.json 目前是占位数据（placeholder: true）")

    problems: list[str] = []
    total_courses = 0
    total_songs = 0
    colors: dict[str, str] = {}

    for c in cls.get("classes", []):
        key = c.get("key", "?")
        label = c.get("label", "?")
        courses = c.get("courses", [])
        colors[label] = c.get("color", "")

        if not courses:
            problems.append(f"  ✗ 等级 {label} 没有任何组曲（AIR 门将无法通过它达成）")

        for course in courses:
            total_courses += 1
            songs = course.get("songs", [])
            if len(songs) != 3:
                problems.append(
                    f"  ✗ 等级 {label} 的组曲「{course.get('title')}」有 {len(songs)} 首（应为 3）"
                )
            for i, s in enumerate(songs, 1):
                total_songs += 1
                link = s.get("linkId")
                if link not in meta:
                    problems.append(
                        f"  ✗ 等级 {label} 组曲「{course.get('title')}」第 {i} 首的 "
                        f"linkId '{link}' 不在 meta.json 里（app 里会显示无图卡片）"
                    )
                if not s.get("difficulty"):
                    problems.append(
                        f"  ✗ 等级 {label} 组曲「{course.get('title')}」第 {i} 首缺 difficulty"
                    )
                if s.get("order") != i:
                    problems.append(
                        f"  · 等级 {label} 组曲「{course.get('title')}」第 {i} 首的 order 是 "
                        f"{s.get('order')}（建议与顺序一致）"
                    )

    print(f"组曲 {total_courses} 个 / 曲目 {total_songs} 首")

    # 等级配色检查
    expected = {
        "I": "#3D66F2", "II": "#0DB991", "III": "#F2AA00",
        "IV": "#E13C29", "V": "#4A0973", "∞": "#FCDBEF",
    }
    for label, want in expected.items():
        got = colors.get(label)
        if got is None:
            problems.append(f"  ✗ 缺等级 {label}")
        elif got.upper() != want.upper():
            problems.append(f"  · 等级 {label} 配色是 {got}，与约定的 {want} 不一致")

    print()
    if problems:
        print("发现问题：")
        print("\n".join(problems))
        # 只有引用缺失算致命，配色/order 不一致只提示
        fatal = [p for p in problems if p.strip().startswith("✗")]
        return 1 if fatal else 0
    print("✅ 段位课程数据一致")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
