# folks3d：街坊和路人的微缩模型小人

和主角同一盒小人：用的是 `pose3d/figure.js`（造型甲大头 Q 版、toy 塑料、同一套光、接触影），朝右。
动作借 `tools/art/folks.py` 的骨架（营生、歇着、走路），一帧一帧和孔版是同一个意思；长相不用 folks.py 的网点配色，在 `folks3d.py` 的 `LOOKS` / `WALKER_LOOKS` 里一人一套。
主角是青绿、梅红，街坊不用这两个颜色。

## 跑

```bash
cd tools/art/diorama/folks3d
python3 folks3d.py                          # 十四张图 + walkers.png + index.json → client/art/folks/（4 路并行约 3 分钟），再拼总览
python3 folks3d.py --only street,walkers    # 只出一部分（index.json 照样整份重写）
python3 folks3d.py --no-render              # 不渲染，只从已有的表拼总览
python3 folks3d.py --try barber,kid --out x.png   # 调长相：几位放大拼一张，不写表
```

总览默认存到 `/mnt/project-files/tongsui/art/diorama/folks_sheet.png`（`--contact` 换地方，最底下两排是游戏里原大，最左两个是主角）。
需要 node 能 `require('playwright')`；`tools/art` 下 8765 端口没有 http 服务的话脚本自己起一个。

## 表的格式（client/scripts/world/folks.gd 读）

- 每格 200×220 世界像素，脚底 (100, 206)，1.25 倍 → 一格 250×275，一行 8 格（宽 2000）。
- `<图>.png`：一人一行（顺序同 client/data/folks.json），列 0~3 干活、4~7 歇着（最后一帧眨眼）。
- `walkers.png`：一种一行，8 帧走路一整步。
- `index.json`：scale、cell、foot、scenes、folks（scene、row、sit、bubbles）、walkers，和孔版时一样。
- 256 色带透明（FASTOCTREE + 误差扩散），`.import` 文件不动（引擎用 LINEAR_WITH_MIPMAPS）。

## 文件

| 文件 | 做什么 |
| --- | --- |
| `folks3d.py` | 命令行：长相表、出帧、拼表、index.json、总览 |
| `folk_parts.js` | 挂到 figure.js 的 `EXT` 上的零件：发型（平头、分头、寸头、谢顶、烫发、盘髻、短发、披肩、马尾）、帽子（工作帽、安全帽、护士帽、草帽、渔夫帽、鸭舌帽）、围裙、套袖、毛巾、小板凳（坐着的都有）、菜篮子、公文包、挎包、烤山芋的汽油桶炉子、婴儿车，脸上的胡子、胡茬、皱纹 |
| `page.html` | 同 pose3d 的页面，多 import 一个 folk_parts.js |

figure.js 里给街坊开的口子（`spec.look`、`EXT`）只在有 `look` 时才走，主角出的图一个像素都不变。
加一位街坊：content/maps 里写 npcs → folks.py 的 FOLKS 写动作 → 这里的 LOOKS 写长相 → 重跑。
