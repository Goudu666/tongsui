extends RefCounted
## 与 server/src/main.ts 中的 OP 保持一致

const SNAPSHOT := 1  ## s→c 完整状态 {lifelineId, names, life, you, progress}
const CHOOSE := 2    ## c→s {optionId}
const RESOLVED := 3  ## s→c {entries, state}
const PROGRESS := 4  ## s→c {chosen, online}
const ERROR := 9     ## s→c {message}
