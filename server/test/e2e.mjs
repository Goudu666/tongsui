// 真 Nakama 端到端：两个机器人走一遍「两台手机一起玩」，专测联机层。
// 需要一台跑着本模块的 Nakama（docker compose 或 CI 里的容器）：
//   NAKAMA_HOST=127.0.0.1 NAKAMA_PORT=7350 NAKAMA_KEY=defaultkey npm --prefix server run e2e
// 覆盖：配对通知 / 并发打开同一个房间 / 进房快照 / 投胎开局 / 走动同步与序号回执 / 心跳 /
//      断线换连接（旧连接被顶掉、旧连接的消息作废）/ 掉线存档 / 重新打开回到同一个房间 / 人生线列表 /
//      版本握手（旧安装包被拦下）/ 从真服务器分块下载剧情内容，和安装包里那份一致
import { readFileSync } from "node:fs";
import assert from "node:assert/strict";
import WebSocket from "ws";

globalThis.WebSocket = WebSocket;
const { Client } = await import("@heroiclabs/nakama-js");

const HOST = process.env.NAKAMA_HOST || "127.0.0.1";
const PORT = process.env.NAKAMA_PORT || "7350";
const KEY = process.env.NAKAMA_KEY || "defaultkey";
const PROTOCOL = 7; // 和 main.ts 的 PROTOCOL_VERSION 一起改（arch.test.mjs 的契约测试会比对）
const OP = { SNAPSHOT: 1, ROLL: 2, ROLL_STATE: 3, MOVE: 4, ACT: 5, CHOOSE: 6, WORLD: 7, EVENT: 8, ERROR: 9, LOG: 10, PRESENCE: 11, PING: 12, PONG: 13, PASS: 22, CANCEL: 23, EXIT: 24, ECHO: 30, AGAIN: 31 };
const run = Date.now().toString(36);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const dec = new TextDecoder();

/** 一个「手机」：登录 + socket + 收到的消息 */
async function phone(name) {
  const client = new Client(KEY, HOST, PORT, false, 7000);
  const session = await client.authenticateDevice(`e2e-${name}-${run}`, true);
  const p = { name, client, session, inbox: [], notes: [], socket: null, matchId: null };
  p.connect = async () => {
    const socket = client.createSocket(false, false);
    socket.onmatchdata = (m) => p.inbox.push({ op: Number(m.op_code), data: JSON.parse(dec.decode(m.data)), socket });
    socket.onnotification = (n) => p.notes.push(n);
    await socket.connect(session, true);
    p.socket = socket;
    return socket;
  };
  // 像真客户端一样，打开人生线时报上自己的协议版本
  p.rpc = async (id, body) => (await client.rpc(session, id, id === "lifeline_open" ? { protocol: PROTOCOL, ...body } : body)).payload;
  // 进房时报协议版本（3 版起的安装包会报）。old = true 模拟不报的旧安装包
  p.join = async (matchId, old = false) => { p.matchId = matchId; await p.socket.joinMatch(matchId, undefined, old ? undefined : { protocol: String(PROTOCOL) }); };
  p.send = (op, body, socket = p.socket) => socket.sendMatchState(p.matchId, op, JSON.stringify(body));
  /** 等到收到满足条件的消息 */
  p.wait = async (op, pred = () => true, ms = 5000, socket = null) => {
    const t0 = Date.now();
    while (Date.now() - t0 < ms) {
      const hit = p.inbox.find((m) => m.op === op && (!socket || m.socket === socket) && pred(m.data));
      if (hit) return hit.data;
      await sleep(20);
    }
    throw new Error(`${name}: 等不到 op ${op}`);
  };
  p.clear = () => { p.inbox.length = 0; };
  return p;
}

const qing = await phone("qing");
const mei = await phone("mei");
await qing.connect();
await mei.connect();

// 1. 配对：青开线，梅输码，青收到通知
const created = await qing.rpc("lifeline_create", { name: "小青" });
assert.equal(created.code.length, 6);
assert.equal((await qing.rpc("lifeline_open", { lifelineId: created.lifelineId })).waitingForPartner, true);
const joined = await mei.rpc("lifeline_join", { code: created.code.toLowerCase(), name: "小梅" });
assert.equal(joined.role, "mei");
for (let i = 0; i < 100 && !qing.notes.some((n) => n.subject === "partner_joined"); i++) await sleep(30);
const note = qing.notes.find((n) => n.subject === "partner_joined");
assert.ok(note, "青应收到 partner_joined 通知");
assert.equal(note.content.lifelineId, created.lifelineId);
console.log("✓ 配对：配对码（不分大小写）/ 青实时收到「TA 来了」通知");

// 2. 两人同一瞬间各打开 8 次：必须全部是同一个房间
const opens = await Promise.all(
  Array.from({ length: 16 }, (_, i) => (i % 2 ? qing : mei).rpc("lifeline_open", { lifelineId: created.lifelineId }))
);
const ids = new Set(opens.map((o) => o.matchId));
assert.equal(ids.size, 1, `并发打开应只拉起一个房间，实际 ${[...ids].join(", ")}`);
const matchId = opens[0].matchId;
console.log("✓ 并发：两人同时打开 16 次，只有一个房间");

// 3. 进房 + 投胎
await qing.join(matchId);
await mei.join(matchId, true); // 梅先用旧安装包进来
const snapQ = await qing.wait(OP.SNAPSHOT);
assert.equal(snapQ.you, "qing");
assert.equal(snapQ.life.phase, "roll");
assert.equal(snapQ.life.rng, undefined);
assert.equal(snapQ.life.life, 1, "头一世");
// 房间知道两边安装包的版本：进房时报了的按报的算，没报的按能进来的最旧版本算（传承，docs/LEGACY.md）
const snapM = await mei.wait(OP.SNAPSHOT);
const oldest = (await qing.rpc("server_info", {})).minClientProtocol;
assert.deepEqual(snapM.protocols, { qing: PROTOCOL, mei: oldest }, "快照里两边安装包的版本");
qing.send(OP.ROLL, { confirm: true });
mei.send(OP.ROLL, { confirm: true });
await qing.wait(OP.SNAPSHOT, (d) => d.life.phase === "life");
const lifeM = await mei.wait(OP.SNAPSHOT, (d) => d.life.phase === "life");
assert.ok(lifeM.life.world.actors.qing && lifeM.life.world.actors.mei);
console.log("✓ 进房快照 / 两人确认投胎后同时开局");

// 4. 心跳
const t = Date.now();
qing.send(OP.PING, { t });
const pong = await qing.wait(OP.PONG, (d) => d.t === t);
console.log(`✓ 心跳：往返 ${Date.now() - t} ms，服务器 tick ${pong.tick}`);

// 5. 青走动，梅在 WORLD 里看到；服务器回执序号
const start = lifeM.life.world.actors.qing;
let x = start.x, seq = 0;
for (let i = 0; i < 15; i++) {
  x += 30;
  qing.send(OP.MOVE, { x, y: start.y, seq: ++seq });
  await sleep(100);
}
const seen = await mei.wait(OP.WORLD, (d) => d.actors.qing.seq === seq && d.actors.qing.x === x);
assert.equal(seen.actors.qing.x, x, "梅看到的青的位置要和青上报的一致");
const ticks = mei.inbox.filter((m) => m.op === OP.WORLD).map((m) => m.data.tick);
assert.ok(ticks.every((v, i) => i === 0 || v > ticks[i - 1]), "WORLD 的 tick 单调递增");
// 乱序的旧包作废
qing.send(OP.MOVE, { x: x - 200, y: start.y, seq: seq - 3 });
await sleep(300);
const after = (await mei.wait(OP.WORLD, (d) => d.tick > seen.tick + 2)).actors.qing;
assert.equal(after.x, x, "旧序号的包不能把人拉回去");
const rate = ticks.length / ((ticks.at(-1) - ticks[0]) / 10 || 1);
console.log(`✓ 同框走动：梅实时看到青走了 ${x - start.x}px / 序号回执 / 旧包作废 / 世界广播约 ${rate.toFixed(1)} Hz`);

// 6. 梅断线换连接（模拟切 4G/Wi-Fi）：新连接进房，旧连接被顶掉
const oldSocket = mei.socket;
const newSocket = await mei.connect();
mei.clear();
await mei.join(matchId);
const resnap = await mei.wait(OP.SNAPSHOT, () => true, 5000, newSocket);
assert.equal(resnap.you, "mei");
assert.deepEqual(resnap.protocols, { qing: PROTOCOL, mei: PROTOCOL }, "梅换了新安装包重新进来，版本跟着变");
assert.equal(resnap.life.phase, "life");
assert.equal(resnap.life.world.actors.qing.x, x, "重连快照里青的位置是最新的");
const meiPos = resnap.life.world.actors.mei;
mei.send(OP.MOVE, { x: meiPos.x + 25, y: meiPos.y, seq: 50 }, oldSocket);
await sleep(400);
const w1 = await qing.wait(OP.WORLD, (d) => d.tick > pong.tick && true);
qing.clear();
const w2 = await qing.wait(OP.WORLD);
assert.equal(w2.actors.mei.x, meiPos.x, "旧连接的 MOVE 不算");
oldSocket.disconnect(false);
await sleep(500);
const pres = qing.inbox.filter((m) => m.op === OP.PRESENCE).at(-1);
assert.ok(!pres || pres.data.online.mei === true, "旧连接断开不能把梅踢下线");
mei.send(OP.MOVE, { x: meiPos.x + 25, y: meiPos.y, seq: 1 });
await qing.wait(OP.WORLD, (d) => d.actors.mei.x === meiPos.x + 25);
void w1;
console.log("✓ 断线重连：新连接接管 / 重连快照 / 旧连接的包作废 / 旧连接断开不掉线 / 序号从 1 重来");

// 7. 梅真的掉线：青看到 TA 下线；梅回来打开，还是同一个房间
qing.clear();
newSocket.disconnect(false);
await qing.wait(OP.PRESENCE, (d) => d.online.mei === false);
const reopen = await mei.rpc("lifeline_open", { lifelineId: created.lifelineId });
assert.equal(reopen.matchId, matchId, "房间存档之后再打开，仍然是同一个房间");
await mei.connect();
await mei.join(matchId);
await qing.wait(OP.PRESENCE, (d) => d.online.mei === true);
console.log("✓ 掉线：青收到「TA 下线了」/ 梅重新打开回到同一个房间 / 青收到「TA 上线了」");

// 8. 列表
const list = (await qing.rpc("lifeline_list", {})).lifelines;
const mine = list.find((l) => l.lifelineId === created.lifelineId);
assert.ok(mine && mine.paired && mine.phase === "life" && mine.names.mei === "小梅" && mine.label);
console.log(`✓ 人生线列表：${mine.names.qing} & ${mine.names.mei} · ${mine.label}`);

// 9. 换手机找回：旧手机绑定找回码（custom id），新手机用它登录，回到同一个账号、看到同一条人生线
const rcode = `tongsui-recover-E2E${run}`.slice(0, 40);
await qing.client.linkCustom(qing.session, { id: rcode });
const fresh = new Client(KEY, HOST, PORT, false, 7000);
const newPhone = await fresh.authenticateCustom(rcode, false);
assert.equal(newPhone.user_id, qing.session.user_id, "找回码登回同一个账号");
const list2 = (await fresh.rpc(newPhone, "lifeline_list", {})).payload.lifelines;
assert.ok(list2.some((l) => l.lifelineId === created.lifelineId), "新手机上能看到原来的人生线");
await assert.rejects(fresh.authenticateCustom("tongsui-recover-WRONGCODE0", false), "错的找回码不能新建账号");
console.log("✓ 换手机找回：找回码登回同一个账号，人生线还在 / 错码登不进");

// 10. 版本握手与内容下发
const info = await qing.rpc("server_info", {});
assert.equal(info.protocol, PROTOCOL, "e2e.mjs 的 PROTOCOL 要和服务器的 PROTOCOL_VERSION 一致");
await assert.rejects(qing.rpc("lifeline_open", { lifelineId: created.lifelineId, protocol: 0 }), "不报协议版本的旧安装包不能进房间");
assert.equal(reopen.content, info.content, "lifeline_open 的回复带内容指纹");
let text = "", parts = 0;
for (;;) {
  const part = await mei.rpc("content_get", { offset: text.length });
  assert.equal(part.version, info.content);
  text += part.chunk;
  parts++;
  if (part.done) { assert.equal(text.length, part.total); break; }
  assert.ok(part.chunk.length > 0 && parts < 50);
}
const bundled = JSON.parse(readFileSync(new URL("../../client/data/content.json", import.meta.url), "utf8"));
assert.deepEqual(JSON.parse(text), bundled, "从服务器下载的内容要和 client/data/content.json 一模一样");
console.log(`✓ 版本握手：服务器协议 ${info.protocol} / 旧安装包被拦下 / 内容 ${info.content} 分 ${parts} 块下载，${text.length} 字符，与安装包一致`);

qing.socket.disconnect(false);
mei.socket.disconnect(false);
process.exit(0);
