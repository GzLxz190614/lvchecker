#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
校验 tools/ 和 test/ 下所有 Python 脚本的语法，以及几个关键不变量。

为什么需要它：本地没有 Python 语法检查的自动化入口
（`check_dart.py` 只管 Dart），而我改脚本时出过好几次
「引号转义写错导致整个脚本语法错误」的事 —— 那种错误如果推到 CI 才发现，
就白烧一轮构建。这个脚本让这类问题在本地立刻暴露。

检查项：
  1. tools/**/*.py 和 test/**/*.py 都能被 ast 解析；
  2. 会写文件的脚本都显式写了 newline="\\n"
     （否则 Windows 上会产生 CRLF，和 .gitattributes 的 eol=lf 冲突，
       热更新还会因此白下一次数据 —— 见 tools/fix_tool_newlines.py 的说明）。

用法：
    python tools/check_python_syntax.py
退出码 0 = 通过，1 = 有问题。
"""

from __future__ import annotations

import ast
import re
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

ROOT = Path(__file__).resolve().parent.parent
DIRS = [ROOT / "tools", ROOT / "test"]

# 这些脚本写的是：临时自检文件、或本来就是 CRLF 的平台文件
# （gradle/Windows 相关）。不做 newline 检查。
NEWLINE_EXEMPT = {
    "fix_tool_newlines.py",  # 它自己就是干这个的
    "check_python_syntax.py",
    "_tmp_mhtml.py",  # 一次性探针，不进仓库
}


def main() -> int:
    files = sorted(p for d in DIRS if d.exists() for p in d.rglob("*.py"))
    if not files:
        print("✗ 一个 python 文件都没找到")
        return 1

    syntax_errors: list[str] = []
    newline_warnings: list[str] = []

    for p in files:
        src = p.read_text(encoding="utf-8")
        rel = p.relative_to(ROOT).as_posix()

        try:
            ast.parse(src, filename=rel)
        except SyntaxError as e:
            syntax_errors.append(f"{rel}:{e.lineno}: {e.msg}")
            continue

        if p.name in NEWLINE_EXEMPT:
            continue

        # 找没带 newline= 的 write_text 调用
        for m in re.finditer(r"\.write_text\(", src):
            # 往后找配平的括号，看这一段里有没有 newline=
            k = m.end()
            depth, quote = 1, None
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
            inner = src[m.end():k - 1]
            if "newline=" not in inner:
                line = src[:m.start()].count("\n") + 1
                newline_warnings.append(f"{rel}:{line}: write_text 没有显式 newline=")

    print(f"扫描 {len(files)} 个 python 文件")
    print()

    if syntax_errors:
        print(f"✗ 语法错误 {len(syntax_errors)} 处：")
        for e in syntax_errors:
            print(f"  {e}")
    else:
        print("✓ 语法全部通过")

    if newline_warnings:
        print()
        print(f"⚠ {len(newline_warnings)} 处 write_text 没写 newline=\"\\n\"：")
        for w in newline_warnings:
            print(f"  {w}")
        print("  （Windows 上会写出 CRLF，和 .gitattributes 的 eol=lf 冲突；")
        print("    跑 `python tools/fix_tool_newlines.py` 可自动修）")

    if syntax_errors:
        return 1
    # newline 问题只警告、不失败：万一某个调用确实需要平台默认换行，
    # 不应该因此让整个 CI 红掉。语法错误才是硬失败。
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
