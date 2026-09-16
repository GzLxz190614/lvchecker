#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从落雪 API 的原始响应里，提取「ORIGIN 门那 30 首」的成绩，输出成小文件。

**为什么要这一步，而不是把原始 JSON 直接发出来：**

  落雪 `/user/chunithm/player/scores` 返回的是你**全部谱面**的成绩。
  原始响应里还有好友码、所有曲目记录等。整份贴出去没必要，而且
  等于把你的完整游玩记录交出去。

  这个脚本只挑出 ORIGIN 门要求的那 30 首（曲名、歌 id、难度、时间），
  你分享的内容就被限定在这个范围内。

用法（需要先把 API 响应存成文件）：

    python tools/lxns_extract_origin.py scores_raw.json

输出：lxns_origin.txt
"""

from __future__ import annotations

import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

LEVEL_NAMES = {0: "BASIC", 1: "ADVANCED", 2: "EXPERT", 3: "MASTER", 4: "ULTIMA", 5: "WORLD'S END"}

CST = timezone(timedelta(hours=8))


def load_json(path: Path) -> dict:
    text = path.read_text(encoding="utf-8", errors="replace")
    # 兼容前面被 curl -s 带上了进度条之类杂字符的情况
    start = text.find("{")
    if start > 0:
        text = text[start:]
    return json.loads(text)


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1

    raw_path = Path(sys.argv[1])
    if not raw_path.exists():
        print(f"找不到文件：{raw_path}")
        return 1

    doc = load_json(raw_path)

    if not doc.get("success"):
        print(f"❌ 接口返回失败：code={doc.get('code')} message={doc.get('message')}")
        print("   （401 一般是密钥无效或过期；429 是限流，等几分钟再试）")
        return 1

    data = doc.get("data")
    if not isinstance(data, list):
        print("❌ 响应里没有成绩列表 —— 接口可能变了")
        return 1

    # ---- ORIGIN 门的曲目清单（从本仓库的数据里读，不写死）----
    gates = json.loads((ROOT / "data" / "gates.json").read_text(encoding="utf-8"))["gates"]
    meta = json.loads((ROOT / "data" / "meta.json").read_text(encoding="utf-8"))["entries"]

    origin = next((g for g in gates if g.get("id") == "origin"), None)
    if origin is None:
        print("❌ data/gates.json 里找不到 origin 门")
        return 1

    want_keys = origin["requirement"]["songKeys"]
    want_ids = {int(k.split(":")[1]): k for k in want_keys}
    release_date = origin.get("releaseDate") or "?"

    # ---- 过滤成绩 ----
    rows = []
    for s in data:
        if not isinstance(s, dict):
            continue
        sid = s.get("id")
        if sid not in want_ids:
            continue
        idx = s.get("level_index")
        rows.append({
            "songId": sid,
            "title": meta.get(want_ids[sid], {}).get("title", "?"),
            "level": LEVEL_NAMES.get(idx, f"?({idx})"),
            "playTimeUtc": s.get("play_time"),
            "score": s.get("score"),
        })

    # 按歌 id、难度排序，便于比对
    rows.sort(key=lambda r: (r["songId"], str(r["level"])))

    # ---- 输出 ----
    lines = []
    lines.append(f"# ORIGIN 门成绩提取（门开放日期 {release_date}）")
    lines.append(f"# 门要求 {len(want_ids)} 首；接口里命中 {len({r['songId'] for r in rows})} 首，"
                 f"{len(rows)} 条谱面记录")
    lines.append(f"# 时间已转成北京时间（接口原始是 UTC）")
    lines.append("")

    hit_ids = {r["songId"] for r in rows}
    lines.append("== 在接口里找到的 ==")
    for r in rows:
        t = r["playTimeUtc"]
        local = ""
        if t:
            try:
                local = (
                    datetime.fromisoformat(t.replace("Z", "+00:00"))
                    .astimezone(CST)
                    .strftime("%Y-%m-%d %H:%M")
                )
            except Exception:  # noqa: BLE001
                local = f"(解析失败: {t})"
        else:
            local = "(接口未给时间)"
        lines.append(
            f"{r['songId']:>5}  {r['level']:<10}  {local:<17}  {r['score'] or 0:>8}  {r['title']}"
        )

    lines.append("")
    lines.append("== 接口里完全没有的（= 这个谱面从没打过）==")
    missing = [k for k in want_keys if int(k.split(":")[1]) not in hit_ids]
    if not missing:
        lines.append("（无，30 首全都有记录）")
    for k in missing:
        lines.append(f"{k:>12}  {meta.get(k, {}).get('title', '?')}")

    out = ROOT / "lxns_origin.txt"
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print("\n".join(lines[:6]))
    print("...")
    print(f"\n已写入 {out}")
    print(f"（这个文件不会进 git 仓库 —— lxns_* 已在 .gitignore 里）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
