#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
段位探查的报告器：把 class_emblem 的取值和 classes.json 的段位表对照，算出它代表哪个 CLASS。

为什么要把这一步交给脚本：`base` 是 int，取值范围未知。可能的解释有
「0/1 布尔量」「段位序号」「段位 ID 的低位」等等。靠人眼比对容易得出
「看起来像」的结论，而这是要写进自动判定逻辑的东西，必须算清楚。

这里列出**所有**能和 base/medal 对上的解释，并明确标注哪些无法排除 ——
不能只报一个「最像的」答案。

用法：
    python tools/probe_lxns_class_report.py .probe3/manifest.json
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

# 只隐去真正的身份字段
PRIVATE = {"friend_code", "qq", "icon_url"}


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8").lstrip("\ufeff").strip())


def brief(v, limit: int = 200) -> str:
    try:
        t = json.dumps(v, ensure_ascii=False)
    except Exception:  # noqa: BLE001
        t = repr(v)
    return t if len(t) <= limit else t[:limit] + f"…（共 {len(t)} 字）"


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

    # ---- 读 classes.json，作为对照表 ----
    tiers = []
    cls_path = ROOT / "data" / "classes.json"
    if cls_path.exists():
        cls = load_json(cls_path)
        for c in cls.get("classes", []):
            tiers.append({
                "key": str(c.get("key")),
                "label": str(c.get("label")),
                "level": c.get("level"),
                "courses": len(c.get("courses", [])),
            })

    # ---- 逐个读响应 ----
    entries = []
    for e in manifest:
        p = Path(e.get("File") or "")
        doc, note = None, ""
        if not p.exists():
            note = "没有响应文件"
        else:
            raw = p.read_text(encoding="utf-8", errors="replace").strip()
            if not raw:
                note = "响应为空"
            elif "page not found" in raw.lower():
                note = "Go 原生 404 —— 路由未匹配"
            else:
                try:
                    doc = json.loads(raw.lstrip("\ufeff"))
                except Exception as ex:  # noqa: BLE001
                    note = f"不是 JSON：{ex}"
        entries.append((e, doc, note))

    print()
    print("=" * 84)
    print("响应总览")
    print("=" * 84)
    for e, doc, note in entries:
        short = (e.get("Path") or "").replace("https://maimai.lxns.net/api/v0", "")
        data = doc.get("data") if isinstance(doc, dict) else None
        if note:
            verdict = f"✗ {note}"
        elif data is None:
            verdict = f"✗ 无 data（message={doc.get('message')!r}）"
        else:
            verdict = "★ 有 data"
        print(f"  http={e.get('Http','?'):>4}  {short:<40} {verdict}")

    # ---- 核心：class_emblem ----
    player = None
    for e, doc, note in entries:
        if isinstance(doc, dict) and isinstance(doc.get("data"), dict) \
                and "class_emblem" in doc["data"]:
            player = doc["data"]
            break

    print()
    print("=" * 84)
    print("★ class_emblem（AIR 门的关键）")
    print("=" * 84)

    if player is None:
        print("  ✗ 没拿到任何含 class_emblem 的响应 —— 无法回答")
        return 1

    emb = player.get("class_emblem")
    print(f"  原始值: {brief(emb, 300)}")

    base = emb.get("base") if isinstance(emb, dict) else None
    medal = emb.get("medal") if isinstance(emb, dict) else None
    print(f"    base  = {base!r}")
    print(f"    medal = {medal!r}")

    # 第一轮的值做对比
    prev = None
    prev_path = ROOT / ".probe" / "01_player.json"
    if prev_path.exists():
        try:
            prev = load_json(prev_path).get("data", {}).get("class_emblem")
        except Exception:  # noqa: BLE001
            prev = None
    if prev is not None:
        print(f"  第一轮（通关前）的值: {brief(prev, 120)}")
        if prev == emb:
            print("  ⚠ 和通关前**完全一样** —— 说明这个字段没随缎带变化，")
            print("    要么它不表示缎带，要么同步没更新（去查分器网页刷新一下成绩再试）。")
        else:
            print("  ✓ 和通关前不同 —— 这个字段确实随缎带变化")

    # ---- 用 classes.json 反推 ----
    print()
    print("=" * 84)
    print("用 classes.json 反推 base 的含义")
    print("=" * 84)
    print("  data/classes.json 里的段位表（这是**我们**的编号，不一定等于游戏的）：")
    print(f"    {'CLASS':<6} {'label':<6} {'level':>6}  {'组曲数':>6}")
    for t in tiers:
        print(f"    {'CLASS ' + t['key']:<6} {t['label']:<6} {str(t['level']):>6}  {t['courses']:>6}")

    if base is None:
        print("  （base 读不出来，无法反推）")
        return 0

    print()
    print(f"  base = {base}")

    # 解释 1：布尔量
    print()
    print("  解释 1 —— 布尔量（0=没有缎带，1=有）？")
    if base == 0:
        print("    ✗ base 仍然是 0。但你已通关 AIR，所以「0/1 布尔量」")
        print("      也和「没拿到」冲突 —— 需要确认成绩同步了没有。")
    elif base == 1:
        print("    ○ 可能。但无法和「CLASS 编号恰好是 1」区分开 —— "
              "去机台通一个别的 CLASS 再看这个值变不变。")
    else:
        print(f"    ✗ base = {base} 超出 0/1，**不是布尔量**。")

    # 解释 2：等于我们 classes.json 里的 level
    print()
    print("  解释 2 —— 等于某个 CLASS 的 level 编号？")
    match_level = [t for t in tiers if t["level"] == base]
    if match_level:
        for t in match_level:
            print(f"    ○ 匹配 CLASS {t['key']}（level={t['level']}，{t['courses']} 组曲）")
        print("      ⚠ 注意：level=0 是 ∞、level=1 是 I。如果你通的是 I，")
        print("        那 base=1 同时符合「布尔量」和「CLASS I」两种解释。")
    else:
        print(f"    ✗ 没有任何 CLASS 的 level 等于 {base}")

    # 解释 3：序号（1..6）
    print()
    print("  解释 3 —— 段位序号（I=1, II=2, ..., V=5, ∞=6）？")
    order = {"I": 1, "II": 2, "III": 3, "IV": 4, "V": 5, "∞": 6}
    match_order = [k for k, v in order.items() if v == base]
    if match_order:
        for k in match_order:
            print(f"    ○ 匹配 CLASS {k}")
    else:
        print(f"    ✗ 没有段位的序号是 {base}")

    # 解释 4：游戏内部 CLASS ID
    print()
    print("  解释 4 —— 游戏内部 CLASS ID（我们没采集过，无法验证）")
    print("    如果 base 是个较大的数（比如 100 以上），很可能是这个。")
    print("    验证方法：去机台再通一个**不同**的 CLASS，看 base 怎么变：")
    print("      · 变成新通的那个段位的编号 -> 它表示「最近/当前拿到的缎带」")
    print("      · 多个段位通掉后取最大值   -> 它表示「最高段位」")
    print("      · 变成两数之和/或       -> 它是位掩码")

    print()
    print("=" * 84)
    print("结论")
    print("=" * 84)
    if base == 0:
        print("  ⚠ base 仍是 0。最可能是成绩还没同步 —— 先去查分器网页点一次同步/刷新，")
        print("    再重跑这个脚本。如果刷新后还是 0，那这个字段就不表示缎带。")
    else:
        print(f"  base = {base}，非 0 —— AIR 门**有希望**自动判定。")
        print("  但要确定它的语义，还需要第二个数据点：")
        print("    去机台通一个**不同**的 CLASS，然后重跑这个脚本，看 base 怎么变。")
        print("    （只有一次观测无法区分「布尔量 / 段位序号 / 最高段位」）")

    # 公开端点的结论
    pub = [e for e, doc, _ in entries if "friendcode" in (e.get("Name") or "")]
    if pub:
        e, doc, note = pub[0]
        print()
        if isinstance(doc, dict) and doc.get("data") is not None:
            print("  ✓ 公开端点 /chunithm/player/{好友码} 也能读到缎带")
            print("    -> 不需要个人密钥就能查（但查分器要开 allow_third_party_fetch_player）")
        else:
            print(f"  ✗ 公开端点读不到：{note or '无 data'}")
            print("    -> 只能用个人密钥的 /user/chunithm/player")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
