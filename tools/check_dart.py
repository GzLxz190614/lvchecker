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
    """去掉注释与字符串字面量，**保持行数不变**。

    早期版本用正则做替换，结果把 190 行压成了 92 行——
    因为处理跨行字符串时，`'...'` 的回退正则会跨行误匹配，把中间的换行一起吞掉。
    而后续的成员扫描是按行做的，行数一变，成员就全丢了（造成 8 处误报）。

    所以现在改成**逐字符扫描，遇到换行一律保留**：
    注释 / 字符串的内容被替换成空格，但 `\\n` 原样留着。
    这样行号与行结构都和原始文件一致。
    """
    out: list[str] = []
    i = 0
    n = len(src)
    while i < n:
        c = src[i]

        # 行注释：吃到最后，但保留换行本身
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            while i < n and src[i] != "\n":
                i += 1
            continue

        # 块注释：保留其中的换行
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            i += 2
            while i < n and not (src[i] == "*" and i + 1 < n and src[i + 1] == "/"):
                if src[i] == "\n":
                    out.append("\n")
                i += 1
            i += 2
            continue

        # 字符串：整段吃掉，但保留其中的换行
        if c in ("'", '"'):
            quote = c
            triple = src[i : i + 3] == quote * 3
            step = 3 if triple else 1
            i += step
            while i < n:
                if triple and src[i : i + 3] == quote * 3:
                    i += 3
                    break
                if not triple:
                    if src[i] == "\\":
                        i += 2
                        continue
                    if src[i] == quote:
                        i += 1
                        break
                if src[i] == "\n":
                    out.append("\n")
                i += 1
            continue

        out.append(c)
        i += 1

    return "".join(out)


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
    """找到与 open_pos 处 `{` 匹配的 `}`。

    必须**跳过字符串和注释里的括号**，否则会被字符串插值骗到——
    例如 `'${_dir.path}/$name'` 里的 `}` 会被误认为类体结束，
    导致后面的成员全部漏掉（这个 bug 让检查器误报了 8 处）。
    """
    depth = 0
    i = open_pos
    n = len(src)
    while i < n:
        c = src[i]

        # 行注释
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            j = src.find("\n", i)
            i = n if j < 0 else j + 1
            continue

        # 块注释
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue

        # 字符串（含插值：插值里的 {} 也要计入深度，但这里只需整体跳过更安全）
        if c in ("'", '"'):
            quote = c
            # 三引号
            if src[i : i + 3] == quote * 3:
                j = src.find(quote * 3, i + 3)
                i = n if j < 0 else j + 3
                continue
            i += 1
            while i < n:
                if src[i] == "\\":
                    i += 2
                    continue
                if src[i] == quote:
                    i += 1
                    break
                i += 1
            continue

        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return n


def _members_of(body: str) -> set[str]:
    """找出类体里的字段、getter、方法名。

    实现方式：**按行扫描 + 大括号水位**。
    只在水位 0（也就是类体直接成员）的层面上识别声明行，
    这样既不会把方法体里的局部变量当成字段，也不会漏掉方法名。

    比一开始用的一堆正则可靠得多：那种写法在
    `Future<SyncReport> sync() async {` 这类签名上会漏，
    而且会被字符串插值里的括号骗到。
    """
    members: set[str] = set()
    depth = 0

    for raw_line in body.split("\n"):
        line = raw_line.strip()
        if not line:
            continue

        # 在水位 0 的层面上识别声明
        if depth == 0:
            # 跳过注解、import、注释
            if line.startswith("@") or line.startswith("///") or line.startswith("//"):
                pass
            else:
                name = _decl_name(line)
                if name:
                    members.add(name)

        # 更新水位。用字符串感知的计数，避免被插值 / 字符串里的括号骗到。
        depth += _brace_delta(raw_line)
        if depth < 0:
            depth = 0

    return members


def _decl_name(line: str) -> str | None:
    """从一行「类体直接成员声明」里取出名字，取不到返回 None。"""
    # 构造函数里的 this.xxx
    m = re.search(r"\bthis\.([a-zA-Z_]\w*)", line)
    if m:
        return m.group(1)

    # getter：  int get foo => ...
    m = re.match(r"^[^=]*?\bget\s+([a-zA-Z_]\w*)", line)
    if m:
        return m.group(1)

    # 方法或字段： [修饰符] [返回类型] name  或  name(...)
    #
    # 去掉常见修饰符后，剩下形如 `Type name` / `Type name(` / `Type name =` / `Type name;`
    cleaned = line
    for kw in ("static", "final", "const", "late", "covariant", "external", "factory"):
        cleaned = re.sub(rf"^\s*{kw}\s+", "", cleaned)

    # 构造函数： ClassName(...) 或 ClassName._(...)  -> 不算新成员
    m = re.match(r"^([A-Z]\w*)(\.[a-zA-Z_]\w*)?\s*\(", cleaned)
    if m:
        return None

    # 返回类型 + 名字
    m = re.match(r"^[\w<>,\?\[\]\s]*?\b([a-zA-Z_]\w*)\s*(?:[=(;{]|$)", cleaned)
    if m:
        name = m.group(1)
        if name in ("return", "if", "for", "while", "switch", "case", "else", "try", "catch"):
            return None
        return name

    return None


def _brace_delta(line: str) -> int:
    """统计一行里净增的大括号数，跳过字符串与行注释。"""
    delta = 0
    i = 0
    n = len(line)
    while i < n:
        c = line[i]
        if c == "/" and i + 1 < n and line[i + 1] == "/":
            break  # 行注释，后面忽略
        if c in ("'", '"'):
            quote = c
            i += 1
            while i < n:
                if line[i] == "\\":
                    i += 2
                    continue
                if line[i] == quote:
                    i += 1
                    break
                i += 1
            continue
        if c == "{":
            delta += 1
        elif c == "}":
            delta -= 1
        i += 1
    return delta


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

    # ---------------- 3. 语句位置的 collection-if 展开 ----------------
    #
    # Dart 的展开语法 `if (cond) ...[a, b]` **只能用在集合字面量里**。
    # 写在方法体（语句位置）时会报一串莫名其妙的错：
    #   Expected an identifier / Expected to find ']' / Expected a class member
    # 而括号计数是平衡的（`[` 与 `]` 配对，只是位置非法），所以数括号抓不到。
    #
    # 这个写法很容易在把「集合字面量」改写成「先建 list 再 add」时残留下来。
    #
    # 只检测**确切的反模式**：`xxx.add(` 之后紧跟 `if (...) ...[`。
    # 不去泛泛地找 `) ...[`——那在 `children: [ if (x) ...[...] ]` 里是合法的，
    # 泛化检测会满屏误报（试过，误报 13 处）。
    spread_problems: list[str] = []
    # 反模式的确切形状（`if` 在前、`.add(` 在后）：
    #     if (sync != null && sync.hasCache) ...[
    #       children.add(const SizedBox(height: 8));
    #       ...
    #     ]
    # 注意 `\.\.\.\s*\[`：`...` 与 `[` 之间**可能有空格**，写成紧邻会漏掉真实案例。
    spread_re = re.compile(r"\)\s*\.\.\.\s*\[")
    for f in files:
        lines = clean[f].split("\n")
        for i in range(1, len(lines)):
            if spread_re.search(lines[i - 1]) and ".add(" in lines[i]:
                spread_problems.append(
                    f"  ✗ {f.relative_to(ROOT).as_posix()}:{i}  "
                    f"上一行用了 'if (...) ...[...]'（语句位置不能展开），"
                    f"下一行却在 `.add(`。改成普通 if 语句 + 逐个 add。"
                )

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

    if spread_problems:
        ok = False
        print("\n❌ 语法错误（`.add(` 之后用了展开语法）：")
        print("\n".join(spread_problems))
    else:
        print("✅ 没有语句位置的展开语法误用")

    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
