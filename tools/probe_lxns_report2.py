#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
第二轮探针的报告器：收藏品端点。

和第一轮 probe_lxns_report.py 的关键区别 —— 第一轮把「404」一律当成
「拿不到」，这是错的。这里必须把三种失败**分开**：

    raw 404 ("404 page not found")  路由压根没匹配 -> 路径写错了，要改路径
    业务 JSON {"success":false,...}  路由通了，业务层拒绝 -> 路径对，是权限/ID 问题
    空 body                          服务器拒绝且不给 body（常见于网关层）

只有区分开才知道下一步该干嘛：改路径，还是放弃这条路。

用法：
    python tools/probe_lxns_report2.py .probe2/manifest.json
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

# 只隐去真正的身份字段。昵称在 Player 顶层单独处理（Collection.name 是物品名，要留）。
PRIVATE = {"friend_code", "qq", "icon_url"}


def load_json(path: Path):
    text = path.read_text(encoding="utf-8", errors="replace")
    return json.loads(text.lstrip("\ufeff").strip())


def brief(value, limit: int = 200) -> str:
    try:
        text = json.dumps(value, ensure_ascii=False)
    except Exception:  # noqa: BLE001
        text = repr(value)
    if len(text) > limit:
        text = text[:limit] + f"…（共 {len(text)} 字）"
    return text


def classify(raw: str, doc):
    """把响应归到四类之一。这是整个报告的核心判断。"""
    if not raw:
        return "EMPTY", "空 body（服务器拒绝且不给 body）"
    if doc is None:
        if "page not found" in raw.lower():
            return "RAW404", "Go 原生 404 —— 路由未匹配，路径写错了"
        return "NOTJSON", f"不是 JSON：{raw[:80]!r}"
    if not isinstance(doc, dict):
        return "NOTOBJ", f"顶层是 {type(doc).__name__}"
    if doc.get("data") is None:
        return "BIZERR", f"业务错误 message={doc.get('message')!r} code={doc.get('code')!r}"
    return "OK", "★ 有 data"


def show_player(data: dict) -> None:
    print("  ── class_emblem（AIR 门的关键）──")
    emb = data.get("class_emblem")
    if emb is None:
        print("  ✗ 没有 class_emblem")
    else:
        print(f"  ★ class_emblem = {brief(emb, 300)}")
        if isinstance(emb, dict):
            print(f"      base  = {emb.get('base')!r}")
            print(f"      medal = {emb.get('medal')!r}")

    ch = data.get("character")
    print("  ── character（角色 RANK）──")
    if isinstance(ch, dict):
        print(f"  ★ {brief(ch, 300)}")
        print(f"      level = {ch.get('level')!r}   ← 证明这个字段带等级")
    else:
        print(f"  character = {ch!r}")

    # 还有哪些字段可能藏着装扮/段位
    others = {k: v for k, v in data.items()
              if k not in ("class_emblem", "character", "friend_code", "name", "qq")}
    print("  ── 其余字段 ──")
    for k, v in others.items():
        if isinstance(v, (dict, list)):
            print(f"    {k:24} = {brief(v, 190)}")
        else:
            print(f"    {k:24} = {v!r}")


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1

    mp = Path(sys.argv[1])
    if not mp.exists():
        print(f"找不到清单：{mp}")
        return 1

    manifest = load_json(mp)
    if isinstance(manifest, dict):
        manifest = [manifest]

    loaded = []
    for entry in manifest:
        p = Path(entry.get("File") or "")
        raw, doc = "", None
        if p.exists():
            raw = p.read_text(encoding="utf-8", errors="replace").strip()
            if raw:
                try:
                    doc = json.loads(raw.lstrip("\ufeff"))
                except Exception:  # noqa: BLE001
                    doc = None
        verdict, why = classify(raw, doc)
        loaded.append((entry, raw, doc, verdict, why))

    # ---- 总表 ----
    print()
    print("=" * 96)
    print("总表   OK=有数据 / BIZERR=路由通但被业务拒绝 / RAW404=路由未匹配 / EMPTY=空响应")
    print("=" * 96)
    print(f"  {'分组':<10} {'http':>5} {'字节':>8}  {'判定':<8} {'路径':<44} 说明")
    print("  " + "-" * 92)
    for entry, raw, doc, verdict, why in loaded:
        short = entry.get("Path", "").replace("https://maimai.lxns.net/api/v0", "")
        print(f"  {entry.get('Group',''):<10} {entry.get('Http','?'):>5} "
              f"{entry.get('Bytes',0):>8}  {verdict:<8} {short:<44} {why[:38]}")

    # ---- 明细 ----
    for entry, raw, doc, verdict, why in loaded:
        print()
        print("=" * 96)
        print(f"{entry.get('Group','')} / {entry.get('Name','')}")
        print(f"  http={entry.get('Http','?')}  {why}")
        print("=" * 96)

        if verdict == "OK" and isinstance(doc, dict):
            data = doc["data"]
            name = str(entry.get("Name", ""))
            if isinstance(data, dict) and "class_emblem" in data:
                show_player({k: v for k, v in data.items() if k not in PRIVATE})
            elif isinstance(data, list):
                print(f"  data 是列表，共 {len(data)} 项")
                if data and isinstance(data[0], dict):
                    print(f"  第一条字段（{len(data[0])} 个）：")
                    for k, v in data[0].items():
                        print(f"    {k:22} = {brief(v, 170)}")
                    # 列表里找我们关心的 ID
                    ids = [d.get("id") for d in data if isinstance(d, dict)]
                    for want in (24320, 14520, 6104401):
                        hit = [d for d in data if isinstance(d, dict) and d.get("id") == want]
                        if hit:
                            print(f"  ★ 列表里找到 id={want}: {brief(hit[0], 220)}")
            elif isinstance(data, dict):
                for k, v in data.items():
                    print(f"  {k:24} = {brief(v, 200)}")
            else:
                print(f"  data = {brief(data)}")
        elif verdict == "BIZERR":
            print("  → 路由是通的（返回了业务 JSON）。说明路径写法对，")
            print("    问题在权限或 ID，而不是路径。")
        elif verdict == "RAW404":
            print("  → 路由未匹配。这条路径不存在，需要换写法。")
        elif verdict == "EMPTY":
            print("  → 服务器拒绝且没给 body。看 http 状态码判断原因。")

    # ---- 结论 ----
    print()
    print("=" * 96)
    print("结论")
    print("=" * 96)

    # 用「精确名字」查，不要用子串匹配 ——
    # 子串匹配踩过坑：name 是 `character_list`（下划线）时匹配不到 `character/list`，
    # 结论会静默变成 None，看起来像「没跑到」，实际是查错了键。
    def verdict_of(group: str, name: str):
        for entry, raw, doc, verdict, why in loaded:
            if entry.get("Group") == group and entry.get("Name") == name:
                return verdict
        return "（没跑）"

    v = verdict_of("Q1 列表", "character/list")
    print(f"  Q1 收藏品路由: character/list -> {v}")
    if v == "OK":
        print("      ✓ 路由存在，且不需要密钥。上一轮的 404 是路径写错，不是接口不存在。")
    elif v == "RAW404":
        print("      ✗ 路由不存在 —— 文档写的端点在实际部署里没有。这条路封死。")

    v = verdict_of("Q1 对照", "zzznotatype/list")
    print(f"  Q1 对照(故意写错的类型) -> {v}")
    if v == "BIZERR":
        print("      ✓ 业务 JSON 错误 -> 路由通、类型在业务层校验。")
    elif v == "RAW404":
        print("      ✗ 也是 raw 404 -> 无法区分「路由不存在」和「类型非法」。")

    print(f"  Q1 对照(song/list 公开接口) -> {verdict_of('Q1 对照', 'song/list')}")

    print(f"  Q2 单个收藏品 character/24320 -> {verdict_of('Q2 单个', 'character/24320')}")
    print(f"  Q2 单个收藏品 character/14520 -> {verdict_of('Q2 单个', 'character/14520')}")

    q3 = [(e.get("Name"), verdict, why) for e, raw, doc, verdict, why in loaded
          if e.get("Group") == "Q3 玩家"]
    if not q3:
        print("  Q3 玩家端点: 跳过（没拿到好友码）")
    for nm, verdict, why in q3:
        print(f"  Q3 {nm} -> {verdict}   {why[:56]}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
