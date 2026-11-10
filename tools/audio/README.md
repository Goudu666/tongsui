# 声音生成器

《同岁》的配乐、环境音、音效全部由这里的 Python 代码合成，没有采样和录音。
设计思路和每个声音的用途见 [docs/AUDIO.md](../../docs/AUDIO.md)。

和美术生成器（`tools/art/`）是同一个想法：改一个数、重新跑一遍，整套声音一起变。

## 运行

```bash
pip install -r tools/audio/requirements.txt      # numpy、scipy
# 另外需要命令行里有 ffmpeg（带 libvorbis）：macOS 上 brew install ffmpeg

python3 tools/audio/build_audio.py               # 全部，四核约两分钟 → client/audio/
python3 tools/audio/build_audio.py music         # 只做配乐（最慢的一部分）
python3 tools/audio/build_audio.py amb sfx       # 只做环境音和音效（几秒）
python3 tools/audio/build_audio.py --only whistle_a,radio,child   # 只做指定的几个
```

生成结果已经提交，不改声音不用跑。生成后用 Godot 打开一次项目让它重新导入。
同一份代码两次生成的文件逐字节相同（随机数的种子从素材名派生，编码器加了 `-bitexact`）。

## 结构

| 文件 | 内容 |
| --- | --- |
| `tongsui_audio/dsp.py` | 底层：包络、滤波、噪声、混响、响度（BS.1770）、循环无缝、导出 |
| `tongsui_audio/inst.py` | 乐器。拨的（八音盒、吉他、钢琴、三弦……）和吟的（竖笛、口琴、大提琴、二胡……） |
| `tongsui_audio/music.py` | 主题的谱子、五个阶段的编曲、默契乐句、标题 / 投胎 / 一生 |
| `tongsui_audio/amb.py` | 河畔里的环境音：循环（`LOOPS`）和单发（`SHOTS`） |
| `tongsui_audio/sfx.py` | 界面音、行动音、脚步 |
| `build_audio.py` | 入口。并行渲染，写 `client/audio/manifest.json` |

## 怎么改

- **换一件乐器的音色**：改 `inst.py` 里那个函数。吟的乐器的音色主要由 `MODELS` 里的共鸣峰决定。
- **改旋律**：`music.py` 的 `Q_FULL` / `M_FULL`（青 / 梅），每个音是 `(拍, 时值, 级, 八度)`；和弦在 `PROG`。
- **改某个阶段的乐器、速度、混响**：`music.py` 的 `STAGES`。各轨的相对响度在 `BALANCE`。
- **加环境音**：在 `amb.py` 写一个返回 numpy 数组的函数，登记到 `LOOPS` 或 `SHOTS`，
  再到 `client/audio/soundscape.json` 里写它在哪儿、几点、哪个年代响。
- **听一下改得对不对**：没有声卡的机器上可以录游戏里的实际混音，见 docs/AUDIO.md §7。
