#!/usr/bin/env python3
"""循暗晓明 程序化音效生成器（纯标准库实现，零外部依赖）。

为 MVP 合成 A 类共 11 个音效，输出到 assets/audio/sfx/ 下：
    cane_hit / wall_hit / step / fall / spray / touch
    ui_click / npc_approach / victory / failure / danger_warning

实现说明：
- 合成块 = 振荡源(正弦/三角/方波) + 白噪声 + 包络(attack/exp-decay/release) + 双二阶滤波(biquad)。
- 每个音效都是物理模型近似，无需任何外部素材，无版权风险。
- 默认输出 16-bit PCM 单声道 WAV（44100Hz）。若系统 PATH 中存在 ffmpeg，
  则自动转码为 .ogg（符合 AGENTS.md “音频优先 ogg” 建议），并删除 WAV。
- 环境无法联网安装 numpy/ffmpeg 时，WAV 仍可被 Godot 4 直接导入，属计划降级方案。

运行：python tools/audio_generator.py
"""
import math
import os
import shutil
import struct
import subprocess
import wave

SR = 44100
HEADROOM = 0.7  # 留约 -3dB 余量，避免削波


# ---------------- 基础合成块 ----------------

def tone(freq: float, dur: float, wavetype: str = "sine", amp: float = 1.0):
    n = int(dur * SR)
    out = []
    for i in range(n):
        t = i / SR
        ph = 2.0 * math.pi * freq * t
        if wavetype == "sine":
            v = math.sin(ph)
        elif wavetype == "triangle":
            v = 2.0 * abs(2.0 * (t * freq - math.floor(t * freq + 0.5))) - 1.0
        elif wavetype == "square":
            v = 1.0 if math.sin(ph) >= 0.0 else -1.0
        else:
            v = math.sin(ph)
        out.append(v * amp)
    return out


def noise(dur: float, amp: float = 1.0):
    """确定性白噪声（LCG），保证每次生成结果一致。"""
    n = int(dur * SR)
    out = []
    seed = 123456789
    for _ in range(n):
        seed = (1103515245 * seed + 12345) & 0x7FFFFFFF
        u = (seed / 0x7FFFFFFF) * 2.0 - 1.0
        out.append(u * amp)
    return out


def bandpass_coeffs(freq: float, q: float):
    w0 = 2.0 * math.pi * freq / SR
    alpha = math.sin(w0) / (2.0 * q)
    cw = math.cos(w0)
    b0, b1, b2 = alpha, 0.0, -alpha
    a0, a1, a2 = 1.0 + alpha, -2.0 * cw, 1.0 - alpha
    return (b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)


def lowpass_coeffs(freq: float, q: float = 0.707):
    w0 = 2.0 * math.pi * freq / SR
    alpha = math.sin(w0) / (2.0 * q)
    cw = math.cos(w0)
    b0 = (1.0 - cw) / 2.0
    b1 = 1.0 - cw
    b2 = (1.0 - cw) / 2.0
    a0 = 1.0 + alpha
    a1 = -2.0 * cw
    a2 = 1.0 - alpha
    return (b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)


def biquad(samples, coeffs):
    b0, b1, b2, a1, a2 = coeffs
    n = len(samples)
    out = [0.0] * n
    x1 = x2 = y1 = y2 = 0.0
    for i in range(n):
        x0 = samples[i]
        y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        out[i] = y0
        x2, x1 = x1, x0
        y2, y1 = y1, y0
    return out


def envelope(n: int, attack: float, decay_tau: float, release: float = 0.0):
    a_n = max(1, int(attack * SR))
    r_n = max(1, int(release * SR))
    env = []
    for i in range(n):
        g = (i / a_n) if i < a_n else 1.0
        g *= math.exp(-i / (decay_tau * SR))
        if release > 0.0 and i > n - r_n:
            g *= (n - i) / r_n
        env.append(g)
    return env


def apply_env(samples, attack=0.0, decay_tau=0.05, release=0.0):
    env = envelope(len(samples), attack, decay_tau, release)
    return [s * e for s, e in zip(samples, env)]


def pad(samples, total_dur: float):
    total = int(total_dur * SR)
    if len(samples) >= total:
        return samples[:total]
    return samples + [0.0] * (total - len(samples))


def mix(lists):
    """等长求和（短者补零）。"""
    maxlen = max(len(s) for s in lists)
    out = [0.0] * maxlen
    for s in lists:
        for i in range(len(s)):
            out[i] += s[i]
    return out


def normalize(samples, target: float = HEADROOM):
    peak = max((abs(x) for x in samples), default=0.0)
    if peak <= 0.0:
        return samples
    scale = target / peak
    return [x * scale for x in samples]


def write_wav(path: str, samples):
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for s in samples:
            v = max(-1.0, min(1.0, s))
            frames += struct.pack("<h", int(v * 32767))
        w.writeframes(bytes(frames))


def maybe_to_ogg(wav_path: str):
    """若 ffmpeg 可用则转 OGG 并删除 WAV，否则保留 WAV。返回最终路径。"""
    ff = shutil.which("ffmpeg")
    if not ff:
        return wav_path
    ogg = wav_path[:-4] + ".ogg"
    try:
        subprocess.run(
            [ff, "-y", "-i", wav_path, "-c:a", "libvorbis", ogg],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        os.remove(wav_path)
        return ogg
    except Exception:
        return wav_path


# ---------------- 各音效合成 ----------------

def snd_cane_hit():
    nb = noise(0.03, 1.0)
    nb = biquad(nb, bandpass_coeffs(1500.0, 1.0))
    nb = apply_env(nb, attack=0.0, decay_tau=0.04)
    head = tone(1500.0, 0.012, "sine", 0.4)
    head = apply_env(head, decay_tau=0.01)
    return pad(mix([nb, head]), 0.14)


def snd_wall_hit():
    # 沉闷真实碰撞：极低频身体撞击 + 重低通噪声 + 微弱残响
    body = mix([tone(60.0, 0.35, "sine", 0.6),
                tone(75.0, 0.35, "sine", 0.45),
                tone(95.0, 0.35, "triangle", 0.3)])
    body = apply_env(body, attack=0.002, decay_tau=0.10)
    thud = noise(0.04, 1.0)
    thud = biquad(thud, lowpass_coeffs(120.0, 0.5))
    thud = apply_env(thud, attack=0.001, decay_tau=0.03)
    ring = tone(180.0, 0.2, "sine", 0.08)
    ring = apply_env(ring, decay_tau=0.08)
    return pad(mix([body, thud, ring]), 0.4)


def snd_step():
    nb = noise(0.02, 1.0)
    nb = biquad(nb, bandpass_coeffs(700.0, 1.0))
    nb = apply_env(nb, decay_tau=0.025)
    return pad(nb, 0.1)


def snd_fall():
    # 沉重坠落：深扫频（300→30Hz 模拟失重感）+ 落地重击 + 极低频震动
    n = int(0.65 * SR)
    sweep = []
    for i in range(n):
        t = i / SR
        freq = 300.0 - 270.0 * min(1.0, t / 0.55)
        v = math.sin(2.0 * math.pi * freq * t) * 0.45
        # 加入微量噪声模拟坠落风阻
        v += math.sin(i * 0.73) * 0.06
        sweep.append(v)
    sweep = apply_env(sweep, decay_tau=0.22)
    # 落地重击：极低通高能量噪声
    impact = noise(0.07, 1.0)
    impact = biquad(impact, lowpass_coeffs(80.0, 0.4))
    impact = apply_env(impact, attack=0.002, decay_tau=0.06)
    # 地面震动感
    rumble = tone(35.0, 0.35, "sine", 0.55)
    rumble = apply_env(rumble, attack=0.002, decay_tau=0.14)
    return pad(mix([sweep, impact, rumble]), 0.8)


def snd_spray():
    nb = noise(0.3, 1.0)
    nb = biquad(nb, bandpass_coeffs(4000.0, 0.7))
    nb = apply_env(nb, attack=0.05, decay_tau=0.2, release=0.05)
    return pad(nb, 0.3)


def snd_touch():
    body = tone(660.0, 0.16, "sine", 0.5)
    body = apply_env(body, attack=0.02, decay_tau=0.07, release=0.05)
    click = tone(3000.0, 0.01, "sine", 0.12)
    click = apply_env(click, decay_tau=0.008)
    return pad(mix([body, click]), 0.2)


def snd_ui_click():
    s = tone(880.0, 0.06, "square", 0.4)
    return pad(apply_env(s, decay_tau=0.02), 0.07)


def snd_npc_approach():
    a = apply_env(tone(523.25, 0.12, "sine", 0.4), decay_tau=0.08)
    b = apply_env(tone(659.25, 0.12, "sine", 0.4), decay_tau=0.08)
    gap = [0.0] * int(0.03 * SR)
    return pad(a + gap + b, 0.3)


def snd_victory():
    # 辉煌上行大三和弦 C5→E5→G5→C6，尾音叠加和弦
    dur = 1.3
    parts: list[float] = []
    freqs = [523.25, 659.25, 783.99, 1046.5]  # C-E-G-C 上行
    for f in freqs:
        s = tone(f, 0.26, "sine", 0.5)
        s = apply_env(s, attack=0.01, decay_tau=0.18)
        parts += s
        parts += [0.0] * int(0.04 * SR)
    # 结尾明亮和弦层
    chord = mix([
        tone(523.25, 0.6, "sine", 0.22),
        tone(659.25, 0.6, "sine", 0.20),
        tone(783.99, 0.6, "sine", 0.17),
        tone(1046.5, 0.6, "sine", 0.13),
    ])
    chord = apply_env(chord, attack=0.01, decay_tau=0.3)
    return pad(mix([pad(parts, dur), chord]), dur)


def snd_failure():
    # 下行减和弦 + 低沉嗡鸣 + 噪声底噪，明显消极向下
    dur = 1.5
    parts: list[float] = []
    # 不协和下行：D#5→C#5→A#4→F#4（减七分解）
    freqs = [622.25, 554.37, 466.16, 369.99]
    for f in freqs:
        s = tone(f, 0.24, "triangle", 0.5)
        s = apply_env(s, decay_tau=0.14)
        parts += s
        parts += [0.0] * int(0.06 * SR)
    # 低沉嗡鸣——减五度，压抑感
    drone = tone(138.59, 0.6, "square", 0.35)
    drone = apply_env(drone, attack=0.01, decay_tau=0.35)
    # 不协和底噪
    buzz = noise(0.35, 0.25)
    buzz = biquad(buzz, bandpass_coeffs(350.0, 0.5))
    buzz = apply_env(buzz, attack=0.1, decay_tau=0.18)
    return pad(mix([pad(parts, dur), drone, buzz]), dur)


def snd_danger_warning():
    """稳定、明确、可重复的双音警示（满足 AGENTS §10 可访问性）。"""
    b1 = apply_env(tone(1046.5, 0.09, "square", 0.45), decay_tau=0.05)
    b2 = apply_env(tone(783.99, 0.09, "square", 0.45), decay_tau=0.05)
    gap = [0.0] * int(0.05 * SR)
    return pad(b1 + gap + b2, 0.28)


SOUNDS = {
    "cane_hit": snd_cane_hit,
    "wall_hit": snd_wall_hit,
    "step": snd_step,
    "fall": snd_fall,
    "spray": snd_spray,
    "touch": snd_touch,
    "ui_click": snd_ui_click,
    "npc_approach": snd_npc_approach,
    "victory": snd_victory,
    "failure": snd_failure,
    "danger_warning": snd_danger_warning,
}


def main():
    out_dir = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
    out_dir = os.path.abspath(out_dir)
    os.makedirs(out_dir, exist_ok=True)

    generated = []
    for name, fn in SOUNDS.items():
        samples = normalize(fn())
        wav = os.path.join(out_dir, name + ".wav")
        write_wav(wav, samples)
        final = maybe_to_ogg(wav)
        generated.append(os.path.basename(final))

    generated.sort()
    print("Generated %d SFX files in %s:" % (len(generated), out_dir))
    for g in generated:
        print("  -", g)


if __name__ == "__main__":
    main()
