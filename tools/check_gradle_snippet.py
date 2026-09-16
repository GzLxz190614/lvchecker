#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
静态检查 `tools/setup_android_signing.py` **会生成什么样的 Kotlin 代码**，
把「语法层面就能看出不对」的问题挡在构建之前。

## 为什么需要

签名那几步我连着踩了三次，都是「生成的 Kotlin 语法在 CI 上编译不过」：

  ① `java.util.Properties()`      -> Unresolved reference: util
  ② （路径基准问题，不是语法）
  ③ `File(r"...")`               -> Expecting ',' / Unresolved reference: r

问题在于**本机没有 Kotlin/Gradle，我验不了语法**，只能推 CI 才知道。
这个脚本把能静态判定的部分挡住：
  · 字符串字面量里不能出现裸的 `r"`（普通字符串里读起来就是 r 后跟引号）
  · `"` 必须成对（排除注释行）—— 漏一个引号会让整个文件解析失败
  · 注入的代码里不能出现全限定类名 java.util./java.io.
  · storeFile 必须是绝对路径

它**不能**替代真正的 Kotlin 编译器，只挡这几类已知的错。

用法：
    python tools/check_gradle_snippet.py
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

KTS_TEMPLATE = '''plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.gzlxz190614.lvchecker"

    defaultConfig {
        applicationId = "io.github.gzlxz190614.lvchecker"
        minSdk = 29
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
'''

GROOVY_TEMPLATE = '''apply plugin: 'com.android.application'

android {
    defaultConfig {
        applicationId "io.github.gzlxz190614.lvchecker"
        minSdk 29
    }

    buildTypes {
        release {
            signingConfig signingConfigs.debug
        }
    }
}
'''


def strip_comment_lines(text: str) -> list[tuple[int, str]]:
    """返回 (行号, 去掉行注释后的内容)。只处理 `//`，够用了。"""
    out = []
    for i, line in enumerate(text.splitlines(), 1):
        s = line
        idx = s.find("//")
        if idx >= 0:
            # 粗略：不考虑 `//` 出现在字符串里的情况。生成的代码里没有这种。
            s = s[:idx]
        out.append((i, s))
    return out


def check_quotes(text: str) -> list[str]:
    """每一行里未转义的 `"` 必须是偶数个。"""
    problems = []
    for lineno, line in strip_comment_lines(text):
        if not line.strip():
            continue
        n = 0
        i = 0
        while i < len(line):
            if line[i] == "\\":
                i += 2
                continue
            if line[i] == '"':
                n += 1
            i += 1
        if n % 2 != 0:
            problems.append(f"  第 {lineno} 行引号不成对（{n} 个）：{line.strip()}")
    return problems


def main() -> int:
    tmp = ROOT / "_tmp_snippet"
    shutil.rmtree(tmp, ignore_errors=True)
    problems: list[str] = []

    try:
        for name, fname, src in (
            ("Kotlin DSL", "build.gradle.kts", KTS_TEMPLATE),
            ("Groovy DSL", "build.gradle", GROOVY_TEMPLATE),
        ):
            android = tmp / name.replace(" ", "")
            app = android / "app"
            app.mkdir(parents=True)
            (app / fname).write_text(src, encoding="utf-8", newline="\n")
            ks = app / "release.jks"
            ks.write_bytes(b"\x00" * 512)

            r = subprocess.run(
                [sys.executable, str(ROOT / "tools" / "setup_android_signing.py"),
                 "--app-dir", str(app), "--keystore", str(ks),
                 "--props", str(android / "key.properties"),
                 "--key-alias", "lvchecker",
                 "--store-password", "x", "--key-password", "x"],
                capture_output=True, text=True, encoding="utf-8", errors="replace",
            )
            if r.returncode != 0:
                problems.append(f"  ✗ {name}: 注入脚本自己失败了")
                problems.extend("    " + l for l in (r.stdout or r.stderr or "").splitlines())
                continue

            gen = (app / fname).read_text(encoding="utf-8")

            print(f"===== {name} 生成的关键片段 =====")
            for lineno, line in strip_comment_lines(gen):
                if "storeFile" in line or "signingConfig" in line:
                    print(f"  {lineno:4}: {line.rstrip()}")
            print()

            # ① 引号成对
            for p in check_quotes(gen):
                problems.append(f"  ✗ {name} {p}")

            # ② 不能出现裸的 r"（普通字符串里 = 字符串内容是 r，多半是原始字符串写错）
            for lineno, line in strip_comment_lines(gen):
                if re.search(r'\br"', line):
                    problems.append(
                        f"  ✗ {name} 第 {lineno} 行出现 `r\"` —— "
                        f"原始字符串写法在这里不被接受（CI 实测报 Unresolved reference: r）"
                    )

            # ③ 不能有全限定类名 java.util./java.io.（Kotlin DSL 特有）
            #
            #    ⚠️ 必须排除 import 行 —— `import java.util.Properties` 本身就含这个前缀，
            #    是**合法且必需**的。第一版没排除，于是两条 import 被误报成问题。
            if fname.endswith(".kts"):
                for lineno, line in strip_comment_lines(gen):
                    if line.lstrip().startswith("import "):
                        continue
                    if re.search(r"\bjava\s*\.\s*(util|io)\s*\.", line):
                        problems.append(
                            f"  ✗ {name} 第 {lineno} 行用了全限定类名 java.util./java.io. —— "
                            f"Gradle Kotlin DSL 里 `java` 是扩展不是包名"
                        )

            # ④ storeFile 必须是绝对路径
            m = re.search(r'storeFile\s*=\s*(?:new\s+)?File\(\s*["\']([^"\']+)["\']\s*\)', gen)
            if not m:
                problems.append(f"  ✗ {name}: 找不到 storeFile = File(\"...\")")
            else:
                val = m.group(1).replace("\\\\", "\\")
                is_abs = val.startswith("/") or re.match(r"^[A-Za-z]:[\\/]", val)
                if not is_abs:
                    problems.append(f"  ✗ {name}: storeFile 不是绝对路径：{val}")
                elif not Path(val).exists():
                    problems.append(f"  ✗ {name}: storeFile 指向的文件不存在：{val}")

            # ⑤ release 必须指向 release 签名
            if not re.search(r"buildTypes[\s\S]*?signingConfig", gen):
                problems.append(f"  ✗ {name}: release 没有指向 signingConfig")

    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print()
    if problems:
        print("❌ 生成的 gradle 代码有问题：")
        for p in problems:
            print(p)
        return 1
    print("✅ 生成的 gradle 片段静态检查通过")
    print("   （注意：这不能替代 Kotlin 编译器，只挡已知的几类语法错）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
