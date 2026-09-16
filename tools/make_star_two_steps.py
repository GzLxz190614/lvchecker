#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把 STAR 门改成「两步条件」（`itemsInSteps`）。

背景 / 为什么要改：
    STAR 的解锁条件是「从地图 VERSE ep.STAR 获得角色
    観音寺 にこる／Mermaid♡Moment，**并**升到 RANK 15」—— 两件事，缺一不可。

    改之前 `requirement` 是 `{"type": "items", "itemKeys": ["chara:24320"]}`，
    界面只渲染**一张角色卡**，勾上就算门通。于是：
      * RANK 15 这个要求完全没有被表达，只写在条目 subtitle 的文案里；
      * 角色只有 RANK 1 时勾一下，App 也会显示 STAR 已解锁 —— 判定是错的。

    改成两步之后，`itemKeys` 变成 `chara:24320` 和 `chara:24320.rank15`，
    两者都勾上才算通。

定义在 `tools/star_steps.py`（和 `build.py` 共用同一份，避免两边漂移）。

幂等：重复运行不会重复追加条目，也不会把已经改好的结构再套一层。

用法：
    python tools/make_star_two_steps.py            # 改 data/gates.json + meta.json
    python tools/make_star_two_steps.py --check    # 只检查，不写入
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# 允许直接 `python tools/make_star_two_steps.py` 运行（此时 sys.path[0] 是 tools/）
sys.path.insert(0, str(Path(__file__).resolve().parent))

import star_steps  # noqa: E402

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = Path(__file__).resolve().parent.parent
GATES = ROOT / "data" / "gates.json"
META = ROOT / "data" / "meta.json"

GATE_ID = "star"


def ensure_meta_entry(entries: dict, char_key: str) -> bool:
    """在 meta.json 里给第 2 步建条目。返回是否改动。"""
    rank_key = star_steps.rank_item_key(char_key)

    src = entries.get(char_key)
    if not isinstance(src, dict):
        print(f"✗ meta.json 里找不到 {char_key}，无法生成第 2 步条目")
        return False

    # 角色卡自己的副标题也统一到共用定义（和 build.py 生成的一致）
    wanted = star_steps.CHAR_SUBTITLE
    if src.get("subtitle") != wanted:
        src["subtitle"] = wanted
        print(f"  ✓ 更新 {char_key} 的 subtitle -> {wanted!r}")
        changed = True
    else:
        changed = False

    if rank_key in entries:
        print(f"  meta.json 里已有 {rank_key}，跳过新增")
        return changed

    entries[rank_key] = star_steps.rank_meta_entry(src)
    print(f"  ✓ 已在 meta.json 新增 {rank_key}")
    return True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="只检查，不写入")
    args = ap.parse_args()

    if not GATES.exists():
        print(f"✗ 找不到 {GATES}")
        return 1
    doc = json.loads(GATES.read_text(encoding="utf-8"))
    gates = doc.get("gates")
    if not isinstance(gates, list):
        print("✗ gates.json 的 gates 不是列表")
        return 1

    target = next((g for g in gates if g.get("id") == GATE_ID), None)
    if target is None:
        print(f"✗ 找不到 id={GATE_ID} 的门")
        return 1

    old_req = target.get("requirement") or {}
    # 从旧的 itemKeys 里取出角色 key（过滤掉可能已存在的 sentinel）
    char_keys = [
        k for k in (old_req.get("itemKeys") or [])
        if isinstance(k, str) and not k.endswith(star_steps.RANK_KEY_SUFFIX)
    ]
    if not char_keys:
        print(f"✗ {GATE_ID} 的 itemKeys 里找不到角色条目：{old_req.get('itemKeys')}")
        return 1

    meta_doc = json.loads(META.read_text(encoding="utf-8"))
    entries = meta_doc.get("entries")
    if not isinstance(entries, dict):
        print("✗ meta.json 的 entries 不是对象")
        return 1

    char_title = ""
    first = entries.get(char_keys[0])
    if isinstance(first, dict):
        char_title = str(first.get("title") or "")

    new_req = star_steps.build_requirement(char_keys, char_title)

    print(f"门 {GATE_ID}（{target.get('name')}）")
    print(f"  改前: {json.dumps(old_req, ensure_ascii=False)}")
    print(f"  改后: {json.dumps(new_req, ensure_ascii=False)}")

    if json.dumps(old_req, ensure_ascii=False) == json.dumps(new_req, ensure_ascii=False):
        print("  （结构已经是对的，无需改动 requirement）")
        req_changed = False
    else:
        req_changed = True

    if args.check:
        print("\n--check：没有写入任何文件")
        return 0

    if req_changed:
        target["requirement"] = new_req
        GATES.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
        print("  ✓ 已写入 data/gates.json")

    print("meta.json：")
    meta_changed = ensure_meta_entry(entries, char_keys[0])
    if meta_changed:
        meta_doc["entries"] = entries
        META.write_text(json.dumps(meta_doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
        print("  ✓ 已写入 data/meta.json")
    elif not req_changed:
        print("  （无需改动）")

    print()
    print("下一步：python tools/check_gates_schema.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
