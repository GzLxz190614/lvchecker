#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
打印一份落雪 API 原始响应的**结构**（字段名 + 少量样本），用于探查。

刻意**不打印**玩家信息里的身份字段（好友码、昵称、QQ 等）——
这个输出是要贴到对话里的，只保留我们判断功能需要的东西。

用法：
    python tools/probe_lxns_raw.py <响应文件> [标题]
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

# 这些字段属于个人身份，不打印
PRIVATE = {
    "friend_code",
    "name",
    "qq",
    "icon_url",
    "trophy",
    "name_plate",
    "map_icon",
    "character",
    "currency",
    "total_currency",
}


def to_local(raw) -> str:
    if not isinstance(raw, str) or not raw:
        return "null"
    try:
        return (
            datetime.fromisoformat(raw.replace("Z", "+00:00"))
            .astimezone(CST)
            .strftime("%Y-%m-%d %H:%M")
        )
    except Exception:  # noqa: BLE001
        return f"解析失败({raw})"


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1

    p = Path(sys.argv[1])
    title = sys.argv[2] if len(sys.argv) > 2 else "响应"

    if not p.exists():
        print(f"  （没有响应文件：{p}）")
        return 1
    raw_text = p.read_text(encoding="utf-8", errors="replace").strip()
    if not raw_text:
        print("  （响应为空）")
        return 1

    try:
        doc = json.loads(raw_text)
    except Exception as e:  # noqa: BLE001
        print(f"  （不是 JSON：{e}）")
        print(f"  原始内容前 200 字：{raw_text[:200]}")
        return 1

    if not isinstance(doc, dict):
        print("  （顶层不是对象）")
        return 1

    print(f"  success={doc.get('success')}  code={doc.get('code')}  "
          f"message={doc.get('message')!r}")

    data = doc.get("data")
    if data is None:
        print("  data = null（这个接口用个人密钥大概没有权限，或路径不对）")
        return 0

    if isinstance(data, dict):
        print("  data 是对象，字段：")
        for k, v in data.items():
            if k in PRIVATE:
                print(f"    {k:16} = <已隐去（身份信息）>")
            elif isinstance(v, (dict, list)):
                print(f"    {k:16} = {type(v).__name__}（{len(v)} 项）")
            else:
                print(f"    {k:16} = {v!r}")
        return 0

    if not isinstance(data, list):
        print(f"  data 是 {type(data).__name__}")
        return 0

    print(f"  data 是列表，共 {len(data)} 条")

    if not data:
        print("  （空列表）")
        return 1

    first = data[0]
    if not isinstance(first, dict):
        print(f"  第一条不是对象：{type(first).__name__}")
        return 1

    print(f"  第一条的字段（共 {len(first)} 个）：")
    for k in sorted(first.keys()):
        v = first[k]
        if k in PRIVATE:
            print(f"    {k:16} = <已隐去>")
        elif k in ("play_time", "upload_time"):
            print(f"    {k:16} = {v!r}  -> 北京 {to_local(v)}")
        else:
            print(f"    {k:16} = {v!r}")

    # 成绩样本里看时间字段的分布，确认哪个字段能用来判断「开门后打过」
    times = [r for r in data if isinstance(r, dict)]
    with_play = sum(1 for r in times if r.get("play_time"))
    with_upload = sum(1 for r in times if r.get("upload_time"))
    print()
    print(f"  统计：{len(times)} 条里，play_time 非空 {with_play} 条，"
          f"upload_time 非空 {with_upload} 条")

    if with_upload:
        # 按 upload_time 倒序，看最近同步的是哪几条（只看时间，不带曲名之外的信息）
        def key(r):
            return r.get("upload_time") or ""

        recent = sorted(times, key=key, reverse=True)[:5]
        print("  最近同步的 5 条（按 upload_time）：")
        for r in recent:
            print(f"    songId={r.get('id')} lv={r.get('level_index')} "
                  f"play={to_local(r.get('play_time'))} "
                  f"upload={to_local(r.get('upload_time'))}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
