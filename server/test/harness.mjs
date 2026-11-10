// 测试共用的底座：把编译好的 build/index.js 装进一个 vm，再配一个假的 Nakama。
// 假 Nakama 尽量贴近真的：存储带版本号（条件写入会冲突、写入返回新版本号）、matchCreate 同步调用 matchInit 并带 ctx.matchId、
// 房间关闭后 matchGet 返回 null、通知会被记下来。
import { readFileSync } from "node:fs";
import vm from "node:vm";

const code = readFileSync(new URL("../build/index.js", import.meta.url), "utf8");
const ctx = vm.createContext({ console, JSON, Math, Date });
vm.runInContext(code, ctx);
/** 取模块里的全局函数 / 变量 */
export const G = (name) => vm.runInContext(name, ctx);
export const C = G("CONTENT");
export const J = (x) => JSON.parse(JSON.stringify(x));
export const SYSTEM_USER = "00000000-0000-0000-0000-000000000000";
export const NAMES = { qing: "青", mei: "梅" };

/** 假 logger：内容记在 logger.lines 里，测试可以查服务器有没有把该说的话写进日志 */
export const logger = {
  lines: [],
  info(...a) { this.lines.push(["info", a.join(" ")]); },
  warn(...a) { this.lines.push(["warn", a.join(" ")]); },
  error(...a) { this.lines.push(["error", a.join(" ")]); },
  debug() {},
};
export function fakeNakama() {
  const store = new Map(); // key -> { value, version, updateTime }
  const k = (c, key, u) => `${c}/${u}/${key}`;
  let ver = 0, matchSeq = 0, clock = 1000;
  const matches = new Map(); // id -> { state }
  const notifications = [];
  const nk = {
    store, matches, notifications, k,
    uuidv4: () => `uuid-${Math.random().toString(16).slice(2)}`,
    storageRead: (reqs) => reqs.flatMap((r) => {
      const o = store.get(k(r.collection, r.key, r.userId));
      return o ? [{ key: r.key, value: structuredClone(o.value), version: o.version, updateTime: o.updateTime }] : [];
    }),
    storageWrite: (ws) => {
      for (const w of ws) {
        const cur = store.get(k(w.collection, w.key, w.userId));
        if (w.version !== undefined) {
          const ok = w.version === "*" ? !cur : cur && cur.version === w.version;
          if (!ok) throw new Error("Storage write rejected - version check failed.");
        }
      }
      return ws.map((w) => {
        const version = `v${++ver}`;
        store.set(k(w.collection, w.key, w.userId), { value: structuredClone(w.value), version, updateTime: ++clock });
        return { collection: w.collection, key: w.key, userId: w.userId, version };
      });
    },
    storageList: (u, c) => ({
      objects: [...store.entries()].filter(([key]) => key.startsWith(`${c}/${u}/`)).map(([key, o]) => ({ key: key.split("/")[2], value: o.value, updateTime: o.updateTime })),
    }),
    matchCreate: (name, params) => {
      const id = `m${++matchSeq}.node`;
      const init = G("matchInit")({ matchId: id }, logger, nk, params); // 失败就抛出，和真的一样
      matches.set(id, { state: init.state });
      return id;
    },
    matchGet: (id) => (matches.has(id) ? { matchId: id } : null),
    notificationsSend: (ns) => notifications.push(...ns),
    binaryToString: (b) => Buffer.from(b).toString("utf8"),
  };
  /** 调 RPC。默认像真客户端一样带上协议版本；想模拟旧安装包就自己传 protocol */
  const rpc = (name, userId, payload) => JSON.parse(G(name)({ userId }, logger, nk, JSON.stringify({ protocol: G("PROTOCOL_VERSION"), ...payload })));
  /** 存储里的那份存档（活引用，改它等于改数据库里的内容，不动版本号） */
  const record = (id) => store.get(k("lifelines", id, SYSTEM_USER)).value;
  return { nk, rpc, record };
}

/** 一个房间的驱动器：收发消息、推进 tick */
export function room(nk, matchId) {
  const sent = [];
  const dispatcher = { broadcastMessage: (op, data, to) => sent.push({ op, data: JSON.parse(data), to: to ? to.map((p) => p.sessionId) : null }) };
  const m = nk.matches.get(matchId);
  let tick = 1;
  const msg = (p, op, body) => ({ sender: p, opCode: op, data: new TextEncoder().encode(JSON.stringify(body)) });
  const r = {
    sent, dispatcher, msg,
    get state() { return m.state; },
    life: () => m.state.record.life,
    join: (ps) => { m.state = G("matchJoin")({}, logger, nk, dispatcher, tick, m.state, ps).state; },
    leave: (ps) => { m.state = G("matchLeave")({}, logger, nk, dispatcher, tick, m.state, ps).state; },
    attempt: (p) => G("matchJoinAttempt")({}, logger, nk, dispatcher, tick, m.state, p),
    loop: (msgs = []) => {
      const res = G("matchLoop")({}, logger, nk, dispatcher, tick++, m.state, msgs);
      if (res === null) { nk.matches.delete(matchId); return false; }
      m.state = res.state;
      return true;
    },
    /** 发给某个连接的消息（含广播） */
    to: (p, op) => sent.filter((x) => x.op === op && (x.to === null || x.to.includes(p.sessionId))),
  };
  return r;
}
