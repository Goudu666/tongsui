# scene3d：底图（十四张横图）

老画法 `tools/art/scenes.py` 一笔不改，录成显示列表再搭成 3D：

    cd tools/art && python3 -m http.server 8765 &          # three 从这里取
    python3 tools/art/diorama/scene3d/bake.py [图 id ...]   # 全部约 2 分钟
    node tools/art/diorama/scene3d/shoot.js street --x 900 --w 2133 --scale 0.9 --backdrop --out /tmp/a.png   # 只看一段

- `record.py`：把 riso 的笔、scenes.py 的画法函数换成记录（每条带「在哪个画法函数里」），出 `out/<图>.json`。
- `build.js`：显示列表 → three.js 模型。规则：
  - 每次挖空（clear）是一样实的东西开始，后面落在它框里的色块是它脸上的花样（decal）；同框再压一版色按孔版叠印相乘。
  - 认得名字的按名字放前后（`PROPS` 立在地上的家具道具、`WALLISH` 贴墙的门窗招牌）；`CUSTOM` 的（地面、楼板、剖开的墙、树坑、河、海）各有专门的搭法。
  - 不认得名字的按大小和离地猜：靠墙的板、立在地上的块、门洞（暗方块）。
  - **最底层地面线以下**的一大片（沙滩、礁石滩、田、栈桥石板）是俯着看的地，搭成往前铺开的平地：z = Z_REF + (y − 地面) / K，后沿补到墙根 z=0；落在上头的水洼、字跟着躺平。
  - 又宽又扁的一大片青（湖）是躺在地上的水面；海的近岸停在 shore，不铺到人走的地方。
  - 墨很重的不规则大块是石头（灰褐色、有厚度），不是一团黑。
- `render.js`：正交镜头 + 斜投影矩阵（在模型上，不在镜头上），太阳、半球光、GTAO；`--backdrop` 只给预览加天和辉光。
- `bake.js` / `bake.py`：一片 1024 世界像素 × 1.25 倍渲染，压 256 色，写 `client/art/scenes/<图>_<k>.png`、`<图>_mask.png`、`anchors.json`；旧的 `.import` 保留（UID 不变）。
