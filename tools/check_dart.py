#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
静态粗查（无 Dart 分析器时的兜底）：

  1. 跨文件的类型引用是否都有对应 import
     （错误样例：`Undefined class 'MetaTable'`）
  2. 对「已知是项目内类型的变量」的成员访问，该成员是否真的存在
     （错误样例：`The getter 'judges' isn't defined for the type 'GateLinkLevels'`）

第 2 项是有限的启发式检查：只处理「变量类型能在同文件或 import 里解析到」的情况，
不追求覆盖全部 Dart 语义。目标是抓出我写错字段名/挂错层这类错误——
在无法本地跑 flutter analyze 的前提下，这类错误以前只能靠 CI 兜。

用法：
    python tools/check_dart.py
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
    """去掉注释与字符串字面量，避免里面的词造成误报。

    注意：import 路径是字符串字面量，会被一起清掉，
    所以提取 import 必须用原始源码，不能用这个结果。
    """
    src = re.sub(r"/\*.*?\*/", " ", src, flags=re.S)
    src = re.sub(r"//[^\n]*", " ", src)
    src = re.sub(r"'''.*?'''", " '' ", src, flags=re.S)
    src = re.sub(r'""".*?"""', ' "" ', src, flags=re.S)
    src = re.sub(r"'(?:\\.|[^'\\])*'", " '' ", src)
    src = re.sub(r'"(?:\\.|[^"\\])*"', ' "" ', src)
    return src


def lib_prefix_for(path: Path) -> str:
    """计算 lib/ 内部相对 import 的前缀深度。"""
    try:
        rel = path.relative_to(ROOT / "lib")
    except ValueError:
        return "../lib/"
    depth = len(rel.parts) - 1  # 减去文件名本身
    return "../" * depth if depth else ""


class DartIndex:
    """一个文件里定义的类型及其成员。"""

    def __init__(self) -> None:
        self.members: dict[str, set[str]] = {}
        self.super_of: dict[str, str] = {}


def parse_indexes(files: list[Path], sources: dict[Path, str]) -> dict[str, DartIndex]:
    """收集所有文件里定义的类型、成员、以及继承关系。"""
    out: dict[str, DartIndex] = {}
    for f in files:
        src = sources[f]
        idx = DartIndex()
        # 逐个类型块解析：从 class X ... { 到匹配的右括号
        for m in re.finditer(
            r"^(?:abstract\s+|sealed\s+|final\s+)?class\s+(\w+)(?:\s+extends\s+([\w<>,\s]+?))?"
            r"(?:\s+with\s+[\w<>,\s]+?)?\s*\{",
            src,
            re.M,
        ):
            name = m.group(1)
            end = _match_brace(src, m.end() - 1)
            body = src[m.end():end]
            idx.members[name] = _members_of(body)
            if m.group(2):
                idx.super_of[name] = m.group(2).strip().split("<")[0].strip()
        out[f.as_posix()] = idx
    return out


def _match_brace(src: str, open_pos: int) -> int:
    depth = 0
    for i in range(open_pos, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return i
    return len(src)


def _members_of(body: str) -> set[str]:
    """找出类体里的字段与 getter 名。

    覆盖：
      final Map<String, String> judges = ...
      String? get note => ...
      late bool _open = ...
      const Foo({required this.bar});   -> bar
      this.baz,
    """
    members: set[str] = set()

    # 字段声明：修饰符 + 类型 + 名字（可能多个，逗号分隔）
    for m in re.finditer(
        r"^\s*(?:static\s+|final\s+|const\s+|late\s+|covariant\s+)*"
        r"(?:[A-Za-z_][\w<>,\s\?]*?)\s+([a-zA-Z_]\w*)\s*(?:=|;|\{)",
        body,
        re.M,
    ):
        members.add(m.group(1))

    # getter： T get name
    for m in re.finditer(r"\bget\s+([a-zA-Z_]\w*)", body):
        members.add(m.group(1))

    # 构造函数里的 this.xxx
    for m in re.finditer(r"\bthis\.([a-zA-Z_]\w*)", body):
        members.add(m.group(1))

    # 方法定义： 返回类型 name(
    for m in re.finditer(r"^\s*(?:[A-Za-z_][\w<>,\s\?\[\]]*?)\s+([a-zA-Z_]\w*)\s*\(", body, re.M):
        members.add(m.group(1))

    return members


def main() -> int:
    files = sorted(p for d in DIRS if d.exists() for p in d.rglob("*.dart"))
    if not files:
        print("找不到 dart 文件")
        return 1
    raw: dict[Path, str] = {}
    clean: dict[Path, str] = {}
    for f in files:
        text = f.read_text(encoding="utf-8")
        raw[f] = text
        clean[f] = strip_comments(text)

    # ---------------- 1. import 完整性 ----------------
    defs: dict[str, Path] = {}
    for f in files:
        for m in re.finditer(
            r"^\s*(?:abstract\s+|sealed\s+|final\s+)?(?:class|enum|mixin|typedef)\s+(\w+)",
            clean[f],
            re.M,
        ):
            defs.setdefault(m.group(1), f)

    imports_of: dict[Path, set[str]] = {}
    for f in files:
        paths = re.findall(r"""^import\s+['"]([^'"]+)['"]""", raw[f], re.M)
        imports_of[f] = {Path(p).stem for p in paths}

    import_problems: list[str] = []
    for name, def_file in sorted(defs.items()):
        if name.startswith("_"):
            continue
        for f in files:
            if f == def_file:
                continue
            if not re.search(rf"\b{re.escape(name)}\b", clean[f]):
                continue
            if def_file.stem not in imports_of[f]:
                import_problems.append(
                    f"  ✗ {name} 定义于 {def_file.relative_to(ROOT).as_posix()}，"
                    f"{f.relative_to(ROOT).as_posix()} 用了它但没 import '{def_file.stem}'"
                )

    # ---------------- 2. 成员访问 ----------------
    indexes: dict[str, set[str]] = {}   # 类型名 -> 成员集合（含继承）
    super_of: dict[str, str] = {}
    for f in files:
        idx = parse_indexes([f], clean)[f.as_posix()]
        for tname, mem in idx.members.items():
            indexes.setdefault(tname, set()).update(mem)
        super_of.update(idx.super_of)

    # 把父类成员并进来（一层即可满足本项目）。
    #
    # 对于继承自 Flutter 框架的类（ChangeNotifier / State 等），父类在
    # package:flutter 里，本索引看不到，所以手工补一份常用成员，
    # 否则 `store.addListener(...)` 这类会变成误报——
    # 检查器有误报比没有检查更糟，会引导去改本来正确的代码。
    FRAMEWORK_MEMBERS: dict[str, set[str]] = {
        "ChangeNotifier": {
            "addListener", "removeListener", "notifyListeners", "dispose", "hasListeners",
        },
        "State": {
            "build", "initState", "dispose", "setState", "didChangeDependencies",
            "didUpdateWidget", "deactivate", "context", "mounted", "widget",
        },
        "StatelessWidget": {"build", "createElement"},
        "StatefulWidget": {"createState", "createElement"},
        "InheritedWidget": {"updateShouldNotify"},
    }
    for tname, parent in super_of.items():
        if parent in indexes and tname in indexes:
            indexes[tname] |= indexes[parent]
        if parent in FRAMEWORK_MEMBERS and tname in indexes:
            indexes[tname] |= FRAMEWORK_MEMBERS[parent]

    # 收集「变量名 -> 类型名」
    #
    # 两个刻意的限制，都是为了压掉误报（误报比不检查更糟，会引导去改正确的代码）：
    #
    # ① 只收**可空**类型（`Foo? name`）。
    #    可空变量的成员访问必须用 `?.` 处理，是「字段名写错/挂错层」的高发区，
    #    也正是本检查要抓的 `linkLevels?.judges` 那一类。
    #    非空变量常出现在 `for (final t in list)` 这种推断场景，
    #    推断出的类型未必等于真实元素类型，容易误报。
    # ② 跳过单字母类型名——那是泛型参数（`T`、`E`），不是真实的类。
    var_types: dict[Path, dict[str, str]] = {}
    decl_re = re.compile(
        r"(?:(?:final|const|late|var|static|required|covariant)\s+)*"
        r"([A-Z]\w*)(\??)\s+([a-z_]\w*)\s*(?:=|;|,|\)|\})"
    )
    for f in files:
        vt: dict[str, str] = {}
        for m in decl_re.finditer(clean[f]):
            tname, nullable, vname = m.group(1), m.group(2), m.group(3)
            if nullable != "?":
                continue
            if len(tname) <= 1:
                continue
            if tname in indexes:
                vt[vname] = tname
        var_types[f] = vt

    member_problems: list[str] = []
    for f in files:
        src = clean[f]
        for vname, tname in var_types[f].items():
            known = indexes.get(tname, set())
            if not known:
                continue
            for m in re.finditer(
                rf"\b{re.escape(vname)}\s*(?:\?\.|\.)\s*([a-zA-Z_]\w*)", src
            ):
                member = m.group(1)
                if member in known:
                    continue
                # 过滤掉明显是链式调用后跟括号的情况（方法名未收录时会有噪声）
                line_no = src[: m.start()].count("\n") + 1
                member_problems.append(
                    f"  ✗ {f.relative_to(ROOT).as_posix()}:{line_no}  "
                    f"'{vname}' 是 {tname}，但它没有成员 '{member}'"
                )

    # 去重（同一处可能被多个正则命中）
    member_problems = sorted(set(member_problems))

    # ---------------- 输出 ----------------
    print(f"扫描 {len(files)} 个 dart 文件，{len(defs)} 个类型定义，"
          f"{len(var_types)} 个文件有可解析的变量类型\n")

    ok = True
    if import_problems:
        ok = False
        print("❌ 缺少 import：")
        print("\n".join(import_problems))
        print()
    else:
        print("✅ 跨文件类型引用都有对应 import")

    if member_problems:
        ok = False
        print("\n❌ 成员访问错误（字段名写错或字段挂错类）：")
        print("\n".join(member_problems))
    else:
        print("✅ 已知类型的成员访问都有效")

    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
