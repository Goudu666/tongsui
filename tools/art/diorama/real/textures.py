#!/usr/bin/env python3
"""仿真微缩（real）的程序化 PBR 贴图：每种材质一组可平铺的 PNG（albedo / normal / roughness / ao / height）。

    python3 tools/art/diorama/real/textures.py            # → tools/art/diorama/real/out/tex/<材质>/ + materials.json
    python3 tools/art/diorama/real/textures.py --copy DIR # 再拷一份到 DIR（交付目录）

全部用 numpy 生成：噪声是 FFT 滤出来的（天生首尾相接），砖、地砖、木板的格子按贴图边长取整，所以四边都能无缝平铺。
normal 是 OpenGL 约定（Y+，绿色朝上；Godot、three 都是这个约定）。albedo 是 sRGB，其余是线性灰度。
tint = true 的贴图接近中性灰白，引擎里乘上物件自己的颜色（同一张灰泥贴图给红墙、绿门脸都能用）。
tile 是一张贴图在游戏里铺多大（世界像素；1 世界像素 ≈ 1 cm，主角 1:3 Q 版另说）。
"""
from __future__ import annotations

import argparse
import json
import os
import shutil

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out", "tex")


# ---------------------------------------------------------------- 工具
def rng(seed):
    return np.random.default_rng(seed)


def fnoise(n, seed, lo=1.0, hi=None, beta=1.0, aniso=(1.0, 1.0)):
    """周期噪声：白噪声在频域里按 1/f^beta 加权，只留 lo~hi 圈（单位：每张贴图几个周期）。返回 0 均值 1 方差。"""
    r = rng(seed)
    w = r.standard_normal((n, n))
    F = np.fft.fft2(w)
    fy = np.fft.fftfreq(n)[:, None] * n * aniso[1]
    fx = np.fft.fftfreq(n)[None, :] * n * aniso[0]
    f = np.sqrt(fx * fx + fy * fy)
    f[0, 0] = 1e9
    hi = hi or n / 2
    filt = np.where((f >= lo) & (f <= hi), 1.0 / np.power(f, beta), 0.0)
    out = np.real(np.fft.ifft2(F * filt))
    out -= out.mean()
    out /= out.std() + 1e-9
    return out


def blur(a, sigma):
    """周期高斯模糊（FFT）。sigma 单位：像素。"""
    n0, n1 = a.shape
    fy = np.fft.fftfreq(n0)[:, None]
    fx = np.fft.fftfreq(n1)[None, :]
    g = np.exp(-2 * (np.pi ** 2) * (sigma ** 2) * (fx * fx + fy * fy))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g))


def norm01(a):
    a = a - a.min()
    return a / (a.max() + 1e-9)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def normal_from_height(h, strength):
    """高度（0~1）→ OpenGL 法线（Y+）。strength：高度 1 相当于多少个像素高。"""
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
    nx, ny, nz = -dx, dy, np.ones_like(h)   # 图像行往下 = v 往下，所以 Y 取正号
    L = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / L, ny / L, nz / L], -1)


def cavity_ao(h, sigma, k):
    """凹处暗：周围平均比自己高多少 → 遮蔽。"""
    d = blur(h, sigma) - h
    return np.clip(1 - np.maximum(d, 0) * k, 0, 1)


def cracks(n, seed, count, length, jitter=0.35, width=1.0):
    """随机游走的细裂缝（取模绕回，可平铺）。返回 0~1 的裂缝深度图。"""
    r = rng(seed)
    m = np.zeros((n, n))
    for _ in range(count):
        x, y = r.uniform(0, n, 2)
        a = r.uniform(0, 2 * np.pi)
        L = int(length * r.uniform(0.5, 1.3))
        for i in range(L):
            a += r.normal(0, jitter)
            x += np.cos(a); y += np.sin(a)
            xi, yi = int(x) % n, int(y) % n
            m[yi, xi] = 1.0
            if r.random() < 0.02:   # 分叉
                a += r.choice([-1, 1]) * r.uniform(0.6, 1.2)
    if width > 0:
        m = blur(m, width) * (2.5 + width)
    return np.clip(m, 0, 1)


def to8(a):
    return (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)


def srgb(rgb_lin):
    a = np.clip(rgb_lin, 0, 1)
    return np.where(a <= 0.0031308, a * 12.92, 1.055 * np.power(a, 1 / 2.4) - 0.055)


def lin(hexs):
    c = np.array([int(hexs[i:i + 2], 16) / 255 for i in (1, 3, 5)])
    return np.where(c <= 0.04045, c / 12.92, np.power((c + 0.055) / 1.055, 2.4))


def save(name, albedo=None, height=None, rough=None, ao=None, nstrength=4.0, alpha=None, normal=None):
    """写 <name>_albedo.png（sRGB）、_normal.png（OpenGL Y+）、_rough.png（单通道）、_ao.png、_height.png。"""
    os.makedirs(OUT, exist_ok=True)
    p = lambda k: os.path.join(OUT, f"{name}_{k}.png")
    if albedo is not None:
        a = to8(srgb(albedo))
        if alpha is not None:
            Image.fromarray(np.dstack([a, to8(alpha)]), "RGBA").save(p("albedo"), optimize=True)
        else:
            Image.fromarray(a, "RGB").save(p("albedo"), optimize=True)
    if height is not None:
        Image.fromarray(to8(height), "L").save(p("height"))
        nm = normal if normal is not None else normal_from_height(height, nstrength)
        Image.fromarray(to8(nm * 0.5 + 0.5), "RGB").save(p("normal"))
    if rough is not None:
        Image.fromarray(to8(rough), "L").save(p("rough"))
    if ao is not None:
        Image.fromarray(to8(ao), "L").save(p("ao"))


def grid(n):
    y, x = np.mgrid[0:n, 0:n].astype(np.float64)
    return x, y


MATS = {}


def meta(name, **kw):
    MATS[name] = kw


# ---------------------------------------------------------------- 砖墙
def brick(n=1024, name="brick_red_tianjin", pal=None, weights=None, mortar_hex="#9D978C", seed=0, soot_k=0.22, effl_k=0.25):
    rows, cols = 20, 5                       # 一张 20 皮砖、每皮 5 块（顺砖错缝）：tile 128 世界像素 → 皮高 6.4，砖长 25.6
    rh, bl = n / rows, n / cols
    mortar = rh * 0.16
    x, y = grid(n)
    row = np.floor(y / rh).astype(int)
    xo = x + (row % 2) * bl / 2
    col = np.floor(xo / bl).astype(int) % cols
    fy = y - row * rh
    fx = np.mod(xo, bl)
    edge = np.minimum(np.minimum(fx, bl - fx), np.minimum(fy, rh - fy))   # 到砖边多远（像素）
    wob = fnoise(n, 11, 8, 300, 0.6) * 1.6 + fnoise(n, 12, 40, 400, 0.2) * 0.9
    m_mask = smooth(mortar * 0.55, mortar * 0.55 + 2.2, edge + wob)        # 1 = 砖面，0 = 灰缝；边缘带点崩口
    bid = (row * 7919 + col * 104729) % 10007
    r = rng(5 + seed)
    table = r.random((10007, 4))
    t = table[bid]
    # 天津红砖：深一点、偏褐的红，夹几块烧过火的紫黑砖（clinker）和发黄的欠火砖
    base_cols = [lin(c) for c in (pal or ["#8E3E2C", "#9A4632", "#7E3628", "#A4553E", "#5E2C26", "#A86A50"])]
    w = np.array(weights or [0.26, 0.22, 0.2, 0.12, 0.08, 0.12])
    cum = np.cumsum(w) / w.sum()
    idx = np.searchsorted(cum, t[..., 0])
    pal = np.array(base_cols)
    alb = pal[idx] * (0.86 + t[..., 1:2] * 0.26)
    mott = fnoise(n, 13, 30, 400, 0.8)
    alb = alb * (1 + 0.07 * mott[..., None])
    # 烧焦的砖边、砖面上的细小气孔
    burnt = smooth(0, rh * 0.45, edge)
    alb = alb * (0.82 + 0.18 * burnt[..., None])
    pores = (fnoise(n, 14, 200, 512, 0.0) > 2.3).astype(float)
    alb = alb * (1 - 0.35 * pores[..., None])
    # 大块的脏：烟熏、泛碱（白霜）
    soot = smooth(0.2, 1.6, fnoise(n, 15, 1, 6, 1.4))
    effl = smooth(0.8, 2.2, fnoise(n, 16, 2, 10, 1.2)) * (1 - m_mask * 0.5)
    mortar_col = lin(mortar_hex) * (1 + 0.08 * fnoise(n, 17, 20, 300, 0.5))[..., None]
    alb = alb * m_mask[..., None] + mortar_col * (1 - m_mask[..., None])
    alb = alb * (1 - soot_k * soot[..., None]) + lin("#D8D2C4") * effl_k * effl[..., None]
    h = 0.35 + 0.55 * m_mask + 0.04 * fnoise(n, 18, 30, 512, 0.6) * m_mask + 0.05 * (t[..., 2:3][..., 0] - 0.5) * m_mask - 0.12 * pores * m_mask
    h = h + 0.03 * fnoise(n, 19, 60, 512, 0.2) * (1 - m_mask)
    h = norm01(h)
    rough = 0.82 + 0.1 * (1 - m_mask) + 0.04 * mott - 0.05 * soot
    ao = cavity_ao(h, 6, 3.0)
    save(name, alb * (0.75 + 0.25 * ao[..., None]), h, rough, ao, nstrength=10)


def bricks():
    brick()
    meta("brick_red_tianjin", tile=[128, 128], metalness=0.0, roughness=[0.78, 0.96], tint=False,
         use="天津红砖墙（五大道、老公房）：顺砖错缝，皮高 6.4 cm、砖长 25.6 cm，灰缝凹进；夹烧过火的紫黑砖、泛碱、烟熏。")
    brick(name="brick_grey", pal=["#6E6E6C", "#7A7976", "#625F5C", "#85837E", "#55534F", "#8C8A84"],
          mortar_hex="#B3AEA4", seed=7, soot_k=0.18, effl_k=0.18)
    meta("brick_grey", tile=[128, 128], metalness=0.0, roughness=[0.8, 0.97], tint=False,
         use="青砖（灰砖）墙：胡同、院墙、老平房。和红砖同一个砌法，灰缝浅。")


# ---------------------------------------------------------------- 灰泥 / 刷了漆的墙
def plaster(n=1024):
    x, y = grid(n)
    lowf = fnoise(n, 21, 1, 8, 1.6)
    mid = fnoise(n, 22, 8, 60, 1.0)
    fine = fnoise(n, 23, 120, 512, 0.0)
    trowel = fnoise(n, 24, 4, 80, 1.0, aniso=(0.35, 1.6))   # 抹子横着抹的痕
    cr = cracks(n, 25, 9, 260, 0.45, 0.6)
    stains = smooth(0.8, 2.4, fnoise(n, 26, 2, 14, 1.3))
    val = 0.86 + 0.04 * lowf + 0.025 * mid + 0.02 * fine - 0.18 * cr - 0.12 * stains
    # 一点点黄（老墙皮），污渍偏褐
    alb = np.stack([val * 1.0, val * 0.985, val * 0.95], -1)
    alb = alb * (1 - stains[..., None] * np.array([0.0, 0.03, 0.08]))
    # 掉皮：露出底下的灰
    peel = smooth(1.9, 2.15, fnoise(n, 27, 6, 60, 0.9))
    alb = alb * (1 - peel[..., None]) + np.array([0.48, 0.46, 0.43]) * peel[..., None]
    h = 0.6 + 0.12 * mid + 0.05 * fine + 0.1 * trowel - 0.5 * cr - 0.28 * peel
    h = norm01(h)
    rough = np.clip(0.9 + 0.04 * fine - 0.05 * stains + 0.04 * peel, 0, 1)
    ao = cavity_ao(h, 4, 2.0)
    save("plaster", alb, h, rough, ao, nstrength=5)
    meta("plaster", tile=[256, 256], metalness=0.0, roughness=[0.82, 0.97], tint=True,
         use="（look test 用）刷了涂料的抹灰墙：接近灰白，乘物件颜色。带细裂缝、水渍、一两处掉皮。")
    # 水泥砂浆抹面（不刷漆）：本色灰，雨水冲出来的竖向深浅
    rain = fnoise(n, 28, 1, 40, 1.0, aniso=(1.0, 0.06))
    cem = np.stack([val * 0.46, val * 0.45, val * 0.425], -1) * (1 - 0.06 * rain[..., None])
    cem = cem * (1 - stains[..., None] * np.array([0.05, 0.08, 0.12]))
    cem = cem * (1 - peel[..., None]) + np.array([0.36, 0.34, 0.31]) * peel[..., None]
    save("plaster_cement", cem * (0.8 + 0.2 * ao[..., None]), h, rough, ao, nstrength=5)
    meta("plaster_cement", tile=[256, 256], metalness=0.0, roughness=[0.82, 0.97], tint=False,
         use="风化的水泥砂浆抹面（不刷漆）：灰、雨水冲出来的竖向深浅、细裂缝、水渍、掉皮露出底层。")


# ---------------------------------------------------------------- 漆面（木板、铁皮上的油漆：招牌、门、柜子）
def paint(n=1024):
    strokes = fnoise(n, 31, 2, 200, 0.8, aniso=(0.08, 1.0))   # 刷子横着刷：纵向频率高
    fine = fnoise(n, 32, 80, 256, 0.0)
    chips = smooth(2.0, 2.25, fnoise(n, 33, 10, 90, 0.7))      # 磕掉的漆
    wear = smooth(0.5, 2.5, fnoise(n, 34, 2, 12, 1.2))
    val = 0.93 + 0.025 * strokes + 0.012 * fine - 0.05 * wear
    alb = np.stack([val, val, val], -1)
    under = np.array([0.42, 0.34, 0.27])                         # 漆底下的木头 / 底漆
    alb = alb * (1 - chips[..., None]) + under * chips[..., None]
    h = norm01(0.5 + 0.06 * strokes + 0.02 * fine - 0.4 * chips)
    rough = np.clip(0.5 + 0.06 * strokes + 0.12 * wear + 0.3 * chips, 0, 1)
    ao = cavity_ao(h, 3, 2.0)
    save("paint", alb, h, rough, ao, nstrength=3)
    meta("paint", tile=[96, 96], metalness=0.0, roughness=[0.45, 0.85], tint=True,
         use="刷了油漆的木头、铁皮：招牌、门、窗框、柜台、冰柜、凳子。刷痕 + 磕掉漆露出的底色。")


# ---------------------------------------------------------------- 旧木头
def painted_wood(n=1024, name="painted_wood_green", hexc="#3F6E58", seed=0):
    """木板上刷的油漆：底下的木纹透上来，磕掉的地方露木头，晒褪了色（发白、粉化）。横着的板，tile 1.28 m。"""
    planks = 8
    x, y = grid(n)
    pw = n / planks
    fy = np.mod(y, pw)
    gap = 1 - smooth(0.5, 3.0, np.minimum(fy, pw - fy))
    grain = fnoise(n, 201 + seed, 20, 512, 0.3, aniso=(0.03, 1.0))
    strokes = fnoise(n, 202 + seed, 2, 300, 0.8, aniso=(0.06, 1.0))
    chips = smooth(1.85, 2.1, fnoise(n, 203 + seed, 6, 80, 0.8) + 0.5 * gap)
    fade = smooth(-1.0, 2.5, 0.6 * fnoise(n, 204 + seed, 1, 8, 1.4) + 0.8 * fnoise(n, 205 + seed, 2, 60, 1.0, aniso=(0.12, 1.0)))
    base = lin(hexc)
    alb = base * (1 + 0.05 * strokes + 0.04 * grain)[..., None]
    alb = alb * (1 - 0.18 * fade[..., None]) + np.array([0.5, 0.5, 0.47]) * 0.18 * fade[..., None]   # 粉化发白
    woodc = lin("#6E553E") * (0.85 + 0.15 * grain[..., None])
    alb = alb * (1 - chips[..., None]) + woodc * chips[..., None]
    alb = alb * (1 - 0.7 * gap[..., None])
    h = norm01(0.6 + 0.04 * grain + 0.03 * strokes - 0.25 * chips - 0.6 * gap)
    rough = np.clip(0.55 + 0.05 * strokes + 0.25 * fade + 0.2 * chips + 0.2 * gap, 0, 1)
    ao = cavity_ao(h, 4, 2.5)
    save(name, alb * (0.8 + 0.2 * ao[..., None]), h, rough, ao, nstrength=6)


def painted_woods():
    painted_wood()
    meta("painted_wood_green", tile=[128, 128], metalness=0.0, roughness=[0.5, 0.95], tint=False,
         use="刷绿漆的木板（门脸、门、窗扇、报亭）：横着的板 16 cm 宽，木纹透上来，磕掉漆露木头，晒褪色。")
    painted_wood(name="painted_wood_red", hexc="#8A3A30", seed=10)
    meta("painted_wood_red", tile=[128, 128], metalness=0.0, roughness=[0.5, 0.95], tint=False,
         use="刷暗红漆的木板（老门、柜台、招牌底板）：同上，暗红。")


def curb(n=1024):
    """路牙石：花岗岩 / 水泥预制块，50 cm 一节，tile 1 m。"""
    x, y = grid(n)
    seg = n / 2
    fx = np.mod(x, seg)
    joint = 1 - smooth(1.0, 5.0, np.minimum(fx, seg - fx))
    r = rng(211)
    sid = np.floor(x / seg).astype(int) % 2
    tone = np.array([0.97, 1.05])[sid]
    g1 = fnoise(n, 212, 150, 512, 0.0)
    g2 = fnoise(n, 213, 60, 300, 0.2)
    mott = fnoise(n, 214, 2, 30, 1.2)
    black = (g1 > 1.5).astype(float)
    white = (g2 > 1.8).astype(float)
    dirt = smooth(0.3, 1.0, y / n) * 0.25 + 0.12 * smooth(0.5, 2.5, fnoise(n, 215, 2, 20, 1.2))
    v = (0.36 + 0.02 * mott) * tone - 0.15 * black + 0.12 * white
    alb = np.stack([v, v * 0.99, v * 0.97], -1) * (1 - dirt[..., None])
    alb = alb * (1 - 0.6 * joint[..., None])
    h = norm01(0.6 + 0.04 * g1 + 0.03 * g2 - 0.5 * joint)
    rough = np.clip(0.8 + 0.05 * g1 - 0.1 * white, 0, 1)
    ao = cavity_ao(h, 4, 2.5)
    save("curb_stone", alb, h, rough, ao, nstrength=5)
    meta("curb_stone", tile=[100, 100], metalness=0.0, roughness=[0.7, 0.9], tint=False,
         use="路牙石（花岗岩预制块，50 cm 一节）：黑白麻点、节缝，往下（v 大）越脏。贴在路牙的立面和顶面。")


def sheet_metal(n=1024):
    """生锈的铁皮：竖着的压型板（瓦楞），褪色的灰蓝漆，大片锈、锈水往下流。tile 1 m。"""
    x, y = grid(n)
    corr = np.sin(x * 2 * np.pi / (n / 12))                  # 12 道瓦楞 / m
    seam = 1 - smooth(0.0, 4.0, np.abs(np.mod(x, n / 2) - 2))
    rust = smooth(0.9, 2.0, fnoise(n, 221, 2, 50, 1.0) + 0.7 * fnoise(n, 222, 30, 300, 0.3) + 0.6 * smooth(0.6, 1.0, y / n))
    streak = smooth(0.5, 2.2, fnoise(n, 223, 1, 80, 1.0, aniso=(1.0, 0.05)))
    fine = fnoise(n, 224, 100, 512, 0.0)
    paintc = lin("#7D8C93") * (0.95 + 0.05 * fnoise(n, 225, 2, 20, 1.2))[..., None]
    rc = np.stack([0.26 + 0.05 * fine, 0.11 + 0.02 * fine, 0.045 + 0.01 * fine], -1)
    alb = paintc * (1 - rust[..., None]) + rc * rust[..., None]
    alb = alb * (1 - 0.35 * streak[..., None] * np.array([0.55, 0.75, 1.0]))
    alb = alb * (1 - 0.15 * seam[..., None])
    h = norm01(0.5 + 0.35 * corr + 0.06 * rust * fine + 0.1 * seam)
    rough = np.clip(0.5 + 0.05 * fine + 0.4 * rust, 0, 1)
    ao = cavity_ao(h, 6, 1.5)
    save("sheet_metal_rusty", alb * (0.85 + 0.15 * ao[..., None]), h, rough, ao, nstrength=14)
    meta("sheet_metal_rusty", tile=[100, 100], metalness=0.25, roughness=[0.45, 0.95], tint=False,
         use="生锈的铁皮（瓦楞压型板，12 道/m，竖着装）：棚子、报亭顶、围挡。褪色灰蓝漆 + 大片锈 + 锈水。金属度 ~0.25（漆和锈都不是裸金属）。")


def wood(n=1024):
    planks = 8                                    # tile 128 → 一块板宽 16 世界像素
    x, y = grid(n)
    pw = n / planks
    pid = np.floor(y / pw).astype(int)
    fy = np.mod(y, pw)
    r = rng(41)
    off = r.uniform(0, n, planks)[pid]
    tone = r.uniform(0.82, 1.15, planks)[pid]
    warp = fnoise(n, 42, 1, 16, 1.2, aniso=(0.25, 1.0)) * 10
    rings = np.sin((y + warp + off * 0.05) * 2 * np.pi / (pw / 5.5) + fnoise(n, 43, 2, 40, 1.0, aniso=(0.2, 1)) * 2.2)
    grain = fnoise(n, 44, 20, 512, 0.3, aniso=(0.03, 1.0))
    knots = smooth(2.6, 3.1, fnoise(n, 45, 4, 30, 1.2))
    gap = 1 - smooth(0.5, 2.2, np.minimum(fy, pw - fy))
    # 板与板之间错开的端缝
    endx = np.mod(x + off, n * 0.5)
    endgap = 1 - smooth(0.5, 2.0, np.minimum(endx, n * 0.5 - endx))
    gap = np.maximum(gap, endgap)
    base = lin("#8A6A4E")
    v = tone * (1 + 0.08 * rings + 0.07 * grain - 0.35 * knots)
    weather = smooth(-1.0, 2.0, 0.6 * fnoise(n, 46, 1, 6, 1.5) + 0.8 * fnoise(n, 47, 2, 60, 1.0, aniso=(0.12, 1.0)))     # 晒灰了的
    alb = base * v[..., None]
    grey = np.array([0.36, 0.34, 0.31]) * v[..., None]
    alb = alb * (1 - 0.4 * weather[..., None]) + grey * 0.4 * weather[..., None]
    alb = alb * (1 - 0.8 * gap[..., None])
    h = norm01(0.6 + 0.05 * rings + 0.08 * grain - 0.6 * gap)
    rough = np.clip(0.72 + 0.08 * grain + 0.1 * weather + 0.1 * gap, 0, 1)
    ao = cavity_ao(h, 4, 2.5)
    save("wood", alb, h, rough, ao, nstrength=6)
    meta("wood", tile=[128, 128], metalness=0.0, roughness=[0.65, 0.92], tint=False,
         use="没上漆的旧木头：木板、木箱、桌面、电线杆（木杆）。纹理沿 u（横向）走，板宽 16 世界像素。")


# ---------------------------------------------------------------- 人行道方砖
def pavers(n=1024):
    k = 4                                          # tile 160 → 一块方砖 40 世界像素
    x, y = grid(n)
    s = n / k
    ix, iy = np.floor(x / s).astype(int), np.floor(y / s).astype(int)
    fx, fy = np.mod(x, s), np.mod(y, s)
    e = np.minimum(np.minimum(fx, s - fx), np.minimum(fy, s - fy))
    wob = fnoise(n, 51, 10, 200, 0.5) * 1.2
    j = smooth(2.0, 4.5, e + wob)                 # 1 = 砖面，0 = 缝
    r = rng(52)
    t = r.random((k, k, 3))[iy % k, ix % k]
    tone = 0.92 + t[..., 0] * 0.14
    speck = fnoise(n, 53, 150, 512, 0.0)
    dark_sp = (speck > 2.2).astype(float)
    mott = fnoise(n, 54, 6, 120, 1.0)
    stains = smooth(1.0, 2.6, fnoise(n, 55, 3, 20, 1.3))
    gum = (fnoise(n, 56, 60, 300, 0.2) > 3.3).astype(float)
    cr = cracks(n, 57, 6, 120, 0.5, 0.6) * j
    base = lin("#A9A196")
    v = tone * (1 + 0.05 * mott + 0.03 * speck) - 0.25 * dark_sp - 0.25 * cr
    alb = base * v[..., None]
    alb = alb * (1 - 0.25 * stains[..., None]) * (1 - 0.35 * gum[..., None])
    jcol = lin("#5E5850")
    alb = alb * j[..., None] + jcol * (1 - j[..., None])
    # 一块砖翘起一点点：每块砖的面有一点倾斜（高度上加一个线性坡）
    tilt = (t[..., 1] - 0.5) * (fx / s - 0.5) * 0.08 + (t[..., 2] - 0.5) * (fy / s - 0.5) * 0.08
    h = norm01(0.4 + 0.5 * j + 0.03 * speck * j + tilt * j - 0.3 * cr)
    rough = np.clip(0.86 + 0.05 * speck - 0.12 * stains + 0.06 * (1 - j), 0, 1)
    ao = cavity_ao(h, 5, 3.0)
    save("concrete_pavers", alb * (0.8 + 0.2 * ao[..., None]), h, rough, ao, nstrength=8)
    meta("concrete_pavers", tile=[160, 160], metalness=0.0, roughness=[0.7, 0.96], tint=False,
         use="人行道的水泥方砖（40×40 世界像素一块），砖缝凹、个别有裂缝、污渍、口香糖点。")


# ---------------------------------------------------------------- 柏油路
def asphalt(n=1024):
    agg = fnoise(n, 61, 180, 512, 0.0)
    agg2 = fnoise(n, 62, 60, 300, 0.3)
    light = (agg > 1.6).astype(float)
    dark = (agg < -1.8).astype(float)
    mott = fnoise(n, 63, 2, 40, 1.2)
    patch = smooth(1.4, 1.6, fnoise(n, 64, 1, 5, 1.6))      # 补过的一块（颜色深、更平）
    cr = cracks(n, 65, 10, 220, 0.4, 0.7) * (1 - patch)
    oil = smooth(1.5, 3.0, fnoise(n, 66, 4, 30, 1.2))
    v = 0.065 + 0.008 * mott + 0.05 * light - 0.025 * dark + 0.008 * agg2
    v = np.clip(v * (1 - 0.12 * patch) - 0.02 * cr - 0.006 * oil, 0.01, 1)
    alb = np.stack([v * 1.0, v * 0.99, v * 1.02], -1)
    h = norm01(0.5 + 0.12 * agg + 0.06 * agg2 - 0.06 * patch - 0.6 * cr)
    rough = np.clip(0.88 + 0.05 * agg - 0.12 * patch - 0.25 * oil, 0, 1)
    ao = cavity_ao(h, 2, 3.0)
    save("asphalt", alb, h, rough, ao, nstrength=6)
    meta("asphalt", tile=[192, 192], metalness=0.0, roughness=[0.6, 0.97], tint=False,
         use="柏油马路：细骨料、补丁、裂缝、油渍。标线另做（贴花或单独的条）。")


# ---------------------------------------------------------------- 水泥（路牙、窗台、楼板、屋顶）
def concrete(n=1024):
    mott = fnoise(n, 71, 2, 40, 1.2)
    fine = fnoise(n, 72, 100, 256, 0.0)
    pores = (fine > 2.4).astype(float)
    form = np.abs(np.sin(np.mgrid[0:n, 0:n][0] * 2 * np.pi / (n / 3))) ** 40     # 模板缝（横着几道）
    stains = smooth(0.6, 2.4, fnoise(n, 73, 2, 16, 1.4))
    v = 0.62 + 0.04 * mott + 0.02 * fine - 0.2 * pores - 0.12 * stains - 0.05 * form
    alb = np.stack([v, v * 0.99, v * 0.96], -1)
    h = norm01(0.5 + 0.06 * mott + 0.04 * fine - 0.4 * pores - 0.15 * form)
    rough = np.clip(0.88 + 0.04 * fine - 0.08 * stains, 0, 1)
    ao = cavity_ao(h, 3, 2.0)
    save("concrete", alb, h, rough, ao, nstrength=4)
    meta("concrete", tile=[128, 128], metalness=0.0, roughness=[0.78, 0.95], tint=True,
         use="水泥：路牙、窗台、楼板、屋顶、台阶。浅灰，可以乘颜色。")


# ---------------------------------------------------------------- 油毡屋面
def roof(n=1024):
    x, y = grid(n)
    grav = fnoise(n, 81, 150, 256, 0.0)
    mott = fnoise(n, 82, 2, 30, 1.2)
    seam = 1 - smooth(0.0, 3.0, np.abs(np.mod(y, n / 4) - 2))
    puddle = smooth(1.6, 2.0, fnoise(n, 83, 2, 10, 1.4))
    v = 0.26 + 0.05 * mott + 0.06 * (grav > 1.2) - 0.03 * seam - 0.05 * puddle
    alb = np.stack([v, v * 0.98, v * 0.96], -1)
    h = norm01(0.5 + 0.1 * grav + 0.3 * seam - 0.1 * puddle)
    rough = np.clip(0.9 + 0.04 * grav - 0.45 * puddle, 0, 1)
    save("roof_felt", alb, h, rough, cavity_ao(h, 3, 2.0), nstrength=4)
    meta("roof_felt", tile=[128, 128], metalness=0.0, roughness=[0.45, 0.95], tint=False,
         use="平屋顶的油毡、撒了石子，横着几道搭接缝，几处积过水的亮斑。")


# ---------------------------------------------------------------- 刷漆的铁 + 锈
def metal(n=1024):
    mott = fnoise(n, 91, 2, 40, 1.2)
    rust = smooth(1.2, 2.2, fnoise(n, 92, 3, 60, 1.0) + 0.6 * fnoise(n, 93, 30, 200, 0.4))
    streak = smooth(0.8, 2.4, fnoise(n, 94, 1, 60, 1.0, aniso=(1.0, 0.08)))   # 竖着流下来的锈水
    fine = fnoise(n, 95, 80, 256, 0.0)
    v = 0.9 + 0.03 * mott + 0.015 * fine
    alb = np.stack([v, v, v], -1)
    rc = np.array([0.30, 0.12, 0.05]) * (0.8 + 0.2 * fine[..., None])
    alb = alb * (1 - 0.85 * rust[..., None]) + rc * 0.85 * rust[..., None]
    alb = alb * (1 - 0.25 * streak[..., None] * np.array([0.6, 0.8, 1.0]))
    h = norm01(0.5 + 0.02 * mott + 0.25 * rust * (0.5 + 0.5 * fine))
    rough = np.clip(0.45 + 0.05 * fine + 0.45 * rust, 0, 1)
    save("metal", alb, h, rough, cavity_ao(h, 3, 2.0), nstrength=4)
    meta("metal", tile=[96, 96], metalness=0.15, roughness=[0.4, 0.92], tint=True,
         use="刷了漆的铁：电线杆、路灯杆、铁栏杆、自行车、冰柜的铁皮。乘物件颜色；锈斑的颜色也会被乘深，深色杆子正好。")


# ---------------------------------------------------------------- 玻璃（只给粗糙度和一点脏）
def glass(n=1024):
    smudge = smooth(0.0, 2.5, fnoise(n, 101, 2, 30, 1.2))
    dust = fnoise(n, 102, 60, 256, 0.2)
    x, y = grid(n)
    bottom = smooth(0.3, 1.0, 0.5 - 0.5 * np.cos(y / n * 2 * np.pi))    # 中间一圈脏（可平铺）
    rough = np.clip(0.06 + 0.25 * smudge + 0.04 * dust + 0.15 * bottom, 0, 1)
    v = 1 - 0.15 * smudge - 0.1 * bottom
    alb = np.stack([v, v, v], -1)
    save("glass", alb, None, rough)
    meta("glass", tile=[64, 64], metalness=0.0, roughness=[0.05, 0.4], tint=True,
         use="窗玻璃：只给粗糙度（手印、灰、底下积灰）和一点点暗；颜色暗、要环境反射（Godot 用 ReflectionProbe 或 sky）。")


# ---------------------------------------------------------------- 布（小人衣服：斜纹）
def fabric(n=1024):
    x, y = grid(n)
    p = 16                                        # 一个纱线周期 16 像素：tile 6 世界像素 → 很细的纹
    warp = np.sin((x + y) * 2 * np.pi / p)
    weft = np.sin(x * 2 * np.pi / (p * 0.5)) * np.sin(y * 2 * np.pi / p)
    tw = 0.6 * warp + 0.25 * weft
    fuzz = fnoise(n, 111, 40, 256, 0.3)
    slub = fnoise(n, 112, 2, 30, 1.0, aniso=(0.1, 1.0))
    v = 0.92 + 0.03 * tw + 0.02 * fuzz + 0.02 * slub
    alb = np.stack([v, v, v], -1)
    h = norm01(0.5 + 0.25 * tw + 0.08 * fuzz)
    rough = np.clip(0.88 + 0.04 * fuzz, 0, 1)
    save("fabric", alb, h, rough, cavity_ao(h, 2, 1.5), nstrength=3)
    meta("fabric", tile=[22, 22], metalness=0.0, roughness=[0.82, 0.95], tint=True, sheen=0.5,
         use="小人的衣服（树脂手办上涂的布纹）：斜纹凹凸，乘衣服颜色；加一点 sheen（Godot：rim）。")


# ---------------------------------------------------------------- 皮肤（手涂的哑光漆）
def skin(n=1024):
    mott = fnoise(n, 121, 2, 30, 1.2)
    brush = fnoise(n, 122, 4, 120, 0.8, aniso=(0.15, 1.0))
    fine = fnoise(n, 123, 80, 256, 0.0)
    v = 0.97 + 0.015 * mott + 0.01 * brush
    alb = np.stack([v, v * 0.985, v * 0.975], -1)
    h = norm01(0.5 + 0.08 * brush + 0.04 * fine + 0.05 * mott)
    rough = np.clip(0.6 + 0.04 * fine + 0.03 * brush, 0, 1)
    save("skin", alb, h, rough, None, nstrength=1.5)
    meta("skin", tile=[30, 30], metalness=0.0, roughness=[0.52, 0.68], tint=True, subsurface="#FF9C7A",
         use="小人的脸和手：哑光、一点刷痕，乘肤色；Godot 里开 subsurface scattering（弱）或加一点暖色 rim。")


# ---------------------------------------------------------------- 头发（雕出来的发丝 + 漆）
def hair(n=1024):
    strands = fnoise(n, 131, 4, 200, 0.6, aniso=(1.0, 0.04))   # 纵向拉长：发丝沿 v 走
    big = fnoise(n, 132, 2, 12, 1.2, aniso=(1.0, 0.15))
    v = 0.92 + 0.05 * strands
    alb = np.stack([v, v, v], -1)
    h = norm01(0.5 + 0.35 * strands + 0.3 * big)
    rough = np.clip(0.42 + 0.08 * strands, 0, 1)
    save("hair", alb, h, rough, cavity_ao(h, 3, 1.5), nstrength=4)
    meta("hair", tile=[14, 14], metalness=0.0, roughness=[0.32, 0.55], tint=True,
         use="小人的头发：雕出来的一缕缕发丝（沿 v），漆面带一点光。")


# ---------------------------------------------------------------- 树叶（模型树的海绵 / 绒粉团）
def foliage(n=1024):
    cl = fnoise(n, 141, 12, 120, 0.8)
    fine = fnoise(n, 142, 100, 256, 0.0)
    holes = smooth(1.5, 2.2, -cl)
    v = 0.85 + 0.12 * cl + 0.05 * fine - 0.4 * holes
    alb = np.stack([v * 0.98, v, v * 0.9], -1)
    h = norm01(0.5 + 0.35 * cl + 0.12 * fine - 0.4 * holes)
    rough = np.clip(0.92 + 0.04 * fine, 0, 1)
    save("foliage", alb, h, rough, cavity_ao(h, 3, 3.0), nstrength=6)
    meta("foliage", tile=[70, 70], metalness=0.0, roughness=[0.88, 0.98], tint=True,
         use="模型树的树冠（海绵颗粒 / 撒绒粉的团子）：坑坑洼洼，乘叶子颜色。")


# ---------------------------------------------------------------- 贴花：墙根的脏、窗台下的流痕、地上的脏边
def decals():
    # 墙根：横向可平铺（1024×256），底下最脏，往上淡掉；溅上去的泥点
    W, H = 1024, 256
    r = rng(151)
    yy = np.linspace(0, 1, H)[:, None]            # 0 顶 → 1 底
    nz = fnoise(W, 152, 2, 60, 1.0)[:H, :]
    edge = 0.55 + 0.12 * nz
    a = smooth(edge - 0.35, edge + 0.25, yy) * 0.85
    sp = fnoise(W, 153, 120, 512, 0.0)[:H, :]
    splash = (sp > 2.0) * smooth(0.45, 0.85, yy) * 0.6
    a = np.clip(a + splash, 0, 0.95)
    col = np.dstack([np.full((H, W), 0.09), np.full((H, W), 0.075), np.full((H, W), 0.06)])
    save("decal_grime_base", col, None, None, alpha=a)
    meta("decal_grime_base", tile=[256, 64], metalness=0.0, roughness=[0.95, 0.95], tint=False, decal=True,
         use="墙根的脏：贴在墙面最底下一溜（高 ~64 世界像素），横向平铺。Godot：Decal 或贴墙的透明面片。")
    # 窗台下的流痕（单张，不平铺）512×512：上沿宽、往下一条条细下去
    n = 512
    x, y = grid(n)
    a = np.zeros((n, n))
    for i in range(14):
        cx = r.uniform(30, n - 30); wd = r.uniform(6, 26); L = r.uniform(0.35, 1.0) * n
        wob = 4 * np.sin(y / r.uniform(20, 60) + r.uniform(0, 6))
        prof = np.exp(-((x - cx - wob) / wd) ** 2) * smooth(L, L * 0.5, y) * r.uniform(0.3, 0.8)
        a = np.maximum(a, prof)
    a = np.clip(a + 0.35 * smooth(60, 0, y) * (1 - smooth(0.4, 0.5, np.abs(x / n - 0.5))), 0, 0.85)
    a = a * smooth(0, 30, x) * smooth(n, n - 30, x)
    col = np.dstack([np.full((n, n), 0.12), np.full((n, n), 0.1), np.full((n, n), 0.08)])
    save("decal_streaks", col, None, None, alpha=a)
    meta("decal_streaks", tile=None, metalness=0.0, roughness=[0.9, 0.9], tint=False, decal=True,
         use="窗台、招牌、空调底下往下流的雨水印。单张贴花，宽度跟窗台一样，高 ~1.4 倍宽。")
    # 地上的脏边：贴着墙根铺在地上，横向可平铺（1024×128），靠墙最深
    W, H = 1024, 128
    yy = np.linspace(0, 1, H)[:, None]
    nz = fnoise(W, 154, 2, 80, 1.0)[:H, :]
    a = smooth(0.75 + 0.15 * nz, 0.0, yy) * 0.7
    leaves = (fnoise(W, 155, 60, 300, 0.2)[:H, :] > 2.4) * smooth(0.8, 0.2, yy) * 0.5
    a = np.clip(a + leaves, 0, 0.9)
    col = np.dstack([np.full((H, W), 0.12), np.full((H, W), 0.1), np.full((H, W), 0.08)])
    save("decal_ground_dirt", col, None, None, alpha=a)
    meta("decal_ground_dirt", tile=[256, 32], metalness=0.0, roughness=[0.95, 0.95], tint=False, decal=True,
         use="地上贴着墙根的一溜灰土、落叶渣（往外 ~30 世界像素淡掉）。")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--copy", default=None, help="生成后再拷一份到这个目录")
    ap.add_argument("--only", nargs="*", default=None)
    a = ap.parse_args()
    jobs = [bricks, plaster, painted_woods, curb, sheet_metal, paint, wood, pavers, asphalt, concrete, roof, metal, glass, fabric, skin, hair, foliage, decals]
    for f in jobs:
        if a.only and f.__name__ not in a.only:
            continue
        f()
        print("✓", f.__name__, flush=True)
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    mj = os.path.join(OUT, "materials.json")
    old = json.load(open(mj)) if (a.only and os.path.exists(mj)) else {}
    old.update(MATS)
    if "materials" in old:
        old = dict(old["materials"], **{k: v for k, v in old.items() if k not in ("materials", "_about")})
    files = sorted(os.listdir(OUT))
    mats = {}
    for k, v in old.items():
        v = dict(v)
        if "tile" in v:
            t = v.pop("tile")
            v["tile_m"] = [round(x / 100, 3) for x in t] if t else None
        v["files"] = {f[len(k) + 1:-4]: f for f in files if f.startswith(k + "_") and f.endswith(".png") and f[len(k) + 1:-4] in ("albedo", "normal", "rough", "ao", "height")}
        mats[k] = v
    doc = {
        "_about": "《同岁》仿真微缩（real）程序化 PBR 材质，tools/art/diorama/real/textures.py 生成。全部 1024×1024、四边无缝。"
                  "tile_m = 一张贴图在真实尺度里铺多大（米；1 世界像素 = 1 cm）。normal = OpenGL 约定（+Y，Godot 直接用）；"
                  "albedo = sRGB（砖、地砖这类已经轻轻烤进了 AO）；rough / ao / height = 线性单通道。"
                  "tint=true：贴图接近中性灰，乘物件颜色用；decal=true：带 alpha 的贴花。required=true 是 Godot 3D 管线点名要的那几种。",
        "materials": mats,
    }
    REQ = ("brick_red_tianjin", "brick_grey", "plaster_cement", "painted_wood_green", "painted_wood_red", "asphalt",
           "concrete_pavers", "curb_stone", "sheet_metal_rusty", "roof_felt")
    for k in REQ:
        if k in doc["materials"]:
            doc["materials"][k]["required"] = True
    json.dump(doc, open(mj, "w"), ensure_ascii=False, indent=1)
    if a.copy:
        dst = a.copy
        if os.path.exists(dst):
            shutil.rmtree(dst)
        shutil.copytree(OUT, dst)
        print("→", dst)


if __name__ == "__main__":
    main()
