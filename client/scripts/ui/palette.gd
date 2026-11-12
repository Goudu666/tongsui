extends RefCounted
## 《同岁》配色：孔版套色（Risograph）的两种专色 + 墨 + 纸

const PAPER := Color("#F4EEE1")
const PAPER_DARK := Color("#E8E0CF")
const INK := Color("#2B2A33")
const INK_SOFT := Color("#8A8578")
const QING := Color("#2E8B7A")  ## 玩家 A 的颜色
const MEI := Color("#D9485F")   ## 玩家 B 的颜色
const OVERLAP := Color("#4A3546")  ## 两色叠印

# ---- 界面规范（11-11 重做界面）：色值不加新色，只是四色的几档深浅 ----
const PAPER_HI := Color("#FBF7EE")   ## 浮在地图上的纸片：比底纸亮一档，压在网点上也干净
const INK_MID := Color("#5D5B63")    ## 第二层的字（说明、单位）：比 INK_SOFT 深，横屏手机上看得清
const HAIR := Color(0.169, 0.165, 0.2, 0.18)  ## 卡片里分区的细线（INK 18%）
const SHADE := Color(0.169, 0.165, 0.2, 0.2)  ## 纸片底下垫的那一层影子（INK 20%），不印专色时用

# 字级：横屏 1080 高的设计稿，手机横拿时 1px ≈ 0.063mm。最小 24（约等于手机上 10pt 的说明字），正文 34。
# 新写的界面只用这几档，别再随手写 22、29。
const FS_HERO := 64    ## 年纪、弹窗里的大标题
const FS_TITLE := 52   ## 卡片标题
const FS_H := 40       ## 小标题、按钮大字
const FS_BODY := 34    ## 正文
const FS_LABEL := 28   ## 标签、次要按钮
const FS_CAPTION := 24 ## 说明、单位（最小）

# 留白：8 的倍数
const SP_XS := 8
const SP_S := 16
const SP_M := 24
const SP_L := 40
const SP_XL := 64

# 线：外框 2.5，纸片里分区 1.5
const LINE := 2.5
const LINE_HAIR := 1.5

# 动效：短的给按下、提示，中的给卡片落下，长的给整屏
const T_FAST := 0.14
const T_BASE := 0.26
const T_SLOW := 0.42

const ROLE_NAME := {"qing": "青", "mei": "梅"}
const WEALTH_NAME := ["清贫", "小康", "殷实"]
const STAT_NAME := {"body": "体魄", "mind": "心智", "charm": "魅力", "luck": "运气"}
const NEED_NAME := {"hunger": "饱腹", "energy": "精力", "mood": "心情", "clean": "清洁"}

const FONT_PATH := "res://fonts/LXGWWenKai-Regular.ttf"
## 像素画的界面字（缝合像素 12px，tools/subset_font.py 裁进来）；裁不到的字退回霞鹜文楷
const PIXEL_FONT_PATH := "res://fonts/FusionPixel-12px.ttf"
static var _font: Font = null


static func role_color(role: String) -> Color:
	return QING if role == "qing" else MEI


static func font() -> Font:
	if _font != null:
		return _font
	var base: Font = load(FONT_PATH) if ResourceLoader.exists(FONT_PATH) else ThemeDB.fallback_font
	_font = base
	if ResourceLoader.exists(PIXEL_FONT_PATH):
		var px = load(PIXEL_FONT_PATH)
		if px is FontFile:
			# 点阵字放大：不要微调、不要亚像素挪位，笔画才是一格一格的
			px.hinting = TextServer.HINTING_NONE
			px.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			px.fallbacks = [base]
			_font = px
	return _font


static func clock(minute: float) -> String:
	var m := int(minute)
	return "%02d:%02d" % [m / 60, m % 60]
