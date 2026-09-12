#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
校验图片格式相关的前置条件。CI 在构建前跑，本地也能跑。

为什么需要这个脚本：

  `tools/build.py` 输出的图片格式由 `IMG_EXT` 决定（当前是 WebP，为了省 15 MB）。
  这只在**两个**条件下成立：

  1. **Pillow 编了 WebP 支持**。官方 wheel 一般都带，但某些环境（精简镜像、
     自行编译的 Pillow）会没有 —— 那时 `build.py` 会直接崩，或者更糟：
     用别的格式悄悄写出去，扩展名却还是 .webp，APK 里的图全部解不开。
  2. **仓库里的图片确实是对应格式**。改格式那次会重新生成，但如果有人手工
     放了一张 PNG 却叫 .webp，Flutter 会按扩展名选解码器然后失败。

  这两种情况的共同点是：**编译期完全看不出来**，只有装到手机上才满屏「图片丢失」。
  所以在这里静态挡掉。

⚠️ 本脚本**需要 Pillow**，没装就直接失败（不降级）。
   原因见下面 ① 的注释：验不了却静默通过，等于假绿勾。
   CI 里由 `Set up Python imaging (Pillow)` 那一步负责装。

用法：
    python tools/check_image_format.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

sys.path.insert(0, str(Path(__file__).resolve().parent))
try:
    from build import IMG_EXT, WEBP_QUALITY  # type: ignore
except Exception:  # noqa: BLE001
    IMG_EXT, WEBP_QUALITY = "webp", 82

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:  # noqa: BLE001
    pass

# Pillow 的格式名 与 我们用的扩展名 的对应
FORMAT_OF_EXT = {
    "webp": "WEBP",
    "png": "PNG",
    "jpg": "JPEG",
    "jpeg": "JPEG",
}

# 不动点：全量检查而不是抽查。
#
# 一开始写的是「取前 12 张抽查」，结果故意放一张「扩展名 .webp 实际是 PNG」的
# 坏图进去，检查**通过了** —— 因为坏图排在 music/51，不在前 12 个里。
# 抽查省下的那点时间（实测全量也就 1~2 秒）远不值得漏报，
# 而这个检查存在的唯一意义就是别漏报。


def main() -> int:
    problems: list[str] = []

    # ---------------------------------------------------------- ① Pillow 能力
    try:
        import PIL
        from PIL import Image, features
    except ImportError as e:
        # 这里**故意不降级**：本脚本存在的意义就是确认「图片能被正确读写」，
        # 没有 Pillow 就什么都验不了，静默通过等于给一个假绿勾。
        #
        # （CI 里由 `Set up Python imaging (Pillow)` 那一步装好；
        #  本地跑之前 pip install Pillow 即可。）
        print(f"❌ 没有装 Pillow：{e}")
        print("   这个检查需要它能读图片才能判断扩展名与实际格式是否一致。")
        print("   修复：python -m pip install 'Pillow>=10'")
        return 1

    ext = IMG_EXT.lower()
    fmt = FORMAT_OF_EXT.get(ext)
    if fmt is None:
        print(f"❌ build.py 的 IMG_EXT='{IMG_EXT}' 不是已知图片格式")
        return 1

    print(f"Pillow {PIL.__version__}；目标格式 {fmt}（扩展名 .{ext}，质量 {WEBP_QUALITY}）")

    if fmt == "WEBP":
        if not features.check("webp"):
            problems.append(
                "Pillow 没有 WebP 支持（features.check('webp') 为 False）。"
                "build.py 会写不出图片。修复：pip install --upgrade --force-reinstall Pillow"
            )
        else:
            # 真的编一张试试，比 features.check 更可靠
            try:
                import io

                buf = io.BytesIO()
                Image.new("RGBA", (8, 8), (255, 0, 0, 255)).save(
                    buf, "WEBP", quality=WEBP_QUALITY
                )
                if buf.tell() == 0:
                    problems.append("WebP 编码出来是空文件")
                else:
                    print(f"  WebP 编码自测：通过（8×8 图 {buf.tell()} 字节）")
            except Exception as e:  # noqa: BLE001
                problems.append(f"WebP 编码自测失败：{e}")

    # -------------------------------------------------- ② 仓库里的图是否对得上
    img_root = ROOT / "assets" / "img"
    files = sorted(
        p for p in img_root.rglob(f"*.{ext}") if p.is_file()
    ) if img_root.exists() else []

    if not files:
        problems.append(
            f"assets/img 下没有任何 .{ext} 文件。"
            f"如果刚改过 IMG_EXT，需要重跑 python tools/build.py 重新生成"
        )
    else:
        mismatched: list[str] = []
        for p in files:
            try:
                with Image.open(p) as im:
                    im.load()
                    actual = im.format
            except Exception as e:  # noqa: BLE001
                mismatched.append(f"{p.relative_to(ROOT).as_posix()}（打不开：{e}）")
                continue
            if actual != fmt:
                mismatched.append(
                    f"{p.relative_to(ROOT).as_posix()}（扩展名是 .{ext}，实际是 {actual}）"
                )

        if mismatched:
            problems.append(
                "以下文件扩展名与实际格式不符（Flutter 按扩展名选解码器，会解不开）：\n"
                + "\n".join(f"      {m}" for m in mismatched)
            )
        else:
            print(f"  全部 {len(files)} 张：扩展名与实际格式一致")

    # -------------------------------------------- ③ 别留旧格式的孤儿文件
    other = sorted(
        p for p in img_root.rglob("*")
        if p.is_file() and p.suffix.lower() in FORMAT_OF_EXT and p.suffix.lower() != f".{ext}"
    ) if img_root.exists() else []
    if other:
        # 不算致命：check_assets.py 会把「磁盘上有图没声明」报出来。
        # 但混着两种格式通常是改格式没清干净，值得提示。
        print(f"  ⚠️ 还存在 {len(other)} 个非 .{ext} 的图片（改格式后没清干净？）")
        for p in other[:5]:
            print(f"      {p.relative_to(ROOT).as_posix()}")

    print()
    if problems:
        print("❌ 图片格式检查失败：")
        for p in problems:
            print(f"  ✗ {p}")
        return 1
    print("✅ 图片格式检查通过")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
