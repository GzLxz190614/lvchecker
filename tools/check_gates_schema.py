#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
校验 data/gates.json 的结构约束。**这些约束违反了不会报错，只会静默出错**，
所以必须显式检查 —— 这是本项目的惯例（能失败的检查才有价值）。

检查项：

1. **每个 gate 的 requirement.type 是已知类型**。拼错的话
   `GateRequirement.fromJson` 会落到 "unknown"，界面表现是空白页，
   不报错、不崩溃 —— 很难查。

2. **itemsInSteps 必须有 steps，且 steps 非空**。
   少了 steps 会让 `allStepItemKeys` 返回空列表，
   于是 `total == 0` → 门永远**判定为未解锁**（因为 `total > 0 && ...`）。
   反过来，steps 存在但 type 写成了 items，则 RANK 那步不会被判定。

3. **同一步内 / 跨步之间，itemKeys 都不能重复**。
   进度按 itemKey 存在 SharedPreferences 里，重复会让一次勾选影响两处，
   把「两步」退化成「一步」—— 这正是 STAR 门原来的 bug 的另一种形态。

4. **所有 itemKeys / songKeys 都必须存在于 meta.json**。
   不存在的 key 会被 `_resolve()` 静默丢掉：卡片不显示、但
   `total` 还是算上了它，于是进度永远差一个、门永远不通。
   这个是**最阴的**一种错，因为它表现为「差 1 个但看不出差哪个」。

用法：
    python tools/check_gates_schema.py
退出码 0 = 全部通过，1 = 有问题。
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = Path(__file__).resolve().parent.parent

KNOWN_TYPES = {
    "playAll",
    "playAnyOfEach",
    "items",
    "itemsInSteps",
    "anyClassAllCourses",
    "clearAllPrev",
    "manualConfirm",
    "remainingHp",
}


def collect_keys(req: dict) -> tuple[list[str], list[str]]:
    """返回 (songKeys 全量, itemKeys 全量)。

    itemKeys 会把 groups 和各 step 的都收进来，因为它们最终都指向 meta 条目。
    """
    songs: list[str] = []
    items: list[str] = []

    raw_songs = req.get("songKeys")
    if isinstance(raw_songs, list):
        songs.extend(str(s) for s in raw_songs)

    raw_items = req.get("itemKeys")
    if isinstance(raw_items, list):
        items.extend(str(s) for s in raw_items)

    for grp in req.get("groups") or []:
        if isinstance(grp, dict):
            for k in grp.get("songKeys") or []:
                songs.append(str(k))
            # 有些实现把组内条目也叫 itemKeys
            for k in grp.get("itemKeys") or []:
                items.append(str(k))

    for step in req.get("steps") or []:
        if isinstance(step, dict):
            for k in step.get("itemKeys") or []:
                items.append(str(k))

    return songs, items


def main() -> int:
    gates_path = ROOT / "data" / "gates.json"
    meta_path = ROOT / "data" / "meta.json"

    for p in (gates_path, meta_path):
        if not p.exists():
            print(f"✗ 找不到 {p}")
            return 1

    gates = json.loads(gates_path.read_text(encoding="utf-8"))["gates"]
    meta = json.loads(meta_path.read_text(encoding="utf-8"))["entries"]
    known = set(meta.keys())

    problems: list[str] = []

    for gate in gates:
        gid = gate.get("id", "?")
        req = gate.get("requirement") or {}
        rtype = req.get("type")

        # --- 1. type 必须已知 ---
        if rtype not in KNOWN_TYPES:
            problems.append(f"{gid}: requirement.type={rtype!r} 不是已知类型 {sorted(KNOWN_TYPES)}")
            continue

        # --- 2. itemsInSteps 必须有非空 steps ---
        if rtype == "itemsInSteps":
            steps = req.get("steps")
            if not isinstance(steps, list) or not steps:
                problems.append(f"{gid}: type=itemsInSteps 但没有 steps（门会永远判定未解锁）")
                continue

            # 逐步检查
            seen: dict[str, str] = {}
            for si, step in enumerate(steps):
                skey = step.get("key") or f"#{si}"
                label = step.get("label") or ""
                if not label:
                    problems.append(f"{gid}/{skey}: 缺少 label（界面上的步骤标题）")
                keys = step.get("itemKeys") or []
                if not keys:
                    problems.append(f"{gid}/{skey}: itemKeys 为空（这一步永远不会完成）")
                for k in keys:
                    k = str(k)
                    if k in seen:
                        problems.append(
                            f"{gid}: itemKey {k!r} 在第 {seen[k]} 步和第 {skey} 步重复 "
                            f"—— 一次勾选会影响两处，两步会退化成一步"
                        )
                    else:
                        seen[k] = skey

            # allStepItemKeys 不能为空，否则 total==0
            if not any((s.get("itemKeys") or []) for s in steps):
                problems.append(f"{gid}: 所有 step 的 itemKeys 都是空的（total 会是 0）")

            # 顶层 itemKeys 是 steps 的**冗余平铺**（老版本 App 只读它，
            # 用来算出正确的 total）。冗余字段必然有漂移风险，所以必须校验。
            # 不一致的后果是静默的：判定用 steps（对），但显示/旧版用 itemKeys（错）。
            flat = req.get("itemKeys")
            if flat is not None:
                from_steps = [str(k) for s in steps for k in (s.get("itemKeys") or [])]
                if [str(k) for k in flat] != from_steps:
                    problems.append(
                        f"{gid}: 顶层 itemKeys 和 steps 里的条目不一致\n"
                        f"       itemKeys = {flat}\n"
                        f"       steps    = {from_steps}"
                    )

        # --- 3. 普通 items 也不能有重复 itemKey ---
        if rtype == "items":
            raw = req.get("itemKeys") or []
            dupes = {k for k in raw if raw.count(k) > 1}
            for d in sorted(dupes):
                problems.append(f"{gid}: itemKeys 里 {d!r} 重复")

        # --- 4. 所有 key 都必须存在于 meta.json ---
        songs, items = collect_keys(req)
        for k in songs + items:
            if k not in known:
                problems.append(
                    f"{gid}: {k!r} 不在 meta.json 里 "
                    f"—— 卡片不会显示，但 total 算上了它，进度会永远差一个"
                )

    print(f"检查 {len(gates)} 个门，meta.json 共 {len(known)} 个条目")
    print()

    if problems:
        print(f"✗ 发现 {len(problems)} 个问题：")
        for p in problems:
            print(f"  - {p}")
        return 1

    # 正面确认 STAR 的结构确实生效了（避免「检查通过但其实没跑到」）
    star = next((g for g in gates if g.get("id") == "star"), None)
    if star:
        req = star.get("requirement") or {}
        n_steps = len(req.get("steps") or [])
        n_items = len(req.get("itemKeys") or [])
        print(f"STAR 门: type={req.get('type')!r}  steps={n_steps}  itemKeys={n_items}")
        if req.get("type") != "itemsInSteps" or n_steps != 2:
            print("✗ STAR 应该已经是两步（type=itemsInSteps, steps=2）")
            return 1

    print("✓ 全部通过")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
