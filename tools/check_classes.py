#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
校验 classes.json（段位课程）的内部一致性。

三件事：
1. 每个固定曲槽的 linkId 必须在 meta.json 里（否则 app 里是「无图卡片」，看起来像 bug）
2. 随机槽的封面文件必须真实存在
3. **等级随机的 fromLevel 内部 ID 必须落在游戏对应的等级上**（下面 EXPECTED_LEVEL_IDS）

第 3 条是重点：内部 ID → 显示等级的换算（ID_n → Lv(n-19)/2 + 10）很容易写错，
而且写错之后 JSON 看起来依然「有数据」，肉眼看不出问题。这里把用户确认过的
映射表硬编码下来当回归测试，换算是错的会立刻失败。

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

# 每个段位等级里，等级随机槽允许出现的 fromLevel 内部 ID。
# 来源：用户确认的游戏内对应关系「CLASS 认定 - Ⅰ - Random 是 Lv10 / Lv10+ / Lv11」，
# 而这三个槽的 fromLevel 是 ID_19 / ID_20 / ID_21 —— 由此定出 ID_n → Lv 的换算，
# 再用它推出其余五个等级（每级 +2 个 ID）。
EXPECTED_LEVEL_IDS = {
    "I": {19, 20, 21},          # Lv10 / Lv10+ / Lv11
    "II": {22, 23, 24},         # Lv11+ / Lv12 / Lv12+
    "III": {24, 25, 26},        # Lv12+ / Lv13 / Lv13+
    "IV": {26, 27, 28},         # Lv13+ / Lv14 / Lv14+
    "V": {27, 28, 29},          # Lv14 / Lv14+ / Lv15
    "∞": {28, 29, 30},          # Lv14+ / Lv15 / Lv15+
}

# 合法等级字符串：'10' ~ '15+' 这种「数字 + 可选 +」
VALID_LEVELS = {
    f"{n}{plus}"
    for n in range(10, 16)
    for plus in ("", "+")
}


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
                kind = s.get("kind", "fixed")
                where = f"等级 {label} 组曲「{course.get('title')}」第 {i} 个槽"

                if kind == "fixed":
                    # 固定曲目：必须有 linkId、该 linkId 在 meta 里、有 difficulty
                    link = s.get("linkId")
                    if link not in meta:
                        problems.append(
                            f"  ✗ {where} 的 linkId '{link}' 不在 meta.json 里"
                            f"（app 里会显示无图卡片）"
                        )
                    if not s.get("difficulty"):
                        problems.append(f"  ✗ {where} 缺 difficulty")
                elif kind == "randomRange":
                    # 等级随机：必须有等级与封面
                    if not s.get("levelFrom") or not s.get("levelTo"):
                        problems.append(f"  ✗ {where} 是 randomRange 但缺 levelFrom/levelTo")
                    if not s.get("display"):
                        problems.append(f"  ✗ {where} 是 randomRange 但缺 display")
                    img = s.get("image")
                    if img and not (ROOT / img).exists():
                        problems.append(f"  ✗ {where} 的封面不存在：{img}")

                    # 等级换算回归测试（见文件头说明）
                    ids = EXPECTED_LEVEL_IDS.get(label)
                    lid = s.get("levelFromId")
                    if ids is None:
                        problems.append(f"  ✗ 等级 {label} 不在已知的段位等级表里")
                    elif lid not in ids:
                        problems.append(
                            f"  ✗ {where} 的 levelFromId={lid} 不在等级 {label} 预期的 "
                            f"{sorted(ids)} 里（等级换算可能写错了）"
                        )
                    lv = s.get("levelFrom")
                    if lv not in VALID_LEVELS:
                        problems.append(
                            f"  ✗ {where} 的 levelFrom='{lv}' 不是合法等级（应为 10~15 或带 +）"
                        )
                    # display 只允许「等级」或「等级 ~ 等级」，且不能残留内部 ID 写法
                    disp = str(s.get("display") or "")
                    parts = [p.strip() for p in disp.split("~")]
                    if any(p not in VALID_LEVELS for p in parts):
                        problems.append(
                            f"  ✗ {where} 的 display='{disp}' 不是等级写法"
                            f"（用户要求写真实等级，例如 '11+'，不要写内部 id）"
                        )
                elif kind == "randomPool":
                    # 曲池随机：必须有池大小与封面
                    if not s.get("poolSize"):
                        problems.append(f"  ✗ {where} 是 randomPool 但缺 poolSize")
                    if not s.get("display"):
                        problems.append(f"  ✗ {where} 是 randomPool 但缺 display")
                    img = s.get("image")
                    if img and not (ROOT / img).exists():
                        problems.append(f"  ✗ {where} 的封面不存在：{img}")
                else:
                    problems.append(f"  ✗ {where} 的 kind '{kind}' 不认识")

                if s.get("order") != i:
                    problems.append(
                        f"  · {where} 的 order 是 {s.get('order')}（建议与顺序一致）"
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
