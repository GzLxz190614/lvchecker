#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把 probe_lxns_collections.ps1 抓到的响应整理成人能看的报告。

设计要点：
  * **只隐去身份字段**（好友码 / 昵称 / QQ / 头像 URL）。
    上一版 probe_lxns_raw.py 把 class_emblem / character / trophy 也隐去了，
    而这次要看的恰好就是它们 —— 隐去了等于白跑一趟。
  * 对每个响应先报 HTTP 状态码，再报业务 code/message。
    这两种信息要分开看：404 是「路径不存在」，业务 message 才是「没权限 / ID 不对」。
  * class_emblem 单独展开成 JSON 打印，因为它是 AIR 门的关键，值本身不含隐私。

用法：
    python tools/probe_lxns_report.py .probe/manifest.json
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

# 只隐去这些。游戏进度类字段（class_emblem / character / trophy / name_plate /
# map_icon / currency ...）**必须保留** —— 它们正是本次探查的目标。
#
# 注意 name 要分场合：Player.name 是玩家昵称（该隐），
# Collection.name 是收藏品/角色的名字（该留）。所以这里不按裸键名隐去，
# 而是在 analyze_player 里单独处理玩家昵称。
PRIVATE = {"friend_code", "qq", "icon_url"}

# 玩家昵称：只在 Player 这一层隐去
PLAYER_PRIVATE = PRIVATE | {"name"}


def mask(key: str, value, private: set = PRIVATE):
    if key in private:
        return "<已隐去（身份信息）>"
    return value


def brief(value, limit: int = 160):
    try:
        text = json.dumps(value, ensure_ascii=False)
    except Exception:  # noqa: BLE001
        text = repr(value)
    if len(text) > limit:
        text = text[:limit] + f"…（共 {len(text)} 字）"
    return text


def show_object(obj: dict, indent: str = "    ", limit: int = 160) -> None:
    for k, v in obj.items():
        v = mask(k, v)
        if isinstance(v, (dict, list)):
            n = len(v)
            print(f"{indent}{k:26} = {type(v).__name__}({n}) {brief(v, limit)}")
        else:
            print(f"{indent}{k:26} = {v!r}")


def analyze_player(doc: dict) -> None:
    """玩家信息：专门盯 class_emblem，并列出所有和装扮可能相关的字段。"""
    data = doc.get("data")
    if not isinstance(data, dict):
        return

    print()
    print("  ── 玩家信息重点字段 ──")

    emblem = data.get("class_emblem")
    if emblem is None:
        print("  ✗ 没有 class_emblem 字段 —— AIR 门无法用这个判定")
    else:
        print(f"  ★ class_emblem = {brief(emblem, 400)}")
        if isinstance(emblem, dict):
            base = emblem.get("base")
            medal = emblem.get("medal")
            print(f"      base  = {base!r}   （缎带：通关该组别全部课题组）")
            print(f"      medal = {medal!r}   （勋章：通关任意一组）")
            if base in (0, None):
                print("      → base 为 0：要么你没拿缎带，要么它是布尔量。")
                print("        要区分这两种，需要对比一个【确定已拿缎带】的段位。")
            else:
                print("      → base 非 0：它是段位标识，不是布尔量。")

    for k in ("character", "trophy", "name_plate", "map_icon", "reborn_count",
              "over_power", "total_play_count", "rating", "level"):
        if k in data:
            v = mask(k, data[k], PLAYER_PRIVATE)
            if isinstance(v, dict):
                print(f"  · {k:18} = {brief(v, 220)}")
            else:
                print(f"  · {k:18} = {v!r}")

    # 装扮：文档里没有对应 collection_type，但也许藏在别处
    avatarish = [k for k in data
                 if any(w in k.lower() for w in ("avatar", "wear", "cloth", "dress", "dressup"))]
    if avatarish:
        print(f"  ★ 疑似装扮相关字段：{avatarish}")
        for k in avatarish:
            print(f"      {k} = {brief(mask(k, data[k]), 300)}")
    else:
        print("  ✗ 玩家信息里没有任何疑似装扮字段")


def analyze_collection(doc: dict, name: str) -> None:
    """Collection 响应：看 level / completed，这是角色 RANK 的答案。"""
    data = doc.get("data")
    if not isinstance(data, dict):
        return
    print()
    print("  ── Collection 字段 ──")
    show_object(data, limit=200)

    if "level" in data:
        lv = data["level"]
        print()
        if lv is None:
            print("  △ level = null —— 文档说「值可空，仅玩家角色」，"
                  "说明这个收藏品不是角色，或你还没有它。")
        else:
            print(f"  ★ level = {lv}  ← 角色 RANK，STAR 门要的是 15")
    else:
        print()
        print("  ✗ 没有 level 字段 —— 文档说只有玩家角色才有")


def load_json(path: Path):
    """读 JSON 并容忍 BOM。

    PowerShell 5.1 的 `Out-File -Encoding utf8` 会写 BOM，而 json.loads 遇到
    开头的 \\ufeff 会直接抛 JSONDecodeError。这里统一剥掉，免得换个 PowerShell
    版本就报一个看不懂的错。
    """
    text = path.read_text(encoding="utf-8", errors="replace")
    return json.loads(text.lstrip("\ufeff").strip())


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1

    manifest_path = Path(sys.argv[1])
    if not manifest_path.exists():
        print(f"找不到清单文件：{manifest_path}")
        return 1

    manifest = load_json(manifest_path)
    if isinstance(manifest, dict):
        manifest = [manifest]

    # 先把每个响应的数据读出来
    loaded = []
    for entry in manifest:
        path = Path(entry.get("File") or "")
        doc = None
        note = ""
        if not path.exists():
            note = "没有响应文件"
        else:
            text = path.read_text(encoding="utf-8", errors="replace").strip()
            if not text:
                note = "响应为空"
            else:
                try:
                    doc = json.loads(text.lstrip("\ufeff").strip())
                except Exception as e:  # noqa: BLE001
                    note = f"不是 JSON：{e}"
        loaded.append((entry, doc, note))

    # ---- 第一部分：一张总表，先看哪些路径通了 ----
    print()
    print("=" * 78)
    print("总表（★ = 返回了 data）")
    print("=" * 78)
    print(f"  {'分组':<12} {'http':>5} {'字节':>9}  {'路径':<40} 结果")
    print("  " + "-" * 74)
    for entry, doc, note in loaded:
        path = entry.get("Path", "")
        short = path.replace("https://maimai.lxns.net/api/v0", "")
        http = entry.get("Http", "?")
        size = entry.get("Bytes", 0)

        if note:
            verdict = f"✗ {note}"
        elif not isinstance(doc, dict):
            verdict = "✗ 顶层不是对象"
        elif doc.get("data") is None:
            verdict = f"✗ 无 data（message={doc.get('message')!r}）"
        else:
            verdict = "★ 有 data"

        print(f"  {entry.get('Group',''):<12} {http:>5} {size:>9}  {short:<40} {verdict}")

    # ---- 第二部分：逐个细看 ----
    for entry, doc, note in loaded:
        print()
        print("=" * 78)
        print(f"{entry.get('Group','')} / {entry.get('Name','')}")
        print(f"  {entry.get('Path','')}")
        print(f"  http={entry.get('Http','?')}  bytes={entry.get('Bytes',0)}")
        print("=" * 78)

        if note:
            print(f"  ✗ {note}")
            continue
        if not isinstance(doc, dict):
            print(f"  ✗ 顶层是 {type(doc).__name__}，不是对象")
            continue

        print(f"  success={doc.get('success')!r}  code={doc.get('code')!r}  "
              f"message={doc.get('message')!r}")

        if doc.get("data") is None:
            print("  → data 为 null。看上面的 message："
                  "若提到权限/密钥，说明个人密钥打不了这个接口；"
                  "若提到不存在/无效，说明路径或 ID 不对。")
            continue

        name = str(entry.get("Name", ""))
        if "player" in name and "scores" not in name:
            analyze_player(doc)
        elif "character" in name or "wear" in name or "avatar" in name or "icon" in name:
            analyze_collection(doc, name)
        else:
            data = doc["data"]
            print(f"  data 类型：{type(data).__name__}")
            if isinstance(data, dict):
                show_object(data)

    # ---- 第三部分：结论 ----
    print()
    print("=" * 78)
    print("结论")
    print("=" * 78)

    def find(name_part: str):
        for entry, doc, note in loaded:
            if name_part in entry.get("Name", "") and isinstance(doc, dict) \
                    and doc.get("data") is not None:
                return doc["data"]
        return None

    player = find("player")
    if player is None:
        print("  ? 玩家信息没拿到 —— 下面的结论都无从谈起")
    else:
        emb = player.get("class_emblem")
        if isinstance(emb, dict):
            print(f"  AIR 门（段位缎带）：class_emblem = {brief(emb, 120)}")
            print("      → 接口能拿到。但 base 具体含义要靠上面的值判断。")
        else:
            print(f"  AIR 门（段位缎带）：✗ 拿不到（class_emblem = {emb!r}）")

    char = find("character")
    if char is not None:
        print(f"  STAR 门（角色 RANK 15）：level = {char.get('level')!r}")
    else:
        print("  STAR 门（角色 RANK 15）：✗ character 接口没返回 data")

    wear_ok = any("wear" in e.get("Name", "") and isinstance(d, dict)
                  and d.get("data") is not None for e, d, _ in loaded)
    avatar_ok = any("avatar" in e.get("Name", "") and isinstance(d, dict)
                    and d.get("data") is not None for e, d, _ in loaded)
    if wear_ok or avatar_ok:
        print("  NEW 门（装扮）：★ 居然能拿到 —— 见上面具体是哪个路径")
    else:
        print("  NEW 门（装扮）：✗ 所有猜法都没返回 data，接口层面拿不到")
        print("      （这就把「文档没写」升级成了「实测不行」）")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
