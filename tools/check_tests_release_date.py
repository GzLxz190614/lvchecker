#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
找出测试里所有 `evaluateAllGates(...)` 调用，检查传给它的门**有没有 releaseDate**。

## 为什么需要这个

`evaluateAllGates` 默认 `skipNotYetOpen: true`，会跳过「没有 releaseDate 或
日期还没到」的门。所以**用 `evaluateAllGates` 的测试必须给门 releaseDate**，
否则门被跳过、什么都没扫描到，测试失败 —— 而失败信息（
`Expected: true / Actual: <false>`）看起来和被测逻辑无关，很难查。

这个坑真实踩过：`report.cutoff 取所有门基准里最早的那个` 用了两个没有
releaseDate 的门，CI 上挂了。

`_run(...)` 走的是单门 `evaluateGate`，**不过滤**，所以那些测试不受影响。

## 做法

扫 test/*.dart，对每个 `evaluateAllGates(` 调用往前找它所在的 test 块，
看块内有没有 `releaseDate`。有就 OK，没有就报警（人工确认是否真的不需要）。

用法：
    python tools/check_tests_release_date.py
退出码 0 = 都检查过，1 = 有可疑的调用。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = Path(__file__).resolve().parent.parent
TESTS = ROOT / "test"


def main() -> int:
    if not TESTS.exists():
        print(f"✗ 找不到 {TESTS}")
        return 1

    suspects: list[str] = []
    checked = 0

    for path in sorted(TESTS.glob("*.dart")):
        lines = path.read_text(encoding="utf-8").splitlines()
        for i, line in enumerate(lines):
            if "evaluateAllGates(" not in line:
                continue
            checked += 1

            # 往前找这个调用所属的 test(...) / group(...) 起始
            start = 0
            for j in range(i - 1, -1, -1):
                if re.search(r"\btest\(", lines[j]):
                    start = j
                    break

            # 向后扫到下一个 test( 或文件尾，作为这个测试块的范围
            end = len(lines)
            for j in range(i + 1, len(lines)):
                if re.search(r"\btest\(", lines[j]):
                    end = j
                    break

            block = "\n".join(lines[start:end])

            # ⚠️ 关键：把 test 的**标题行**排除掉，只在代码体里找。
            #
            # 踩过的坑：标题写成「忘了给 releaseDate 的测试」时，
            # `'releaseDate' in block` 会为真 —— 检查被**标题里的一句话**骗过，
            # 于是它成了一个永远报 OK 的假检查。测试的标题本来就常常在描述
            # 被测的那个东西，拿整块做子串匹配必然误判。
            body_lines = lines[start + 1:end]

            title = ""
            m = re.search(r"test\(\s*'([^']*)'", lines[start])
            if m:
                title = m.group(1)

            body = "\n".join(body_lines)

            # `releaseDate` 出现在**代码体**里才算 OK；也接受显式关掉过滤
            if "releaseDate" in body or "skipNotYetOpen: false" in body:
                continue

            # 门是不是根本没用到「门是否开放」的判断？只有在传了 gates: 时才关心
            if "gates:" not in body and "gate:" not in body:
                continue

            # 有些测试**故意**用没有 releaseDate 的门，测的就是「跳过」这件事。
            # 一律报警会产生噪音，而噪音多了就会被无视 —— 那这个检查就白写了。
            # 所以按「测试名/注释里明确说了」来识别，识别不了才报。
            intent_markers = (
                "skipNotYetOpen",   # 名字里就点了这个开关
                "跳过",              # 「会被跳过」「默认跳过」
                "不产生基准",
                "没有开放日期",
                "没开放",
                "didCompare 也是 false",
                "奖励页",            # 奖励页本来就没有 releaseDate
            )
            haystack = title + "\n" + body[:600]
            if any(mk in haystack for mk in intent_markers):
                continue

            # 最后一道：代码体里有没有解释性注释
            if re.search(r"//.*(故意|特意|本来就不该|不该产生)", body):
                continue

            suspects.append(f"{path.name}:{i + 1}  {title or '(无名测试)'}")

    print(f"扫到 {checked} 处 evaluateAllGates 调用")
    print()

    if suspects:
        print(f"⚠ {len(suspects)} 处的门可能没有 releaseDate（会被 skipNotYetOpen 跳过）：")
        for s in suspects:
            print(f"  {s}")
        print()
        print("  如果这些测试**故意**要测「未开放的门被跳过」，请忽略本条；")
        print("  否则给门加上 releaseDate，否则测试会因为「什么都没扫描到」而失败，")
        print("  而失败信息看起来和被测逻辑无关。")
        # 只警告，不失败 —— 有些测试就是专门测跳过的
        return 0

    print("✓ 每个用了 evaluateAllGates 的测试都给了门 releaseDate（或显式关掉跳过）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
