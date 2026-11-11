extends RefCounted
## 混音表：三条总线和每个音效的音量。改音量只改这里。
## 导演（audio_director.gd）读这两张表；单测查表里的每个名字都有素材。
##
## 口径（数是 tools/audio/analyze.py --game 量出来的，改了声音就重跑一遍，照「该改成」那一列填）：
##   游戏里的响度 = 文件的短时最大响度（400 ms 窗，按调用处的 pitch 变速后量）+ CUE_DB + 调用处的 db + Sfx 总线
##   配乐参照 = 四轨全开的文件 -20 LUFS + Music 总线 = -18 LUFS。下面的目标都写成「比配乐响多少 LU」：
##     点按   tap -14  page -16  toast -12  type -22        一直在按，听一小时不能烦，最轻
##     反馈   bead -10（一整串）  gain -7  coin -8  cord -10   轻，但清楚
##     提示   shake -5  bell_duet -6  error -8  对门的门 -10
##     结果   pass 0  seal -1  settle -1  xingmu -2  miss -3  stamp -5   最重，不超过配乐 +2
##     仪式   death 0  birth -1  day_end -2
##     行动   act_* -6（拉灯 act_sleep 按 cord 算 -10）；对方做的事 audio_director.act 再轻 6 dB 以上
##   2~6 kHz 占比高于 -6 dB 的（车铃、钢镚儿、纸、铅笔、电铃……）目标再让 2 LU：同样响，这一段最扎耳朵。
##   最响的那次调用算数：gain 是揭晓过线那下（-2 dB、pitch 1.5），seal 是名次章（-1 dB、pitch 1.12），
##   bead 按 reveal.gd 的数法一整串量（72 分，约 26 颗）。
##   脚步不走这张表：音量在 audio_director.step()，文件响度在 sfx.py（STEP_LUFS），目标 -17（土路 -19）。

const BUS_DB := {"Music": 2.0, "Ambience": 1.0, "Sfx": -1.0}
## 单个音效的音量微调（dB）。没列出来的是 -6
const CUE_DB := {
	# 点按
	"tap": -5.5, "page": -9.5, "toast": -6.5, "type": -2.5,
	# 反馈（爽感层 ui/juice.gd、ui/reveal.gd）：算盘珠、长一点
	"bead": -10.5, "gain": -11.5, "coin": -8.0, "cord": -8.0,
	# 提示
	"shake": -5.0, "bell_duet": -14.5, "error": -4.0, "door_open": -8.0, "door_close": -7.5,
	# 结果：盖大印、够线、差一点、一个阶段过完；做选择的章、醒木
	"pass": -4.0, "seal": -1.0, "settle": -4.0, "miss": -9.5, "stamp": 2.0, "xingmu": -6.0,
	# 仪式
	"birth": -5.0, "day_end": -7.5, "death": -6.5,
	# 行动（audio_director.act 另外再 -4）
	"act_eat": -10.5, "act_eat_out": -5.0, "act_fish": -7.0, "act_knock": -0.5, "act_listen": -7.5,
	"act_perform": -6.0, "act_play_alley": -2.0, "act_play_river": 0.0, "act_play_roof": -3.0, "act_school": -13.0,
	"act_sleep": -4.0, "act_study": -5.5, "act_wash": -9.0, "act_work": -8.0}
