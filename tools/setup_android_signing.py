#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
给 `flutter create` 生成的 android/app/build.gradle(.kts) 加上**固定的 release 签名**。

## 为什么必须有这个（这是「装新版要卸载、进度全丢」的根因）

CI 里没有配任何签名，`flutter build apk --release` 就会用 **debug keystore** 签名。
而 GitHub Actions 每次跑都是**全新机器** —— 那个 debug keystore 每次都重新随机生成。

Android 规定：**签名不同的 APK 不能覆盖安装**，只能先卸载。
于是「装新版」变成「卸载 → 重装」，而 SharedPreferences（你的打勾进度）
存在应用私有目录里，卸载就一起没了。

**版本号解决不了这个问题** —— 签名不固定的话，改多大版本号都得卸载重装。

## 做法

从仓库 Secret 解出 keystore 与口令（写在 android/key.properties，不进 git），
再把 signingConfigs 注入 gradle：

    signingConfigs { create("release") { ... } }     或
    signingConfigs { release { ... } }               （旧 Groovy 写法）
    buildTypes { release { signingConfig = signingConfigs.getByName("release") } }

两种模板都支持，并且**改完会断言**：没注入成功就直接失败，
免得又出一个签名错的包（那种失败只有装到手机上才发现）。

用法：
    python tools/setup_android_signing.py \
        --keystore android/app/release.jks \
        --props android/key.properties \
        --key-alias lvchecker
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

SIGNING_NAME = "release"


def unescape_kotlin(s: str) -> str:
    """
    把从 gradle 文件里读到的字符串字面量内容还原成真实字符串。

    为什么需要：在 Windows 上路径全是反斜杠，写进 Kotlin 字符串时会成为 `\\\\`
    （我用的是原始字符串 r"..."，所以其实是原样的单个反斜杠；
    但如果将来改回普通字符串就会是双写）。这里统一反转义，
    这样断言在 Windows 和 Linux 上都能正确比对 —— 否则会出现
    「注入正确但断言误报」的假失败（我第一版就是这样）。
    """
    return s.replace("\\\\", "\\")

# ⚠️ 判断「有没有 signingConfigs 块」**不能用 `"signingConfigs" in text`**。
#
# Flutter 模板的 release 块里本来就有这么一句：
#     signingConfig = signingConfigs.getByName("debug")
# 所以 `"signingConfigs" in text` 永远是 True，我第一次就是这么写的，
# 结果注入被整个跳过，而脚本还报「已就绪」—— 又是一次假绿勾。
# 必须匹配真正的**块声明**。
_HAVE_BLOCK_KTS = re.compile(r"signingConfigs\s*\{")
_HAVE_BLOCK_GROOVY = re.compile(r"signingConfigs\s*\{")


def ensure_kts_imports(text: str) -> tuple[str, str]:
    """
    在 .kts 文件顶部补上 `import java.util.Properties` / `import java.io.FileInputStream`。

    为什么需要：注入的 signingConfigs 里要用这两个类，但**不能写全限定名** ——
    在 Gradle Kotlin DSL 里 `java` 会被解析成 Gradle 的 java 扩展而不是包名，
    `java.util.Properties()` 会报 `Unresolved reference: util`（实测踩过，
    整个构建失败）。显式 import 之后就能只用简单类名 `Properties()`。
    """
    needed = ["java.util.Properties", "java.io.FileInputStream"]
    missing = [n for n in needed if re.search(rf"^import\s+{re.escape(n)}\s*$", text, re.MULTILINE) is None]
    if not missing:
        return text, "import 已存在，跳过"

    # 插到第一行之前（import 必须出现在文件顶部，Kotlin 要求在所有声明之前）
    lines = "\n".join(f"import {n}" for n in needed)
    return f"{lines}\n\n{text}", f"已补 import: {', '.join(missing)}"


def patch_kts(text: str, keystore_abs: str) -> tuple[str, str]:
    """Kotlin DSL 版本。返回值里带 keystore 的**绝对路径**（见下）。"""
    if _HAVE_BLOCK_KTS.search(text):
        return text, "已有 signingConfigs 块，跳过注入"

    m = re.search(r"^([ \t]*)buildTypes\s*\{", text, re.MULTILINE)
    if not m:
        raise SystemExit("build.gradle.kts 里找不到 buildTypes 块 —— 模板变了")
    indent = m.group(1)
    pos = m.start()

    # ⚠️⚠️ storeFile 这里写**绝对路径**，而且**不经过 key.properties 中转**。
    #
    # 踩过的坑（两次 CI 失败）：
    #   `storeFile = file(cfg.getProperty("storeFile"))` 解析出来的位置取决于
    #   Gradle 把哪个目录当基准 —— 第二次 CI 报
    #       Keystore file '.../android/app/app/release.jks' not found
    #   说明它按 `android/app/` 解析，而不是我以为的 `android/`。
    #   而本机没有 Flutter/Gradle，我**没法在本地验证**基准目录到底是什么。
    #
    #   所以干脆不要那个基准：Python 脚本知道 keystore 的真实绝对路径
    #   （CI 里就是 runner 上的路径），直接写进来。绝对路径 Gradle 原样使用，
    #   不拼接、不需要 import、不受 rootProject 影响。
    #
    #   代价：这个文件是**每次构建现改的**（android/ 本身不入 git），
    #   所以路径写死没有可移植性问题。
    # ⚠️ 用**普通字符串**，不用 Kotlin 原始字符串 `r"..."`。
    #
    #   我上一版用了 `File(r"...")`，CI 报：
    #       Expecting ','    /    Unresolved reference: r
    #   原始字符串在这个位置没被接受。我本地没有 Kotlin 编译器，**验不了**语法，
    #   所以不冒险 —— 普通字符串是绝对安全的。
    #
    #   代价是要转义反斜杠（Windows 路径才有）。CI 跑在 Linux 上，路径里
    #   本来就没有反斜杠，转义是空操作；但保留它让脚本在 Windows 上也能用。
    escaped = keystore_abs.replace("\\", "\\\\")
    block = (
        f"{indent}signingConfigs {{\n"
        f"{indent}    // release 用固定的 keystore。\n"
        f"{indent}    // storeFile 用**绝对路径**（由 tools/setup_android_signing.py 写入）：\n"
        f"{indent}    // Gradle 对相对路径按哪个目录解析，在本机无法验证，已经踩过两次坑\n"
        f"{indent}    // （android/android/app/... 和 android/app/app/... 各一次）。\n"
        f"{indent}    // 绝对路径原样使用，不受 rootProject 影响。\n"
        f"{indent}    // 口令仍从 android/key.properties 读，不写在这个文件里。\n"
        f"{indent}    create(\"{SIGNING_NAME}\") {{\n"
        f"{indent}        storeFile = File(\"{escaped}\")\n"
        f"{indent}        val cfg = Properties()\n"
        f"{indent}        val f = rootProject.file(\"key.properties\")\n"
        f"{indent}        if (f.exists()) {{\n"
        f"{indent}            cfg.load(FileInputStream(f))\n"
        f"{indent}        }}\n"
        f"{indent}        storePassword = cfg.getProperty(\"storePassword\")\n"
        f"{indent}        keyAlias = cfg.getProperty(\"keyAlias\")\n"
        f"{indent}        keyPassword = cfg.getProperty(\"keyPassword\")\n"
        f"{indent}    }}\n"
        f"{indent}}}\n"
        f"\n"
    )
    text = text[:pos] + block + text[pos:]
    return text, "已注入 signingConfigs（Kotlin DSL，storeFile 绝对路径 + 口令读 key.properties）"


def patch_groovy(text: str, keystore_abs: str) -> tuple[str, str]:
    """旧 Groovy DSL 版本（flutter create 老版本会生成 build.gradle）。"""
    if _HAVE_BLOCK_GROOVY.search(text):
        return text, "已有 signingConfigs 块，跳过注入"

    m = re.search(r"^([ \t]*)buildTypes\s*\{", text, re.MULTILINE)
    if not m:
        raise SystemExit("build.gradle 里找不到 buildTypes 块 —— 模板变了")
    indent = m.group(1)
    pos = m.start()

    escaped = keystore_abs.replace("\\", "\\\\")
    block = (
        f"{indent}signingConfigs {{\n"
        f"{indent}    release {{\n"
        f"{indent}        // storeFile 用绝对路径（见 setup_android_signing.py 的说明：\n"
        f"{indent}        // Gradle 对相对路径的基准目录在本机无法验证，已踩过两次坑）\n"
        f"{indent}        storeFile = new File(\"{escaped}\")\n"
        f"{indent}        def props = new Properties()\n"
        f"{indent}        def f = rootProject.file('key.properties')\n"
        f"{indent}        if (f.exists()) {{ props.load(new FileInputStream(f)) }}\n"
        f"{indent}        storePassword = props['storePassword']\n"
        f"{indent}        keyAlias = props['keyAlias']\n"
        f"{indent}        keyPassword = props['keyPassword']\n"
        f"{indent}    }}\n"
        f"{indent}}}\n"
        f"\n"
    )
    text = text[:pos] + block + text[pos:]
    return text, "已注入 signingConfigs（Groovy DSL，storeFile 绝对路径）"


def wire_release(text: str, is_kts: bool) -> tuple[str, str]:
    """把 release buildType 指向 release 签名（替换掉模板里的 debug）。"""
    # 找 buildTypes { release {
    m = re.search(r"buildTypes\s*\{[\s\S]*?release\s*\{", text)
    if not m:
        raise SystemExit("找不到 buildTypes 里的 release 块 —— 模板变了")
    body_start = m.end()

    # 只在 release 块体内看（到第一个顶层 } 之前，粗略取 1500 字符）
    tail = text[body_start:body_start + 1500]

    if is_kts:
        # 已经是 release 了就不动
        if re.search(r'signingConfig\s*=\s*signingConfigs\.getByName\(\s*"release"\s*\)', tail):
            return text, "release 已指向 release 签名，跳过"
        # 模板默认：signingConfig = signingConfigs.getByName("debug")  -> 替换
        new_tail, n = re.subn(
            r'signingConfig\s*=\s*signingConfigs\.getByName\(\s*"debug"\s*\)',
            f'signingConfig = signingConfigs.getByName("{SIGNING_NAME}")',
            tail,
        )
    else:
        if re.search(r"signingConfig\s+signingConfigs\.release", tail):
            return text, "release 已指向 release 签名，跳过"
        new_tail, n = re.subn(
            r"signingConfig\s+signingConfigs\.debug",
            f"signingConfig signingConfigs.{SIGNING_NAME}",
            tail,
        )

    if n == 0:
        # 模板里没写 signingConfig（少见），那就插一行到 release 块开头
        indent_m = re.search(r"\n([ \t]*)", tail)
        indent = indent_m.group(1) if indent_m else "            "
        line = (
            f"\n{indent}signingConfig = signingConfigs.getByName(\"{SIGNING_NAME}\")"
            if is_kts
            else f"\n{indent}signingConfig signingConfigs.{SIGNING_NAME}"
        )
        return text[:body_start] + line + text[body_start:], "release 原本没有 signingConfig，已插入"

    text = text[:body_start] + new_tail + text[body_start + 1500:]
    return text, "已把 release 从 debug 签名换成 release 签名"


def main() -> int:
    ap = argparse.ArgumentParser(description="给 Android 配置固定的 release 签名")
    ap.add_argument("--app-dir", default="android/app", help="android/app 目录")
    ap.add_argument("--keystore", required=True, help="keystore 文件路径")
    ap.add_argument("--props", required=True, help="key.properties 路径")
    ap.add_argument("--key-alias", required=True)
    ap.add_argument("--store-password", required=True)
    ap.add_argument("--key-password", required=True)
    args = ap.parse_args()

    app_dir = Path(args.app_dir)
    keystore = Path(args.keystore)
    props = Path(args.props)

    if not keystore.exists():
        raise SystemExit(f"keystore 不存在：{keystore}（CI 里要先从 Secret 解出来）")
    if keystore.stat().st_size < 100:
        raise SystemExit(f"keystore 太小（{keystore.stat().st_size} 字节），大概是解 base64 失败了")

    # 找一个存在的 gradle 文件
    kts = app_dir / "build.gradle.kts"
    groovy = app_dir / "build.gradle"
    if kts.exists():
        target, is_kts = kts, True
    elif groovy.exists():
        target, is_kts = groovy, False
    else:
        raise SystemExit(f"{app_dir} 下找不到 build.gradle(.kts)")

    # android/key.properties —— 存口令用。
    #
    # ⚠️ 这里**不再写 storeFile**。原因：Gradle 对相对路径按哪个目录解析，
    #    在本机无法验证，已经踩过两次坑（`android/android/app/...` 和
    #    `android/app/app/...` 各一次 —— 同一份相对路径，我的脚本和 Gradle
    #    解析到了不同位置）。现在 keystore 的绝对路径直接写进 gradle，
    #    key.properties 只留口令，不再参与路径解析。
    props.parent.mkdir(parents=True, exist_ok=True)
    props.write_text(
        "# 由 tools/setup_android_signing.py 生成 —— 内含签名口令，**绝不进 git**\n"
        "# 注意：keystore 路径不在这个文件里（直接写在 build.gradle 的 storeFile，用绝对路径）\n"
        f"storePassword={args.store_password}\n"
        f"keyAlias={args.key_alias}\n"
        f"keyPassword={args.key_password}\n",
        encoding="utf-8",
    )
    print(f"已写 {props}（只含口令；keystore 绝对路径直接写进 gradle）")

    # keystore 的绝对路径 —— 直接注入 gradle，避开 Gradle 的路径基准问题
    keystore_abs = str(keystore.resolve())
    print(f"keystore 绝对路径：{keystore_abs}")

    text = target.read_text(encoding="utf-8")
    notes = []

    # Kotlin 需要在顶部 import（不能用全限定名，见 ensure_kts_imports 的说明）
    if is_kts:
        text, note = ensure_kts_imports(text)
        notes.append(note)

    text, note = patch_kts(text, keystore_abs) if is_kts else patch_groovy(text, keystore_abs)
    notes.append(note)
    text, note = wire_release(text, is_kts)
    notes.append(note)

    target.write_text(text, encoding="utf-8")
    for n in notes:
        print(f"  · {n}")

    # ---------- 断言：没生效就直接失败，别出一个签名错的包 ----------
    final = target.read_text(encoding="utf-8")
    problems = []
    if "signingConfigs" not in final:
        problems.append("没有 signingConfigs 块")
    if not re.search(r"buildTypes[\s\S]*?signingConfig", final):
        problems.append("release buildType 没有指向 signingConfig")

    if is_kts:
        # ★ 这两条是这次 CI 失败的直接原因，必须挡住：
        #   Gradle Kotlin DSL 里 `java` 不是包名，`java.util.Properties()` 会编译失败。
        #
        #   注意要**排除 import 行和注释行** ——
        #   `import java.util.Properties` 本身就含 `java.util.`，是合法的；
        #   注释里也可能提到它。只看真正的代码。
        offending = [
            (i, ln) for i, ln in enumerate(final.splitlines(), 1)
            if re.search(r"\bjava\s*\.\s*(util|io)\s*\.", ln)
            and not ln.lstrip().startswith("import ")
            and not ln.lstrip().startswith("//")
        ]
        if offending:
            problems.append(
                "注入的代码里用了全限定类名（java.util. / java.io.）—— "
                "Gradle Kotlin DSL 里 `java` 会被解析成 Gradle 扩展而不是包名，"
                "会报 Unresolved reference 导致构建失败。"
                f"位置：{offending}"
            )
        if "import java.util.Properties" not in final:
            problems.append("缺少 `import java.util.Properties`（Kotlin DSL 下必须显式 import）")
        if "Properties()" not in final:
            problems.append("signingConfigs 里没有构造 Properties()")

    # ★ storeFile 必须出现在 gradle 里、且是**绝对路径**。
    #
    #   这里踩过两次（同一份相对路径，我的脚本和 Gradle 解析到不同位置）：
    #     · storeFile=android/app/release.jks  ->  报 android/android/app/release.jks
    #     · storeFile=app/release.jks          ->  报 android/app/app/release.jks
    #   既然 Gradle 的基准目录在本机无法验证，就彻底不用相对路径。
    m = re.search(r'storeFile\s*=\s*(?:new\s+)?File\(\s*r?["\']([^"\']+)["\']\s*\)', final)
    if not m:
        problems.append(
            "gradle 里没有 `storeFile = File(\"<绝对路径>\")` —— "
            "相对路径的基准目录无法验证，必须用绝对路径"
        )
    else:
        written = unescape_kotlin(m.group(1))
        ok_abs = written.startswith("/") or re.match(r"^[A-Za-z]:[\\/]", written)
        if not ok_abs:
            problems.append(f"storeFile='{written}' 不是绝对路径")
        if written != keystore_abs:
            problems.append(
                f"storeFile 写的是 '{written}'，与 keystore 实际路径 '{keystore_abs}' 不一致"
            )
        # 真的去 stat 一遍，别只看字符串
        exists = Path(written).exists()
        if not exists:
            problems.append(f"storeFile 指向的 {written} 不存在")
        print(f"storeFile = {written}（绝对路径，存在={exists}）")

    print()
    print("----- gradle 关键行 -----")
    for i, line in enumerate(final.splitlines(), 1):
        if any(k in line for k in ("signingConfig", "buildTypes", "release {", 'create("release")')):
            print(f"{i:4}: {line}")

    if problems:
        print()
        print("❌ 签名配置没注入成功：")
        for p in problems:
            print(f"  ✗ {p}")
        print("   （签名不固定会导致「装新版必须先卸载」，卸载会清掉本机进度）")
        return 1

    print()
    print("✅ release 签名配置已就绪")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
