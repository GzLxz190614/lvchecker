#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
STAR 门「两步条件」的定义。**这是唯一的一份定义**，两处共用：

  * `tools/build.py`                       —— 重新生成 gates.json 时自动套上
  * `tools/make_star_two_steps.py`         —— 对已有的 gates.json 做原地改造（修复 / 补数据）

为什么要抽出来共用，而不是各写一份：
    两边各写一份的话，改了一处忘了另一处，**数据结构和实际生成的结构就会漂移**。
    漂移的表现是「手动跑脚本改好了，但重新 build 又变回去了」——
    这类问题不会报错，只会在某次重新生成数据时静默回退。

STAR 的条件原文：
    「从地图 VERSE ep.STAR 获得 角色観音寺 にこる／Mermaid♡Moment ，然后升到15级」
即两件事：① 获得该角色；② 把它升到 RANK 15。缺一不可。

为什么第 2 步要单独一个 itemKey，而不是复用 chara:24320：
    进度是按 itemKey 存在 SharedPreferences 里的。两步共用同一个 key 的话，
    勾第 1 步会同时把第 2 步也勾上，两步就退化成一步了 ——
    那正是改造之前的状态（只判角色卡，RANK 15 完全没判定）。
"""

from __future__ import annotations

# 第 2 步的等级门槛。改这个值时会自动反映到标签、说明和 sentinel key 上。
RANK = 15

# 第 2 步的 sentinel itemKey。规则：`<角色 key>.rank<等级>`，一眼看出是哪个角色的哪一级。
RANK_KEY_SUFFIX = f".rank{RANK}"

STEP1_NOTE = "从地图 VERSE ep.STAR 获得"
STEP2_LABEL = f"升到 RANK {RANK}"
STEP2_NOTE = f"角色练到 RANK {RANK} 即达成"
# 故意不写成和角色卡一样的「角色 · 需升到 RANK 15」——
# 两张卡图相同，副标题再一样就分不清哪张是「获得」哪张是「练级」。
STEP2_SUBTITLE = f"练级进度 · 升到 RANK {RANK} 后勾选"

# 第 1 步的卡片副标题（角色卡本身）
CHAR_SUBTITLE = f"角色 · 需升到 RANK {RANK}"


def rank_item_key(char_key: str) -> str:
    return f"{char_key}{RANK_KEY_SUFFIX}"


def build_requirement(char_keys: list[str], char_title: str = "") -> dict:
    """按角色 key 生成两步 requirement。

    正常情况下 [char_keys] 只有一个（観音寺 にこる）。多于一个也能处理：
    第 1 步包含全部角色，第 2 步为每个角色各要一个等级条目。
    """
    rank_keys = [rank_item_key(k) for k in char_keys]

    step1_label = "获得角色" + (f" {char_title}" if char_title else "")

    return {
        "type": "itemsInSteps",
        # 冗余保留一份平铺的 itemKeys：
        #   * 老版本 App 读新数据时仍能算出正确的 total（不会永远差一个）；
        #   * 设置页/导入这些只读 itemKeys 的地方不用改。
        # 冗余字段必须和 steps 保持同步 —— 由 tools/check_gates_schema.py 校验。
        "itemKeys": [*char_keys, *rank_keys],
        "steps": [
            {
                "key": "obtain",
                "label": step1_label,
                "note": STEP1_NOTE,
                "itemKeys": list(char_keys),
            },
            {
                "key": "rank",
                "label": STEP2_LABEL,
                "note": STEP2_NOTE,
                "itemKeys": rank_keys,
            },
        ],
    }


def rank_meta_entry(char_entry: dict) -> dict:
    """由角色条目推出第 2 步的 meta 条目。

    复用同一张图：这一步是**同一个角色的属性**，不是另一个角色。
    """
    return {
        "type": "chara",
        "id": char_entry.get("id"),
        "title": char_entry.get("title") or "",
        "subtitle": STEP2_SUBTITLE,
        "image": char_entry.get("image"),
    }
