#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
模拟「CI 环境」跑一遍 CI 里所有静态检查，确保它们不依赖本地才有的 `condition/`。

为什么需要这个：
    `condition/` 是 **gitignore 的**（游戏解包原始资源，版权属 SEGA），
    CI 上克隆下来的仓库里没有它。

    于是很容易写出「本地跑得好好的、一上 CI 就炸」的检查 ——
    我这次就写了一个：`check_music_order.py` 需要 `condition/MusicSort.xml`，
    本地有、CI 没有，CI 红在 `✗ 读不到 MusicSort.xml —— 无法核对`。
    这类错误**只有推到 CI 才会暴露**（本地永远能过），一轮构建白烧。

## 怎么模拟

关键是**用一个空的 `condition/` 占位**，而不是把它改名：

    改名（错）：路径变了，但文件还在，检查换个路径照样能找到数据 -> 测不出来。
    占位（对）：路径不变、内容为空，和 CI 上的状态真正等价。

（第一版就是改名的，结果 `check_music_order.py` 因为找不到数据而
  **按设计跳过并返回 0**，防护工具误报 OK —— 等于防护工具本身是假的。
  「跳过」和「通过」的退出码相同，所以判据不能只看退出码。）

## 判据

对每个检查跑两次：一次正常、一次在空 condition/ 下，然后比较输出。
**输出不同 = 这个检查依赖 condition/**，在 CI 上行为会和本地不一致。

比较前会把绝对路径规范化（临时目录名会出现在报错信息里）。

检查清单从 workflow 文件里解析，不是手写的 —— 手写的话新加检查时必然忘记同步。

用法：
    python tools/check_ci_safety.py
退出码 0 = 所有 CI 检查都不依赖 condition/，1 = 有检查依赖它。
"""

from __future__ import annotations

import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = ROOT / ".github" / "workflows" / "build-apk.yml"
CONDITION = ROOT / "condition"
STASH = ROOT / "condition__stashed_for_ci_test"

# 绝对路径会出现在输出里（临时目录名不同），比较前统一抹掉
_ABS = re.compile(r"[A-Za-z]:[\\/][^\s'\"]*|/(?:home|Users|tmp|workspace)/[^\s'\"]*")


def normalize(text: str) -> str:
    return _ABS.sub("<path>", text or "").strip()


def checks_from_workflow() -> list[list[str]]:
    """从 workflow 里抽出所有 `python3 tools/xxx.py [flags]` 调用。"""
    if not WORKFLOW.exists():
        print(f"✗ 找不到 {WORKFLOW}")
        return []

    cmds: list[list[str]] = []
    for line in WORKFLOW.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^python3\s+(tools/[\w./-]+\.py(?:\s+--[\w-]+)*)\s*$", line.strip())
        if m:
            cmds.append(shlex.split(m.group(1)))
    return cmds


def run(args: list[str]) -> tuple[int, str]:
    p = subprocess.run(
        [sys.executable, *args],
        cwd=ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    return p.returncode, normalize((p.stdout or "") + (p.stderr or ""))


def main() -> int:
    cmds = checks_from_workflow()
    if not cmds:
        print("✗ 从 workflow 里没解析出任何 python 检查 —— 解析规则可能过时了")
        return 1

    if not CONDITION.exists():
        print(f"⚠ 本机没有 {CONDITION}，无法模拟（CI 环境本来就是这样）")
        return 0

    if STASH.exists():
        print(f"✗ {STASH} 已存在 —— 上次可能被打断，请先手动处理")
        return 1

    print(f"从 workflow 解析出 {len(cmds)} 个 python 检查")
    print("先跑一遍正常环境（作为基准）…")

    baseline: dict[str, tuple[int, str]] = {}
    for args in cmds:
        baseline[" ".join(args)] = run(args)

    print("再用**空的 condition/ 占位**跑一遍（模拟 CI）…")
    print()

    results: list[tuple[str, int, str, bool]] = []
    CONDITION.rename(STASH)
    try:
        CONDITION.mkdir()          # 空占位：路径在、内容空
        for args in cmds:
            label = " ".join(args)
            code, out = run(args)
            base_code, base_out = baseline[label]
            same = (code == base_code and out == base_out)
            results.append((label, code, out.splitlines()[-1] if out else "", same))
    finally:
        shutil.rmtree(CONDITION, ignore_errors=True)
        if STASH.exists():
            STASH.rename(CONDITION)

    print(f"condition/ 已恢复：{CONDITION.exists()}  "
          f"(MusicSort.xml 在：{(CONDITION / 'MusicSort.xml').exists()})")
    print()

    dependent: list[tuple[str, int, str, bool]] = []
    for label, code, tail, same in results:
        if same:
            print(f"  [独立] {label}")
        else:
            dependent.append((label, code, tail, same))
            print(f"  [依赖 condition/] {label}  (exit={code})")
            if tail:
                print(f"          {tail[:140]}")

    print()
    if dependent:
        print(f"✗ {len(dependent)} 个 CI 检查的行为依赖 condition/：")
        for label, code, tail, _ in dependent:
            print(f"    {label}")
        print()
        print("修法二选一：")
        print("  1. 让检查在缺数据时明确跳过（打印「跳过 != 通过」，别打绿勾），")
        print("     并加 --require 开关供本地强制核对；")
        print("  2. 把该检查从 workflow 里去掉，只在本地跑。")
        return 1

    print("✓ 所有 CI 检查的行为都不受 condition/ 有无的影响")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
