"""《同岁》声音管线的底层：振荡、包络、滤波、混响、响度、导出。

全部是 numpy/scipy 的纯函数，采样率固定 44100。所有随机数都从素材名派生种子，
所以同一份代码两次生成的文件逐字节相同（仓库里不会出现无意义的二进制改动）。
"""
from __future__ import annotations

import subprocess
import zlib
from functools import lru_cache
from pathlib import Path

import numpy as np
from scipy import signal

SR = 44100
TAU = 2.0 * np.pi


# ---------------------------------------------------------------- 基础 ----

def rng_for(name: str) -> np.random.Generator:
    return np.random.default_rng(zlib.crc32(name.encode("utf-8")))


def sec(seconds: float) -> int:
    return int(round(seconds * SR))


def times(n: int) -> np.ndarray:
    return np.arange(n) / SR


def midi(m: float) -> float:
    return 440.0 * 2.0 ** ((m - 69.0) / 12.0)


def db(x: float) -> float:
    return 10.0 ** (x / 20.0)


def cents(c):
    return 2.0 ** (np.asarray(c) / 1200.0)


# ---------------------------------------------------------------- 包络 ----

def fade(x: np.ndarray, a: float = 0.003, r: float = 0.01) -> np.ndarray:
    """首尾各加一小段余弦淡入淡出，防止爆音。"""
    y = np.array(x, dtype=np.float64, copy=True)
    na, nr = min(sec(a), len(y) // 2), min(sec(r), len(y) // 2)
    if na > 0:
        w = 0.5 - 0.5 * np.cos(np.pi * np.arange(na) / na)
        y[:na] = (y[:na].T * w).T
    if nr > 0:
        w = 0.5 + 0.5 * np.cos(np.pi * np.arange(nr) / nr)
        y[-nr:] = (y[-nr:].T * w).T
    return y


def adsr(n: int, a: float, d: float, s: float, r: float, curve: float = 3.0) -> np.ndarray:
    """n 是按住的采样数，返回长度 n + release。衰减段用指数曲线。"""
    na, nd, nr = max(1, sec(a)), max(1, sec(d)), max(1, sec(r))
    hold = max(n, na)
    env = np.empty(hold + nr)
    env[:na] = 0.5 - 0.5 * np.cos(np.pi * np.arange(na) / na)
    k = np.arange(hold - na)
    env[na:hold] = s + (1.0 - s) * np.exp(-curve * k / nd)
    last = env[hold - 1]
    env[hold:] = last * np.exp(-5.0 * np.arange(nr) / nr) * (1.0 - np.arange(nr) / nr)
    return env


def swell(n: int, peak: float = 0.5, power: float = 1.0) -> np.ndarray:
    """0 → 1 → 0 的鼓包，peak 是最高点的位置（0~1）。"""
    x = np.arange(n) / max(1, n - 1)
    up = np.clip(x / max(peak, 1e-6), 0, 1)
    down = np.clip((1 - x) / max(1 - peak, 1e-6), 0, 1)
    return (np.sin(0.5 * np.pi * np.minimum(up, down))) ** (2 * power)


def lfo_noise(n: int, rate: float, rng: np.random.Generator) -> np.ndarray:
    """平滑的随机游走，范围大约 -1~1，rate 是每秒大概变几回。"""
    pts = max(4, int(n / SR * rate) + 4)
    knots = rng.uniform(-1, 1, pts)
    x = np.linspace(0, pts - 1, n)
    i = np.floor(x).astype(int).clip(0, pts - 2)
    f = x - i
    f = f * f * (3 - 2 * f)
    return knots[i] * (1 - f) + knots[i + 1] * f


# ---------------------------------------------------------------- 滤波 ----

def _sos(kind: str, fc, order: int):
    fc = np.clip(np.asarray(fc, dtype=float), 10.0, SR * 0.49)
    return signal.butter(order, fc, btype=kind, fs=SR, output="sos")


def lp(x, fc: float, order: int = 2):
    return signal.sosfilt(_sos("low", fc, order), x, axis=0)


def hp(x, fc: float, order: int = 2):
    return signal.sosfilt(_sos("high", fc, order), x, axis=0)


def bp(x, lo: float, hi: float, order: int = 2):
    return signal.sosfilt(_sos("band", [lo, hi], order), x, axis=0)


def reson(x, f: float, q: float, gain: float = 1.0):
    """二阶谐振带通（恒定峰值增益），做木头、金属、共鸣腔。"""
    f = float(np.clip(f, 20.0, SR * 0.45))
    b, a = signal.iirpeak(f, q, fs=SR)
    return gain * signal.lfilter(b, a, x, axis=0)


def peak(x, f: float, q: float, gain_db: float):
    """RBJ 峰值均衡。"""
    a_ = 10 ** (gain_db / 40.0)
    w0 = TAU * f / SR
    alpha = np.sin(w0) / (2 * q)
    b = [1 + alpha * a_, -2 * np.cos(w0), 1 - alpha * a_]
    a = [1 + alpha / a_, -2 * np.cos(w0), 1 - alpha / a_]
    return signal.lfilter(np.array(b) / a[0], np.array(a) / a[0], x, axis=0)


def shelf(x, f: float, gain_db: float, high: bool = True):
    a_ = 10 ** (gain_db / 40.0)
    w0 = TAU * f / SR
    cs, sn = np.cos(w0), np.sin(w0)
    alpha = sn / 2 * np.sqrt(2.0)
    s2 = 2 * np.sqrt(a_) * alpha
    if high:
        b = [a_ * ((a_ + 1) + (a_ - 1) * cs + s2), -2 * a_ * ((a_ - 1) + (a_ + 1) * cs), a_ * ((a_ + 1) + (a_ - 1) * cs - s2)]
        a = [(a_ + 1) - (a_ - 1) * cs + s2, 2 * ((a_ - 1) - (a_ + 1) * cs), (a_ + 1) - (a_ - 1) * cs - s2]
    else:
        b = [a_ * ((a_ + 1) - (a_ - 1) * cs + s2), 2 * a_ * ((a_ - 1) - (a_ + 1) * cs), a_ * ((a_ + 1) - (a_ - 1) * cs - s2)]
        a = [(a_ + 1) + (a_ - 1) * cs + s2, -2 * ((a_ - 1) + (a_ + 1) * cs), (a_ + 1) + (a_ - 1) * cs - s2]
    return signal.lfilter(np.array(b) / a[0], np.array(a) / a[0], x, axis=0)


def softclip(x, drive: float = 1.0):
    return np.tanh(x * drive) / np.tanh(drive)


# ---------------------------------------------------------------- 噪声 ----

def white(n: int, rng: np.random.Generator) -> np.ndarray:
    return rng.standard_normal(n)


def colored(n: int, rng: np.random.Generator, slope: float = -3.0) -> np.ndarray:
    """slope 是每倍频程的 dB：-3 粉噪，-6 棕噪。"""
    spec = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = f[1]
    spec *= (f / 1000.0) ** (slope / 6.0)
    spec[f < 20] = 0
    y = np.fft.irfft(spec, n)
    return y / (np.std(y) + 1e-12)


def moving_band(n: int, rng, f_lo: float, f_hi: float, rate: float = 0.2, bands: int = 6, q: float = 1.2):
    """中心频率慢慢游走的带通噪声（风）。用几条固定频带按权重交叠，避免逐采样的时变滤波。"""
    centers = np.geomspace(f_lo, f_hi, bands)
    pos = (lfo_noise(n, rate, rng) * 0.5 + 0.5) * (bands - 1)
    src = white(n, rng)
    out = np.zeros(n)
    for i, fc in enumerate(centers):
        w = np.clip(1.0 - np.abs(pos - i), 0, 1)
        out += reson(src, fc, q) * w
    return out


def bursts(n: int, rng, density: float, dur: tuple, band: tuple, amp_spread: float = 1.0) -> np.ndarray:
    """随机撒一堆很短的带通噪声粒（油星、噼啪、掌声、沙沙）。density 是每秒几粒。"""
    out = np.zeros(n)
    count = rng.poisson(density * n / SR)
    for _ in range(count):
        d = sec(rng.uniform(*dur))
        at = rng.integers(0, max(1, n - d))
        g = white(d, rng) * np.exp(-np.arange(d) / (d * 0.3))
        out[at:at + d] += g * rng.uniform(0.2, 1.0) ** amp_spread
    return bp(out, band[0], band[1])


def modal(n: int, freqs, decays, amps, rng=None, strike: float = 0.002) -> np.ndarray:
    """一组指数衰减的正弦：敲一下木头、铁片、瓷碗。前面带一小段噪声当作敲击的那一下。"""
    tt = times(n)
    out = np.zeros(n)
    for f, d, a in zip(freqs, decays, amps):
        if f < SR * 0.45:
            ph = 0.0 if rng is None else rng.uniform(0, TAU)
            out += a * np.exp(-tt / d) * np.sin(TAU * f * tt + ph)
    if rng is not None and strike > 0:
        k = min(n, sec(strike))
        out[:k] += white(k, rng) * np.linspace(1, 0, k) * 0.5 * max(amps)
    return fade(out, 0.0005, 0.004)


# ---------------------------------------------------------------- 混音 ----

def to_stereo(x: np.ndarray, pan: float = 0.0) -> np.ndarray:
    """pan -1 左 … 1 右，等功率。"""
    if x.ndim == 2:
        return x
    a = (pan + 1) * np.pi / 4
    return np.stack([x * np.cos(a), x * np.sin(a)], axis=1)


class Mix:
    """一条立体声带子。add 时超出末尾的部分自动延长（混响尾巴）。"""

    def __init__(self, seconds: float):
        self.buf = np.zeros((sec(seconds), 2))

    def add(self, x: np.ndarray, at: float, gain: float = 1.0, pan: float = 0.0) -> None:
        s = to_stereo(np.asarray(x, dtype=np.float64), pan) * gain
        i = max(0, sec(at))
        end = i + len(s)
        if end > len(self.buf):
            self.buf = np.concatenate([self.buf, np.zeros((end - len(self.buf), 2))])
        self.buf[i:end] += s

    def mono(self) -> np.ndarray:
        return self.buf.mean(axis=1)


@lru_cache(maxsize=32)
def impulse(rt60: float, bright: float = 5000.0, seed: int = 7, predelay: float = 0.012, early: float = 0.5) -> np.ndarray:
    """造一个房间：指数衰减的立体声噪声，高频掉得快，前面撒几下早期反射。"""
    rng = np.random.default_rng(seed)
    n = sec(rt60 * 1.4)
    tt = times(n)[:, None]
    raw = rng.standard_normal((n, 2))
    k = 6.91  # ln(1000)：rt60 时掉 60 dB
    ir = lp(raw, 350) * np.exp(-k * tt / (rt60 * 1.15))
    ir += bp(raw, 350, bright) * np.exp(-k * tt / rt60)
    ir += hp(raw, bright) * np.exp(-k * tt / (rt60 * 0.4)) * 0.7
    n_in = sec(0.02)
    ir[:n_in] *= (np.arange(n_in) / n_in)[:, None] ** 2
    ir /= np.sqrt((ir ** 2).sum(axis=0, keepdims=True))
    if early > 0:
        for j in range(7):
            at = sec(rng.uniform(0.004, 0.055))
            ir[at, j % 2] += early * rng.uniform(0.35, 0.9) * (0.85 ** j) * rng.choice([-1, 1])
    pre = np.zeros((sec(predelay), 2))
    return np.concatenate([pre, ir])


def reverb(x: np.ndarray, rt60: float = 1.6, wet: float = 0.25, bright: float = 5000.0, seed: int = 7,
           predelay: float = 0.012, dry: float = 1.0, early: float = 0.5, low_cut: float = 0.0) -> np.ndarray:
    """返回立体声，长度 = 原长 + 尾巴。low_cut>0 时把混响尾巴里这个频率以下的去掉：
    低频的混响又长又糊，配乐的「浑」多半是它攒出来的（干声不动）。"""
    s = to_stereo(x)
    ir = impulse(rt60, bright, seed, predelay, early)
    mono_in = s.mean(axis=1)
    tail = np.stack([signal.fftconvolve(mono_in, ir[:, c]) for c in range(2)], axis=1)
    if low_cut > 0:
        tail = hp(tail, low_cut)
    out = tail * wet
    out[:len(s)] += s * dry
    return out


def echo(x: np.ndarray, delay: float, feedback: float = 0.35, mix: float = 0.3, damp: float = 3000.0, taps: int = 5):
    """几下越来越闷的回声（远处、楼与楼之间）。"""
    s = to_stereo(x)
    d = sec(delay)
    out = np.concatenate([s, np.zeros((d * taps, 2))])
    cur = s
    for i in range(1, taps + 1):
        cur = lp(cur, damp)
        tap = cur if i % 2 == 0 else cur[:, ::-1]
        out[d * i:d * i + len(cur)] += tap * mix * feedback ** (i - 1)
    return out


def far(x: np.ndarray, amount: float, rt60: float = 1.2, seed: int = 11) -> np.ndarray:
    """把声音推远：削高频、去低频、加湿。amount 0 贴脸 … 1 隔着两栋楼。"""
    cutoff = 9000.0 * (1 - amount) + 1400.0 * amount
    y = lp(to_stereo(x), cutoff)
    y = hp(y, 80 + 220 * amount, 1)
    return reverb(y, rt60=rt60, wet=0.15 + 0.5 * amount, bright=3500, seed=seed, dry=1.0 - 0.45 * amount)


def trim(x: np.ndarray, floor_db: float = -60.0, release: float = 0.25) -> np.ndarray:
    """把末尾听不见的尾巴切掉（相对峰值 floor_db 以下），再淡出。"""
    mag = np.abs(x).max(axis=1) if x.ndim == 2 else np.abs(x)
    live = np.nonzero(mag > mag.max() * db(floor_db))[0]
    end = min(len(x), (live[-1] if len(live) else 0) + sec(release))
    return fade(x[:end], 0.001, release)


# ---------------------------------------------------------------- 循环 ----

def loop_wrap(x: np.ndarray, n: int) -> np.ndarray:
    """把超出 n 的尾巴（余音、混响）折回开头，循环点上余音不断。"""
    out = np.array(x[:n], dtype=np.float64, copy=True)
    rest = x[n:]
    while len(rest) > 0:
        k = min(n, len(rest))
        out[:k] += rest[:k]
        rest = rest[k:]
    return out


def loop_xfade(x: np.ndarray, overlap: float) -> np.ndarray:
    """噪声类的底噪：把末尾 overlap 秒等功率交叠到开头。返回长度 = 原长 - overlap。"""
    k = sec(overlap)
    n = len(x) - k
    out = np.array(x[:n], dtype=np.float64, copy=True)
    w = np.linspace(0, 1, k)
    if x.ndim == 2:
        w = w[:, None]
    out[:k] = x[:k] * np.sin(0.5 * np.pi * w) + x[n:] * np.cos(0.5 * np.pi * w)
    return out


def warp(x: np.ndarray, depth_cents: float, cycles: tuple, loop_seconds: float) -> np.ndarray:
    """磁带的抖晃：按确定的 LFO 重采样。cycles 是每个循环里各 LFO 转几整圈，
    整圈数保证循环点对得上；各分轨用同一组参数，所以仍然同步。"""
    n = len(x)
    tt = times(n)
    dev = np.zeros(n)
    for i, c in enumerate(cycles):
        dev += np.sin(TAU * c * tt / loop_seconds + 1.3 * i) / len(cycles)
    ratio = cents(dev * depth_cents)
    pos = np.cumsum(ratio)
    pos = pos - pos[0]
    pos *= (n - 1) / pos[-1]
    idx = np.arange(n)
    if x.ndim == 1:
        return np.interp(pos, idx, x)
    return np.stack([np.interp(pos, idx, x[:, c]) for c in range(x.shape[1])], axis=1)


# ---------------------------------------------------------------- 响度 ----

def _k_weight(x: np.ndarray) -> np.ndarray:
    # ITU-R BS.1770 的两级滤波，按 44.1 kHz 重新算系数
    def biquad(kind, fc, q, gain_db=0.0):
        a_ = 10 ** (gain_db / 40.0)
        w0 = TAU * fc / SR
        alpha = np.sin(w0) / (2 * q)
        cs = np.cos(w0)
        if kind == "hs":
            b = [a_ * ((a_ + 1) + (a_ - 1) * cs + 2 * np.sqrt(a_) * alpha), -2 * a_ * ((a_ - 1) + (a_ + 1) * cs),
                 a_ * ((a_ + 1) + (a_ - 1) * cs - 2 * np.sqrt(a_) * alpha)]
            a = [(a_ + 1) - (a_ - 1) * cs + 2 * np.sqrt(a_) * alpha, 2 * ((a_ - 1) - (a_ + 1) * cs),
                 (a_ + 1) - (a_ - 1) * cs - 2 * np.sqrt(a_) * alpha]
        else:
            b = [(1 + cs) / 2, -(1 + cs), (1 + cs) / 2]
            a = [1 + alpha, -2 * cs, 1 - alpha]
        return np.array(b) / a[0], np.array(a) / a[0]

    b1, a1 = biquad("hs", 1500.0, 1 / np.sqrt(2), 4.0)
    b2, a2 = biquad("hp", 38.0, 0.5)
    return signal.lfilter(b2, a2, signal.lfilter(b1, a1, x, axis=0), axis=0)


def true_peak(x: np.ndarray) -> float:
    """真峰值（dBTP）：4 倍过采样后的最大值，比采样峰值更接近解码、重采样后真正会冒到多高。"""
    up = signal.resample_poly(to_stereo(np.asarray(x, dtype=np.float64)), 4, 1, axis=0)
    return float(20 * np.log10(np.max(np.abs(up)) + 1e-12))


def band_share(x: np.ndarray, lo: float, hi: float, weighted: bool = True) -> float:
    """lo~hi 这一段占全频带能量的多少（dB）。weighted=True 先过 K 加权，更接近耳朵听到的比例。
    检查用：2~6 kHz 太多就扎耳朵，120~400 Hz 太多就浑。"""
    s = to_stereo(np.asarray(x, dtype=np.float64))
    s = (_k_weight(s) if weighted else s).mean(axis=1)
    f, p = signal.welch(s, SR, nperseg=8192)
    return float(10 * np.log10(p[(f >= lo) & (f < hi)].sum() / (p[f > 30].sum() + 1e-20) + 1e-20))


def lufs(x: np.ndarray) -> float:
    """带门限的综合响度（BS.1770）。太短的声音退回不带门限的整体值。"""
    s = _k_weight(to_stereo(x))
    block, hop = sec(0.4), sec(0.1)
    if len(s) < block:
        p = float((s ** 2).mean(axis=0).sum())
        return -0.691 + 10 * np.log10(p + 1e-12)
    c = np.cumsum(np.concatenate([[0.0], (s ** 2).sum(axis=1)]))
    starts = np.arange(0, len(s) - block + 1, hop)
    p = (c[starts + block] - c[starts]) / block
    l = -0.691 + 10 * np.log10(p + 1e-12)
    keep = p[l > -70]
    if len(keep) == 0:
        return -70.0
    rel = -0.691 + 10 * np.log10(keep.mean()) - 10
    keep = keep[(-0.691 + 10 * np.log10(keep + 1e-12)) > rel]
    return float(-0.691 + 10 * np.log10(keep.mean() + 1e-12))


def peak_db(x: np.ndarray) -> float:
    return float(20 * np.log10(np.max(np.abs(x)) + 1e-12))


def level(x: np.ndarray, target_lufs: float | None = None, peak: float = -1.5) -> np.ndarray:
    """调到目标响度；峰值超了就整体降下来（不压缩，保住动态）。"""
    y = np.asarray(x, dtype=np.float64)
    if target_lufs is not None:
        y = y * db(target_lufs - lufs(y))
    over = peak_db(y) - peak
    if over > 0 or target_lufs is None:
        y = y * db(-over)
    return y


# ---------------------------------------------------------------- 导出 ----

def write_ogg(path: Path, x: np.ndarray, quality: float = 3.0) -> None:
    """用 ffmpeg 的 libvorbis 编码。-bitexact 让输出可复现。"""
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    y = np.asarray(x, dtype=np.float64)
    ch = 1 if y.ndim == 1 else y.shape[1]
    pcm = (np.clip(y, -1, 1) * 32767.0).round().astype("<i2").tobytes()
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "s16le", "-ar", str(SR), "-ac", str(ch),
           "-i", "pipe:0", "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact",
           "-c:a", "libvorbis", "-q:a", str(quality), str(path)]
    subprocess.run(cmd, input=pcm, check=True)


def read_audio(path: Path) -> np.ndarray:
    """解码回来做检查用（循环点、响度、频谱）。"""
    info = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=channels",
                           "-of", "csv=p=0", str(path)], capture_output=True, text=True, check=True)
    ch = int(info.stdout.strip().split(",")[0])
    raw = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(path), "-f", "f32le",
                          "-ar", str(SR), "pipe:1"], capture_output=True, check=True).stdout
    y = np.frombuffer(raw, dtype="<f4").astype(np.float64)
    return y.reshape(-1, ch) if ch > 1 else y
