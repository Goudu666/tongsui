#!/usr/bin/env node
// 量一下对门的电脑有多「跟着你」：电脑替两个人过 N 世，数默契事件和关口上两个人选到一块儿的比例，按默契分档。
// 跟着的那一份在 web/local.js 的 follow；不跟时按自己的性子选（影子的选法），本来就可能一样，这里量的是合起来的。
//   node web/build.mjs build/web && node web/follow.mjs [几世，默认 16] [tongsui-local.js 路径]
import { readFileSync } from "node:fs"; import vm from "node:vm";
const code = readFileSync(process.argv[3] || new URL("../build/web/tongsui-local.js", import.meta.url).pathname, "utf8");
const stats = {}; const mstats={};
for (let life=0; life<Number(process.argv[2]||16); life++){
  const disk=new Map(); const ctx={console,JSON,Math,Date,TextEncoder,TextDecoder,structuredClone,performance,localStorage:{getItem:()=>null,setItem(){},removeItem(){}},document:{hidden:true},setInterval:()=>0,setTimeout:()=>0,clearTimeout(){},location:{}};
  ctx.window=ctx; vm.createContext(ctx); vm.runInContext(code,ctx);
  const T=ctx.TongsuiLocal; const rpc=(n,b)=>JSON.parse(T.rpcCall(n,JSON.stringify(b)));
  const S=T._debug().S; const m=rpc("lifeline_create",{name:"x"}); const o=rpc("lifeline_open",{lifelineId:m.lifelineId,protocol:S.PROTOCOL_VERSION});
  T.joinMatch(o.matchId,"{}"); T.sendMsg(S.OP.ROLL,JSON.stringify({confirm:true}));
  T._autopilot(true); const D=T._debug();
  let seenLog=0;
  for(let i=0;i<10*3600*3;i++){
    const L=D.room.state.record.life; if(L.phase==="ended") break;
    if(L.phase==="life"){ while(seenLog<L.log.length){ const e=L.log[seenLog++]; if((e.kind==="mirror"||e.kind==="milestone")&&e.choices&&e.choices.qing&&e.choices.mei&&e.events.qing===e.events.mei&&!(e.shadow||[]).length){
        const b=Math.floor(((L.bond&&L.bond.sync)||0)/20)*20; const st=e.kind==="milestone"?mstats:stats; st[b]=st[b]||[0,0]; st[b][1]++; if(e.choices.qing===e.choices.mei) st[b][0]++; } } }
    D.step(); T.drain();
  }
}
const f=(o)=>Object.entries(o).sort((a,b)=>a[0]-b[0]).map(([k,[s,n]])=>`默契${k}+: ${s}/${n}=${Math.round(100*s/n)}%`).join("  ");
console.log("关口:",f(mstats)); console.log("默契事件:",f(stats));
