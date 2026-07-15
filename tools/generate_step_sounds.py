"""
程序化生成不同材质表面的脚步声 (.wav)。
通过噪声整形、带通滤波、包络控制和混响模拟来区分材质。
"""
import struct
import wave
import numpy as np

SAMPLE_RATE = 44100
BIT_DEPTH = 16
DURATION = 0.35  # 单个脚步声时长（秒）
OUTPUT_DIR = r"D:\Coding\BlindWalker\assets\audio\sfx"

MATERIALS = {
    "step": {
        "label": "默认脚步",
        "center_freq": 480, "bandwidth": 600, "decay": 0.06,
        "noise_color": 1.4, "reverb_mix": 0.13, "reverb_decay": 0.20, "gain": 0.88,
    },
    "step_asphalt": {
        "label": "柏油路面",
        "center_freq": 380, "bandwidth": 500, "decay": 0.08,
        "noise_color": 1.5, "reverb_mix": 0.12, "reverb_decay": 0.18, "gain": 0.85,
    },
    "step_concrete": {
        "label": "水泥地面",
        "center_freq": 550, "bandwidth": 700, "decay": 0.06,
        "noise_color": 1.3, "reverb_mix": 0.15, "reverb_decay": 0.22, "gain": 0.9,
    },
    "step_pavement": {
        "label": "盲道砖",
        "center_freq": 900, "bandwidth": 1000, "decay": 0.04,
        "noise_color": 0.8, "reverb_mix": 0.20, "reverb_decay": 0.28, "gain": 0.95,
    },
    "step_tiles": {
        "label": "瓷砖",
        "center_freq": 1100, "bandwidth": 1200, "decay": 0.05,
        "noise_color": 0.6, "reverb_mix": 0.35, "reverb_decay": 0.55, "gain": 0.75,
    },
    "step_wood": {
        "label": "木地板",
        "center_freq": 250, "bandwidth": 400, "decay": 0.10,
        "noise_color": 1.8, "reverb_mix": 0.22, "reverb_decay": 0.35, "gain": 0.8,
    },
    "step_metal": {
        "label": "金属",
        "center_freq": 1800, "bandwidth": 2200, "decay": 0.12,
        "noise_color": 2.5, "reverb_mix": 0.40, "reverb_decay": 0.70, "gain": 0.65,
    },
}


def colored_noise(n_samples: int, color: float) -> np.ndarray:
    white = np.random.normal(0, 1, n_samples)
    freqs = np.fft.rfftfreq(n_samples, d=1.0 / SAMPLE_RATE)
    shaping = np.ones_like(freqs)
    nonzero = freqs > 0
    shaping[nonzero] = 1.0 / (freqs[nonzero] ** color)
    shaping = np.clip(shaping / shaping.max(), 0.0, 100.0)
    fft_white = np.fft.rfft(white)
    shaped = np.fft.irfft(fft_white * shaping, n=n_samples)
    rms = np.sqrt(np.mean(shaped ** 2))
    if rms > 0:
        shaped /= rms * 0.5
    return shaped


def bandpass_filter(signal: np.ndarray, center: float, bw: float) -> np.ndarray:
    freqs = np.fft.rfftfreq(len(signal), d=1.0 / SAMPLE_RATE)
    fft_sig = np.fft.rfft(signal)
    response = np.exp(-((freqs - center) ** 2) / (2 * (bw / 3.0) ** 2))
    fft_sig *= response
    return np.fft.irfft(fft_sig, n=len(signal))


def impact_envelope(n_samples: int, decay_time: float) -> np.ndarray:
    t = np.arange(n_samples) / SAMPLE_RATE
    attack = np.clip(t / 0.002, 0, 1)
    decay = np.exp(-t / decay_time) if decay_time > 0 else np.ones(n_samples)
    return attack * decay


def schroeder_reverb(signal: np.ndarray, mix: float, decay: float) -> np.ndarray:
    if mix <= 0:
        return signal
    delays = [0.0297, 0.0371, 0.0411, 0.0437]
    gains = [0.6, 0.55, 0.5, 0.45]
    output = signal.copy()
    for delay_s, g in zip(delays, gains):
        delay_samples = int(delay_s * SAMPLE_RATE)
        feedback_gain = g * decay * 0.5
        delayed = np.zeros(len(signal) + delay_samples)
        delayed[delay_samples:] = signal
        for _ in range(3):
            delayed = delayed + np.roll(delayed, delay_samples) * feedback_gain * 0.7
        output += delayed[:len(signal)] * mix * 0.3 * g / len(delays)
    return output


def multi_impact(params: dict, n_samples: int, seed_offset: int = 0) -> np.ndarray:
    rng = np.random.RandomState(42 + hash(params["label"]) % 1000 + seed_offset)
    sound = np.zeros(n_samples)

    # 主冲击
    main = colored_noise(n_samples, params["noise_color"])
    main = bandpass_filter(main, params["center_freq"], params["bandwidth"])
    env = impact_envelope(n_samples, params["decay"])
    sound += main * env * 0.7

    # 2-3 次微冲击
    for i in range(rng.randint(2, 4)):
        offset = int(rng.uniform(0.003, 0.015) * SAMPLE_RATE)
        sub = colored_noise(n_samples, params["noise_color"] * rng.uniform(0.7, 1.3))
        sub = bandpass_filter(sub, params["center_freq"] * rng.uniform(0.5, 2.0),
                              params["bandwidth"] * rng.uniform(0.6, 1.4))
        sub_env = impact_envelope(n_samples, params["decay"] * rng.uniform(0.3, 0.7))
        sub_env[:offset] = 0
        sound += sub * sub_env * rng.uniform(0.15, 0.35)

    # 低频共振体感
    if params["center_freq"] > 300:
        body_res = np.sin(2 * np.pi * rng.uniform(60, 150) *
                         np.arange(n_samples) / SAMPLE_RATE)
        body_env = impact_envelope(n_samples, params["decay"] * rng.uniform(1.5, 3.0))
        sound += body_res * body_env * rng.uniform(0.08, 0.15)

    # 混响
    sound = schroeder_reverb(sound, params["reverb_mix"], params["reverb_decay"])

    peak = np.max(np.abs(sound))
    if peak > 0:
        sound = sound / peak * params["gain"] * 0.9

    return sound


def apply_fade_out(signal: np.ndarray, fade_start: float = 0.7) -> np.ndarray:
    n = len(signal)
    fade_start_idx = int(n * fade_start)
    if fade_start_idx >= n:
        return signal
    fade_len = n - fade_start_idx
    fade = np.cos(np.linspace(0, np.pi / 2, fade_len)) ** 2
    signal[fade_start_idx:] *= fade
    return signal


def write_wav(filepath: str, signal: np.ndarray) -> None:
    signal = np.clip(signal, -1.0, 1.0)
    samples = (signal * 32767).astype(np.int16)
    with wave.open(filepath, "w") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(samples.tobytes())


def main():
    np.random.seed(12345)
    n_samples = int(SAMPLE_RATE * DURATION)

    for name, params in MATERIALS.items():
        print(f"生成 {params['label']} 脚步声: {name}.wav ...")
        sound = multi_impact(params, n_samples)
        sound = apply_fade_out(sound)
        filepath = f"{OUTPUT_DIR}\\{name}.wav"
        write_wav(filepath, sound)

    print("\n验证生成的文件：")
    import os
    for name in MATERIALS:
        fpath = os.path.join(OUTPUT_DIR, f"{name}.wav")
        size = os.path.getsize(fpath)
        print(f"  {name}.wav  [{size} bytes]")

    print("\n全部生成完毕！")
    print("TIPS: 在 Godot 编辑器中打开项目，引擎会自动导入这些 .wav 文件。")


if __name__ == "__main__":
    main()
