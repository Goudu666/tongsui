extends RefCounted
## 与 server/src/main.ts 中的 OP 保持一致

const SNAPSHOT := 1    ## s→c 完整状态 {lifelineId, names, life, you, online}
const ROLL := 2        ## c→s {reroll: true} | {confirm: true}
const ROLL_STATE := 3  ## s→c {rolls}
const MOVE := 4        ## c→s {x, y}
const ACT := 5         ## c→s {spot}
const CHOOSE := 6      ## c→s {optionId}
const WORLD := 7       ## s→c {minute, schoolDay, actors, needs, money, event, bond, hints}
const EVENT := 8       ## s→c {event}
const ERROR := 9       ## s→c {message}
const LOG := 10        ## s→c {entries}
const PRESENCE := 11   ## s→c {online}
