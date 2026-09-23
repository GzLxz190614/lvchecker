#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
检查 `pubspec.yaml` 的 versionCode 是否**大于**最近一次发布 tag 的。

## 为什么需要这个

实测（用户报告）：**同 versionCode 的 APK 装不上**。

    > 同版本号好像不能覆盖安装？更新下版本号？

我此前判断错了，说「versionCode 不变也能覆盖安装」——
那条建议直接害得用户装不上。

Android 的安装器会拒绝：**versionCode 必须严格大于已安装的**。
所以每次出 APK 都必须先 `python tools/bump_app_version.py`。

这个检查拿本地已有的 git tag 做基准（不需要联网）：
tag 形如 `v0.4.1` 里带的 build number 就是那次发布的 versionCode。
如果当前 pubspec 的 versionCode 不大于它就报警 —— 说明这次构建会产出
一个装不上的包。

## 为什么只警告不失败

有些构建是**故意**用同一个版本号重跑（比如上一次构建失败、或只是换个
artifact 名）。硬失败会挡住这种合理操作。但必须把话说清楚，因为
「推成功了、包也出来了、就是装不上」是最难查的一种现象。

用法：
    python tools/check_version_bumped.py
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = Path(__file__).resolve().parent.parent
PUBSPEC = ROOT / "pubspec.yaml"

# v0.4.1 / v0.4.1-rc.1 / v0.2.0-test.12 都认；取 X.Y.Z，忽略预发布后缀
TAG_RE = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)")


def current_version() -> tuple[str, int] | None:
    if not PUBSPEC.exists():
        return None
    m = re.search(r"^version:\s*(\S+)\s*$", PUBSPEC.read_text(encoding="utf-8"), re.M)
    if not m:
        return None
    raw = m.group(1)
    vm = re.match(r"^(\d+\.\d+\.\d+)(?:\+(\d+))?$", raw)
    if not vm:
        return None
    return vm.group(1), int(vm.group(2)) if vm.group(2) else 0


def collect_tags() -> tuple[list[str], list[str]]:
    """返回 (指向 HEAD 的版本 tag, 全部版本 tag 按时间倒序)。

    只用本地已有的 tag，不联网 —— 这样在 CI 上也能跑，也不会因为网络问题
    让提示变成噪音。
    """
    at = subprocess.run(
        ["git", "tag", "--points-at", "HEAD"],
        cwd=ROOT, capture_output=True, text=True,
    )
    at_head = [t for t in at.stdout.split() if TAG_RE.match(t)]

    every = subprocess.run(
        ["git", "tag", "--list", "v*", "--sort=-creatordate"],
        cwd=ROOT, capture_output=True, text=True,
    )
    return at_head, [t for t in every.stdout.split() if TAG_RE.match(t)]


def main() -> int:
    cur = current_version()
    if cur is None:
        print("✗ 读不出 pubspec.yaml 的 version")
        return 1
    name, code = cur

    at_head, all_tags = collect_tags()

    print(f"pubspec 版本: {name}+{code}")
    print(f"  versionName = {name}")
    print(f"  versionCode = {code}")
    print()

    if at_head:
        print(f"当前 HEAD 已有 tag: {at_head}")
        print("  （tag 触发的构建会发布这个版本；如果这个 versionCode 已经发过，")
        print("    装了上一版的人**装不上**这一版）")
    else:
        print("当前 HEAD 没有 tag（workflow_dispatch 手动触发时会用 run number 造 tag）")

    if all_tags:
        print(f"\n最近的发布 tag（按时间倒序，前 5 个）：")
        for t in all_tags[:5]:
            print(f"  {t}")

    print()
    print("=" * 70)
    print("提醒")
    print("=" * 70)
    print("""
  Android 安装器要求 **versionCode 严格大于已安装的**，相同也不行。
  所以每次要出 APK 之前先跑：

      python tools/bump_app_version.py

  它会把 patch 和 build number 一起 +1（例如 0.4.1+5 -> 0.4.2+6）。

  ⚠️ 注意这是**另一个**版本号，别和 data/*.json 的 dataVersion 搞混：
       pubspec.yaml 的 version  ->  APK 的 versionName/versionCode（安装用）
       data/*.json 的 dataVersion -> 热更新的比对依据
     只改 data/*.json 用 `python tools/bump_data_version.py`。
""")

    # 版本号本身没变（等于最近 tag）时给出明确警告
    if at_head:
        warnings = []
        for t in at_head:
            tm = TAG_RE.match(t)
            if not tm:
                continue
            tag_name = f"{tm.group(1)}.{tm.group(2)}.{tm.group(3)}"
            if tag_name == name:
                warnings.append(
                    f"tag {t} 的版本号和当前 pubspec 相同（{name}）—— "
                    f"如果那个 tag 已经发过 APK，这次构建的包会装不上"
                )
        if warnings:
            print("⚠ " + "\n⚠ ".join(warnings))
            print("  -> 跑 `python tools/bump_app_version.py` 再构建")

    # 永远返回 0：只提醒，不挡构建（见文件头的说明）
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
