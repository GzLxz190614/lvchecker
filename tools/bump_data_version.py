#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把 data/*.json 的 `dataVersion` 序号 +1。

为什么要单独写个脚本：
    `dataVersion` 是热更新的判定依据。用户在设置页点「立即更新」时，
    `data_sync.dart` 对每个文件做**两层**判断：
      1. 文本完全一致        -> unchanged
      2. 文本不同但版本号相同 -> unchanged（认为只是格式/换行变了）
      3. 版本号不同          -> updated
    所以改了数据却**忘了 bump 版本号**，用户那边会显示「无变化」，
    数据实际上没生效 —— 而且这个错误没有任何报错，只能靠人记得。
    写成本脚本 + 在 CI 校验，就不用靠人记了。

它改三处（保持同步，避免漂移）：
    data/gates.json  的 dataVersion
    data/meta.json   的 dataVersion
    tools/build.py   的 DATA_VERSION 常量（重新生成数据时用的基准）

用法：
    python tools/bump_data_version.py            # 全部 +1
    python tools/bump_data_version.py --dry-run  # 只看会变成什么
    python tools/bump_data_version.py --set 2026.09.11-7
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = Path(__file__).resolve().parent.parent
GATES = ROOT / "data" / "gates.json"
META = ROOT / "data" / "meta.json"
BUILD_PY = ROOT / "tools" / "build.py"


def parse_version(v: str) -> tuple[str, int]:
    """`2026.09.11-4` -> ("2026.09.11", 4)。

    格式不对时抛 ValueError —— 宁可直接失败，也不要静默生成一个
    奇怪的版本号（那样两个源之间的比较会失效）。
    """
    m = re.fullmatch(r"(\d{4}\.\d{2}\.\d{2})-(\d+)", v.strip())
    if not m:
        raise ValueError(f"版本号格式不认识：{v!r}（应为 YYYY.MM.DD-N）")
    return m.group(1), int(m.group(2))


def bump(v: str) -> str:
    date, n = parse_version(v)
    return f"{date}-{n + 1}"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--set", dest="set_to", help="直接设为指定版本号，不做 +1")
    args = ap.parse_args()

    # ---- 读当前版本 ----
    gate_doc = json.loads(GATES.read_text(encoding="utf-8"))
    meta_doc = json.loads(META.read_text(encoding="utf-8"))
    build_src = BUILD_PY.read_text(encoding="utf-8")

    cur_gate = gate_doc.get("dataVersion", "")
    cur_meta = meta_doc.get("dataVersion", "")

    m = re.search(r'^DATA_VERSION\s*=\s*"([^"]+)"', build_src, re.M)
    cur_build = m.group(1) if m else None

    print("当前：")
    print(f"  data/gates.json : {cur_gate}")
    print(f"  data/meta.json  : {cur_meta}")
    print(f"  build.py        : {cur_build}")

    # ---- 算新版本 ----
    if args.set_to:
        new = args.set_to
        parse_version(new)  # 校验格式
    else:
        # 以三者中**最大**的那个为基准 +1。
        # 用最大而不是 gates 的：万一之前只 bump 了某一个文件，
        # 这样能一次把三者拉齐，不会出现回退。
        candidates = [v for v in (cur_gate, cur_meta, cur_build) if v]
        if not candidates:
            print("✗ 三个地方都没有版本号")
            return 1
        date, n = max((parse_version(v) for v in candidates), key=lambda t: t[1])
        new = f"{date}-{n + 1}"

    print(f"\n新的：{new}")
    if args.dry_run:
        print("（--dry-run，没有写入）")
        return 0

    gate_doc["dataVersion"] = new
    meta_doc["dataVersion"] = new
    GATES.write_text(json.dumps(gate_doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    META.write_text(json.dumps(meta_doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"  ✓ data/gates.json -> {new}")
    print(f"  ✓ data/meta.json  -> {new}")

    if m:
        new_src = re.sub(
            r'^(DATA_VERSION\s*=\s*")[^"]+(")',
            lambda mm: mm.group(1) + new + mm.group(2),
            build_src,
            count=1,
            flags=re.M,
        )
        if new_src != build_src:
            BUILD_PY.write_text(new_src, encoding="utf-8", newline="\n")
            print(f"  ✓ tools/build.py DATA_VERSION -> {new}")
        else:
            print("  （build.py 未改动）")
    else:
        print("  ⚠ build.py 里找不到 DATA_VERSION 常量，未改动")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
