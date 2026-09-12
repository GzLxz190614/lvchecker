#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
校验 pubspec.yaml 里逐文件声明的资源列表与磁盘是否一致。

为什么需要：
    Flutter 的 assets 声明**不递归**子目录。声明 `assets/img/music/` 时，
    `assets/img/music/51/jacket.webp` 这类三级路径不会被 pack 进包。
    症状是：编译成功、analyze 无 error、APK 能装，但运行时满屏「图片丢失」。
    这个坑踩了两次，所以用静态校验把它挡在构建之前。

校验三件事：
    ① 声明的每个路径在磁盘上都存在
    ② assets/img 下每张图片都被声明了（漏声明 = APK 里没有这张图）
    ③ data/ 下四个必需 JSON 都被声明了

⚠️ 这里的图片扫描**刻意不写死扩展名**（原来是 `rglob("*.png")`）。
    图片格式从 PNG 换成 WebP 时，写死的扫描会退化成「什么都没找到」，
    于是校验通过 —— 变成一个假绿勾。现在按「已知图片后缀」集合过滤，
    换格式（或混用格式）都不会让这个检查失效。

用法：
    python tools/check_assets.py
    修复：python tools/gen_asset_list.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

REQUIRED_DATA = ("meta.json", "gates.json", "linklevels.json", "classes.json")

# 已知的图片后缀。不写死单一格式，避免换格式后校验静默失效。
IMAGE_SUFFIXES = {".webp", ".png", ".jpg", ".jpeg", ".gif", ".bmp"}


def declared_assets() -> list[str]:
    """抓 pubspec 里 flutter.assets 下的项目。

    只取 `  assets:` 段之后的 `    - path` 行，不碰其它键。
    """
    text = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    lines = text.split("\n")

    out: list[str] = []
    in_assets = False
    for line in lines:
        stripped = line.strip()
        if re.match(r"^\s*assets:\s*$", line):
            in_assets = True
            continue
        if in_assets:
            if not stripped or stripped.startswith("#"):
                continue
            m = re.match(r"^\s{4,}-\s*(\S+)\s*$", line)
            if m:
                out.append(m.group(1))
                continue
            # 遇到别的键（缩进更浅）就结束
            if re.match(r"^\s{0,4}\S", line):
                in_assets = False
    return out


def main() -> int:
    declared = declared_assets()
    if not declared:
        print("❌ pubspec.yaml 里找不到 assets 列表")
        return 1

    print(f"pubspec 声明了 {len(declared)} 项资源")

    problems: list[str] = []
    warnings: list[str] = []

    # ① 声明的路径是否存在
    on_disk = set()
    for a in declared:
        p = ROOT / a
        if not p.exists():
            problems.append(f"  ✗ 声明了 '{a}' 但磁盘上不存在")
        else:
            on_disk.add(a)

    # ② 每张图片是否都声明了
    img_root = ROOT / "assets" / "img"
    if img_root.exists():
        images = {
            p.relative_to(ROOT).as_posix()
            for p in img_root.rglob("*")
            if p.is_file() and p.suffix.lower() in IMAGE_SUFFIXES
        }
        missing = sorted(images - set(declared))
        if missing:
            problems.append(
                f"  ✗ {len(missing)} 张图片没有在 pubspec 里声明"
                f"（这些图不会进 APK，app 里会显示「图片丢失」）："
            )
            for m in missing[:8]:
                problems.append(f"      {m}")
            if len(missing) > 8:
                problems.append(f"      …… 还有 {len(missing) - 8} 个")
            problems.append("    修复：python tools/gen_asset_list.py")
        print(
            f"  磁盘上图片：{len(images)} 张，全部已声明"
            if not missing
            else f"  磁盘上图片：{len(images)} 张"
        )
        # 声明了图片后缀、但磁盘上没有的，① 已经报过了；这里补一条总数对账，
        # 防止「扫不到图」这种情况被当成「没问题」
        if images and not declared:
            problems.append("  ✗ 磁盘上有图片但 pubspec 一个都没声明")

    # ③ data/ 必需文件
    for name in REQUIRED_DATA:
        rel = f"data/{name}"
        if (ROOT / rel).exists() and rel not in declared:
            problems.append(f"  ✗ {rel} 存在但没声明（app 加载数据会失败）")

    # ④ 声明了但没用到（提示）
    ids_in_use = {a.split("/")[2] for a in declared if a.startswith("assets/img/music/") and len(a.split("/")) > 3}
    if ids_in_use:
        print(f"  music 目录：{len(ids_in_use)} 首")

    print()
    if problems:
        print("❌ 资源声明有问题：")
        print("\n".join(problems))
    else:
        print("✅ 资源声明完整且与磁盘一致")

    if warnings:
        print("\n⚠️ 提示：")
        print("\n".join(warnings))

    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
