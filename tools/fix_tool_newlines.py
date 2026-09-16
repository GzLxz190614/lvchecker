#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把会写文件的 tools/*.py 统一改成**显式写 LF 换行**。

为什么必须这么做：
    仓库根有 `.gitattributes` 声明 `*.json text eol=lf`（还有 .py/.yml/.dart 等），
    目的是让所有平台上的换行符统一成 LF。

    但 Python 的 `Path.write_text()` 在 Windows 上默认会做换行翻译：
    `\n` 被写成 `\r\n`。于是：
      * 工作区文件是 CRLF，而 git 索引里存的是 LF；
      * 每次改动 git 都警告「CRLF will be replaced by LF」；
      * diff 里混进大量行尾变化，掩盖真正的改动；
      * 更阴的是**热更新**：`data_sync.dart` 是拿文本直接和缓存比的，
        换个平台跑一次 build.py 就可能让所有用户白下一次数据。

    修法是给 write_text 加 `newline="\\n"`，它会让 Python 不做翻译。
    （不能靠 `core.autocrlf`：实测本机是 false，但 Python 自己就会翻译，
      所以必须在代码里显式指定。）

这个脚本只改**真正会写文件的**调用，跳过自检用的临时文件
（那些写在 tempfile 目录里，行尾无所谓）。

用法：
    python tools/fix_tool_newlines.py            # 改
    python tools/fix_tool_newlines.py --dry-run  # 只看会改哪些
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

TOOLS = Path(__file__).resolve().parent


def add_newline_arg(src: str) -> tuple[str, int]:
    """给 write_text(...) 调用补上 newline="\\n"。返回 (新源码, 改动数)。

    用括号配平来定位调用的结尾，而不是正则去匹配参数 ——
    参数里可能有嵌套的括号和字符串，正则很容易切错。
    """
    out = []
    i = 0
    changed = 0

    while True:
        j = src.find(".write_text(", i)
        if j < 0:
            out.append(src[i:])
            break

        # 找到左括号，然后配平到对应的右括号
        k = j + len(".write_text(")
        depth = 1
        quote = None
        while k < len(src) and depth > 0:
            ch = src[k]
            if quote:
                if ch == "\\":
                    k += 2
                    continue
                if ch == quote:
                    quote = None
            elif ch in "\"'":
                quote = ch
            elif ch in "([{":
                depth += 1
            elif ch in ")]}":
                depth -= 1
            k += 1

        call = src[j:k]          # 含 .write_text(...)
        inner = call[len(".write_text("):-1]

        out.append(src[i:j])
        if "newline=" in inner:
            out.append(call)     # 已经有了，不动
        else:
            # 在最后一个参数后面追加。保持单行调用的可读性。
            new_inner = inner.rstrip()
            sep = "" if new_inner.endswith(",") else ","
            out.append(f".write_text({new_inner}{sep} newline=\"\\n\")")
            changed += 1

        i = k

    return "".join(out), changed


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    total = 0
    for path in sorted(TOOLS.glob("*.py")):
        if path.name == Path(__file__).name:
            continue
        src = path.read_text(encoding="utf-8")
        if ".write_text(" not in src:
            continue
        new, n = add_newline_arg(src)
        if n == 0:
            continue
        total += n
        print(f"  {path.name}: {n} 处 write_text 补上 newline")
        if not args.dry_run:
            path.write_text(new, encoding="utf-8", newline="\n")

    print()
    if total == 0:
        print("✓ 没有需要改的（都已经显式写 LF）")
    elif args.dry_run:
        print(f"（--dry-run）共 {total} 处待改")
    else:
        print(f"✓ 共改了 {total} 处")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
