#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
检查 pubspec.yaml 的资源声明与磁盘上的实际目录是否一致。

为什么需要这个脚本：
    实测教训——把资源声明写成 `assets/img/`（只一级）时，APK 里所有曲绘都读不到，
    app 里满屏「图片丢失」，但编译完全成功。这种「编译过了但图全丢」的问题
    在无法本地运行 app 的情况下极难发现。
    所以这里做静态校验，把它挡在 CI 之前。

用法：
    python tools/check_assets.py
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


def declared_assets() -> list[str]:
    """从 pubspec.yaml 里手工抓 flutter.assets 列表。

    不引入 PyYAML 依赖——只需要取一段缩进列表，正则足够且不会因为
    缩进风格变化而误判。
    """
    text = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    lines = text.split("\n")

    out: list[str] = []
    in_assets = False
    base_indent = 0
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if re.match(r"^\s*assets:\s*$", line):
            in_assets = True
            base_indent = len(line) - len(line.lstrip())
            continue
        if in_assets:
            indent = len(line) - len(line.lstrip())
            if indent <= base_indent:
                in_assets = False
                continue
            m = re.match(r"^\s*-\s*(\S+)\s*$", line)
            if m:
                out.append(m.group(1))
    return out


def main() -> int:
    declared = declared_assets()
    if not declared:
        print("❌ pubspec.yaml 里找不到 flutter.assets 声明")
        return 1

    print(f"pubspec 声明了 {len(declared)} 项资源：")
    for d in declared:
        print(f"  {d}")

    problems: list[str] = []
    warnings: list[str] = []

    # ① data/ 必须至少覆盖 meta.json 与 gates.json
    data_dir = ROOT / "data"
    if "data/" in declared:
        for required in ("meta.json", "gates.json", "linklevels.json", "classes.json"):
            if not (data_dir / required).exists():
                problems.append(f"  ✗ data/{required} 不存在（app 运行时会加载失败）")
    else:
        warnings.append("  · pubspec 没有声明 'data/'，app 将找不到 gates.json / meta.json")

    # ② assets/img/* 必须逐个列出二级子目录
    img_root = ROOT / "assets" / "img"
    if img_root.exists():
        on_disk = sorted(p.name for p in img_root.iterdir() if p.is_dir())
        for sub in on_disk:
            want = f"assets/img/{sub}/"
            if want not in declared:
                problems.append(
                    f"  ✗ {want} 在磁盘上存在但 pubspec 没声明 —— "
                    f"这个目录下的图在 app 里会全部显示「图片丢失」"
                )

        # ③ 反向：声明了但磁盘上没有
        for d in declared:
            if d.startswith("assets/img/"):
                if not (ROOT / d).exists():
                    problems.append(f"  ✗ pubspec 声明的 '{d}' 在磁盘上不存在")

        # ④ 有多少个 id 子目录（只是信息，用于提醒新增时要补声明）
        for sub in on_disk:
            n = sum(1 for p in (img_root / sub).iterdir() if p.is_dir())
            print(f"    assets/img/{sub}/ 下有 {n} 个 id 目录")

    # ⑤ 每个 id 目录里应该有图（music/avatar）或至少 meta.json
    missing_meta: list[str] = []
    for sub in ("music", "avatar"):
        d = img_root / sub
        if not d.exists():
            continue
        for id_dir in sorted(p for p in d.iterdir() if p.is_dir()):
            if not (id_dir / "meta.json").exists():
                missing_meta.append(f"assets/img/{sub}/{id_dir.name}/meta.json")
    if missing_meta:
        warnings.append(f"  · {len(missing_meta)} 个 id 目录缺 meta.json（不影响 app，但不利于维护）")

    print()
    if problems:
        print("❌ 资源声明有问题：")
        print("\n".join(problems))
    else:
        print("✅ 资源声明与磁盘目录一致")

    if warnings:
        print("\n⚠️ 提示：")
        print("\n".join(warnings))

    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
