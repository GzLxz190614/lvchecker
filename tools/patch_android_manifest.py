#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
给 `flutter create` 生成的 android/app/src/main/AndroidManifest.xml 打补丁：
  1. 改应用显示名（android:label）
  2. **声明 INTERNET 权限**（这是本项目最隐蔽的一个坑，见下）

为什么必须单独写个脚本（而不是像原来那样用 sed 内联在 workflow 里）：

  a) `sed` 的插入命令没法在本地验证（Windows 上没有可用的 sed），
     只能靠推到 CI 跑一次才知道对不对——而它失败时 APK **照样能构建成功**，
     只有装到手机上才会发现「又不能联网了」。又是一个「假绿勾」。
     Python 版本可以在本地直接跑一遍验证。
  b) 权限漏掉时没有任何编译期报错，必须显式断言把它变成构建失败。

⚠️ 关于 INTERNET 权限（这个坑值得单独说明）：

  `flutter create` 生成的 manifest **只有 debug/profile 那份带 INTERNET**
  （那是给 Flutter 工具连 VM Service 用的），主 manifest 里没有。
  release APK 用主 manifest，所以**默认完全不能联网**。

  而它的表现非常像「被墙」：所有请求都抛 Failed host lookup（域名解析失败），
  于是「每个源都不通」看起来像网络问题，实际上 app 连 DNS 都没权限查。

  实测症状：手机浏览器打开 raw 链接正常，但 app 里 6 个数据源**全部**报
  「域名解析失败」——连国内域名 Gitee 都不通。
  **「所有域名一起失败」就是缺权限的指纹**；真被墙只会是部分域名失败。

  INTERNET 是 normal 权限，安装时就授予，不需要运行时申请。

用法（在 `flutter create` 之后、`flutter build` 之前跑）：
    python3 tools/patch_android_manifest.py \
        --manifest android/app/src/main/AndroidManifest.xml \
        --label "Linked VERSE Checker"

单独跑也可以，默认就是上面的路径和名字。

自检（CI 会跑，也可以在本地跑）：
    python3 tools/patch_android_manifest.py --self-test

  它会用一份仿模板的 manifest 验证三件事：补丁生效、重复跑幂等、
  以及「模板变了」时**必须以非零退出**（否则会出一个没权限的坏 APK 而无人发现）。
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
import uuid
from pathlib import Path

# Windows 控制台默认是 GBK，打印 ✅/✗ 或中文错误信息会抛 UnicodeEncodeError，
# 而这个异常会把**真正的错误盖住**（比如「没找到 INTERNET」被编码错误顶掉）。
# 改成 utf-8 + errors=replace，保证错误信息一定打得出来。
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

DEFAULT_MANIFEST = Path("android/app/src/main/AndroidManifest.xml")
DEFAULT_LABEL = "Linked VERSE Checker"

# 自检用的模板样本。结构与 `flutter create` 生成的主 manifest 一致，
# **关键点是它没有任何 <uses-permission>** —— 这正是要修的问题。
SAMPLE_TEMPLATE = """<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:label="lvchecker"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
"""

INTERNET = '<uses-permission android:name="android.permission.INTERNET" />'


def patch(manifest: Path, label: str) -> list[str]:
    """就地打补丁，返回这次做了哪些改动的说明。"""
    if not manifest.exists():
        raise SystemExit(f"找不到 manifest：{manifest}（flutter create 跑了吗？）")

    # 明确用 utf-8 而不是平台默认编码：Windows 上 open() 默认 GBK，
    # 而这个文件里可能有非 ASCII 字符，读写编码不一致会直接损坏文件。
    text = manifest.read_text(encoding="utf-8")
    done: list[str] = []

    # ---------------------------------------------------------------- label
    new_text, n = re.subn(
        r'(android:label=")[^"]*(")', rf"\g<1>{label}\g<2>", text, count=1
    )
    if n == 0:
        # 模板里一定有 label；没有说明模板变了，不能静默放过
        raise SystemExit('manifest 里找不到 android:label="..."，模板可能变了')
    text = new_text
    done.append(f'显示名 -> "{label}"')

    # ------------------------------------------------------- INTERNET 权限
    if "android.permission.INTERNET" in text:
        done.append("INTERNET 权限已存在（跳过）")
    else:
        # 插到第一个 <application 之前。<uses-permission> 必须是 <manifest> 的直接子元素，
        # 放在 <application> 前面是最省事也最稳的位置。
        # 保留该行的缩进，让 diff 好看一点。
        m = re.search(r"^([ \t]*)<application\b", text, re.MULTILINE)
        if m is None:
            raise SystemExit("manifest 里找不到 <application>，无法插入权限")
        indent = m.group(1)
        insert_at = m.start()
        text = (
            text[:insert_at]
            + f"{indent}{INTERNET}\n"
            + text[insert_at:]
        )
        done.append("INTERNET 权限已声明")

    manifest.write_text(text, encoding="utf-8")
    return done


def verify(manifest: Path, label: str) -> None:
    """打完之后自己再读一遍确认，失败就非零退出（让 CI 红，而不是出个坏 APK）。"""
    text = manifest.read_text(encoding="utf-8")

    problems: list[str] = []
    if f'android:label="{label}"' not in text:
        problems.append(f'没找到 android:label="{label}"')
    if 'android:name="android.permission.INTERNET"' not in text:
        problems.append("没找到 INTERNET 权限声明 —— 装到手机上会完全无法联网")
    # 权限必须在 <application> 之前（虽然 XML 不强制，但这样最不容易被模板结构影响）
    app_at = text.find("<application")
    perm_at = text.find("android.permission.INTERNET")
    if app_at != -1 and perm_at != -1 and perm_at > app_at:
        problems.append("INTERNET 权限插到了 <application> 之后，位置不对")

    # 出现多次说明插入逻辑没做幂等
    if text.count("android.permission.INTERNET") != 1:
        problems.append(
            f"INTERNET 权限出现了 {text.count('android.permission.INTERNET')} 次（应为 1 次）"
        )

    if problems:
        print("❌ manifest 校验失败：")
        for p in problems:
            print(f"  ✗ {p}")
        raise SystemExit(1)

    print("✅ manifest 校验通过")


def main() -> int:
    ap = argparse.ArgumentParser(description="给 AndroidManifest.xml 打补丁")
    ap.add_argument("--manifest", default=str(DEFAULT_MANIFEST), help="manifest 路径")
    ap.add_argument("--label", default=DEFAULT_LABEL, help="应用显示名")
    ap.add_argument(
        "--self-test",
        action="store_true",
        help="用内置样本验证补丁逻辑（不碰真实文件）",
    )
    args = ap.parse_args()

    if args.self_test:
        return _self_test(args.label)

    manifest = Path(args.manifest)
    print(f"目标：{manifest}")

    for item in patch(manifest, args.label):
        print(f"  · {item}")

    verify(manifest, args.label)

    print()
    print("----- manifest 关键行 -----")
    for i, line in enumerate(manifest.read_text(encoding="utf-8").splitlines(), 1):
        if any(k in line for k in ("android:label", "uses-permission", "<application")):
            print(f"{i:4}: {line}")
    return 0


def _self_test(label: str) -> int:
    """
    自检：在临时文件上验证补丁生效 + 幂等 + 失败路径。

    为什么值得写：这个脚本的作用是「防止 APK 静默地没有联网权限」，
    它自己出错就毫无意义了。而它只能在 CI 里对真实模板跑第一次 ——
    自检让它在本地和 CI 都能被验证。

    临时文件放在**仓库内**而不是系统临时目录：某些受限环境（沙箱 / CI 容器）
    不允许在系统 temp 下写文件，放仓库里两边都能跑。
    """
    failures: list[str] = []
    tmp = Path(__file__).resolve().parent / f".selftest-{uuid.uuid4().hex[:8]}"

    try:
        tmp.mkdir(parents=True, exist_ok=True)
        m = tmp / "AndroidManifest.xml"
        m.write_text(SAMPLE_TEMPLATE, encoding="utf-8")

        # 1) 首次打补丁：应改 label 并插入权限
        patch(m, label)
        text = m.read_text(encoding="utf-8")
        if f'android:label="{label}"' not in text:
            failures.append("首次运行没有改掉 android:label")
        if "android.permission.INTERNET" not in text:
            failures.append("首次运行没有插入 INTERNET 权限")
        if 'android:label="lvchecker"' in text:
            failures.append("旧的 label 值还在")

        # 2) 幂等：再跑一次不应重复插入、也不应改变内容
        patch(m, label)
        again = m.read_text(encoding="utf-8")
        if again.count("android.permission.INTERNET") != 1:
            failures.append(
                f"重复运行后 INTERNET 出现 {again.count('android.permission.INTERNET')} 次（应为 1）"
            )
        if again != text:
            failures.append("重复运行改变了文件内容（不幂等）")

        # 3) verify 应通过
        try:
            verify(m, label)
        except SystemExit:
            failures.append("verify 在正确结果上失败了")

        # 4) 失败路径：模板没有 label 时必须非零退出，而不是静默出一个坏 manifest
        bad = tmp / "bad.xml"
        bad.write_text("<manifest><foo/></manifest>\n", encoding="utf-8")
        try:
            patch(bad, label)
            failures.append("模板里没有 android:label 时居然没报错（会静默产出坏 APK）")
        except SystemExit as e:
            if e.code in (0, None):
                failures.append("缺 label 时退出码是 0，CI 不会红")

        # 5) 失败路径：没有 <application> 也必须报错
        bad2 = tmp / "bad2.xml"
        bad2.write_text('<manifest>\n<foo android:label="x"/>\n</manifest>\n', encoding="utf-8")
        try:
            patch(bad2, label)
            failures.append("没有 <application> 时居然没报错")
        except SystemExit as e:
            if e.code in (0, None):
                failures.append("缺 <application> 时退出码是 0，CI 不会红")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print("===== patch_android_manifest.py 自检 =====")
    if failures:
        for f in failures:
            print(f"  ✗ {f}")
        return 1
    print("  ✓ 首次打补丁生效（label + INTERNET）")
    print("  ✓ 重复运行幂等")
    print("  ✓ verify 通过")
    print("  ✓ 模板缺 android:label 时非零退出")
    print("  ✓ 模板缺 <application> 时非零退出")
    print("✅ 自检通过")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
