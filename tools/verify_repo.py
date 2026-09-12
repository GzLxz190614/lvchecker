#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
校验仓库的关键不变量。CI 在构建前跑，本地也能跑。

**为什么要单独写这个脚本**（本来这些断言是写在 workflow 里的 shell）：

  workflow 里原来有一步是：

      test -f lib/main.dart
      test -f assets/img/music/51/jacket.png
      ...

  这几个断言的目的有两个：① 确认 `flutter create` 没有覆盖我们的源文件；
  ② 确认关键资源在。但它们在**图片格式从 PNG 换成 WebP 时直接挂了** ——
  因为路径是写死的，改格式的人不会想到去改 workflow 里的 shell。

  讽刺的是：那个断言存在的意义就是防止资源出问题，结果它自己成了唯一
  因为资源改名而挂掉的东西。

  所以把它挪进脚本，并且**扩展名从 build.py 的 IMG_EXT 取**（唯一真源），
  这样换格式时不需要改这里，也就不可能漏。

用法：
    python tools/verify_repo.py                    # 打完补丁前跑（android/ 可能还不存在）
    python tools/verify_repo.py --expect-manifest  # 打完补丁后跑，会断言 INTERNET 权限

⚠️ 顺序很重要，这里踩过一次：
    这个脚本**必须**在 `tools/patch_android_manifest.py` **之后**才能检查
    manifest 的权限 —— `flutter create` 生成的模板本来就没有 INTERNET，
    权限是后面那一步插进去的。如果顺序反了，这里会对「还没打补丁的模板」
    断言权限，必然失败。

    所以 manifest 的断言只在 `--expect-manifest` 下做，
    workflow 里对应地跑两次：早期一次（查源文件/资源），
    patch 之后一次（查 manifest）。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    from build import IMG_EXT  # type: ignore
except Exception:  # noqa: BLE001
    IMG_EXT = "webp"

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass


def main() -> int:
    ap = argparse.ArgumentParser(description="校验仓库关键不变量")
    ap.add_argument(
        "--expect-manifest",
        action="store_true",
        help="断言 AndroidManifest 已打好补丁（显示名 + INTERNET 权限）。"
             "必须在 patch_android_manifest.py 之后跑。",
    )
    args = ap.parse_args()

    problems: list[str] = []

    # ------------------------------------------------ ① flutter create 没覆盖源文件
    #
    # `flutter create` 只补缺失的文件、不覆盖已有的。所以这几个必须还在，
    # 而且 pubspec 的名字不能被改回模板默认值。
    must_exist = [
        "lib/main.dart",
        "lib/pages/gate_pager.dart",
        "lib/pages/gate_page.dart",
        "lib/data/data_sync.dart",
        "tools/build.py",
        "test/widget_test.dart",
    ]
    for rel in must_exist:
        if not (ROOT / rel).exists():
            problems.append(f"{rel} 不见了（flutter create 覆盖了源文件？）")

    pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    if not pubspec.startswith("name: lvchecker"):
        problems.append("pubspec.yaml 的 name 不是 lvchecker（被模板覆盖了？）")

    # ------------------------------------------------ ② 四个数据 JSON 都在且可解析
    for name in ("meta.json", "gates.json", "linklevels.json", "classes.json"):
        p = ROOT / "data" / name
        if not p.exists():
            problems.append(f"data/{name} 不存在")
            continue
        try:
            doc = json.loads(p.read_text(encoding="utf-8"))
        except Exception as e:  # noqa: BLE001
            problems.append(f"data/{name} 不是合法 JSON：{e}")
            continue
        if not isinstance(doc, dict):
            problems.append(f"data/{name} 顶层不是对象")
        if "dataVersion" not in doc:
            problems.append(f"data/{name} 缺 dataVersion（热更新靠它判断版本）")

    # ------------------------------------------------ ③ 图片按 IMG_EXT 真的在
    #
    # 这里**不写死扩展名**：用 build.py 的 IMG_EXT。换格式时这一条自动跟上。
    probe = ROOT / "assets" / "img" / "music" / "51" / f"jacket.{IMG_EXT}"
    if not probe.exists():
        problems.append(
            f"assets/img/music/51/jacket.{IMG_EXT} 不存在。"
            f"如果是刚改过 IMG_EXT，需要重跑 python tools/build.py"
        )

    img_root = ROOT / "assets" / "img"
    n_img = len([p for p in img_root.rglob(f"*.{IMG_EXT}") if p.is_file()]) if img_root.exists() else 0
    if n_img == 0:
        problems.append(f"assets/img 下没有任何 .{IMG_EXT} 文件")

    # ------------------------------------------------ ④ Android manifest（仅 patch 之后）
    #
    # 这一条最值得查：release APK 少了 INTERNET 权限时**完全不能联网**，
    # 而编译、analyze、build 全都不会报错（详见 DESIGN.md Q17）。
    #
    # 但**只有在 patch 之后才能查** —— `flutter create` 生成的模板本来就没有
    # 这个权限。所以用 --expect-manifest 显式区分，避免顺序搞反时误报。
    if args.expect_manifest:
        manifest = ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
        if not manifest.exists():
            problems.append(
                "android/app/src/main/AndroidManifest.xml 不存在"
                "（flutter create 没跑？）"
            )
        else:
            text = manifest.read_text(encoding="utf-8")
            if "android.permission.INTERNET" not in text:
                problems.append(
                    "AndroidManifest.xml 缺少 INTERNET 权限 —— "
                    "装上去会完全无法联网（所有数据源都报域名解析失败）"
                )
            if 'android:label="Linked VERSE Checker"' not in text:
                problems.append('AndroidManifest.xml 的应用显示名不是 "Linked VERSE Checker"')
            if not problems:
                print("  manifest：显示名与 INTERNET 权限均已就绪")
    else:
        print("  manifest：跳过（这是打补丁前的检查；补丁后会带 --expect-manifest 再查一次）")

    # ------------------------------------------------ 输出
    print(f"图片格式 {IMG_EXT}；assets/img 下 {n_img} 张")
    print()
    if problems:
        print("❌ 仓库不变量校验失败：")
        for p in problems:
            print(f"  ✗ {p}")
        return 1
    print("✅ 仓库不变量校验通过")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
