#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
自测 probe_lxns_class_report.py：用合成的 class_emblem 覆盖各种取值，
确认报告器不崩、且判断正确。

为什么要写这个：这个报告器的输出会用来决定「AIR 门怎么自动判定」，
如果它把 base=1 说成「确定是布尔量」而实际是「CLASS I」，我就会照着
写错逻辑。所以先用几个确定性的用例把它钉住。

用法：
    python tools/_selftest_class_report.py
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = Path(__file__).resolve().parent.parent
DIR = ROOT / ".probe3_selftest"

CASES = [
    # (base, medal, 说明, 期望输出里必须出现的片段)
    (0, 0, "没缎带（第一轮的状态）", ["base = 0", "仍然是 0"]),
    (1, 0, "只在 I 拿了缎带 / 或是布尔量", ["base = 1", "布尔量", "CLASS I"]),
    (3, 1, "只在 III 拿了缎带", ["base = 3", "CLASS III"]),
    # 序号解释下 I=1…V=5、∞=6，所以 base=6 应该匹配 CLASS ∞。
    # 同时 classes.json 里 ∞ 的 level 是 0（不等于 6），
    # 所以「等于某个 CLASS 的 level 编号」那条解释应该**不**匹配。
    #
    # ⚠ 不能期望「没有段位的序号是 6」——那句属于解释 3 的**失败**分支，
    #    而这里 base=6 在解释 3 里是命中的。这两句互斥，写在一起永远失败。
    (6, 1, "序号解释（∞ = 6）", ["base = 6", "匹配 CLASS ∞", "没有任何 CLASS 的 level 等于 6"]),
    (1234, 5, "大数（内部 CLASS ID）", ["base = 1234", "游戏内部 CLASS ID"]),
]


def main() -> int:
    shutil.rmtree(DIR, ignore_errors=True)
    DIR.mkdir()

    # 报告器会读 .probe/01_player.json 跟「通关前」的值做对比。
    # 真实文件在的话，输出会随你本机的数据变化 —— 自测就不确定了。
    # 临时挪开，测完放回去。
    real_probe = ROOT / ".probe"
    stashed = ROOT / ".probe__selftest_stash"
    stashed_it = False
    if real_probe.exists() and not stashed.exists():
        real_probe.rename(stashed)
        stashed_it = True

    failures = []
    try:
        failures = _run_cases()
    finally:
        if stashed_it and stashed.exists():
            stashed.rename(real_probe)
        shutil.rmtree(DIR, ignore_errors=True)

    print()
    if failures:
        print(f"✗ {len(failures)} 个用例失败")
        base, desc, code, missing, out, err = failures[0]
        print(f"--- 第一个失败的完整输出（base={base} / {desc}）---")
        print(out)
        if err:
            print("--- stderr ---")
            print(err)
        return 1

    print(f"✓ {len(CASES)} 个用例全部通过")
    return 0


def _run_cases():
    failures = []
    for i, (base, medal, desc, musts) in enumerate(CASES, 1):
        body = {
            "success": True,
            "code": 0,
            "data": {
                "friend_code": 123456789,
                "name": "测试玩家",
                "class_emblem": {"base": base, "medal": medal},
                "character": {"id": 14520, "name": "アレウス", "level": 28},
            },
        }
        fp = DIR / f"01_player_{base}.json"
        fp.write_text(json.dumps(body, ensure_ascii=False), encoding="utf-8", newline="\n")

        man = [{
            "Name": "player",
            "Path": "https://maimai.lxns.net/api/v0/user/chunithm/player",
            "Http": "200",
            "Bytes": fp.stat().st_size,
            "File": str(fp),
        }]
        mp = DIR / "manifest.json"
        mp.write_text(json.dumps(man, ensure_ascii=False), encoding="utf-8", newline="\n")

        r = subprocess.run(
            [sys.executable, "tools/probe_lxns_class_report.py", str(mp)],
            cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace",
        )
        out = r.stdout or ""

        ok = r.returncode == 0
        missing = [m for m in musts if m not in out]
        if not ok or missing:
            failures.append((base, desc, r.returncode, missing, out, r.stderr))

        status = "OK" if (ok and not missing) else "FAIL"
        print(f"  [{status}] base={base:<5} {desc}")
        if missing:
            print(f"          缺少片段: {missing}")
        if not ok:
            print(f"          exit={r.returncode}")
            for line in (r.stderr or "").splitlines()[-4:]:
                print(f"          {line}")

    return failures


if __name__ == "__main__":
    raise SystemExit(main())
