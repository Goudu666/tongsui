// 架构层面的保证（不测玩法数值，测「东西坏了以后会怎样」和「两边对不对得上」）：
// 1) 版本握手与内容下发  2) 消息校验  3) 存档往返不变  4) 剧情改了以后旧存档还能打开
// 5) 规则出错时回滚到上一次存档  6) 一条人生线只有一个房间能写存档  7) 客户端和服务端手抄的常量没有走样
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { G, C, J, NAMES, SYSTEM_USER, fakeNakama, room, logger } from "./harness.mjs";

const repo = (p) => readFileSync(new URL("../../" + p, import.meta.url), "utf8");
const OP = G("OP");
const pa = { userId: "user-a", sessionId: "sa" };
const pb = { userId: "user-b", sessionId: "sb" };

/** 配对、进房、确认投胎，得到一个正在过日子的房间 */
function startedRoom() {
  const env = fakeNakama();
  const a = env.rpc("rpcLifelineCreate", "user-a", { name: "小青" });
  env.rpc("rpcLifelineJoin", "user-b", { code: a.code, name: "小梅" });
  const open = env.rpc("rpcLifelineOpen", "user-a", { lifelineId: a.lifelineId });
  const R = room(env.nk, open.matchId);
  R.join([pa, pb]);
  R.loop([R.msg(pa, OP.ROLL, { confirm: true }), R.msg(pb, OP.ROLL, { confirm: true })]);
  assert.equal(R.life().phase, "life");
  return { ...env, R, id: a.lifelineId, matchId: open.matchId };
}

/** 模拟服务器重启：房间全没了，存档里的 matchId 是陈旧的 */
function restart(env, id) {
  env.nk.matches.clear();
  env.record(id).matchClaimedAt = Date.now() - 60000;
}

// ---------- 1. 版本握手与内容下发 ----------
{
  const env = fakeNakama();
  const a = env.rpc("rpcLifelineCreate", "user-a", { name: "小青" });
  // 旧安装包（不带协议版本 = 0）：在门口就被拦下，拿到一句人话
  assert.throws(() => env.rpc("rpcLifelineOpen", "user-a", { lifelineId: a.lifelineId, protocol: 0 }), /太旧[\s\S]*CLIENT_TOO_OLD/);
  const waiting = env.rpc("rpcLifelineOpen", "user-a", { lifelineId: a.lifelineId });
  assert.equal(waiting.protocol, G("PROTOCOL_VERSION"), "等配对时也要报版本");
  assert.equal(waiting.content, C.version);
  env.rpc("rpcLifelineJoin", "user-b", { code: a.code, name: "小梅" });
  const open = env.rpc("rpcLifelineOpen", "user-b", { lifelineId: a.lifelineId });
  assert.ok(open.matchId && open.protocol === G("PROTOCOL_VERSION") && open.content === C.version);
  assert.ok(G("MIN_CLIENT_PROTOCOL") <= G("PROTOCOL_VERSION"));

  const info = env.rpc("rpcServerInfo", "user-a", {});
  assert.deepEqual(info, { protocol: G("PROTOCOL_VERSION"), minClientProtocol: G("MIN_CLIENT_PROTOCOL"), content: C.version, lifeVersion: G("LIFE_VERSION"), events: C.events.length });

  // 内容指纹就是内容本身的哈希：内容一样指纹就一样，改一个字就变
  const { version, ...body } = J(C);
  assert.equal(version, createHash("sha256").update(JSON.stringify(body)).digest("hex").slice(0, 12));
  const bundled = JSON.parse(repo("client/data/content.json"));
  assert.equal(bundled.version, C.version, "client/data/content.json 和服务端内容不是同一版，运行 npm run content");

  // 分块下载：拼起来就是服务器手里那一份
  let text = "", offset = 0, calls = 0;
  for (;;) {
    const part = env.rpc("rpcContentGet", "user-a", { offset });
    assert.equal(part.offset, offset);
    assert.equal(part.version, C.version);
    assert.ok(part.chunk.length > 0 && part.chunk.length <= G("CONTENT_CHUNK"));
    const last = part.chunk.charCodeAt(part.chunk.length - 1);
    assert.ok(!(last >= 0xd800 && last <= 0xdbff), "不能把一个字拆成两半");
    text += part.chunk;
    offset += part.chunk.length;
    assert.ok(++calls < 50);
    if (part.done) { assert.equal(text.length, part.total); break; }
  }
  assert.deepEqual(JSON.parse(text), bundled, "下载到的内容要和安装包里带的那份一模一样");
  assert.equal(env.rpc("rpcContentGet", "user-a", { offset: 1e9 }).chunk, "", "越界的 offset 回空块，不报错");
  console.log(`✓ 版本握手：旧安装包被拦下并提示 / 回复带协议版本和内容指纹 / 内容指纹 = 内容哈希 / 内容分 ${calls} 块下载后与安装包一致`);
}

// ---------- 2. 消息校验：坏消息只换来一个 ERROR，房间不能倒 ----------
{
  const { R } = startedRoom();
  const raw = (p, op, text) => ({ sender: p, opCode: op, data: new TextEncoder().encode(text) });
  const bad = [
    raw(pa, OP.PING, "null"), raw(pa, OP.PING, "5"), raw(pa, OP.MOVE, "[1,2]"), raw(pa, OP.CHOOSE, '"x"'),
    raw(pa, OP.ACT, "{oops"), raw(pa, 99, "{}"), raw(pa, OP.SNAPSHOT, "{}"),
  ];
  const before = R.to(pa, OP.ERROR).length;
  for (const m of bad) assert.equal(R.loop([m]), true, "坏消息不能让房间关掉");
  assert.equal(R.to(pa, OP.ERROR).length - before, bad.length, "每条坏消息都回一个 ERROR");
  assert.ok(R.sent.filter((m) => m.op === OP.ERROR).every((m) => m.to && m.to[0] === "sa"), "ERROR 只回给发的人");
  // 字段类型不对（不是崩，是被规则拒绝）
  R.loop([R.msg(pa, OP.MOVE, { x: "abc", y: null, seq: {} }), R.msg(pa, OP.ACT, { spot: 123 }), R.msg(pa, OP.CHOOSE, {})]);
  assert.equal(R.loop(), true);
  assert.equal(R.loop([R.msg(pa, OP.PING, { t: 7 })]), true);
  assert.equal(R.to(pa, OP.PONG).at(-1).data.t, 7, "正常消息照常处理");
  console.log("✓ 消息校验：null / 数字 / 数组 / 字符串 / 坏 JSON / 未知消息号 / 服务端专用消息号 都只回 ERROR，房间照常");
}

// ---------- 3. 存档往返不变：存档就是全部状态 ----------
// 同一个种子的人生，中途随时「存档 → 读档」（JSON 往返），结果必须和一口气跑完的一模一样。
// 哪天有人把状态放到 LifeState 外面（模块级变量、闭包、没进存档的字段），这里会第一时间挂掉。
{
  const pick = (s, role, eventId) => {
    const ev = C.events.find((e) => e.id === eventId);
    const h = createHash("md5").update(`${eventId}/${role}/${s.turn}`).digest();
    return ev.options[h[0] % ev.options.length].id;
  };
  const live = (seed, reloadEvery) => {
    let s = G("lifeCreate")(seed, C);
    G("lifeConfirm")(s, C, "qing", NAMES);
    G("lifeConfirm")(s, C, "mei", NAMES);
    for (let tick = 1; s.phase !== "ended"; tick++) {
      G("worldAdvance")(s, C, 0.1, { qing: false, mei: false });
      if (s.world && s.world.event) {
        const pe = s.world.event;
        for (const r of pe.roles) G("worldChoose")(s, C, r, pick(s, r, pe.eventId), false);
      }
      if (reloadEvery && tick % reloadEvery === 0) s = J(s);
      assert.ok(tick < 400000, "人生没有结束");
    }
    return s;
  };
  let reloads = 0;
  for (const seed of [3, 11, 20261110]) {
    const straight = live(seed, 0);
    for (const every of [7, 997]) {
      const reloaded = live(seed, every);
      assert.deepEqual(J(reloaded), J(straight), `种子 ${seed}：每 ${every} 跳读一次档，人生走样了`);
      reloads++;
    }
    assert.deepEqual(J(live(seed, 0)), J(straight), `种子 ${seed}：同一个种子跑两遍结果不同`);
  }
  console.log(`✓ 存档往返：3 条人生 × ${reloads / 3} 种读档节奏，和一口气跑完逐字段一致；同种子可复现`);
}

// ---------- 4. 剧情改了以后，旧存档还能打开 ----------
{
  // 4a. 纯函数：人生过到一半，把存档正指着的事件、行动从内容里删掉，修复后还能过完一生
  let fixedTotal = 0;
  for (let seed = 1; seed <= 12; seed++) {
    const s = G("lifeCreate")(seed, C);
    G("lifeConfirm")(s, C, "qing", NAMES);
    G("lifeConfirm")(s, C, "mei", NAMES);
    const stopAt = 5 + seed * 5; // 在不同的年纪动手
    let gone = null, C2 = C;
    for (let tick = 0; s.phase !== "ended"; tick++) {
      G("worldAdvance")(s, C2, 0.1, { qing: false, mei: false });
      // 等到「有事件卡着」的一跳再删内容，这样悬空引用最多：卡着的事件、今天剩下的命运、做到一半的行动
      if (!gone && s.turn >= stopAt && s.world && s.world.event) {
        const w = s.world;
        gone = new Set([w.fate.mirror, w.fate.qing, w.fate.mei, w.event.eventId].filter(Boolean));
        const busy = ["qing", "mei"].map((r) => w.actors[r] && w.actors[r].action).filter((x) => x && x !== "sleep");
        C2 = { ...C, version: "rewritten", events: C.events.filter((e) => !gone.has(e.id)) };
        if (busy.length) C2.map = { ...C.map, actions: C.map.actions.filter((x) => !busy.includes(x.id)), spots: C.map.spots.filter((sp) => !busy.includes(sp.action)) };
        assert.throws(() => { const t = J(s); G("worldChoose")(t, C2, t.world.event.roles[0], "x", true); }, /not found/, "不修复的话，规则代码一查这个事件就抛错");
        const notes = G("lifeRepair")(s, C2);
        assert.ok(notes.length >= 1, "应该报告摘掉了什么");
        assert.equal(s.world.event, null);
        assert.equal(s.contentVersion, "rewritten");
        assert.equal(G("lifeRepair")(s, C2).length, 0, "修过一次就干净了");
        fixedTotal += notes.length;
      }
      if (s.world && s.world.event) {
        const pe = s.world.event;
        for (const r of pe.roles) G("worldChoose")(s, C2, r, G("lifeShadowChoose")(s, C2, r, pe.eventId), true);
      }
      assert.ok(tick < 400000);
    }
    assert.ok(gone, `种子 ${seed}：没等到可以动手的时机`);
    assert.equal(s.log.at(-1).kind, "end");
  }

  // 4b. 抽卡阶段：抽到的人家被删了，替他重抽，不扣次数
  {
    const s = G("lifeCreate")(5, C);
    const lost = s.rolls.qing.familyId, left = s.rolls.qing.rerollsLeft;
    s.rolls.qing.confirmed = true;
    const C2 = { ...C, version: "x", families: C.families.filter((f) => f.id !== lost) };
    assert.ok(G("lifeRepair")(s, C2).some((n) => n.includes(lost)));
    assert.ok(C2.families.some((f) => f.id === s.rolls.qing.familyId) && s.rolls.qing.familyId !== s.rolls.mei.familyId);
    assert.equal(s.rolls.qing.rerollsLeft, left);
    assert.equal(s.rolls.qing.confirmed, false, "换了人家要重新确认");
  }

  // 4c. 走真实路径：存档里留着悬空引用，服务器重启后 lifeline_open 照样能拉起房间
  {
    const env = startedRoom();
    env.R.leave([pb]); // 存档
    restart(env, env.id);
    const saved = env.record(env.id).life;
    saved.version = 2; // 旧结构
    delete saved.contentVersion;
    saved.world.fate = { mirror: "ghost_mirror", qing: "ghost_solo", mei: null };
    saved.world.event = { eventId: "ghost_event", kind: "solo", roles: ["qing"], choices: {}, shadow: [] };
    Object.assign(saved.world.actors.mei, { action: "ghost_action", spot: "ghost_spot", until: 600, x: 99999, y: -5 });
    saved.persons.qing.familyId = "ghost_family";
    logger.lines.length = 0;
    const open = env.rpc("rpcLifelineOpen", "user-a", { lifelineId: env.id });
    const R2 = room(env.nk, open.matchId);
    R2.join([{ userId: "user-a", sessionId: "sa2" }]);
    const life = R2.life();
    assert.equal(life.version, G("LIFE_VERSION"));
    assert.equal(life.contentVersion, C.version);
    assert.deepEqual(J(life.world.fate), { mirror: null, qing: null, mei: null });
    assert.equal(life.world.event, null);
    assert.equal(life.world.actors.mei.action, null);
    assert.ok(life.world.actors.mei.x <= C.map.size[0] && life.world.actors.mei.y >= 0);
    assert.ok(logger.lines.some(([lv, t]) => lv === "info" && t.includes("ghost_event")), "修了什么要写进服务器日志");
    // 去吃饭：结算时要查家境，查不到的人家按普通家境算，不能崩
    const table = C.map.spots.find((sp) => sp.action === "eat" && C.map.zones.find((z) => z.id === sp.zone).owner === "qing");
    Object.assign(life.world.actors.qing, { x: table.at[0], y: table.at[1] });
    life.persons.qing.needs.hunger = 10;
    R2.loop([R2.msg({ userId: "user-a", sessionId: "sa2" }, OP.ACT, { spot: table.id })]);
    assert.equal(life.world.actors.qing.action, "eat");
    for (let i = 0; i < 3000; i++) assert.equal(R2.loop(), true, "修复后的房间要能一直跑下去");
    assert.ok(life.persons.qing.needs.hunger > 10 || life.turn > 0, "饭吃上了");
    assert.equal(env.record(env.id).life.version, G("LIFE_VERSION"), "升级后的结构写回了存档");

    // 存档比服务器还新（服务器被回滚了）：不硬读，把原因说清楚
    R2.leave([{ userId: "user-a", sessionId: "sa2" }]);
    restart(env, env.id);
    env.record(env.id).life.version = 99;
    assert.throws(() => env.rpc("rpcLifelineOpen", "user-a", { lifelineId: env.id }), /暂时打不开[\s\S]*存档版本 99/);
    assert.equal(env.record(env.id).life.version, 99, "打不开的存档不能被改写");
  }
  console.log(`✓ 内容变更：12 条人生中途删掉正在用的事件/行动（共摘掉 ${fixedTotal} 处悬空引用）仍过完一生 / 抽卡阶段重抽 / v2 存档升级 / 悬空引用经 lifeline_open 自动修复并记日志 / 未来版本存档拒绝打开`);
}

// ---------- 5. 规则出错：回滚到上一次存档，而不是带着改了一半的状态继续 ----------
{
  const env = startedRoom();
  const { R } = env;
  for (let i = 0; i < 20; i++) R.loop();
  R.leave([pb]); // 存档点
  R.join([pb]);
  const savedMinute = env.record(env.id).life.world.minute;
  for (let i = 0; i < 50; i++) R.loop();
  assert.ok(R.life().world.minute > savedMinute);
  // 模拟一个规则 bug：内存里的状态坏了（存档里是好的）
  R.life().world.fate.qing = "ghost_event_from_a_bug";
  logger.lines.length = 0;
  assert.equal(R.loop(), false, "出错的房间要关掉");
  const rec = env.record(env.id);
  assert.equal(rec.matchId, null, "清掉 matchId，重连时马上能拉起新房间");
  assert.equal(rec.faults, 1);
  assert.match(rec.lastFault, /ghost_event_from_a_bug/);
  assert.equal(rec.life.world.minute, savedMinute, "存档停在出错前的存档点");
  assert.ok(!JSON.stringify(rec.life).includes("ghost_event_from_a_bug"), "坏状态不能进存档");
  const told = R.sent.filter((m) => m.op === OP.ERROR && m.data.fault).at(-1);
  assert.ok(told && told.to === null, "两个人都要被告知");
  assert.ok(logger.lines.some(([lv, t]) => lv === "error" && t.includes("room fault") && t.includes(env.id)), "日志里要有人生线 id 和现场");
  // 客户端自动重连：从存档重新拉起，接着过
  const again = env.rpc("rpcLifelineOpen", "user-a", { lifelineId: env.id });
  assert.notEqual(again.matchId, env.matchId);
  const R2 = room(env.nk, again.matchId);
  R2.join([pa, pb]);
  for (let i = 0; i < 100; i++) assert.equal(R2.loop(), true);
  assert.ok(R2.life().world.minute > savedMinute);
  console.log("✓ 出错回滚：房间关闭 / 存档停在上一个存档点且不含坏状态 / 记下次数和原因 / 通知两人 / 日志带现场 / 重连后从存档接着过");
}

// ---------- 6. 一条人生线只有一个房间能写存档 ----------
{
  const env = startedRoom();
  const { R, nk } = env;
  const key = { collection: "lifelines", key: env.id, userId: SYSTEM_USER };
  // 6a. 存档被动过但还是这个房间的（比如在 Nakama 控制台里手动保存）：以房间里的为准
  nk.storageWrite([{ ...key, value: J(env.record(env.id)) }]);
  for (let i = 0; i < 10; i++) R.loop();
  R.leave([pb]);
  assert.equal(R.state.superseded, false);
  assert.equal(env.record(env.id).life.world.minute, R.life().world.minute, "还是自己的房间：照常存上");
  R.join([pb]);
  // 6b. 另一个房间接管了这条人生线，而且已经往前过了
  const theirs = J(env.record(env.id));
  theirs.matchId = "another-room.node";
  theirs.life.turn = 41;
  nk.storageWrite([{ ...key, value: theirs }]);
  R.leave([pb]); // 这个房间想存档
  assert.equal(R.state.superseded, true);
  assert.equal(env.record(env.id).matchId, "another-room.node");
  assert.equal(env.record(env.id).life.turn, 41, "不能把对方的进度盖回去");
  assert.equal(R.loop(), false, "被接管的房间下一跳就退场");
  assert.equal(env.record(env.id).life.turn, 41, "退场时也不写");
  assert.equal(env.record(env.id).matchId, "another-room.node");
  console.log("✓ 单写者：存档带版本号条件写入 / 手动改过的存档以房间为准 / 被别的房间接管后不再写、自动退场");
}

// ---------- 7. 契约：客户端和服务端各抄了一份的东西没有走样 ----------
{
  // 消息号、通知码、协议版本
  const gd = repo("client/scripts/net/protocol.gd");
  const consts = Object.fromEntries([...gd.matchAll(/^const (\w+) := (-?\d+)/gm)].map((m) => [m[1], Number(m[2])]));
  for (const [name, code] of Object.entries(J(OP))) assert.equal(consts[name], code, `protocol.gd 的 ${name} 应为 ${code}（main.ts 的 OP）`);
  const extra = Object.keys(consts).filter((k) => !(k in OP) && !["NOTIFY_PARTNER_JOINED", "NOTIFY_PARTNER_ONLINE", "VERSION", "MIN_SERVER"].includes(k));
  assert.deepEqual(extra, [], "protocol.gd 里有服务端没有的消息号");
  assert.equal(consts.NOTIFY_PARTNER_JOINED, G("NOTIFY_PARTNER_JOINED"));
  assert.equal(consts.NOTIFY_PARTNER_ONLINE, G("NOTIFY_PARTNER_ONLINE"));
  assert.equal(consts.VERSION, G("PROTOCOL_VERSION"), "protocol.gd 的 VERSION 要和 main.ts 的 PROTOCOL_VERSION 一起改");
  assert.ok(consts.MIN_SERVER <= G("PROTOCOL_VERSION"), "仓库里的客户端连不上仓库里的服务端");
  assert.ok(G("MIN_CLIENT_PROTOCOL") <= consts.VERSION, "仓库里的服务端不让仓库里的客户端进");
  // 测试机器人用的消息号
  const bot = repo("server/test/e2e.mjs").match(/const OP = (\{[^}]+\})/);
  assert.deepEqual(new Function(`return ${bot[1]}`)(), J(OP), "server/test/e2e.mjs 的 OP 和 main.ts 不一致");
  assert.equal(Number(repo("server/test/e2e.mjs").match(/const PROTOCOL = (\d+)/)[1]), G("PROTOCOL_VERSION"), "server/test/e2e.mjs 的 PROTOCOL 和 main.ts 不一致");

  // 回合 → 年龄阶段（客户端只用来显示和换角色外观）
  const lt = repo("client/scripts/ui/life_time.gd");
  const stages = [...lt.matchAll(/\{"stage": "(\w+)", "from_age": (\d+), "tpy": ([\d. /]+), "years": (\d+)\}/g)]
    .map((m) => ({ stage: m[1], fromAge: Number(m[2]), turnsPerYear: new Function(`return ${m[3]}`)(), years: Number(m[4]) }));
  assert.deepEqual(stages, J(G("STAGE_TABLE")), "life_time.gd 的 STAGES 和 sim.ts 的 STAGE_TABLE 不一致");

  // 走动：客户端必须比服务器的限速慢一点、够得着的范围小一点，否则会被服务器拽回去 / 点了没反应
  const num = (file, name) => {
    const m = repo(file).match(new RegExp(`^const ${name} := ([\\d.]+)`, "m"));
    assert.ok(m, `${file} 里找不到 const ${name}（改名了的话，把这条契约也改过来）`);
    return Number(m[1]);
  };
  assert.ok(num("client/scripts/world/actor.gd", "WALK_SPEED") < G("WALK_SPEED"), "客户端走得比服务器限速还快");
  assert.ok(num("client/scripts/world/world_view.gd", "SPOT_RADIUS") < G("SPOT_RADIUS"), "客户端的互动范围比服务器的大");
  assert.equal(num("client/scripts/world/world_view.gd", "TICK_RATE"), G("TICK_RATE"), "客户端按错误的 tick 频率插值");
  console.log(`✓ 契约：${Object.keys(OP).length} 个消息号 / 通知码 / 协议版本 / 测试机器人消息号 / 年龄阶段表 / 走动限速与互动范围 / tick 频率 两边一致`);
}
