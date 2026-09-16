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
import re
import sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

SIGNING_NAME = "release"

# ⚠️ 判断「有没有 signingConfigs 块」**不能用 `"signingConfigs" in text`**。
#
# Flutter 模板的 release 块里本来就有这么一句：
#     signingConfig = signingConfigs.getByName("debug")
# 所以 `"signingConfigs" in text` 永远是 True，我第一次就是这么写的，
# 结果注入被整个跳过，而脚本还报「已就绪」—— 又是一次假绿勾。
# 必须匹配真正的**块声明**。
_HAVE_BLOCK_KTS = re.compile(r"signingConfigs\s*\{")
_HAVE_BLOCK_GROOVY = re.compile(r"signingConfigs\s*\{")


def patch_kts(text: str) -> tuple[str, str]:
    """Kotlin DSL 版本。返回 (新内容, 说明)。"""
    if _HAVE_BLOCK_KTS.search(text):
        return text, "已有 signingConfigs 块，跳过注入"

    m = re.search(r"^([ \t]*)buildTypes\s*\{", text, re.MULTILINE)
    if not m:
        raise SystemExit("build.gradle.kts 里找不到 buildTypes 块 —— 模板变了")
    indent = m.group(1)
    pos = m.start()

    block = (
        f"{indent}signingConfigs {{\n"
        f"{indent}    // release 用固定的 keystore（口令从 android/key.properties 读，不进 git）。\n"
        f"{indent}    // 见 tools/setup_android_signing.py 顶部说明：签名不固定会导致\n"
        f"{indent}    // 「装新版必须先卸载」，而卸载会清掉本机进度。\n"
        f"{indent}    create(\"{SIGNING_NAME}\") {{\n"
        f"{indent}        val props = java.util.Properties()\n"
        f"{indent}        val f = rootProject.file(\"key.properties\")\n"
        f"{indent}        if (f.exists()) f.inputStream().use {{ props.load(it) }}\n"
        f"{indent}        storeFile = props.getProperty(\"storeFile\")?.let {{ file(it) }}\n"
        f"{indent}        storePassword = props.getProperty(\"storePassword\")\n"
        f"{indent}        keyAlias = props.getProperty(\"keyAlias\")\n"
        f"{indent}        keyPassword = props.getProperty(\"keyPassword\")\n"
        f"{indent}    }}\n"
        f"{indent}}}\n"
        f"\n"
    )
    text = text[:pos] + block + text[pos:]
    return text, "已注入 signingConfigs（Kotlin DSL）"


def patch_groovy(text: str) -> tuple[str, str]:
    """旧 Groovy DSL 版本（flutter create 老版本会生成 build.gradle）。"""
    if _HAVE_BLOCK_GROOVY.search(text):
        return text, "已有 signingConfigs 块，跳过注入"

    m = re.search(r"^([ \t]*)buildTypes\s*\{", text, re.MULTILINE)
    if not m:
        raise SystemExit("build.gradle 里找不到 buildTypes 块 —— 模板变了")
    indent = m.group(1)
    pos = m.start()

    block = (
        f"{indent}signingConfigs {{\n"
        f"{indent}    release {{\n"
        f"{indent}        def props = new Properties()\n"
        f"{indent}        def f = rootProject.file('key.properties')\n"
        f"{indent}        if (f.exists()) {{ props.load(new FileInputStream(f)) }}\n"
        f"{indent}        storeFile = props['storeFile'] ? file(props['storeFile']) : null\n"
        f"{indent}        storePassword = props['storePassword']\n"
        f"{indent}        keyAlias = props['keyAlias']\n"
        f"{indent}        keyPassword = props['keyPassword']\n"
        f"{indent}    }}\n"
        f"{indent}}}\n"
        f"\n"
    )
    text = text[:pos] + block + text[pos:]
    return text, "已注入 signingConfigs（Groovy DSL）"


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

    # android/key.properties —— 与 android/app 同级，rootProject.file() 才找得到
    props.parent.mkdir(parents=True, exist_ok=True)
    store_rel = keystore.name if keystore.parent.resolve() == props.parent.resolve() else str(keystore)
    props.write_text(
        "# 由 tools/setup_android_signing.py 生成 —— 内含签名口令，**绝不进 git**\n"
        f"storeFile={store_rel}\n"
        f"storePassword={args.store_password}\n"
        f"keyAlias={args.key_alias}\n"
        f"keyPassword={args.key_password}\n",
        encoding="utf-8",
    )
    print(f"已写 {props}（storeFile={store_rel}）")

    text = target.read_text(encoding="utf-8")
    notes = []

    text, note = patch_kts(text) if is_kts else patch_groovy(text)
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
