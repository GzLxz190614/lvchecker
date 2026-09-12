#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
lvchecker —— M0 数据与资源构建脚本

从 condition/ 目录（游戏数据）生成：
    data/meta.json         全局条目元数据（图片/名称）去重表
    data/gates.json        13 个门的完整定义
    data/linklevels.json   通关条件缓和配置 + 判定色
    data/classes.json      AIR 段位课程（由 tools/gen_classes.py 生成）
    assets/img/music/{id}/jacket.<IMG_EXT> + meta.json
    assets/img/avatar/{id}/icon.<IMG_EXT> + tex.<IMG_EXT> + meta.json
    assets/img/chara/{id}/meta.json

用法：
    python tools/build.py

依赖：Pillow（用于 dds -> png）。若缺失，图片步骤会跳过并警告，数据仍会生成。
"""

from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path
from xml.etree import ElementTree as ET

# ---------------------------------------------------------------- 路径

ROOT = Path(__file__).resolve().parent.parent
CONDITION = ROOT / "condition"
DATA = ROOT / "data"
IMG = ROOT / "assets" / "img"

# Windows 控制台默认 GBK，中文/日文会炸。强制 UTF-8 输出。
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

SCHEMA_VERSION = 1
# 数据版本号。meta/gates/linklevels/classes 四个 json 共用同一个值
# （gen_classes.py 会从这里 import，免得两边写不一致）。
# 改数据后把它 +1，App 的「检查更新」就是靠比对这个字符串来判断有没有新数据的。
DATA_VERSION = "2026.09.11-3"

# ---------------------------------------------------------------------------
# 输出图片格式：WebP。
#
# 为什么用 WebP（实测数据，160 张图）：
#   PNG  19.31 MB  →  WebP(q=82)  4.13 MB      省 78.6% / 15.18 MB
#   曲绘原始分辨率是 300×300（正好对应卡片 ~95~104dp 的高密度屏显示，没有过度打包），
#   1080×1080 的角色立绘也从 710KB 降到 141KB。
#
#   兼容性没有问题：Android 4.0+ 原生支持解码 WebP，Flutter 的 Image.asset
#   也支持——但**靠文件扩展名选解码器**，所以路径里的扩展名必须跟着改。
#
# ⚠️ 连带影响（改格式时别忘了这几处）：
#   · data/*.json 里所有 "image" 路径（由本文件生成，会自动跟上）
#   · pubspec.yaml 的 assets 列表（由 tools/gen_asset_list.py 重建）
#   · tools/check_assets.py 与 gen_asset_list.py 里的 `rglob("*.png")`
#   · lib/widgets/item_card.dart 等处的注释示例
#   · 仓库根目录的 icon.png **不要动**：那是 flutter_launcher_icons 的输入，
#     它按扩展名找文件，而且启动图标本来就该是 PNG。
# ---------------------------------------------------------------------------
IMG_EXT = "webp"
WEBP_QUALITY = 82


def save_image(im, out_path, *, quality: int = WEBP_QUALITY) -> None:
    """把 PIL 图像按 IMG_EXT 指定的格式写盘。

    `method=6` 是 WebP 编码器的最高压缩档（更慢但更小）。
    这个脚本只在本地/CI 偶尔跑一次，慢一点无所谓。
    """
    if IMG_EXT == "webp":
        im.save(out_path, "WEBP", quality=quality, method=6)
    else:
        im.save(out_path, "PNG", optimize=True)


# 门的开放日期（来自 condition/*/日期.txt）
RELEASE_OPEN = "2026-09-10T10:00"   # 无时区，按手机本地时间解析
RELEASE_OPEN_RAW = "2026/9/10"

# BOSS 曲信息。
# 优先从 condition/boss/musicXXXX/ 读（本地游戏数据，含精确难度）；
# 下面的表在缺少 boss 目录时作为兜底。
BOSSES = {
    "origin":   {"songId": 8010, "title": "神鳴",      "artist": "Rígr feat. 光吉猛修",
                 "levels": {"basic": "6", "advanced": "10+", "expert": "14", "master": "15+"}},
    "air":      {"songId": 8011, "title": "Tru'nembra", "artist": "Team Grimoire & 穴山大輔",
                 "levels": {"basic": "5", "advanced": "10", "expert": "14", "master": "15+"}},
    "star":     {"songId": None, "title": "Everything Will Be One", "artist": "void(Mournfinale)",
                 "levels": None},
    "amazon":   {"songId": None, "title": "OUTRAGE",   "artist": "USAO vs DJ Myosuke",
                 "levels": None},
    "crystal":  {"songId": None, "title": "輪廻玲々",   "artist": "suzu",
                 "levels": None},
    "paradise": {"songId": None, "title": "創 -汝ら新世界へ歩む者なり-",
                 "artist": "BlackY VS Yooh VS siromaru VS xi VS モリモリあつし",
                 "levels": None},
    "new":      {"songId": None, "title": "轆轤首",     "artist": "かねこちはる",
                 "levels": {"basic": "5", "advanced": "9", "expert": "13+", "master": "15"}},
    "sun":      {"songId": None, "title": "Sweet & Sour", "artist": "Sakuzyo or Sobrem",
                 "levels": {"basic": "5", "advanced": "10", "expert": "14", "master": "15+"}},
    "luminous": {"songId": None, "title": "Phantom Crisis", "artist": "t+pazolite vs Yuta Imai",
                 "levels": {"basic": "6", "advanced": "11+", "expert": "14", "master": "15+"}},
    "verse":    {"songId": None, "title": "月葬",       "artist": "黒魔 × rintaro soma",
                 "levels": {"basic": "5", "advanced": "9", "expert": "14", "master": "15+"}},
    "xverse":   {"songId": None, "title": "YOUNITHM",   "artist": "大国奏音",
                 "levels": {"basic": "8", "advanced": "12+", "expert": "14+", "master": "15+", "ultima": "15+"}},
    "reverse":  {"songId": None, "title": "YOUNITHM",   "artist": "大国奏音",
                 "levels": {"basic": "8", "advanced": "12+", "expert": "14+", "master": "15+", "ultima": "15+"}},
    "universe": {"songId": None, "title": "Melodiniq",  "artist": "onoken a.k.a. owl＊tree",
                 "levels": {"basic": "8+", "advanced": "13", "expert": "14+", "master": "15+", "ultima": "16"}},
}

# BOSS 曲：游戏数据在 condition/boss/musicXXXX/ 下，通过 songId 反推所属门。
BOSS_SONG_TO_GATE = {
    2838: "origin",
    2846: "air",
    2858: "star",
    2869: "amazon",
    2880: "crystal",
    2891: "paradise",
    2919: "new",
    2938: "sun",
    2954: "luminous",
    2966: "verse",
    2967: "xverse",      # YOUNITHM，同时是 RE:VERSE 的 BOSS
    2999: "universe",
}
# 同一个 BOSS 被多个门共用
BOSS_SHARED = {2967: ["xverse", "reverse"]}

# 全部门通关后的奖励乐曲（单独一页，不参与解锁条件）
REWARD_SONG_ID = 3000     # Linked Tune
REWARD_GATE_ID = "reward"

# 段位课程目录
CLASS_DIR = CONDITION / "class"
CLASS_COURSE_DIR = CLASS_DIR / "course"
CLASS_MUSIC_DIR = CLASS_DIR / "music"
CLASS_RANDOM_COVER = CLASS_DIR / "random" / "cover.png"          # 「?」图
CLASS_RANGE_COVER = CLASS_DIR / "random in range" / "cover.png"  # 「!」图

# fromLevel 的内部 ID -> 真实难度显示。
#
# 这个映射是**验证过的**，不是猜的：组曲「カオス Set」的随机槽 fromLevel = ID_19，
# 而同一组曲的固定曲 混沌を越えし我らが神聖なる調律主を讃えよ(id407) 在本地
# Music.xml 里是 ADVANCED Lv10 —— 两处吻合，所以 ID_19 = Lv10。
# 其余按 1 递增，'.0' 显示成整数、'.5' 显示成 'x+'（游戏内写法）。
LEVEL_ID_BASE = 19          # ID_19 对应 Lv10
LEVEL_ID_BASE_DIFFICULTY = 10

# 判定色（用户提供）
JUDGES = {
    "JUSTICE":          {"damage": -5,  "color": "#FF6A00"},
    "ATTACK":           {"damage": -10, "color": "#00FF00"},
    "MISS":             {"damage": -20, "color": "#000000"},
    "JUSTICE_CRITICAL": {"damage": -1,  "color": "#F6E80D"},
}

# 亚服/国服 Link GAUGE 数值（等级 -> 最低难度 / 生命 / 用到的判定）
LINK_LEVEL_TABLE = [
    (5, "MASTER", 300,  ["JUSTICE", "ATTACK", "MISS"]),
    (4, "MASTER", 1000, ["JUSTICE", "ATTACK", "MISS"]),
    (3, "MASTER", 2000, ["JUSTICE", "ATTACK", "MISS"]),
    (2, "EXPERT", 3000, ["JUSTICE", "ATTACK", "MISS"]),
    (1, "BASIC",  3000, ["JUSTICE", "ATTACK", "MISS"]),
]

# 说明：段位（CLASS）的配色与显示名不再写在这里。
# 段位数据由 tools/gen_classes.py 直接解析 condition/class/course/*/Course.xml 生成
# data/classes.json（含 color 字段），build.py 只负责把 class/music 里的曲目登记进 meta 表。
# 早期版本的 build_classes_placeholder() 已经删除——它会在 Course.xml 缺失时
# 用假数据填满 classes.json，导致「看起来有数据其实是占位」的假象。

warnings: list[str] = []
meta: dict[str, dict] = {}


def warn(msg: str) -> None:
    warnings.append(msg)
    print(f"  [warn] {msg}")


# ---------------------------------------------------------------- 工具

def read_text(p: Path) -> str:
    return p.read_text(encoding="utf-8-sig").strip()


def gate_dirs() -> list[tuple[int, str, Path]]:
    out = []
    for d in CONDITION.iterdir():
        if not d.is_dir():
            continue
        m = re.match(r"^(\d+)[-_](.+)$", d.name)
        if m:
            out.append((int(m.group(1)), d.name, d))
    return sorted(out)


def parse_music(xml_path: Path) -> dict:
    root = ET.parse(xml_path).getroot()
    name_el = root.find("name")
    artist_el = root.find("artistName")
    genre_el = root.find("genreNames/list/StringID")
    works_el = root.find("worksName")
    return {
        "id": int(name_el.find("id").text),
        "title": (name_el.find("str").text or "").strip(),
        "artist": (artist_el.find("str").text or "").strip() if artist_el is not None else "",
        "genre": (genre_el.find("str").text or "").strip() if genre_el is not None else "",
        "works": (works_el.find("str").text or "").strip() if works_el is not None else "",
        "levels": parse_fumen_levels(root),
        "hasUltima": (root.findtext("enableUltima") or "false").strip() == "true",
    }


# 难度等级显示：level=14 + levelDecimal=50 -> "14.5"
LEVEL_KEYS = ["basic", "advanced", "expert", "master", "ultima"]


def level_str(level_text: str | None, decimal_text: str | None) -> str:
    lv = (level_text or "0").strip()
    try:
        ld = int((decimal_text or "0").strip())
    except ValueError:
        ld = 0
    if ld <= 0:
        return lv
    # 数据里是「小数位 × 10」：50 -> .5、60 -> .6、12 -> .2、8 -> .8
    return f"{lv}.{ld % 10 if ld % 10 else ld // 10}"


def parse_fumen_levels(root: ET.Element) -> dict:
    """读出各难度的显示等级（含小数），只返回 enable=true 的。"""
    out: dict[str, str] = {}
    for f in root.findall("fumens/MusicFumenData"):
        t = (f.findtext("type/str") or "").strip().lower()
        if t not in LEVEL_KEYS:
            continue
        if (f.findtext("enable") or "false").strip() != "true":
            continue
        out[t] = level_str(f.findtext("level"), f.findtext("levelDecimal"))
    return out


def build_boss_map() -> dict[str, dict]:
    """解析 condition/boss/ 下的 BOSS 曲，返回 {门 id: boss 对象}。

    BOSS 曲同时登记进 meta（这样曲绘和名字统一走一套），
    并在门对象里内嵌完整信息，避免 app 加载时还要回查。
    """
    boss_dir = CONDITION / "boss"
    out: dict[str, dict] = {}
    if not boss_dir.exists():
        warn("找不到 condition/boss/，BOSS 信息只能靠兜底表")
        return out

    for d in sorted(p for p in boss_dir.iterdir() if p.is_dir()):
        xml = d / "Music.xml"
        if not xml.exists():
            continue
        info = parse_music(xml)
        sid = info["id"]
        gate_ids = BOSS_SHARED.get(sid) or (
            [BOSS_SONG_TO_GATE[sid]] if sid in BOSS_SONG_TO_GATE else []
        )
        if sid == REWARD_SONG_ID:
            gate_ids = [REWARD_GATE_ID]     # 奖励乐曲不挂在任何门上，但要登记进 meta
        if not gate_ids:
            warn(f"BOSS 曲 {sid} {info['title']} 未映射到任何门，已跳过")
            continue

        # 登记曲绘（转换阶段会填上真实路径）
        key = f"music:{sid}"
        meta.setdefault(key, {
            "type": "music",
            "id": sid,
            "title": info["title"],
            "artist": info["artist"],
            "genre": info["genre"],
            "works": info["works"],
            "image": f"assets/img/music/{sid}/jacket.{IMG_EXT}",
        })
        # 难度信息一律以 boss 目录的 Music.xml 为准（最完整，含小数）
        meta[key]["levels"] = info["levels"]
        meta[key]["hasUltima"] = info["hasUltima"]

        boss_obj = {
            "linkId": key,
            "title": info["title"],
            "artist": info["artist"],
            "levels": info["levels"],
            "hasUltima": info["hasUltima"],
        }
        for gid in gate_ids:
            out[gid] = boss_obj

    return out


def add_music(xml_path: Path, gate: str) -> int:
    """把一首曲目加入 meta 表，返回 songId。

    图片路径**固定按曲目 id 推导**为 `assets/img/music/<id>/jacket.<IMG_EXT>`，
    因为转换阶段（convert_one_dds）会往那里写。
    """
    info = parse_music(xml_path)
    sid = info["id"]
    key = f"music:{sid}"
    if key not in meta:
        meta[key] = {
            "type": "music",
            "id": sid,
            "title": info["title"],
            "artist": info["artist"],
            "genre": info["genre"],
            "works": info["works"],
            "image": f"assets/img/music/{sid}/jacket.{IMG_EXT}",
        }
    return sid


def collect_class_music() -> list[int]:
    """把 condition/class/music 下所有曲目登记进 meta。

    为什么必须单独收：
        这批曲目（76 首）是**段位组曲**用到的，不属于任何「门」，
        之前 build.py 只扫门的目录和 boss/，所以它们一直没进 app，
        段位页面里这些曲子会全部显示「图片缺失」。

    注意曲绘文件名不能从目录名推：
        WE 谱面目录用**曲目 id**（music8198），但里面的图是 `CHU_UI_Jacket_0889.dds`
        —— 889 才是原曲 id（8198 是它的 WORLD'S END 谱面）。
        所以这里读 `jaketFile` 声明，记下来给 convert_images 用。
    """
    if not CLASS_MUSIC_DIR.exists():
        warn(f"找不到 {CLASS_MUSIC_DIR}，段位曲目不会进 meta")
        return []

    ids: list[int] = []
    for d in sorted(p for p in CLASS_MUSIC_DIR.iterdir() if p.is_dir()):
        xml = d / "Music.xml"
        if not xml.exists():
            continue
        ids.append(add_music(xml, "class"))
    return ids


def avatar_slot(title: str) -> str:
    if "の服" in title:
        return "wear"
    if "の頭" in title:
        return "head"
    if "ランドセル" in title:
        return "back"
    return "other"


def add_manual_item(key: str, itype: str, iid: int, title: str, subtitle: str,
                    image: str | None, **extra) -> str:
    k = f"{itype}:{iid}"
    if k not in meta:
        entry = {"type": itype, "id": iid, "title": title, "subtitle": subtitle, "image": image}
        entry.update(extra)
        meta[k] = entry
    return k


def ref(itype: str, iid: int) -> str:
    return f"{itype}:{iid}"


# ---------------------------------------------------------------- 各门数据

def collect_songs(gate_path: Path, gate_id: str) -> list[str]:
    """把门目录下所有 music*/Music.xml 收集为 linkId 列表（按曲 id 排序）。"""
    ids: set[int] = set()
    for sub in sorted(p for p in gate_path.iterdir() if p.is_dir()):
        for xml in sorted(sub.rglob("Music.xml")):
            ids.add(add_music(xml, gate_id))
    return [ref("music", i) for i in sorted(ids)]


# 国服正式解锁条件描述。
# 你的 condition/*/条件.txt 是速记（有时会误导，例如 SUN 写的「所有乐曲」实际只要 5 首），
# 这里用你确认过的国服事实重写。官方原文会另存为 conditionOriginal。
CONDITION_TEXT = {
    "origin": "2026-09-10 更新后，把这 30 首各打一次（难度与分数不限）",
    "air": "获得一个段位缎带。即把任一 CLASS（I / II / III / IV / V / ∞）内的所有组曲通关一遍（Extra 除外）",
    "star": "从地图 VERSE ep.STAR 获得角色「観音寺 にこる／Mermaid♡Moment」，并升到 RANK 15",
    "amazon": "把 Climax 和 Killing Rhythm 加入收藏，再从收藏文件夹中各打一次",
    "crystal": "国服解锁条件未知（日服需队伍功能，国服无此功能），请在机台确认后手动标记",
    "paradise": "五位曲师（光吉猛修 / 穴山大輔 / Kai / 水野健治 / 大国奏音）各打一首他们作曲的乐曲，"
                "即最少需要打 5 首（每位曲师一首）",
    "new": "更新后从 Mission 获得 3 件「淀川 沙音瑠」服装（服 / 頭 / ランドセル），穿上后打一次",
    "sun": "2026-09-10 更新后，把这 5 首各打一次（难度与分数不限）",
    "luminous": "当期 Mission 收集 100 个气球获得称号 MISSION still in progress，"
                "下局解锁隐藏地图 Secret AREA: LUMINOUS 并跑完",
    "verse": "从「推荐乐曲文件夹」中游玩 メッちゅう殴打 / Theatore Creatore / Crossmythos Rhapsodia 各一次",
    "xverse": "通关前面 10 个门（ORIGIN～VERSE）后自动解锁",
    "reverse": "通关 X-VERSE 后解锁地图 Secret AREA: MUSIC GAME EX。卡内每首乐曲都要通关课题曲才能获得，"
               "所以跑完地图拿全 11 首即等于全部游玩过一遍",
    "universe": "通关 RE:VERSE 时剩余血量 ≥ 指定血量（指定值按日期缓和）",
    "reward": "通关全部 13 个门后自动显示",
}


def build_gates(boss_map: dict[str, dict]) -> list[dict]:
    gates: list[dict] = []

    # ---------------- Stage 1 ----------------
    for order, dirname, gpath in gate_dirs():
        gid = re.sub(r"^\d+-", "", dirname).replace("：", "").replace(" ", "")
        # 目录名 -> 内部 id
        id_map = {
            "origin": "origin", "air": "air", "star": "star", "amazon": "amazon",
            "crystal": "crystal", "paradise": "paradise", "new": "new", "sun": "sun",
            "luminous": "luminous", "verse": "verse",
            "x-verse": "xverse", "re：verse": "reverse", "re:verse": "reverse",
            "universe": "universe",
        }
        gid = id_map.get(gid, gid)

        cond_txt = read_text(gpath / "条件.txt") if (gpath / "条件.txt").exists() else ""
        date_txt = read_text(gpath / "日期.txt") if (gpath / "日期.txt").exists() else ""
        is_open = date_txt.replace(" ", "") == RELEASE_OPEN_RAW

        stage = 1 if gid not in ("xverse", "reverse", "universe") else 2
        name_zh = {
            "origin": "Linked GATE ORIGIN", "air": "Linked GATE AIR",
            "star": "Linked GATE STAR", "amazon": "Linked GATE AMAZON",
            "crystal": "Linked GATE CRYSTAL", "paradise": "Linked GATE PARADISE",
            "new": "Linked GATE NEW", "sun": "Linked GATE SUN",
            "luminous": "Linked GATE LUMINOUS", "verse": "Linked GATE VERSE",
            "xverse": "Linked GATE X-VERSE", "reverse": "Linked GATE RE:VERSE",
            "universe": "Linked GATE UNIVERSE",
        }[gid]

        gate: dict = {
            "id": gid,
            "order": order,
            "stage": stage,
            "name": name_zh,
            "boss": boss_map.get(gid) or BOSSES.get(gid),
            "releaseDate": RELEASE_OPEN if is_open else None,
            "releaseStatus": "open" if is_open else "notYetOpen",
            "conditionSource": "official",
            "releaseNote": "",
            "conditionText": CONDITION_TEXT.get(gid, cond_txt),
            "conditionOriginal": cond_txt,
            "prerequisites": [],
        }

        # ---- 按门设置 tracking 与 requirement ----
        if gid == "origin":
            gate["tracking"] = "songs"
            gate["requirement"] = {"type": "playAll", "songKeys": collect_songs(gpath, gid)}

        elif gid == "amazon":
            gate["tracking"] = "songs"
            gate["requirement"] = {"type": "playAll", "songKeys": collect_songs(gpath, gid)}

        elif gid == "sun":
            gate["tracking"] = "songs"
            gate["requirement"] = {"type": "playAll", "songKeys": collect_songs(gpath, gid)}

        elif gid == "verse":
            gate["tracking"] = "songs"
            gate["requirement"] = {"type": "playAll", "songKeys": collect_songs(gpath, gid)}

        elif gid == "reverse":
            gate["tracking"] = "songs"
            gate["requirement"] = {"type": "playAll", "songKeys": collect_songs(gpath, gid)}
            gate["prerequisites"] = ["xverse"]
            gate["unresolved"] = ("国服条件原文为「完成地图，获得地图内所有歌曲即可」，"
                                  "与日服「play all」不同。待用户确认是「需游玩」还是「拿到歌即可」。")

        elif gid == "paradise":
            gate["tracking"] = "songs"
            groups = []
            for artist_dir in sorted(p for p in gpath.iterdir() if p.is_dir()):
                ids = collect_songs(artist_dir, gid)
                if ids:
                    groups.append({"key": artist_dir.name, "songKeys": ids})
            gate["requirement"] = {"type": "playAnyOfEach", "groups": groups}

        elif gid == "air":
            gate["tracking"] = "class"
            gate["requirement"] = {"type": "anyClassAllCourses", "dataFile": "data/classes.json"}
            gate["releaseNote"] = ""

        elif gid == "star":
            gate["tracking"] = "items"
            items = []
            for sub in sorted(p for p in gpath.iterdir() if p.is_dir()):
                cx = sub / "Chara.xml"
                if not cx.exists():
                    continue
                root = ET.parse(cx).getroot()
                cid = int(root.find("name/id").text)
                ctitle = (root.find("name/str").text or "").strip()
                works = (root.find("works/str").text or "").strip()
                has_img = any(sub.glob("*.dds"))
                if not has_img:
                    warn(f"角色 {ctitle} 没有图片资源（{sub.name} 只有 Chara.xml）")
                k = add_manual_item(f"chara:{cid}", "chara", cid, ctitle,
                                    "角色 · 需升到 RANK 15",
                                    f"assets/img/chara/{cid}/icon.{IMG_EXT}" if has_img else None,
                                    works=works)
                items.append(k)
            gate["requirement"] = {"type": "items", "itemKeys": items}

        elif gid == "new":
            gate["tracking"] = "items"
            items = []
            for sub in sorted(p for p in gpath.iterdir() if p.is_dir()):
                ax = sub / "AvatarAccessory.xml"
                if not ax.exists():
                    continue
                root = ET.parse(ax).getroot()
                aid = int(root.find("name/id").text)
                atitle = (root.find("name/str").text or "").strip()
                slot = avatar_slot(atitle)
                if slot == "other":
                    # 冰淇淋等非条件内条目，排除
                    print(f"  [skip] 排除 {atitle}（不在解锁条件内）")
                    continue
                k = add_manual_item(f"avatar:{aid}", "avatar", aid, atitle,
                                    {"wear": "服装 · ウェア", "head": "头饰 · ヘッド",
                                     "back": "背包 · バック"}[slot],
                                    f"assets/img/avatar/{aid}/icon.{IMG_EXT}",
                                    slot=slot)
                items.append(k)
            gate["requirement"] = {"type": "items", "itemKeys": items}

        elif gid == "luminous":
            gate["tracking"] = "items"
            items = []
            cm = gpath / "cmission0350" / "CMission.xml"
            if cm.exists():
                root = ET.parse(cm).getroot()
                cid = 350
                ctitle = (root.find("name/str").text or "").strip()
                k = add_manual_item(f"mission:{cid}", "mission", cid, ctitle,
                                    "Mission · 集 100 气球拿称号", None)
                items.append(k)
            mp = gpath / "map03020815" / "Map.xml"
            if mp.exists():
                root = ET.parse(mp).getroot()
                mid = 3020815
                mtitle = (root.find("name/str").text or "").strip()
                k = add_manual_item(f"map:{mid}", "map", mid, mtitle,
                                    "隐藏地图 · 跑完即可", None)
                items.append(k)
            gate["requirement"] = {"type": "items", "itemKeys": items}

        elif gid == "crystal":
            gate["tracking"] = "manual"
            gate["releaseNote"] = "国服无队伍功能，解锁条件未知，需在机台确认后手动标记"
            gate["requirement"] = {"type": "manualConfirm"}

        elif gid == "xverse":
            gate["tracking"] = "auto"
            gate["prerequisites"] = ["origin", "air", "star", "amazon", "crystal",
                                     "paradise", "new", "sun", "luminous", "verse"]
            gate["requirement"] = {"type": "clearAllPrev"}

        elif gid == "universe":
            gate["tracking"] = "universe"
            gate["prerequisites"] = ["reverse"]
            gate["requirement"] = {
                "type": "remainingHp",
                "requiredHp": None,
                "note": "通关 RE:VERSE 时剩余血量 ≥ 指定血量（按日期缓和）",
            }

        else:
            gate["tracking"] = "manual"
            gate["requirement"] = {"type": "manualConfirm"}

        gates.append(gate)

    # ---------------- 奖励乐曲（单独一页，不参与解锁条件） ----------------
    reward_key = f"music:{REWARD_SONG_ID}"
    if reward_key in meta:
        rm = meta[reward_key]
        gates.append({
            "id": REWARD_GATE_ID,
            "order": len(gates) + 1,
            "stage": 3,
            "name": "奖励乐曲",
            "kind": "reward",
            "boss": {
                "linkId": reward_key,
                "title": rm["title"],
                "artist": rm["artist"],
                "levels": rm.get("levels", {}),
                "hasUltima": rm.get("hasUltima", False),
            },
            "releaseDate": None,
            "releaseStatus": "locked",
            "conditionSource": "official",
            "releaseNote": "",
            "conditionText": CONDITION_TEXT["reward"],
            "conditionOriginal": "Linked Tune 为最后的奖励乐曲",
            "prerequisites": ["origin", "air", "star", "amazon", "crystal", "paradise",
                              "new", "sun", "luminous", "verse", "xverse", "reverse",
                              "universe"],
            "tracking": "auto",
            "requirement": {"type": "clearAllPrev"},
        })
    else:
        warn(f"奖励乐曲 music:{REWARD_SONG_ID} 不在 meta 中，未生成奖励页")

    return gates


# ---------------------------------------------------------------- linklevels

def build_linklevels() -> dict:
    """生成各门的 Link LEVEL 缓和表。

    关键点：**每个门有自己的开放日期和缓和周期，不能共用一份**。

    已知的只有 ORIGIN 与 AIR（你的 condition/*/日期.txt 写了 2026/9/10），
    所以：
      - 这两个门的 V 档日期 = 该门开放时间
      - 其余门尚未开放，releaseDate 为 null，缓和日期一律 null（不猜）
      - IV~I 档的缓和日期全部未知 —— 日服的周期（ORIGIN 的 V 档 2025/7/16、
        I 档 2025/8/14）比国服上线早一整年，照抄必然算错，所以留 null
    """
    # 门 id -> 该门开放时间（None = 未开放，日期未知）
    gate_open: dict[str, str | None] = {
        "origin": RELEASE_OPEN,
        "air": RELEASE_OPEN,
        "star": None,
        "amazon": None,
        "crystal": None,
        "paradise": None,
        "new": None,
        "sun": None,
        "luminous": None,
        "verse": None,
        "xverse": None,
        "reverse": None,
    }

    base_levels = []
    for lv, diff, life, judges in LINK_LEVEL_TABLE:
        base_levels.append({
            "level": lv,
            "label": str(lv),
            "from": None,               # 由下面按门填 V 档
            "minDifficulty": diff,
            "life": life,
            "judges": judges,
            "source": "user",           # 默认「未知」，V 档已知的会改成 official
        })

    gates: dict[str, dict] = {}
    for gid, opened in gate_open.items():
        levels = []
        for tpl in base_levels:
            t = dict(tpl)
            if t["level"] == 5 and opened:
                t["from"] = opened
                t["source"] = "official"
            levels.append(t)
        if opened:
            gates[gid] = {"levels": levels}
        else:
            gates[gid] = {
                "levels": levels,
                "note": "该门在国服尚未开放，开放日期与缓和周期都未公布，因此不填任何日期。",
            }

    # ---------------- UNIVERSE：剩余血量要求（多段，按日期缓和） ----------------
    #
    # 数值是占位。国服的具体血量门槛与缓和日期都还没公布，
    # 所以日期全部留 null，source 标 user —— UI 会显示「缓和日期未公布」。
    gates["universe"] = {
        "levels": [
            {"level": 3, "label": "∞（最严）", "from": None, "minDifficulty": "ULTIMA",
             "life": 2000, "judges": ["JUSTICE_CRITICAL", "JUSTICE", "ATTACK", "MISS"],
             "requiredHp": 1000, "source": "user"},
            {"level": 2, "label": "缓和 I", "from": None, "minDifficulty": "ULTIMA",
             "life": 2000, "judges": ["JUSTICE_CRITICAL", "JUSTICE", "ATTACK", "MISS"],
             "requiredHp": 600, "source": "user"},
            {"level": 1, "label": "缓和 II", "from": None, "minDifficulty": "MASTER",
             "life": 5000, "judges": ["JUSTICE", "ATTACK", "MISS"],
             "requiredHp": 300, "source": "user"},
            {"level": 0, "label": "缓和 III", "from": None, "minDifficulty": "EXPERT",
             "life": 5000, "judges": ["JUSTICE", "ATTACK", "MISS"],
             "requiredHp": 1, "source": "user"},
        ],
        "note": "解锁条件：通关 RE:VERSE 时剩余血量 ≥ 指定值。该指定值按日期缓和；"
                "当前血量门槛与缓和日期均为占位，待国服公布后更新。",
    }

    return {
        "schemaVersion": SCHEMA_VERSION,
        "dataVersion": DATA_VERSION,
        "region": "cn",
        "note": "国服缓和周期未完全公布。已知的填日期，未知的留 null（不猜）。"
                "每个门的开放日期与缓和周期各自独立，不共用。",
        "defaultLevel": 5,
        "judges": JUDGES,
        "gates": gates,
    }


# ---------------------------------------------------------------- 图片转换

def convert_images() -> None:
    try:
        import PIL  # noqa: F401
    except ImportError:
        warn("未安装 Pillow，跳过图片转换（pip install Pillow）")
        return

    targets: list[Path] = []

    # ① condition/<门>/... 下的所有 dds
    for gate_order, dirname, gpath in gate_dirs():
        targets += [p for p in gpath.rglob("*.dds") if p.is_file()]

    # ② condition/boss/<曲>/ 下的 dds
    boss_dir = CONDITION / "boss"
    if boss_dir.exists():
        targets += [p for p in boss_dir.rglob("*.dds") if p.is_file()]

    # ③ condition/class/music/<曲>/ 下的 dds（段位组曲用到的曲目）
    if CLASS_MUSIC_DIR.exists():
        targets += [p for p in CLASS_MUSIC_DIR.rglob("*.dds") if p.is_file()]

    # 门根目录下的 dds（例如 condition/3-star/CHU_UI_Character_2432_00_00.dds）
    for gate_order, dirname, gpath in gate_dirs():
        targets += [p for p in gpath.glob("*.dds") if p.is_file()]

    for dds in sorted(set(targets)):
        try:
            convert_one_dds(dds)
        except Exception as e:  # noqa: BLE001
            warn(f"转换失败 {dds}: {type(e).__name__}: {e}")


def song_id_of_dds_dir(folder: Path) -> int | None:
    """按 dds 所在目录里的 Music.xml 精确取 song_id。

    为什么不能按文件名反查：
        多首曲目可能共用同一张曲绘（例如几首曲目用同一张图），
        按文件名反查会串号，还会在 assets/img/music/ 下生成多余的 id 目录。
        读同目录的 Music.xml 才是唯一可靠的依据。
    """
    xml = folder / "Music.xml"
    if not xml.exists():
        return None
    try:
        sid = ET.parse(xml).getroot().findtext("name/id")
        return int(sid) if sid else None
    except (ET.ParseError, ValueError):
        return None


def convert_one_dds(dds: Path) -> None:
    from PIL import Image

    base = dds.stem

    # 角色立绘：CHU_UI_Character_2432_00_00.dds
    # 前 4 位是角色 id 的高位，补一位 0 得到完整 id（2432 -> 24320）。
    # 这里不靠猜：直接读同目录的 Chara.xml 拿真实 id。
    if re.match(r"^CHU_UI_Character_", base):
        # Chara.xml 可能和 dds 同目录，也可能在子目录里（例如
        # condition/3-star/CHU_UI_Character_....dds + condition/3-star/chara024320/Chara.xml）
        candidates = [dds.parent / "Chara.xml"]
        candidates += sorted(dds.parent.rglob("Chara.xml"))
        candidates += sorted(dds.parent.parent.rglob("Chara.xml")) if dds.parent.parent else []
        chara_xml = next((c for c in candidates if c.exists()), None)
        if chara_xml is None:
            warn(f"角色 dds 附近找不到 Chara.xml，无法确定 id：{dds}")
            return
        cid = int(ET.parse(chara_xml).getroot().findtext("name/id"))
        mkey = f"chara:{cid}"
        if mkey not in meta:
            warn(f"角色 dds 对应的 {mkey} 不在 meta 中：{dds}")
            return
        out_dir = IMG / "chara" / str(cid)
        out_dir.mkdir(parents=True, exist_ok=True)
        out_path = out_dir / f"image.{IMG_EXT}"
        if not out_path.exists():
            with Image.open(dds) as im:
                im.load()
                save_image(im.convert("RGBA"), out_path)
        meta[mkey]["image"] = f"assets/img/chara/{cid}/image.{IMG_EXT}"
        return

    m = re.match(r"^(?:CHU_UI_)?(Jacket|Avatar_Icon|Avatar_Tex)[_](\d+)$", base)
    if not m:
        warn(f"无法识别的 dds 命名：{dds}")
        return
    kind, raw = m.group(1), m.group(2)

    if kind == "Jacket":
        # 段位曲目的曲绘文件名**不一定等于曲目 id**：
        #   music8198（WE 谱面）里的图是 CHU_UI_Jacket_0889.dds，
        #   889 才是原曲 id。而 music8252 用的是 2162 的图……
        # 更麻烦的是**多首曲目可能共用同一张图**，所以不能按文件名反查
        # （会串号、生成多余目录）。这里按 dds 所在目录精确取 song_id。
        sid = song_id_of_dds_dir(dds.parent) or int(raw)
        out_dir = IMG / "music" / str(sid)
        out_name = f"jacket.{IMG_EXT}"
        mkey = f"music:{sid}"
    elif kind == "Avatar_Icon":
        aid = int(raw)
        out_dir = IMG / "avatar" / str(aid)
        out_name = f"icon.{IMG_EXT}"
        mkey = f"avatar:{aid}"
    else:
        aid = int(raw)
        out_dir = IMG / "avatar" / str(aid)
        out_name = f"tex.{IMG_EXT}"
        mkey = f"avatar:{aid}"

    # 只转换 meta 表里真正会用到的资源。
    # 被排除的条目（例如 NEW 门里不在条件内的「アイス」）不生成目录和图，避免孤儿资源进 APK。
    if mkey not in meta:
        return

    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / out_name

    if out_path.exists():
        return  # 同名已转换过（去重）

    with Image.open(dds) as im:
        im.load()
        save_image(im.convert("RGBA"), out_path)

    meta[mkey]["image"] = f"assets/img/{out_dir.relative_to(IMG).as_posix()}/{out_name}"


def write_meta_sidecars() -> None:
    """每个资源文件夹写一个 meta.json（不用原来的 XML）。"""
    by_dir: dict[Path, dict] = {}
    for key, entry in meta.items():
        if not entry.get("image"):
            continue
        d = ROOT / entry["image"]
        by_dir.setdefault(d.parent, {})[d.name] = {
            k: v for k, v in entry.items() if k not in ("image", "subtitle")
        }

    for d, files in by_dir.items():
        d.mkdir(parents=True, exist_ok=True)
        (d / "meta.json").write_text(
            json.dumps(files, ensure_ascii=False, indent=2), encoding="utf-8"
        )

    # 没有图片的条目也要有 meta.json（例如缺图的角色）
    for key, entry in meta.items():
        if entry.get("type") == "chara" and not entry.get("image"):
            d = IMG / "chara" / str(entry["id"])
            d.mkdir(parents=True, exist_ok=True)
            (d / "meta.json").write_text(
                json.dumps({k: v for k, v in entry.items() if k not in ("image", "subtitle")},
                           ensure_ascii=False, indent=2),
                encoding="utf-8",
            )


# ---------------------------------------------------------------- main

def main() -> int:
    if not CONDITION.exists():
        print(f"找不到 {CONDITION}", file=sys.stderr)
        return 1

    DATA.mkdir(parents=True, exist_ok=True)
    IMG.mkdir(parents=True, exist_ok=True)

    print("== 解析 BOSS 曲 ==")
    boss_map = build_boss_map()
    print(f"  解析到 {len(boss_map)} 个门的 BOSS")

    print("\n== 解析门与曲目 ==")
    gates = build_gates(boss_map)

    print("\n== 解析段位曲目 ==")
    class_ids = collect_class_music()
    print(f"  段位曲目 {len(class_ids)} 首")

    print("\n== 转换图片 ==")
    convert_images()

    print("\n== 写 meta.json 侧车文件 ==")
    write_meta_sidecars()

    print("\n== 写 data/*.json ==")
    meta_doc = {
        "schemaVersion": SCHEMA_VERSION,
        "dataVersion": DATA_VERSION,
        "region": "cn",
        "note": "全局条目元数据。gates.json / classes.json 通过 linkId 引用这里。",
        "entries": meta,
    }
    gates_doc = {
        "schemaVersion": SCHEMA_VERSION,
        "dataVersion": DATA_VERSION,
        "region": "cn",
        "gameVersion": "中二节奏 2027 (CN1.40)",
        "updatedAt": "2026-09-11",
        "gates": gates,
    }
    (DATA / "gates.json").write_text(
        json.dumps(gates_doc, ensure_ascii=False, indent=2), encoding="utf-8")
    (DATA / "meta.json").write_text(
        json.dumps(meta_doc, ensure_ascii=False, indent=2), encoding="utf-8")
    (DATA / "linklevels.json").write_text(
        json.dumps(build_linklevels(), ensure_ascii=False, indent=2), encoding="utf-8")
    # ---- 段位课程（classes.json）----
    #
    # 段位数据在 condition/class/ 下，格式和门不同（Course.xml），
    # 所以由 tools/gen_classes.py 独立处理，这里调用它，
    # 保证 build.py 一条命令就能全量重建。
    print("\n== 生成段位课程（condition/class → classes.json）==")
    if CLASS_COURSE_DIR.exists():
        try:
            import subprocess
            gen = ROOT / "tools" / "gen_classes.py"
            r = subprocess.run([sys.executable, str(gen)], capture_output=True, text=True,
                               encoding="utf-8")
            print(r.stdout.strip() if r.stdout else "")
            if r.returncode != 0:
                warn("gen_classes.py 执行失败，classes.json 可能不完整")
                if r.stderr:
                    print(r.stderr[-800:])
        except Exception as e:  # noqa: BLE001
            warn(f"无法调用 gen_classes.py：{e}")
    else:
        warn(f"找不到 {CLASS_COURSE_DIR}，跳过段位课程生成")

    # ---- 重新生成 pubspec 的资源列表 ----
    #
    # 必须做，否则新增曲目后它的曲绘不会被打进 APK。
    # Flutter 的 assets 声明不递归子目录，所以 pubspec 里是逐文件列表。
    print("\n== 重新生成 pubspec 的资源列表 ==")
    try:
        import subprocess
        gen = ROOT / "tools" / "gen_asset_list.py"
        r = subprocess.run([sys.executable, str(gen)], capture_output=True, text=True, encoding="utf-8")
        print("  " + (r.stdout or r.stderr).strip())
        if r.returncode != 0:
            warn("gen_asset_list.py 执行失败，pubspec 的资源列表可能已过期")
    except Exception as e:  # noqa: BLE001
        warn(f"无法调用 gen_asset_list.py：{e}")

    # ---- 汇总 ----
    print("\n== 汇总 ==")
    print(f"门数：{len(gates)}")
    for g in gates:
        r = g.get("requirement", {})
        n = ""
        if r.get("type") == "playAll":
            n = f"{len(r['songKeys'])} 首"
        elif r.get("type") == "playAnyOfEach":
            n = f"{len(r['groups'])} 组 / {sum(len(x['songKeys']) for x in r['groups'])} 首"
        elif r.get("type") == "items":
            n = f"{len(r['itemKeys'])} 项"
        print(f"  {g['order']:>2}. {g['id']:<10} {g['tracking']:<9} "
              f"{'已开放' if g['releaseStatus'] == 'open' else '未更新':<6} {n}")

    print(f"\nmeta 条目：{len(meta)}")
    for t in ("music", "chara", "avatar", "mission", "map"):
        c = sum(1 for v in meta.values() if v["type"] == t)
        if c:
            print(f"  {t:<10} {c}")

    imgs = list(IMG.rglob(f"*.{IMG_EXT}"))
    size = sum(p.stat().st_size for p in imgs)
    print(f"\n{IMG_EXT.upper()}：{len(imgs)} 个，合计 {size / 1024 / 1024:.2f} MB")

    if warnings:
        print(f"\n⚠️ {len(warnings)} 条警告：")
        for w in warnings:
            print(f"  - {w}")
    return 0


# 这个 __name__ 判断不是可有可无的：gen_classes.py 会 `from build import DATA_VERSION`，
# 如果没有它，那次 import 会把 build.py 整个 main() 再跑一遍（还会递归调用 gen_classes）。
if __name__ == "__main__":
    raise SystemExit(main())
