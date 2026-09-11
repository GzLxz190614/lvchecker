#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从 condition/class/course/*/Course.xml 生成 data/classes.json，并处理段位用到的曲目与封面。

数据来源与结构：
    condition/class/course/<id>/Course.xml   36 个组曲（6 个 CLASS）
    condition/class/music/<id>/Music.xml     组曲用到的 76 首曲目
    condition/class/random/cover.png         「?」——等级随机的封面
    condition/class/random in range/cover.png「!」——范围随机的封面

Course.xml 里每个槽的 type：
    0 = 固定曲目（selectMusic/musicName 有 id）
    1 = 按等级随机（selectLevel/fromLevel 给内部等级 ID，无 toLevel）
    2 = 指定曲池随机（selectMusicList 里是候选列表）

关于 fromLevel 的 ID：
    实测 ID_19 = Lv10（见 tools/build.py 里的说明与验证），其余按 1 递推，
    '.5' 在游戏内显示成 'x+'。

用法（单独运行也行）：
    python tools/gen_classes.py
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
CONDITION = ROOT / "condition"
DATA = ROOT / "data"
IMG_OUT = ROOT / "assets" / "img" / "class"

CLASS_DIR = CONDITION / "class"
COURSE_DIR = CLASS_DIR / "course"
CLASS_MUSIC_DIR = CLASS_DIR / "music"
RANDOM_COVER = CLASS_DIR / "random" / "cover.png"
RANGE_COVER = CLASS_DIR / "random in range" / "cover.png"

SCHEMA_VERSION = 1
LEVEL_ID_BASE = 19            # ID_19
LEVEL_ID_BASE_DIFFICULTY = 10  # -> Lv10

# dataVersion 必须和 build.py 生成的其他 json 一致，否则 App 同步时会看到
# classes.json 的版本号和 meta.json 不一样，误判成「有更新」。
# 用 import 而不是复制一份，就是为了防止两边漂移。
sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    from build import DATA_VERSION  # type: ignore
except Exception:  # noqa: BLE001
    DATA_VERSION = "2026.09.11-2"

CLASS_META = {
    "CLASS Ⅰ": ("I", 1, "#3D66F2"),
    "CLASS Ⅱ": ("II", 2, "#0DB991"),
    "CLASS Ⅲ": ("III", 3, "#F2AA00"),
    "CLASS Ⅳ": ("IV", 4, "#E13C29"),
    "CLASS Ⅴ": ("V", 5, "#4A0973"),
    "CLASS ∞": ("∞", 0, "#FCDBEF"),
}

# 组曲难度槽的显示名
DIFF_LABEL = {
    "BASIC": "BASIC", "ADVANCED": "ADVANCED", "EXPERT": "EXPERT",
    "MASTER": "MASTER", "ULTIMA": "ULTIMA", "WORLD'S END": "WORLD'S END",
}

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

warnings: list[str] = []


def warn(msg: str) -> None:
    warnings.append(msg)
    print(f"  [warn] {msg}")


def level_from_id(level_id: int) -> str:
    """
    内部等级 ID -> 游戏内显示的等级字符串。

    实测（见 tools/build.py 里的验证）：ID_19 = Lv10，之后每 +1 个 ID 是 +0.5 级，
    游戏内 '.5' 显示成 'x+'。所以：
        ID_19 -> '10'   ID_20 -> '10+'  ID_21 -> '11'
        ID_24 -> '12+'  ID_25 -> '13'   ID_30 -> '15+'

    ⚠️ 注意别把这里当成「等级 = ID - 9」。ID_19 看起来像 19-9=10 纯属巧合，
    ID_20 → 10+ 而不是 11 才说明真正的规律是「每 2 个 ID 涨 1 级」。
    """
    offset = level_id - LEVEL_ID_BASE
    return f"{LEVEL_ID_BASE_DIFFICULTY + offset // 2}{'+' if offset % 2 else ''}"


def txt(el, path: str) -> str:
    v = el.findtext(path)
    return (v or "").strip()


def main() -> int:
    if not COURSE_DIR.exists():
        print(f"找不到 {COURSE_DIR}")
        return 1

    IMG_OUT.mkdir(parents=True, exist_ok=True)

    # ---------------------------------------------------------------- 封面
    covers: dict[str, str] = {}
    for src, key, out_name in (
        (RANDOM_COVER, "classRandom", "random_cover.png"),
        (RANGE_COVER, "classRange", "range_cover.png"),
    ):
        if not src.exists():
            warn(f"缺少封面文件：{src}")
            continue
        try:
            from PIL import Image
            with Image.open(src) as im:
                im.load()
                im.convert("RGBA").save(IMG_OUT / out_name, "PNG", optimize=True)
            covers[key] = f"assets/img/class/{out_name}"
        except Exception as e:  # noqa: BLE001
            warn(f"封面转换失败 {src}: {e}")

    # ---------------------------------------------------------------- 曲目清单
    # 组曲固定曲目需要在 meta 里有条目才能显示曲名/曲绘。
    # 这里只收集「组曲用到的」曲目及其难度，具体并入 meta.json 由 build.py 负责
    # （它会扫 condition/class/music 下的 Music.xml）。
    needed_ids: set[int] = set()
    for f in sorted(COURSE_DIR.glob("*/Course.xml")):
        root = ET.parse(f).getroot()
        infos = root.find("infos")
        if infos is None:
            continue
        for info in infos.findall("CourseMusicDataInfo"):
            if (info.findtext("type") or "0") != "0":
                continue
            v = info.findtext("selectMusic/musicName/id")
            if v:
                needed_ids.add(int(v))

    # ---------------------------------------------------------------- 组曲
    by_class: dict[str, list[dict]] = {}
    for f in sorted(COURSE_DIR.glob("*/Course.xml")):
        root = ET.parse(f).getroot()
        cls_raw = txt(root, "difficulty/data")
        if cls_raw not in CLASS_META:
            warn(f"{f.parent.name} 的 CLASS 名不认识：{cls_raw!r}")
            continue

        course = {
            "key": root.findtext("dataName") or f.parent.name,
            "title": txt(root, "name/str"),
            "songs": [],
        }

        infos = root.find("infos")
        if infos is None:
            warn(f"{f.parent.name} 没有 infos")
            continue

        for idx, info in enumerate(infos.findall("CourseMusicDataInfo"), start=1):
            t = (info.findtext("type") or "0").strip()
            if t == "0":
                sid = int(info.findtext("selectMusic/musicName/id") or -1)
                diff = txt(info, "selectMusic/musicDiff/data")
                course["songs"].append({
                    "order": idx,
                    "kind": "fixed",
                    "linkId": f"music:{sid}",
                    "difficulty": DIFF_LABEL.get(diff, diff),
                })
            elif t == "1":
                # 等级随机槽。数据里有 fromLevel，通常没有 toLevel——
                # 也就是「范围」就是这个等级本身（CLASS Ⅰ 是 Lv10 / Lv10+ / Lv11）。
                # 用 findtext 再解析一次，是为了万一以后官方加了 toLevel 也能直接用。
                from_id = int(info.findtext("selectLevel/fromLevel/id") or "0")
                to_raw = info.findtext("selectLevel/toLevel/id")
                to_id = int(to_raw) if to_raw else from_id
                lv_from = level_from_id(from_id)
                lv_to = level_from_id(to_id)
                course["songs"].append({
                    "order": idx,
                    "kind": "randomRange",
                    "levelFromId": from_id,
                    "levelToId": to_id,
                    "levelFrom": lv_from,
                    "levelTo": lv_to,
                    # display 是给 UI 直接用的字符串，格式和固定曲的等级显示保持一致。
                    # 用户明确要求写真实等级（"11+"），不要写内部 id，也不要只写 "等级随机"。
                    "display": lv_from if lv_from == lv_to else f"{lv_from} ~ {lv_to}",
                    "image": covers.get("classRange"),
                })
            elif t == "2":
                lst = info.find("selectMusicList/musicList/list")
                pool = []
                if lst is not None:
                    for sub in lst.findall("CourseMusicListSubData"):
                        cmd = sub.find("courseMusicData")
                        if cmd is None:
                            continue
                        v = cmd.findtext("name/id")
                        if v:
                            pool.append(int(v))
                course["songs"].append({
                    "order": idx,
                    "kind": "randomPool",
                    "poolSize": len(pool),
                    # 用户要求：这个直接写「范围内随机选择」，不列具体曲目
                    "display": "范围内随机选择",
                    "image": covers.get("classRandom"),
                })
            else:
                warn(f"{f.parent.name} 槽 {idx} 的 type={t} 未处理")

        by_class.setdefault(cls_raw, []).append(course)

    # ---------------------------------------------------------------- 装成 JSON
    classes = []
    for cls_raw, (label, level, color) in CLASS_META.items():
        courses = sorted(by_class.get(cls_raw, []), key=lambda c: c["key"])
        if not courses:
            warn(f"{cls_raw} 没有任何组曲")
        classes.append({
            "key": label,
            "label": label,
            "level": level,
            "color": color,
            "classRawName": cls_raw,
            "courses": courses,
        })
    # ∞(0) 排最前，然后 V..I
    classes.sort(key=lambda c: (0 if c["level"] == 0 else 1, -c["level"]))

    doc = {
        "schemaVersion": SCHEMA_VERSION,
        "dataVersion": DATA_VERSION,
        "placeholder": False,
        "region": "cn",
        "note": "段位课程来自 condition/class/course 的 36 个 Course.xml；"
                "随机槽按等级或曲池随机，因此只给等级/池大小，不列具体曲目。",
        "gateId": "air",
        "unlockRule": {
            "type": "anyClassAllCourses",
            "text": "完成任一 CLASS 内的所有组曲，即可获得缎带",
        },
        "levelIdMapping": {
            "note": "fromLevel 的内部 ID 与游戏内难度的对应关系（已验证）",
            "baseId": LEVEL_ID_BASE,
            "baseDifficulty": f"Lv{LEVEL_ID_BASE_DIFFICULTY}",
        },
        "classes": classes,
    }

    DATA.mkdir(parents=True, exist_ok=True)
    (DATA / "classes.json").write_text(
        json.dumps(doc, ensure_ascii=False, indent=2), encoding="utf-8")

    # ---------------------------------------------------------------- 汇总
    print(f"段位课程：{len(classes)} 个 CLASS")
    total_courses = 0
    total_fixed = 0
    total_rand = 0
    for c in classes:
        n_fixed = sum(1 for co in c["courses"] for s in co["songs"] if s["kind"] == "fixed")
        n_rand = sum(1 for co in c["courses"] for s in co["songs"] if s["kind"] != "fixed")
        total_courses += len(c["courses"])
        total_fixed += n_fixed
        total_rand += n_rand
        print(f"  {c['label']:<4} {len(c['courses'])} 组曲 · 固定曲 {n_fixed} · 随机槽 {n_rand}")
    print(f"合计：{total_courses} 组曲 · 固定曲槽 {total_fixed} · 随机槽 {total_rand}")
    print(f"组曲涉及的曲目（去重）：{len(needed_ids)} 首")
    print(f"封面：{covers}")

    if warnings:
        print(f"\n⚠️ {len(warnings)} 条警告")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
