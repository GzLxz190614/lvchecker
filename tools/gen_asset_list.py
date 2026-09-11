#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
完整生成 pubspec.yaml。

为什么由脚本生成而不是手写 assets 列表：
    Flutter 的 assets 声明**不递归**子目录。官方文档原文：
      "To include all assets under a directory, only assets directly in the
       directory are included. For subdirectories, you must declare each one."
    声明 `assets/img/music/` 时，`assets/img/music/51/jacket.png`（三级）不会被
    打进 APK。结果是编译成功、analyze 无 error、运行时满屏「图片丢失」。
    这个坑踩了两次，所以改成显式逐文件生成，并由 check_assets.py 校验。

为什么整体生成而不是正则替换：
    一开始想在已有 pubspec 里替换 `flutter:` 段，但正则匹配到了
    `dependencies:` 下的 `flutter:` 子键，导致替换错位、重复运行还会膨胀。
    整体生成是幂等的，也不会被文件的其它内容干扰。

被 build.py 调用，也可单独运行：
    python tools/gen_asset_list.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PUBSPEC = ROOT / "pubspec.yaml"

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass


def collect_assets() -> list[str]:
    """要打进 APK 的文件：data/ 下的 JSON + assets/img 下所有 PNG。"""
    out: list[str] = []

    data_dir = ROOT / "data"
    if data_dir.exists():
        for p in sorted(data_dir.glob("*.json")):
            out.append(p.relative_to(ROOT).as_posix())

    img_root = ROOT / "assets" / "img"
    if img_root.exists():
        for p in sorted(img_root.rglob("*.png")):
            out.append(p.relative_to(ROOT).as_posix())

    return out


HEAD = '''name: lvchecker
description: "中二节奏 2027 连章（Linked VERSE）门解锁进度记录工具"
publish_to: "none"
version: 0.2.0+2

environment:
  sdk: ">=3.4.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  shared_preferences: ^2.3.2
  # 热更新：从 GitHub 拉最新的 data/*.json
  http: ^1.2.2
  # 热更新：把拉到的 JSON 缓存到应用私有目录，离线时用缓存
  path_provider: ^2.1.4

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  # 从仓库根目录的 icon.png 生成各密度的 Android 启动图标。
  # 由 CI 执行 `dart run flutter_launcher_icons`，本地无需 Flutter。
  flutter_launcher_icons: ^0.14.1

flutter:
  # 必须为 true。
  # 代码里用了 Icons.*（chevron_right / check_circle / settings_outlined 等），
  # 这些字形来自 MaterialIcons 字体。设为 false 时编译器不报错，
  # 但运行时所有图标会变成空白方块——这种「编译过但看起来坏了」的坑很难查。
  uses-material-design: true

  # ------------------------------------------------------------------
  # 资源列表：**必须逐文件列出**，不能只写目录。
  #
  # Flutter 的 assets 声明不递归子目录：声明 `assets/img/music/` 时，
  # `assets/img/music/51/jacket.png` 这类三级路径不会被 pack 进包。  # 结果是编译成功、analyze 无 error、运行时却满屏「图片丢失」。
  #
  # 下面这段由 tools/gen_asset_list.py 生成（tools/build.py 也会调用），
  # 请勿手动编辑。新增曲目后重跑 tools/build.py 即可。
  # ------------------------------------------------------------------
  assets:
'''

TAIL = '''
# 启动图标配置（见上面的 flutter_launcher_icons 依赖）。
flutter_launcher_icons:
  android: true
  ios: false
  image_path: "icon.png"
  adaptive_icon_background: "#14141C"
  adaptive_icon_foreground: "icon.png"
  min_sdk_android: 29
'''


def render_pubspec(assets: list[str]) -> str:
    body = "\n".join(f"    - {a}" for a in assets)
    return f"{HEAD}{body}\n{TAIL}"


def main() -> int:
    assets = collect_assets()
    if not assets:
        print("❌ 没找到任何资源文件")
        return 1

    text = render_pubspec(assets)
    PUBSPEC.write_text(text, encoding="utf-8")

    n_data = sum(1 for a in assets if a.startswith("data/"))
    n_png = sum(1 for a in assets if a.endswith(".png"))
    print(f"已生成 pubspec.yaml：{len(assets)} 个资源（data {n_data} 个 / PNG {n_png} 个）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
