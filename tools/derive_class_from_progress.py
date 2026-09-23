#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
用你实际勾选的段位组曲，反推 `class_emblem.base` 到底对应哪个 CLASS。

为什么必须做这一步：
    落雪返回 base=3。我手头有游戏内部编号表（Ⅰ=10 Ⅱ=11 Ⅲ=12 Ⅳ=13 Ⅴ=14 ∞=20），
    所以能确定 base=3 **不是**内部 id。但「base=3 是段位序号 3（=CLASS Ⅲ）」
    这个结论**依赖「你通的确实是 Ⅲ」这个前提** —— 而我并不知道你通的是哪个。

    如果直接拿「base=3 → Ⅲ」去写自动判定，就是循环论证：
    先假设了结论，再用它验证自己。

    所以这里换个方向：从**你勾选的组曲**算出哪些 CLASS 已全通，
    再看 base 的值能不能对上。

用法：
    python tools/derive_class_from_progress.py
"""

from __future__ import annotations

import json
import re
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = Path(__file__).resolve().parent.parent
COURSE_DIR = ROOT / "condition" / "class" / "course"
CLASSES_JSON = ROOT / "data" / "classes.json"

# 游戏内部 difficulty.id -> 标签
INTERNAL_ID_LABEL = {10: "Ⅰ", 11: "Ⅱ", 12: "Ⅲ", 13: "Ⅳ", 14: "Ⅴ", 20: "∞"}
# 标签 -> 罗马序号
SEQ = {"Ⅰ": 1, "Ⅱ": 2, "Ⅲ": 3, "Ⅳ": 4, "Ⅴ": 5, "∞": 6}


def parse_label(text: str) -> str | None:
    m = re.search(r"CLASS\s*(\S+)", text or "")
    return m.group(1) if m else None


def main() -> int:
    # ---- 从 Course.xml 建「组曲 -> 段位标签」 ----
    course_to_label: dict[str, str] = {}
    if COURSE_DIR.exists():
        for d in sorted(p for p in COURSE_DIR.iterdir() if p.is_dir()):
            cx = d / "Course.xml"
            if not cx.exists():
                continue
            root = ET.parse(cx).getroot()
            diff = root.find("difficulty")
            data_el = diff.find("data") if diff is not None else None
            label = parse_label(data_el.text if data_el is not None else "")
            if label:
                course_to_label[d.name] = label
    else:
        print(f"⚠ 找不到 {COURSE_DIR}，改用 classes.json 的 key 前缀推断段位")

    # ---- classes.json 给出每个段位有哪些组曲 ----
    if not CLASSES_JSON.exists():
        print(f"✗ 找不到 {CLASSES_JSON}")
        return 1
    cls = json.loads(CLASSES_JSON.read_text(encoding="utf-8"))

    tiers: dict[str, list[str]] = {}
    for c in cls.get("classes", []):
        key = str(c.get("key"))
        tiers[key] = [x.get("key") for x in c.get("courses", [])]

    print("各段位的组曲数：")
    for k, v in tiers.items():
        print(f"  CLASS {k:<3} {len(v):>2} 组曲")
    print()

    # ---- 读你的勾选 ----
    print("=" * 74)
    print("你的勾选状态（SharedPreferences 不好直接读，改看导出/手动输入）")
    print("=" * 74)

    print("""
  说明：App 把段位勾选存在手机的 SharedPreferences（键 `c:air`）里，
  这个脚本在本机读不到。所以有两条路：

  A) 你在 App 里**已经**勾好的那些组曲 —— 如果你记得通的是哪个段位，
     直接看下面的推断表：你通的段位对应的 base 应该是多少。

  B) 更可靠：去机台再通一个**不同**的段位，重跑 probe_lxns_class.ps1，
     看 base 怎么变。两个数据点就能定死语义。
""")

    print("=" * 74)
    print("落雪 base=3 在各种解释下分别是什么")
    print("=" * 74)
    base = 3
    print(f"  观测值：base = {base}，medal = 3（你已通关 AIR）")
    print()
    print("  解释 A —— 段位序号（Ⅰ=1 Ⅱ=2 Ⅲ=3 Ⅳ=4 Ⅴ=5 ∞=6）")
    hits = [k for k, s in SEQ.items() if s == base]
    print(f"    -> {'CLASS ' + '、'.join(hits) if hits else '无匹配'}")
    print("       含义可能是「最高已通关段位」，也可能是「最近通关段位」")
    print()
    print("  解释 B —— 游戏内部 difficulty.id")
    hits = [INTERNAL_ID_LABEL[d] for d in INTERNAL_ID_LABEL if d == base]
    print(f"    -> {'CLASS ' + '、'.join(hits) if hits else '无匹配（内部 id 只有 10/11/12/13/14/20）'}")
    print()
    print("  解释 C —— classes.json 的 level 字段（我们自己的编号）")
    hits = [str(c.get("key")) for c in cls.get("classes", []) if c.get("level") == base]
    print(f"    -> {'CLASS ' + '、'.join(hits) if hits else '无匹配'}")
    print("       ⚠ 这只是**我们**的排序编号，不是游戏数据，不能当证据")
    print()
    print("  解释 D —— 位掩码（每个已通关段位占一位）")
    print("    -> base=3 = 二进制 11")
    print("       若「每个段位一位、从 bit0 起」：通 Ⅰ=1、Ⅱ=2、Ⅲ=4、Ⅳ=8…")
    print("       你只通一个段位，那就该是 2 的幂（1/2/4/8/16/32），而实际是 3。")
    print("       ⚠ 但这**不能**据此排除掩码：也可能 bit0=「有缎带」、")
    print("         bit1..=段位，或编号不从 bit0 起。一个观测定不了掩码的位定义。")

    print()
    print("=" * 74)
    print("结论：AIR 门怎么自动判定")
    print("=" * 74)
    print("""
  好消息：**不需要**解开上面那个歧义，AIR 门就能自动判定。

  AIR 的条件是「任一 CLASS 内所有组曲通关」—— 也就是「至少拿到一个缎带」。
  所以判据只需要回答「有没有缎带」，不需要知道是哪个段位：

      base > 0   →  有缎带  →  AIR 门解锁
      base == 0  →  没缎带  →  未解锁

  这和文档对 base 的描述（「缎带（通关该组别全部课题组），默认值为 0」）
  完全一致：默认 0 = 没有，非 0 = 有。

  ⚠ 但有一个前提必须验证：**通第二个段位时 base 不能变小或归零**。
     如果 base 表示「最近通关的段位」而你之后通了一个更低序号以外的段位，
     它可能变化 —— 不过只要它保持 > 0，判定依然正确。

  medal 也可以做**交叉验证**：MEDAL 是「通关任意一组」（单个组曲）。
  你现在 base=3、medal=3。两个字段同时从 0 变 3，符合「同一套序号」。

  要彻底确认，只需要一个额外观测：**再通一个不同段位**，看 base 是否
  仍 > 0。这是唯一能把「base>0 = 有缎带」钉死的实验。
""")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
