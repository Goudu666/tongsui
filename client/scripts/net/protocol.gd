extends RefCounted
## 与 server/src/main.ts 中的 OP 保持一致（server/test/arch.test.mjs 会逐项比对，改一边忘了另一边测试会挂）

## 协议版本：和 main.ts 的 PROTOCOL_VERSION 一起改。进房间前双方互报版本，对不上就提示更新，而不是进去以后卡住
const VERSION := 5
## 能用的最旧的服务器。连到比这还旧的服务器时提示「服务器需要更新」
## 4：一天五段。旧服务器的钟一直在跑，这个安装包没有那套按钮了
## 5：一张张横着的图，人只左右走。旧服务器还是原来那张大地图
const MIN_SERVER := 5

const SNAPSHOT := 1    ## s→c 完整状态 {lifelineId, names, life, you, online, protocols, tick}  protocols：两人安装包的协议版本，不在线是 0
const ROLL := 2        ## c→s {reroll: true} | {confirm: true} | {heirloom: 老物件 id | null}  挑一件老物件带上 / 放下
const ROLL_STATE := 3  ## s→c {rolls}  每人多了 house（家业传了几代）、offer（摆在面前的老物件）、heirloomId（挑中的）
const MOVE := 4        ## c→s {x, y, seq}
const ACT := 5         ## c→s {spot}
const CHOOSE := 6      ## c→s {optionId, guess?}  guess：默契事件里猜 TA 选了哪一项
const WORLD := 7       ## s→c {tick, minute, slot, ready{qing,mei}, playing, wait, rest, actors{x,y,act,spot,sleep,seq,tg}, needs, money, event, bond, hints, stats, eff, goals, tracks}
const EVENT := 8       ## s→c {event}
const ERROR := 9       ## s→c {message}
const LOG := 10        ## s→c {entries}
const PRESENCE := 11   ## s→c {online, protocols}
const PING := 12       ## c→s {t}
const PONG := 13       ## s→c {t, tick}
const PASS := 22       ## c→s {}  这一段歇着（不做正经事，等这一段过去）
const CANCEL := 23     ## c→s {}  改主意：撤回这一段定下的事
const EXIT := 24       ## c→s {exit, seq}  走出口（门、楼梯、街口）。seq 是走之前最后一条 MOVE
const ECHO := 30       ## c→s {turn, optionId}  回话：补答影子替我选过的默契事件；optionId 为 null 是「不提了」
const AGAIN := 31      ## c→s {yes}  一世走完以后点「再来一世」（false 是收回）；s→c {again: {qing, mei}} 谁点了。两人都点了改发 SNAPSHOT
## 从这个协议版本起才有传承（老物件、再来一世）。服务器或对门的安装包比它旧，就不给「再来一世」的按钮
const LEGACY_SINCE := 3

## 通知码（Nakama notification code），与 main.ts 保持一致
const NOTIFY_PARTNER_JOINED := 101
const NOTIFY_PARTNER_ONLINE := 102
