#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把 `pubspec.yaml` 的版本号 +1（同时升 patch 和 build number）。

## 为什么需要这个脚本

Android **装不上同 versionCode 的 APK** —— 实测（用户报告）：

    同版本号好像不能覆盖安装

之前我判断错了，说「versionCode 不变也能覆盖安装」。**那个说法害得用户装不上。**
（虽然 Android 文档常写「相同 versionCode 可以覆盖」，但实测情况下
 安装器直接拒绝，不容含糊。）

所以**每次要出 APK 都必须让 versionCode 严格递增**。

## 两个版本号是不同的东西，别搞混

| 文件 | 字段 | 作用 | 谁 bump |
|---|---|---|---|
| `pubspec.yaml` | `version: 0.4.0+4` | APK 的 versionName/versionCode | **本脚本** |
| `data/*.json` | `dataVersion: 2026.09.11-6` | 热更新的比对依据 | `bump_data_version.py` |

改动 Dart 代码/UI 要用本脚本；只改 `data/*.json` 用另一个。

`version: X.Y.Z+N` 里 **`+N` 才是 versionCode**，`X.Y.Z` 是 versionName。
CI 会校验 APK 里的两个值和 pubspec 一致。

用法：
    python tools/bump_app_version.py                # 0.4.0+4 -> 0.4.1+5
    python tools/bump_app_version.py --build-only   # 0.4.0+4 -> 0.4.0+5（只升 code）
    python tools/bump_app_version.py --dry-run
    python tools/bump_app_version.py --set 0.5.0+6
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = Path(__file__).resolve().parent.parent
PUBSPEC = ROOT / "pubspec.yaml"

# 形如 0.4.0+4；`+N` 可以缺省（Flutter 默认算 0）
VERSION_RE = re.compile(
    r"^(?P<name>(?P<maj>\d+)\.(?P<min>\d+)\.(?P<pat>\d+))(?:\+(?P<build>\d+))?$"
)


def parse(v: str) -> dict:
    m = VERSION_RE.match(v.strip())
    if not m:
        raise ValueError(f"版本号格式不认识：{v!r}（应为 主.次.补 或 主.次.补+构建号）")
    return {
        "name": m.group("name"),
        "maj": int(m.group("maj")),
        "min": int(m.group("min")),
        "pat": int(m.group("pat")),
        # 没写 +N 时按 0 处理 —— 和 Flutter 的行为一致
        "build": int(m.group("build")) if m.group("build") is not None else 0,
        "had_build": m.group("build") is not None,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--build-only", action="store_true",
                    help="只升 +N（versionCode），不动 X.Y.Z")
    ap.add_argument("--set", dest="set_to", help="直接设为指定版本号")
    args = ap.parse_args()

    if not PUBSPEC.exists():
        print(f"✗ 找不到 {PUBSPEC}")
        return 1

    src = PUBSPEC.read_text(encoding="utf-8")
    m = re.search(r"^version:\s*(\S+)\s*$", src, re.M)
    if not m:
        print("✗ pubspec.yaml 里找不到 `version:` 行")
        return 1

    cur = m.group(1)
    try:
        info = parse(cur)
    except ValueError as e:
        print(f"✗ {e}")
        return 1

    print(f"当前 pubspec 版本: {cur}")
    print(f"  versionName = {info['name']}   （X.Y.Z）")
    print(f"  versionCode = {info['build']}   （+N）")
    if not info["had_build"]:
        print("  ⚠ 原来没写 `+N` —— Flutter 会把 versionCode 当作 0。"
              "每次出包都必须让它递增，建议补上。")

    # ---- 算新版本 ----
    if args.set_to:
        new = args.set_to.strip()
        new_info = parse(new)  # 校验格式
    else:
        if args.build_only:
            new_name = info["name"]
        else:
            new_name = f"{info['maj']}.{info['min']}.{info['pat'] + 1}"
        new_info = {"build": info["build"] + 1}
        new = f"{new_name}+{new_info['build']}"

    if new == cur:
        print(f"\n✗ 新版本和当前一样（{cur}）—— versionCode 没变，装不上")
        return 1

    # 硬性要求：versionCode 必须严格变大。相同或变小都装不上。
    new_parsed = parse(new)
    if new_parsed["build"] <= info["build"]:
        print(f"\n✗ 新 versionCode 是 {new_parsed['build']}，"
              f"没有大于当前的 {info['build']} —— 这样装不上")
        return 1

    print(f"\n新的 pubspec 版本: {new}")
    print(f"  versionName = {new_parsed['name']}")
    print(f"  versionCode = {new_parsed['build']}  （{info['build']} -> {new_parsed['build']}）")

    if args.dry_run:
        print("\n（--dry-run，没有写入）")
        return 0

    out = src[:m.start(1)] + new + src[m.end(1):]
    # newline="\n"：仓库 .gitattributes 要求 eol=lf，Windows 上默认会写成 CRLF
    PUBSPEC.write_text(out, encoding="utf-8", newline="\n")
    print(f"\n✓ 已写入 {PUBSPEC.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
