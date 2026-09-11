"""静态粗查：跨文件的类型引用是否都有对应 import。

这是我自己写的兜底检查——因为无法在本地跑 flutter analyze，
至少用脚本把「删错 import」这类错误抓出来（上一次就是这么挂的）。

用法：
    python tools/check_imports.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIRS = [ROOT / "lib", ROOT / "test"]

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass


def strip_comments(src: str) -> str:
    """去掉 // 行注释、/* */ 块注释和字符串字面量，避免注释里的词造成误报。"""
    src = re.sub(r"/\*.*?\*/", " ", src, flags=re.S)
    src = re.sub(r"//[^\n]*", " ", src)
    # 去掉字符串（含三引号）
    src = re.sub(r"'''.*?'''", " '' ", src, flags=re.S)
    src = re.sub(r'""".*?"""', ' "" ', src, flags=re.S)
    src = re.sub(r"'(?:\\.|[^'\\])*'", " '' ", src)
    src = re.sub(r'"(?:\\.|[^"\\])*"', ' "" ', src)
    return src


def main() -> int:
    files = sorted(p for d in DIRS if d.exists() for p in d.rglob("*.dart"))
    if not files:
        print("找不到 dart 文件")
        return 1

    sources: dict[Path, str] = {}
    raw: dict[Path, str] = {}
    for f in files:
        text = f.read_text(encoding="utf-8")
        raw[f] = text
        sources[f] = strip_comments(text)

    # 从「原始源码」提取 import。
    # 注意不能用 strip_comments 的结果：它会把字符串字面量换成 ''，
    # 而 import 的路径正好是字符串字面量，会被一起吃掉。
    imports_of: dict[Path, set[str]] = {}
    for f in files:
        paths = re.findall(r"""^import\s+['"]([^'"]+)['"]""", raw[f], re.M)
        imports_of[f] = {Path(p).stem for p in paths}

    # 收集定义：class / enum / mixin / typedef
    defs: dict[str, Path] = {}
    for f, src in sources.items():
        for m in re.finditer(r"^\s*(?:abstract\s+|sealed\s+|final\s+)?(?:class|enum|mixin|typedef)\s+(\w+)", src, re.M):
            name = m.group(1)
            defs.setdefault(name, f)

    problems: list[str] = []

    for name, def_file in sorted(defs.items()):
        if name.startswith("_"):
            continue  # 私有的只在同文件用
        for f, src in sources.items():
            if f == def_file:
                continue
            if not re.search(rf"\b{re.escape(name)}\b", src):
                continue
            if def_file.stem not in imports_of[f]:
                rel_u = f.relative_to(ROOT).as_posix()
                rel_d = def_file.relative_to(ROOT).as_posix()
                problems.append(
                    f"  ✗ {name} 定义于 {rel_d}，{rel_u} 用了它但没 import '{def_file.stem}'"
                )

    # 反向检查：import 了但完全没用到（info 级，不致命）
    unused: list[str] = []
    for f, src in sources.items():
        # import 行本身要去掉，否则路径里的词会被误当成使用
        body = re.sub(r"""^import\s+['"][^'"]+['"];?\s*$""", "", src, flags=re.M)
        for imp in sorted(imports_of[f]):
            if imp in ("material", "widgets", "services", "foundation", "main"):
                continue
            target = next((p for p in files if p.stem == imp), None)
            if target is None:
                continue
            names = re.findall(
                r"^(?:abstract\s+|sealed\s+|final\s+)?(?:class|enum|mixin|typedef)\s+(\w+)",
                sources[target], re.M,
            )
            names += re.findall(r"^(?:const|final|var)\s+(\w+)", sources[target], re.M)
            if not names:
                continue
            if not any(re.search(rf"\b{re.escape(n)}\b", body) for n in names):
                rel = f.relative_to(ROOT).as_posix()
                unused.append(f"  · {rel} 导入了 '{imp}.dart' 但似乎没用到其中任何公开名字")

    print(f"扫描 {len(files)} 个 dart 文件，找到 {len(defs)} 个类型定义\n")

    if problems:
        print("❌ 缺少 import（会导致 undefined_class 编译失败）：")
        print("\n".join(problems))
    else:
        print("✅ 所有跨文件类型引用都有对应 import")

    if unused:
        print("\n⚠️ 可能多余的 import（只是提示，不影响构建）：")
        print("\n".join(unused))

    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
