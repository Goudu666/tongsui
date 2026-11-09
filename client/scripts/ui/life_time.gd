extends RefCounted
## 回合 → 年龄与标签。与 server/src/sim.ts 的 lifeTimeAt 保持一致（只用于显示）。

const SEASONS := ["spring", "summer", "autumn", "winter"]
const SEASON_LABEL := ["立春", "立夏", "立秋", "立冬"]
const STAGES := [
	{"stage": "childhood", "from_age": 3, "tpy": 4.0, "years": 9},
	{"stage": "teen", "from_age": 12, "tpy": 2.0, "years": 6},
	{"stage": "young", "from_age": 18, "tpy": 1.0, "years": 12},
	{"stage": "middle", "from_age": 30, "tpy": 1.0 / 3.0, "years": 30},
	{"stage": "old", "from_age": 60, "tpy": 0.2, "years": 1000},
]


static func at(turn: int) -> Dictionary:
	var start := 0
	for i in STAGES.size():
		var st: Dictionary = STAGES[i]
		var turns := int(round(st.years * st.tpy))
		if turn < start + turns or i == STAGES.size() - 1:
			var k := turn - start
			var age := int(floor(st.from_age + k / st.tpy))
			if st.stage == "childhood":
				return {"age": age, "stage": st.stage, "label": "%d 岁 · %s" % [age, SEASON_LABEL[k % 4]]}
			if st.stage == "teen":
				return {"age": age, "stage": st.stage, "label": "%d 岁 · %s" % [age, "上学期" if k % 2 == 0 else "下学期"]}
			if st.stage == "young":
				return {"age": age, "stage": st.stage, "label": "%d 岁" % age}
			return {"age": age, "stage": st.stage, "label": "%d 岁那几年" % age}
		start += turns
	return {"age": 0, "stage": "childhood", "label": ""}
