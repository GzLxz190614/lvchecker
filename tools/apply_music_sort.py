#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把 `data/gates.json` 里各门的曲目顺序，按 `condition/MusicSort.xml`（游戏内顺序）重排。

## 为什么不直接跑 tools/build.py

因为 `build.py` 会**整体重新生成** `gates.json`，包括 `conditionText` ——
而 `data/gates.json` 里的条件文本后来被手工改过（措辞更准确），
`build.py` 里的 `CONDITION_TEXT` 还是旧文案，跑一遍就会把那 9 处改动覆盖掉。

所以这个脚本只做**一件事**：重排曲目顺序。其余字段一律不动。

> 等 `build.py` 的 `CONDITION_TEXT` 同步成新文案之后，重跑 `build.py` 也能得到同样结果
> （`build.py` 里已经接了 `sort_gate_songs`）。在那之前，用这个脚本。

## 排序规则

- 顺序取 `MusicSort.xml` 的 `<SortList>` 文档顺序（= 游戏内显示顺序）
- **AIR 跳过**：段位课程的曲目顺序由 `Course.xml` 的槽位决定，不能重排
- PARADISE 的**分组之间不动**（按曲师分栏），只排每组内部
- 不在表里的曲目排到最后，彼此保持原顺序

用法：
    python tools/apply_music_sort.py --dry-run   # 只看会改什么
    python tools/apply_music_sort.py             # 真的改
    python tools/apply_music_sort.py --bump-version  # 改完顺便把 dataVersion +1
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

sys.path.insert(0, str(Path(__file__).resolve().parent))

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

from build import load_music_order, sort_gate_songs  # noqa: E402

GATES = ROOT / "data" / "gates.json"


def bump(version: str) -> str:
    """`2026.09.11-3` -> `2026.09.11-4`；没有 -N 后缀就加 -2。"""
    m = re.match(r"^(.*?)-(\d+)$", version)
    if m:
        return f"{m.group(1)}-{int(m.group(2)) + 1}"
    return f"{version}-2"


def main() -> int:
    ap = argparse.ArgumentParser(description="按 MusicSort.xml 重排门曲目顺序")
    ap.add_argument("--dry-run", action="store_true", help="只显示会改什么，不写文件")
    ap.add_argument("--bump-version", action="store_true",
                    help="顺便把 dataVersion 加一（让热更新能识别为「有新数据」）")
    args = ap.parse_args()

    if not GATES.exists():
        print(f"找不到 {GATES}")
        return 1

    doc = json.loads(GATES.read_text(encoding="utf-8"))
    gates = doc.get("gates")
    if not isinstance(gates, list):
        print("gates.json 结构不对")
        return 1

    order = load_music_order()
    if not order:
        print("❌ 读不到 MusicSort 顺序，放弃（不会改动文件）")
        return 1
    print(f"MusicSort 顺序：{len(order)} 首")

    # 先记下改动前的样子，便于逐门报告
    before: dict[str, list] = {}
    for g in gates:
        req = g.get("requirement") or {}
        if isinstance(req.get("songKeys"), list):
            before[g["id"]] = list(req["songKeys"])

    touched = sort_gate_songs(gates, order)
    print(f"重排了 {touched} 个门（AIR 已跳过）")
    print()

    # 逐门对比，只报告真的变了的
    for g in gates:
        gid = g["id"]
        req = g.get("requirement") or {}
        cur = req.get("songKeys")
        old = before.get(gid)
        if old is None or cur is None:
            continue
        if old != cur:
            print(f"  {gid}: 顺序变了（{len(cur)} 首）")
            print(f"    前: {old[:4]} ...")
            print(f"    后: {cur[:4]} ...")

    old_ver = doc.get("dataVersion")
    if args.bump_version:
        new_ver = bump(str(old_ver))
        doc["dataVersion"] = new_ver
        print()
        print(f"dataVersion: {old_ver} -> {new_ver}")

    if args.dry_run:
        print()
        print("（--dry-run，没有写文件）")
        return 0

    GATES.write_text(
        json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print()
    print(f"已写入 {GATES}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
