// 一张贴图一个活：{ type: 'tree', kind, season } / { type: 'far', era } / { type: 'place', kind } / { type: 'mid', era } / { type: 'fore', kind }
// 搭好模型、拍一张，返回 PNG 的 dataURL（S 倍超采样，post.py 再缩回去、虚化、减色）
import { shoot } from './kit.js';
import { buildTree } from './trees.js';

export async function run(job) {
  const S = job.S || 2;
  if (job.type === 'tree') {
    const { kit, frame } = buildTree(job.kind, job.season);
    return shoot(kit, { ...frame, S: S * 1.25, aoRadius: 20 });  // 树按 1.25 倍出图（TREE_SCALE）
  }
  const strips = await import('./strips.js');
  const { kit, frame, lit } = strips.build(job);
  return shoot(kit, { ...frame, S, lit, aoRadius: job.type === 'fore' ? 30 : 16, shadowMap: 8192 });
}
