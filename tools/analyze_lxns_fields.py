"""确认 last_played_time 的分布与语义。

这是从真实响应的字段列表里发现的字段 —— **官方文档的 Score 结构体里没有它**。
在依赖它之前，先把它的分布和语义用真实数据确认清楚：
  · 有多少条有这个字段？
  · 有没有为 null 的？
  · 它和 play_time / upload_time 的大小关系是什么？

用法：
    python tools/analyze_lxns_fields.py <响应文件>
"""

from __future__ import annotations

import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

CST = timezone(timedelta(hours=8))


def local(raw):
    if not isinstance(raw, str) or not raw:
        return None
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00")).astimezone(CST)
    except Exception:  # noqa: BLE001
        return None


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    p = Path(sys.argv[1])
    text = p.read_text(encoding="utf-8", errors="replace")
    start = text.find("{")
    if start > 0:
        text = text[start:]
    doc = json.loads(text)
    data = doc.get("data")
    if not isinstance(data, list):
        print("响应里没有成绩列表")
        return 1

    rows = [r for r in data if isinstance(r, dict)]
    n = len(rows)
    print(f"共 {n} 条成绩")
    print()

    # 字段出现率
    from collections import Counter

    counter = Counter()
    for r in rows:
        for k in r:
            counter[k] += 1
    print("=== 字段出现率 ===")
    for k, c in sorted(counter.items(), key=lambda kv: -kv[1]):
        print(f"  {k:20} {c}/{n}")

    print()
    has_lpt = sum(1 for r in rows if r.get("last_played_time"))
    null_lpt = sum(1 for r in rows if "last_played_time" in r and not r.get("last_played_time"))
    missing_lpt = sum(1 for r in rows if "last_played_time" not in r)
    print("=== last_played_time 分布 ===")
    print(f"  有值: {has_lpt}")
    print(f"  键存在但为 null: {null_lpt}")
    print(f"  键不存在: {missing_lpt}")

    if has_lpt == 0:
        print("\n没有一条有 last_played_time —— 这个字段不可用")
        return 1

    # 排序，看最新的一批
    def lpt(r):
        return local(r.get("last_played_time")) or datetime.min.replace(tzinfo=CST)

    recent = sorted(rows, key=lpt, reverse=True)[:15]
    print()
    print("=== last_played_time 最新的 15 条 ===")
    for r in recent:
        lp = local(r.get("last_played_time"))
        pp = local(r.get("play_time"))
        print(
            f"  id={r.get('id'):>6} lv={r.get('level_index')} "
            f"last={lp.strftime('%Y-%m-%d %H:%M') if lp else 'null':<17} "
            f"play={pp.strftime('%Y-%m-%d %H:%M') if pp else 'null':<17} "
            f"{(r.get('song_name') or '')[:28]}"
        )

    # last_played_time 应该 >= play_time（最后游玩不可能早于最好成绩那次）
    viol = 0
    for r in rows:
        lp, pp = local(r.get("last_played_time")), local(r.get("play_time"))
        if lp and pp and lp < pp:
            viol += 1
    print()
    print(f"=== 一致性：last_played_time < play_time 的条数 = {viol} ===")
    print("（应该为 0：最后游玩时间不可能早于最好成绩那次的时间）")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
