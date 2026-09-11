#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 M0 验收预览图（不进 APK，只给人看）。

    python tools/preview.py

产出 preview/：
    gates_overview.png   14 个门的数据总览
    page_origin.png      ORIGIN 页（30 首曲绘）
    page_paradise.png    PARADISE 页（5 组曲师，验证分组 UI）
    page_star.png        STAR 页（角色立绘）
    page_reward.png      奖励乐曲页

字体说明（踩过的坑）：
    PIL 不做字体回退，且 `textlength()` 对「豆腐块」也返回宽度，所以不能拿它
    判断字形是否存在。实测用 fontTools 查 cmap：
        msyh.ttc     缺 2 字   ♡ ♥
        YuGothM.ttc  缺 37 字  为乐仅们值动图头奖导师带时显查标组缎缓获览认记设请课过这进钥锁队隐难预题饰
    组合后 0 缺字，所以这里逐字选字体。
    真实 APK 在 Android 上由系统字体回退链处理，不存在这个问题。
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "preview"

BG, CARD2, TXT, DIM = "#14141c", "#1d1d28", "#e8e8f0", "#7d8399"
ACC, WARN, BOSS = "#4ade80", "#c98a2e", "#d8b46a"

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

# ---------------------------------------------------------------- 字体回退

FONT_CHAIN = [
    ("C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/msyhbd.ttc"),
    ("C:/Windows/Fonts/YuGothM.ttc", "C:/Windows/Fonts/YuGothM.ttc"),
    ("C:/Windows/Fonts/seguisym.ttf", "C:/Windows/Fonts/seguisym.ttf"),
]
_cmap: dict[str, set[int]] = {}
_font_cache: dict[tuple[str, int], ImageFont.FreeTypeFont] = {}
MISSING: set[str] = set()


def cmap_of(path: str) -> set[int]:
    if path in _cmap:
        return _cmap[path]
    from fontTools.ttLib import TTFont, TTCollection

    cps: set[int] = set()
    try:
        if path.lower().endswith(".ttc"):
            for f in TTCollection(path).fonts:
                for t in f["cmap"].tables:
                    cps |= set(t.cmap.keys())
        else:
            for t in TTFont(path, fontNumber=0)["cmap"].tables:
                cps |= set(t.cmap.keys())
    except Exception:  # noqa: BLE001
        pass
    _cmap[path] = cps
    return cps


def _font(path: str, size: int) -> ImageFont.FreeTypeFont:
    key = (path, size)
    if key not in _font_cache:
        _font_cache[key] = ImageFont.truetype(path, size)
    return _font_cache[key]


def pick(ch: str, size: int, bold: bool) -> ImageFont.FreeTypeFont:
    for reg, bd in FONT_CHAIN:
        p = bd if bold else reg
        if ord(ch) in cmap_of(p):
            return _font(p, size)
    MISSING.add(ch)
    return _font(FONT_CHAIN[0][0], size)


def tlen(d: ImageDraw.ImageDraw, text: str, size: int) -> float:
    return sum(d.textlength(c, font=pick(c, size, False)) for c in text)


def draw(d: ImageDraw.ImageDraw, xy, text: str, size: int, fill, bold: bool = False):
    x, y = xy
    for c in text:
        f = pick(c, size, bold)
        d.text((x, y), c, font=f, fill=fill)
        x += d.textlength(c, font=f)


def fit(d: ImageDraw.ImageDraw, text: str, size: int, max_px: float) -> str:
    if tlen(d, text, size) <= max_px:
        return text
    ew = tlen(d, "…", size)
    lo, hi = 0, len(text)
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if tlen(d, text[:mid], size) + ew <= max_px:
            lo = mid
        else:
            hi = mid - 1
    return text[:lo] + "…"


def wrap(d: ImageDraw.ImageDraw, text: str, size: int, max_px: float,
         max_lines: int = 2) -> list[str]:
    lines, cur = [], ""
    for ch in text:
        if tlen(d, cur + ch, size) > max_px and cur:
            lines.append(cur)
            cur = ch
            if len(lines) == max_lines:
                break
        else:
            cur += ch
    if cur and len(lines) < max_lines:
        lines.append(cur)
    if sum(len(x) for x in lines) < len(text) and lines:
        lines[-1] = fit(d, lines[-1] + "…", size, max_px)
    return lines or [""]


def save(img: Image.Image, name: str) -> None:
    OUT.mkdir(exist_ok=True)
    p = OUT / name
    img.save(p, "PNG", optimize=True)
    print(f"写出 {p.relative_to(ROOT)}  {img.size}  {p.stat().st_size/1024:.0f} KB")


# ---------------------------------------------------------------- 数据

def load():
    meta = json.loads((ROOT / "data" / "meta.json").read_text(encoding="utf-8"))["entries"]
    gates = json.loads((ROOT / "data" / "gates.json").read_text(encoding="utf-8"))["gates"]
    return meta, gates


def level_line(levels: dict) -> str:
    order = [("basic", "BASIC"), ("advanced", "ADV"), ("expert", "EXP"),
             ("master", "MAS"), ("ultima", "ULT")]
    return "   ".join(f"{n} {levels[k]}" for k, n in order if k in levels)


# ---------------------------------------------------------------- 总览页

def gates_overview(meta, gates):
    W = 1400
    H = 118 + len(gates) * 50 + 20
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    draw(d, (24, 20), "14 个门 · M0 数据总览", 28, "#ffffff", bold=True)
    draw(d, (24, 62), "前 13 个是解锁条件门，第 14 个是奖励乐曲（全部门通关后显示）", 14, DIM)

    xs = [24, 70, 250, 340, 470, 1010, 1105]
    for x, t in zip(xs, ["#", "门", "状态", "跟踪", "解锁条件", "数量", "BOSS 难度"]):
        draw(d, (x, 90), t, 14, "#6f7690", bold=True)

    label = {"songs": "曲目清单", "items": "条目勾选", "class": "段位课程",
             "auto": "自动推导", "universe": "血量确认", "manual": "手动确认"}

    y = 118
    for g in gates:
        r = g.get("requirement", {})
        t = r.get("type", "")
        if t == "playAll":
            n = f"{len(r.get('songKeys', []))} 首"
        elif t == "playAnyOfEach":
            n = f"{len(r.get('groups', []))} 组 / {sum(len(x['songKeys']) for x in r['groups'])} 首"
        elif t == "items":
            n = f"{len(r.get('itemKeys', []))} 项"
        else:
            n = "—"

        if g["releaseStatus"] == "open":
            st, c = "已开放", ACC
        elif g["releaseStatus"] == "locked":
            st, c = "锁定", WARN
        else:
            st, c = "未更新", DIM

        b = g.get("boss") or {}
        bl = " ".join(f"{k[0].upper()}{v}" for k, v in b.get("levels", {}).items())

        draw(d, (xs[0], y), str(g["order"]), 14, "#5a6076")
        draw(d, (xs[1], y), g["name"].replace("Linked GATE ", ""), 16, TXT, bold=True)
        draw(d, (xs[2], y), st, 14, c)
        draw(d, (xs[3], y), label.get(g["tracking"], g["tracking"]), 14, "#9aa0b5")
        draw(d, (xs[4], y), fit(d, g["conditionText"], 13, 520), 13, "#9aa0b5")
        draw(d, (xs[5], y), n, 14, TXT)
        draw(d, (xs[6], y), bl, 12, "#8a90a8")
        y += 50

    save(img, "gates_overview.png")


# ---------------------------------------------------------------- 门页

def gate_page(meta, gates, gid: str, title: str, *, cols=5, thumb=168):
    g = next(x for x in gates if x["id"] == gid)
    r = g.get("requirement", {})
    rtype = r.get("type")

    blocks: list[tuple[str | None, list]] = []
    if rtype == "playAll":
        blocks.append((None, [(k, meta[k]["title"], meta[k]["artist"], meta[k].get("image"))
                              for k in r["songKeys"]]))
    elif rtype == "items":
        blocks.append((None, [(k, meta[k]["title"], meta[k].get("subtitle", ""), meta[k].get("image"))
                              for k in r["itemKeys"]]))
    elif rtype == "playAnyOfEach":
        for grp in r["groups"]:
            blocks.append((grp["key"],
                           [(k, meta[k]["title"], meta[k]["artist"], meta[k].get("image"))
                            for k in grp["songKeys"]]))

    pad, cell_w, cell_h = 24, thumb + 20, thumb + 82
    head_h = 128
    content_h = sum((34 if name else 0) + ((len(items) + cols - 1) // cols) * cell_h
                    for name, items in blocks)
    boss_h = 104
    W = pad * 2 + cols * cell_w - 20
    H = head_h + pad + content_h + boss_h
    img = Image.new("RGB", (W, max(H, 400)), BG)
    d = ImageDraw.Draw(img)

    # ---- 标题行 ----
    draw(d, (pad, 20), title, 30, "#ffffff", bold=True)
    if gid == "reward":
        st, c = "锁定", WARN
    elif g["releaseStatus"] == "open":
        st, c = "已开放", ACC
    else:
        st, c = "未更新", DIM
    draw(d, (pad + tlen(d, title, 30) + 14, 32), st, 16, c, bold=True)

    # ---- 解锁条件（真实 App 里默认折叠）----
    cy = 66
    for line in wrap(d, "解锁条件：" + g["conditionText"], 15, W - pad * 2, 3):
        draw(d, (pad, cy), line, 15, "#9aa0b5")
        cy += 22
    if gid == "paradise":
        draw(d, (pad, cy + 2), "（每位曲师任打一首即可，所以最少要打 5 首）", 14, WARN)
    if gid == "reward":
        draw(d, (pad, cy + 2), "（这是最后一页，只显示奖励乐曲；全部门完成后才出现）", 14, WARN)

    # ---- 卡片区 ----
    y = head_h + pad
    for gname, items in blocks:
        if gname:
            draw(d, (pad, y), gname, 18, "#c9cfe4", bold=True)
            draw(d, (pad + tlen(d, gname, 18) + 10, y + 3), f"0/{len(items)}", 14, DIM)
            y += 34
        for i, (k, t, sub, im) in enumerate(items):
            rr, cc = divmod(i, cols)
            x, yy = pad + cc * cell_w, y + rr * cell_h
            d.rounded_rectangle([x, yy, x + thumb, yy + cell_h - 12], 10, fill=CARD2)
            jp = ROOT / im if im else None
            if jp and jp.exists():
                with Image.open(jp) as imo:
                    img.paste(imo.convert("RGB").resize((thumb, thumb), Image.LANCZOS), (x, yy))
            else:
                d.rectangle([x, yy, x + thumb, yy + thumb], fill="#2b2b3a")
                draw(d, (x + thumb // 2 - 15, yy + thumb // 2 - 9), "无图", 15, "#666e88")
            d.rectangle([x, yy, x + thumb, yy + thumb], outline="#33334a", width=1)
            ty = yy + thumb + 7
            for line in wrap(d, t, 14, thumb, 2):
                draw(d, (x + 3, ty), line, 14, TXT)
                ty += 19
            draw(d, (x + 3, ty + 1), fit(d, sub, 11, thumb), 11, DIM)
        y += ((len(items) + cols - 1) // cols) * cell_h

    # ---- BOSS 区块（真实 App 里：达成解锁条件后才显示）----
    by = H - boss_h + 14
    d.line([(pad, by - 12), (W - pad, by - 12)], fill="#2a2a3a", width=1)
    b = g.get("boss") or {}
    if b.get("levels"):
        draw(d, (pad, by), "BOSS", 14, "#6f7690", bold=True)
        draw(d, (pad + 56, by - 3), f"{b['title']} / {b['artist']}", 17, TXT, bold=True)
        draw(d, (pad, by + 28), level_line(b["levels"]), 15, BOSS)
        note = ("（本页奖励乐曲，全部门完成后才显示）" if gid == "reward"
                else "（集齐上面全部条目后，本页底部显示此区块）")
        draw(d, (pad, by + 54), note, 12, DIM)
    else:
        draw(d, (pad, by + 20), "（达成解锁条件后，本页底部显示 BOSS 通关条件）", 14, DIM)

    save(img, f"page_{gid}.png")


def main() -> int:
    meta, gates = load()
    gates_overview(meta, gates)
    gate_page(meta, gates, "origin", "Linked GATE ORIGIN")
    gate_page(meta, gates, "paradise", "Linked GATE PARADISE", cols=4)
    gate_page(meta, gates, "star", "Linked GATE STAR", cols=4)
    gate_page(meta, gates, "reward", "奖励乐曲", cols=3)
    if MISSING:
        print(f"\n⚠️ 字体链仍缺这些字符：{''.join(sorted(MISSING))}")
    else:
        print("\n字体链覆盖：0 缺字 ✅")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
