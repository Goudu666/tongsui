// 材质的本色（白天、不打光）。各画风在这上面打光、调色、减色。
const MAT = {
  // 天、远处
  far: '#9AA3C4', mid: '#7D7FA8',
  // 墙
  brick: '#C0574A', brick2: '#9C4A3E', brick3: '#B8634C', plaster: '#E6CFA6', trim: '#EFE4CF',
  recess: '#4A3B42', glass: '#5C6E86', glassLit: '#FFD48A', frame: '#3F7F6E', frame2: '#E9E2D2', frameWood: '#6B4430',
  curtainA: '#E7B85C', curtainB: '#D87A6A', curtainC: '#8EB6A6',
  acBox: '#E8E4DA', acGrill: '#8E8A84', metal: '#56545E', pin: '#E2C15A', pipe: '#8B8178',
  cloth1: '#F0EDE4', cloth2: '#4E7FB0', cloth3: '#E6A23C', pot: '#B4673F', plant: '#4F8F55', plant2: '#7FA04A',
  tank: '#A9B4B8',
  // 门脸
  shopDark: '#3E3238', shopIn: '#6B4A3A', goods1: '#E2554A', goods2: '#F2C04E', goods3: '#4F9AA0', door: '#5D4A3F', counter: '#8A5A3C',
  awning: '#E8E2D4', awning2: '#2F8F7A', awningEdge: '#2A7464',
  signRed: '#C8323A', signDark: '#2F3A4A', signWhite: '#F3EEE2', signText: '#FFF4DA', signInk: '#2B2A33',
  fridge: '#E9EEF0', crate: '#C84A3A', crate2: '#3C7A9A',
  alley: '#3A3040', alley2: '#2A2232',
  balcony: '#E1D8C6', balconyLow: '#CFC4AE', shutter: '#7A7C82', pegboard: '#B79A6A', toolbox: '#C8423A',
  wood: '#9A6A44', woodDark: '#6E4A33', woodPanel: '#7A4C34', coop: '#A27A52', coopRoof: '#5E5A62',
  silhouette: '#7A4A30', doorRed: '#A3343A', lantern: '#E23B36', lanternCap: '#E8B54A', cup: '#F3EEE2',
  // 地
  sidewalk: '#B9AFA6', curb: '#D7D0C6', road: '#5B5862', roadLine: '#E9E2D2', manhole: '#4B4850', treePit: '#5B4A40',
  pole: '#8F8A86', insulator: '#E9E4DA', xfmr: '#6E7C7A', notice: '#F3EEE2', notice2: '#F2C04E', wire: '#2E2B33',
  bird: '#3A3640', birdFly: '#3A3640',
  lampPole: '#3F5A58', lampHead: '#3F5A58', lampBulb: '#FFE6A8',
  trunk: '#6A4E3E', leaf: '#4F8A5A', leafHi: '#78A65E', fence: '#3C3A44', bush: '#3E6A4A',
  bikeFrame: '#2F8F7A', bikeFrame2: '#2B2A33', tire: '#2A282E', seat: '#3A2E2A', basket: '#C9B27A',
  // 人
  qing: '#2E9A84', qingDark: '#237564', mei: '#E0485C', meiDark: '#B03548', collar: '#F3EEE2',
  pants: '#3A4A6A', pants2: '#44567A', shoe: '#2B2A33', skin: '#F2C7A5', hair: '#2B2530', eye: '#2B2530', cheek: '#F09A8A',
  bagQ: '#E6A23C', bagM: '#4E7FB0',
  // 家里
  section: '#5A4A4E', wallRoom: '#EADFC8', wallLow: '#7FAE9A', wallHall: '#DCD6C6', wallHallLow: '#6F9E8C',
  slab: '#7A6E70', brickCut: '#A85A4A', stairWell: '#2A2430', floorRoom: '#B58A62', floorHall: '#9E968C', below: '#3A3238',
  lampShade: '#E8B54A', skyWin: '#BFE0F0', farWin: '#9FB8CC', curtainRod: '#6E4A33', curtainHome: '#E9A46A',
  mattress: '#F3EEE2', quilt: '#2E9A84', quiltDot: '#F3EEE2', pillow: '#F7D9A8', paperWhite: '#F6F1E6', meiLite: '#E8707E',
  awardText: '#C8323A', clockRim: '#C8423A', clockFace: '#F6F1E6',
  book1: '#C8423A', book2: '#3C7A9A', book3: '#E6A23C', lampArm: '#2F8F7A', lampShadeG: '#2F8F7A',
  cabinet: '#9A6A44', cabinet2: '#A87A52', knob: '#E2C15A', tvBody: '#5A5458', tvScreen: '#3A4A50', doily: '#F6F1E6',
  thermos: '#D8434A', thermosCap: '#F2C04E', tableTop: '#B07A4E', bowl: '#F6F1E6', bowl2: '#8EB6CC', steam: '#FFFFFF',
  basin: '#E6EEF0', mirror: '#C9DCE6', towel: '#E8707E',
  doorQing: '#2F8F7A', doorMei: '#C8423A', qingHi: '#3FA58E', meiHi: '#DA5A58', doorFrame: '#6E4A33', plate: '#2B2A33', plateText: '#F6F1E6',
  fu: '#E23B36', meter: '#B7BCB8', noticeLine: '#8E8A84', bulb: '#FFE6A8', stair: '#7E7678', rail: '#3F5A58', ladder: '#3F4A50',
  coal: '#2E2B30', parapet: '#C8BBA8', pigeon: '#8C8A9A', foam: '#F2F0EA', scallion: '#5FA04E', sheet1: '#F3EEE2', sheet2: '#E8B7A6',
  roofHut: '#D6C6A8',
};
const EMISSIVE = new Set(['glassLit', 'lampBulb', 'bulb', 'signText']);
function hex(h) { const n = parseInt(h.slice(1), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; }
function rgb(c, a = 1) { return `rgba(${c[0] | 0},${c[1] | 0},${c[2] | 0},${a})`; }
function mix(a, b, t) { return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]; }
function mul(a, b) { return [a[0] * b[0] / 255, a[1] * b[1] / 255, a[2] * b[2] / 255]; }
function lighten(c, t) { return mix(c, [255, 255, 255], t); }
function darken(c, t) { return mix(c, [0, 0, 0], t); }
function matColor(m) { return hex(MAT[m] || '#FF00FF'); }
