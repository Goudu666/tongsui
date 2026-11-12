# pose3d：两个主角的微缩模型小人

three.js 搭 3D 小人，在 Playwright 的 Chromium（swiftshader WebGL）里一格一格离线渲染，Python 拼成精灵表。
格子和墨线版一样（`client/scripts/world/actor.gd`）：每格 200×220 世界像素，脚底 (100, 206)，8 列；
底图 `{role}_{stage}.png` 5 行、2 倍，行动表 `{role}_{stage}_act.png` 11 行、1.5 倍。人朝右，朝左由引擎翻。

## 文件

| 文件 | 做什么 |
| --- | --- |
| `poses.py` | 借 `tools/art/actors.py`、`actor_acts.py` 的骨架：拿一个「记账的画笔」跑 `draw_person`，收关节（髋、肩、肘、手、头、膝、踝、脚跟脚尖），hook 里画的道具（本子、碗、球、车轱辘、风筝…）连同它在哪一层一并记下。每一帧和墨线版、像素版是同一个意思。按造型方案改头身比，腿短了就把摆腿幅度放大，走一步还是前进那么多（脚不打滑） |
| `figure.js` | 按关节搭人：大圆头（脸是贴在球上的画：眼睛、高光、腮红、嘴、十几种表情）、头发是变形的球壳（发际线按方位角走，刘海、翘毛、揪揪、马尾、短发、发髻）、回转体的身子和衣服、胶囊胳膊腿、手套手、圆头鞋；中年以后戴眼镜。道具把 2D 的形状挤成小块、线变成管子、圆的变成球。斜投影正交镜头（README 里的 K = 0.28），太阳、半球光、ACES、PCF 软影，脚下一团接触影 |
| `page.html`、`render.js` | 页面只暴露 `renderJob(job)`；`render.js jobs.json outdir` 每格存一张 PNG |
| `figures.py` | 命令行：出表、预览、造型方案、总览 |

## 跑

```bash
cd tools/art/diorama/pose3d
python3 figures.py --variant toy                       # 十张底图 + 十张行动表 → client/art/actors/（4 路并行约 6 分钟）
python3 figures.py --variant toy --contact 总览.png     # 出完再拼一张总览（最底下一行是游戏里原大）
python3 figures.py --no-render --contact 总览.png       # 不渲染，只从已有的表拼总览
python3 figures.py --only teen --roles mei              # 只出一部分
python3 figures.py --preview out.png --variant clay     # 两人五个年纪：站、走两帧、招手、坐（2 倍）
python3 figures.py --design c --portrait out.png        # 造型方案：全身 + 大头特写
```

需要 node 能 `require('playwright')`（全局装的就行）。`tools/art` 下 8765 端口没有 http 服务的话，脚本自己起一个。

## 造型方案（`--design`）和材质（`--variant`）

- `a` 甲 · 大头 Q 版（约 1:3，小时候约 1:2.2）：深色椭圆眼带两点高光，尖尖的刘海，胳膊腿粗一点。**现在出图用的就是它**（`DEFAULT_DESIGN`）。
- `b` 乙 · 绘本修长（约 1:5，接近墨线版的头身比）：小豆豆眼，侧分 / 八字刘海，蛋形头。
- `c` 丙 · 大眼娃娃（约 1:3.5）：棕色渐变的大眼睛、粗上眼线，几大缕的刘海，胳膊腿细一点。

换方案就是 `--design b` 重跑一遍，别的不用动。

材质：`toy` 塑料（roughness 0.42 + 一层清漆，和场景里的小人一样）、`clay` 黏土（哑光 0.9、颜色暖一点、指纹和麻点的凹凸）、
`lowpoly` 低多边形（平面着色、面数很少）。三种用的是同一副模型、同一套姿势。

## 衣服（随年纪）

| | 青 | 梅 |
| --- | --- | --- |
| 小时候 | 青绿白条 T 恤、藏青短裤、白袜、红球鞋，头顶一撮翘毛 | 红连衣裙白领子、浅粉打底裤、红搭扣鞋，两个小揪揪 |
| 中学 | 青绿运动校服（袖子、裤腿一道白杠）、白球鞋、黄书包 | 红运动校服、白球鞋、黄书包，高马尾 |
| 青年 | 白 T 恤外面敞着青绿夹克、牛仔裤 | 红色长大衣系腰带、藏青裤，齐肩短发 |
| 中年 | 白衬衫、青绿外套、有点肚子、眼镜 | 米色衬衫、深红开衫、眼镜 |
| 老年 | 灰头发、浅青衬衫、青绿外套、金边眼镜、拐杖 | 灰头发挽个髻、浅红衬衫、红开衫、金边眼镜 |
