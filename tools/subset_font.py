#!/usr/bin/env python3
"""把霞鹜文楷裁成「游戏里会出现的字」，APK 从 +25 MB 变成 +3 MB 左右。

收字范围：
  - GB2312 全部 6763 个汉字（玩家起名字、聊天够用）
  - ASCII、中文标点、常用符号
  - 仓库里 content/、client/ 下所有文本里实际出现的字（剧情里的生僻字不会丢）
裁不到的字，Godot 会回退到手机系统字体，不会变成方块。

用法：python3 tools/subset_font.py [字体路径，默认 client/fonts/LXGWWenKai-Regular.ttf]
依赖：pip install fonttools（Ubuntu: apt install python3-fonttools）
"""
import pathlib
import sys

from fontTools import subset

ROOT = pathlib.Path(__file__).resolve().parent.parent
FONT = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "client/fonts/LXGWWenKai-Regular.ttf"
# 像素画的界面字：缝合像素 12px（OFL，原件在 tools/art/pixel/fonts/），同样裁一份进 client/fonts/
PIXEL_SRC = ROOT / "tools/art/pixel/fonts/fusion-pixel-12px-proportional-zh_hans.ttf"
PIXEL_DST = ROOT / "client/fonts/FusionPixel-12px.ttf"


def gb2312() -> str:
    out = []
    for hi in range(0xB0, 0xF8):
        for lo in range(0xA1, 0xFF):
            try:
                out.append(bytes([hi, lo]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    return "".join(out)


def repo_text() -> str:
    chunks = []
    for pattern in ("content/**/*.yaml", "client/**/*.gd", "client/**/*.json", "client/**/*.tscn"):
        for p in ROOT.glob(pattern):
            if "addons" in p.parts:
                continue
            chunks.append(p.read_text(encoding="utf-8", errors="ignore"))
    return "".join(chunks)


def main() -> None:
    if not FONT.exists():
        sys.exit(f"找不到字体 {FONT}，先运行 tools/fetch_addons.sh")
    ascii_ = "".join(chr(c) for c in range(0x20, 0x7F))
    punct = "，。、；：？！…—·「」『』（）《》〈〉【】“”‘’～￥％＋－×÷＝０１２３４５６７８９✓✗←→↑↓★☆♥○●△□◇"
    chars = set(gb2312() + ascii_ + punct + repo_text())
    chars = {c for c in chars if c.isprintable() or c == " "}
    cut(FONT, FONT, chars)
    if len(sys.argv) <= 1 and PIXEL_SRC.exists():
        PIXEL_DST.parent.mkdir(parents=True, exist_ok=True)
        cut(PIXEL_SRC, PIXEL_DST, chars)


def cut(src, dst, chars) -> None:
    FONT = src
    before = FONT.stat().st_size
    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    opts.glyph_names = False
    font = subset.load_font(str(FONT), opts)
    sub = subset.Subsetter(opts)
    sub.populate(text="".join(sorted(chars)))
    sub.subset(font)
    subset.save_font(font, str(dst), opts)
    after = dst.stat().st_size
    print(f"✓ 字体裁剪 {dst.name}：{len(chars)} 个字符，{before / 1e6:.1f} MB → {after / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
