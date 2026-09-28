# -*- coding: utf-8 -*-
"""《保卫鄱阳湖》算分动画音效生成器（纯 Python 标准库，零第三方依赖）

用法：
    python tools/make_ding.py

产出：
    assets/audio/ding.wav   「叮」——逐张弹分 / 指标结算
    assets/audio/land.wav   「啪」——甩牌落桌的闷响

⚠ 生成后必须在 Godot 编辑器里打开一次工程（或跑 godot --headless --import），
   让它产出 .import 文件；否则导出包里没有音效。

音色设计要点（改参数前先读这段）：
  · 基频选 E6(1318.5Hz)：明亮但不刺耳，比 C6 更有「叮」的穿透力，
    又不像 2kHz 那样在连击时聒噪。
  · 上滑(chirp)：击槌瞬间频率抬高 5.5% 再回落，τ=18ms。
    这是「叮」和正弦波「哔」的分界线 —— 去掉它就成了电子音。
  · 分音刻意用非谐比率(1.00/2.01/2.99/4.17/5.43)：产生金属/木琴质感。
    若改成整倍数(1/2/3/4/5)会立刻变成风琴音，失去「敲击」感。
  · 高次分音衰减更快(11→36/s)，符合真实物理的阻尼规律。
  · 6ms 白噪模拟击槌接触瞬间，给声音「实体感」；固定随机种子保证
    每次生成字节完全一致（否则每次跑都产生 git diff，无法入库比对）。
"""

import array
import math
import os
import random
import sys
import wave

SR = 44100          # 采样率：Godot 原生格式，零重采样
PEAK = 0.89         # 归一化峰值（留约 1dB 余量，多声叠播不削顶）
ATTACK = 0.002      # 2ms 起音斜坡（防起始爆音）
FADE = 0.010        # 10ms 收尾淡出（防截断爆音）

# 音色配方
#   f0        基频 Hz
#   dur       总时长 秒
#   chirp     上滑比例（正=起手抬高，负=起手压低）
#   chirp_t   上滑时间常数 秒
#   noise     击槌噪声幅度
#   noise_t   噪声衰减时间常数 秒
#   partials  [(频率比, 振幅, 衰减系数 1/s), ...]
RECIPES = {
    # 逐张弹分 / 指标结算的「叮」
    "ding": dict(
        f0=1318.5, dur=0.30, chirp=0.055, chirp_t=0.018,
        noise=0.10, noise_t=0.006,
        partials=[(1.00, 1.00, 11.0), (2.01, 0.42, 15.0), (2.99, 0.22, 21.0),
                  (4.17, 0.13, 28.0), (5.43, 0.07, 36.0)],
    ),
    # 甩牌落桌的闷响
    "land": dict(
        f0=170.0, dur=0.16, chirp=-0.030, chirp_t=0.010,
        noise=0.55, noise_t=0.010,
        partials=[(1.00, 1.00, 34.0), (1.58, 0.34, 46.0), (2.42, 0.14, 62.0)],
    ),
}


def synth(recipe, seed=20260928):
    """按配方合成一段归一化到 [-1, 1] 的单声道浮点样本。"""
    n = int(SR * recipe["dur"])
    out = [0.0] * n
    chirp = recipe["chirp"]
    chirp_t = recipe["chirp_t"]

    # 分音叠加。用相位积分而不是直接 sin(2πft)，才能做频率滑移。
    for ratio, amp, decay in recipe["partials"]:
        f0 = recipe["f0"] * ratio
        phase = 0.0
        for i in range(n):
            t = i / SR
            inst_f = f0 * (1.0 + chirp * math.exp(-t / chirp_t))
            phase += 2.0 * math.pi * inst_f / SR
            out[i] += amp * math.exp(-decay * t) * math.sin(phase)

    # 击槌噪声。固定种子 → 每次生成结果字节一致，可入库比对。
    rng = random.Random(seed)
    noise = recipe["noise"]
    noise_t = recipe["noise_t"]
    for i in range(n):
        out[i] += noise * math.exp(-(i / SR) / noise_t) * (rng.random() * 2.0 - 1.0)

    # 起音 / 收尾斜坡，消除爆音
    na = max(1, int(SR * ATTACK))
    nf = max(1, int(SR * FADE))
    for i in range(na):
        out[i] *= i / na
    for i in range(nf):
        out[n - 1 - i] *= i / nf

    # tanh 软限幅 + 归一化：避免任何数字尖峰被硬削顶
    peak = max(abs(v) for v in out) or 1.0
    g = PEAK / peak
    return [math.tanh(v * g * 1.15) / math.tanh(1.15) for v in out]


def write_wav(path, samples):
    """写出 16bit / 单声道 / 44.1kHz 的 WAV。"""
    pcm = array.array("h")
    for v in samples:
        s = int(round(v * 32767.0))
        pcm.append(max(-32768, min(32767, s)))
    if sys.byteorder != "little":
        pcm.byteswap()          # WAV 要求小端
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return len(pcm)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "assets", "audio")
    os.makedirs(out_dir, exist_ok=True)

    for name, recipe in RECIPES.items():
        frames = write_wav(os.path.join(out_dir, name + ".wav"), synth(recipe))
        print("wrote %s.wav  (%d frames, %.2fs)" % (name, frames, frames / SR))

    print("\n下一步：在 Godot 编辑器里打开一次工程，生成 .import 文件。")


if __name__ == "__main__":
    main()
