#!/usr/bin/env python3
"""腾讯云 TTS 离线批量生成叙事台词语音。

从 assets/narrative/*.tres 提取被游戏引用的台词，按 tools/tts/voice_map.json
配置的角色音色调用腾讯云语音合成（TextToVoice），输出确定性命名的
assets/audio/voice/{audio_id}.ogg，并回填 tres 的 speaker_id / audio_id / duration。

特性：
- 密钥仅从环境变量 TENCENTCLOUD_SECRET_ID / TENCENTCLOUD_SECRET_KEY 读取，绝不硬编码。
- 幂等：voice_manifest.json 记录每句文本 hash，只有文本变化或文件缺失才重新合成。
- 只处理被场景/脚本引用的台词；未接线文本默认跳过（--include-unused 强制合成）。
- --dry-run 只预览；--limit N 限量合成（先小批量验证再全量）。

用法：
    python tools/tts/generate_tts_voices.py --dry-run
    python tools/tts/generate_tts_voices.py --limit 3
    python tools/tts/generate_tts_voices.py
"""
import argparse
import base64
import hashlib
import hmac
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
import uuid
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
NARRATIVE_DIR = os.path.join(ROOT, "assets", "narrative")
VOICE_DIR = os.path.join(ROOT, "assets", "audio", "voice")
MANIFEST_PATH = os.path.join(VOICE_DIR, "voice_manifest.json")
VOICE_MAP_PATH = os.path.join(ROOT, "tools", "tts", "voice_map.json")
SSML_OVERRIDES_PATH = os.path.join(ROOT, "tools", "tts", "ssml_overrides.json")

TTS_HOST = "tts.tencentcloudapi.com"
TTS_VERSION = "2019-08-23"
TTS_ACTION = "TextToVoice"
TTS_SERVICE = "tts"
TTS_REGION = ""  # 可选

MAX_TEXT_LENGTH = 150  # 中文最大 150 汉字
SAMPLE_RATE = 16000
DURATION_PADDING = 0.2  # duration = 音频时长 + 0.2s

# 角色显示名 -> 稳定 speaker_id
SPEAKER_NAME_TO_ID = {
    "晓明": "xiaoming",
    "李奶奶": "li_grandma",
    "王叔": "wang_shu",
    "好心路人": "kind_passersby",
}

# 无 speaker 的旁白行：intro 第一人称独白归入晓明；其余旁白标记为 narrator
NARRATOR_ID = "narrator"
INTRO_XIAOMING_LINES = {  # 文件名 -> 1-based 行号列表（晓明第一人称独白，与晓明同音色）
    "intro_fullscreen": [1, 2, 3],
}

# 明确不配音的行（第三人称叙述 / 舞台提示 / 系统提示），保持静默字幕
SKIP_NARRATIVE_LINES = {
    "dialogue_endpoint": [2, 3],
    "outro_fullscreen": [1, 2, 3],
    "sample_neighbor_request": [3],
    "failure_fullscreen": [1],
    "intro_fullscreen": [4],
}

BRACKET_RE = re.compile(r"【[^】]*】")
PAREN_RE = re.compile(r"[（(][^）)]*[）)]")


class Line:
    def __init__(self, seq, index, text, speaker_name, speaker_id, audio_id, duration):
        self.seq = seq            # 文件名（不含 .tres）
        self.index = index        # 1-based 行号（tres 内第几个含 text 的 NarrativeLine）
        self.text = text
        self.speaker_name = speaker_name
        self.speaker_id = speaker_id
        self.audio_id = audio_id
        self.duration = duration

    @property
    def audio_id_value(self):
        return "voice_%s_%02d" % (self.seq_short, self.index)

    @property
    def seq_short(self):
        return self.seq.removeprefix("dialogue_")


def load_voice_map():
    with open(VOICE_MAP_PATH, encoding="utf-8") as f:
        return json.load(f)


def load_ssml_overrides():
    """按 audio_id 的合成文本覆盖（SSML 或微调文本）。字幕与台词原文不受影响。"""
    if os.path.exists(SSML_OVERRIDES_PATH):
        with open(SSML_OVERRIDES_PATH, encoding="utf-8") as f:
            return json.load(f)
    return {}


def synth_text_for(audio_id, base_text, overrides):
    return overrides.get(audio_id, base_text)


def is_referenced(seq):
    """检查该叙事资源是否被场景或脚本引用。"""
    pattern = re.compile(re.escape("assets/narrative/" + seq + ".tres"))
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in (".git", ".godot", "exports", "assets")]
        for name in filenames:
            if not (name.endswith(".tscn") or name.endswith(".gd")):
                continue
            path = os.path.join(dirpath, name)
            try:
                with open(path, encoding="utf-8", errors="ignore") as f:
                    if pattern.search(f.read()):
                        return True
            except OSError:
                pass
    return False


def scan_tres(seq):
    """解析一个 tres 文件中的所有 NarrativeLine（行号 = 第 N 个含 text 的块）。"""
    path = os.path.join(NARRATIVE_DIR, seq + ".tres")
    with open(path, encoding="utf-8") as f:
        src = f.read()
    lines = []
    for block in re.split(r"(?=\[sub_resource)", src):
        if "NarrativeLine" not in block:
            continue
        m_text = re.search(r'^\s*text = "(.*)"', block, re.M)
        if not m_text:
            continue
        m_name = re.search(r'^\s*speaker_name = "([^"]*)"', block, re.M)
        m_sid = re.search(r'^\s*speaker_id = &"([^"]*)"', block, re.M)
        m_aid = re.search(r'^\s*audio_id = &"([^"]*)"', block, re.M)
        m_dur = re.search(r'^\s*duration = ([\d.]+)', block, re.M)
        lines.append(Line(
            seq,
            len(lines) + 1,
            m_text.group(1),
            m_name.group(1) if m_name else "",
            m_sid.group(1) if m_sid else "",
            m_aid.group(1) if m_aid else "",
            float(m_dur.group(1)) if m_dur else 0.0,
        ))
    return lines


def resolve_speaker_id(line):
    if line.speaker_id:
        return line.speaker_id
    if line.speaker_name in SPEAKER_NAME_TO_ID:
        return SPEAKER_NAME_TO_ID[line.speaker_name]
    if line.seq in INTRO_XIAOMING_LINES and line.index in INTRO_XIAOMING_LINES[line.seq]:
        return "xiaoming"
    return NARRATOR_ID


def clean_text(text):
    # 剥离操作提示【...】；内心独白用的全角括号只去掉括号字符、保留内容，
    # TTS 不应读出括号本身，但整句在括号内的独白仍需朗读。
    text = BRACKET_RE.sub("", text)
    text = text.replace("（", "").replace("）", "").replace("(", "").replace(")", "")
    return text.strip()


def is_skip(line):
    return line.seq in SKIP_NARRATIVE_LINES and line.index in SKIP_NARRATIVE_LINES[line.seq]


def load_manifest():
    if os.path.exists(MANIFEST_PATH):
        with open(MANIFEST_PATH, encoding="utf-8") as f:
            return json.load(f)
    return {}


def save_manifest(manifest):
    os.makedirs(VOICE_DIR, exist_ok=True)
    with open(MANIFEST_PATH, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent="\t")
        f.write("\n")


def text_hash(text):
    return hashlib.md5(text.encode("utf-8")).hexdigest()[:12]


# ---------------- 腾讯云 TC3-HMAC-SHA256 签名 ----------------

def _hmac_sha256(key, msg):
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()


def _sha256_hex(data):
    return hashlib.sha256(data).hexdigest()


def tc3_sign(secret_id, secret_key, timestamp, payload):
    date = time.strftime("%Y-%m-%d", time.gmtime(timestamp))
    canonical_headers = "content-type:application/json; charset=utf-8\nhost:%s\n" % TTS_HOST
    signed_headers = "content-type;host"
    canonical_request = "\n".join([
        "POST", "/", "", canonical_headers, signed_headers,
        _sha256_hex(payload),
    ])
    credential_scope = "%s/%s/tc3_request" % (date, TTS_SERVICE)
    string_to_sign = "\n".join([
        "TC3-HMAC-SHA256", str(timestamp), credential_scope,
        _sha256_hex(canonical_request.encode("utf-8")),
    ])
    secret_date = _hmac_sha256(("TC3" + secret_key).encode("utf-8"), date)
    secret_service = _hmac_sha256(secret_date, TTS_SERVICE)
    secret_signing = _hmac_sha256(secret_service, "tc3_request")
    signature = hmac.new(secret_signing, string_to_sign.encode("utf-8"), hashlib.sha256).hexdigest()
    authorization = "TC3-HMAC-SHA256 Credential=%s/%s, SignedHeaders=%s, Signature=%s" % (
        secret_id, credential_scope, signed_headers, signature)
    return authorization


def call_tts(voice_config, text, session_id, max_retries=3):
    secret_id = os.environ.get("TENCENTCLOUD_SECRET_ID")
    secret_key = os.environ.get("TENCENTCLOUD_SECRET_KEY")
    if not secret_id or not secret_key:
        sys.exit("缺少密钥：请设置环境变量 TENCENTCLOUD_SECRET_ID / TENCENTCLOUD_SECRET_KEY")

    payload = json.dumps({
        "Text": text,
        "SessionId": session_id,
        "VoiceType": voice_config["voice_type"],
        "Speed": voice_config.get("speed", 0.0),
        "Volume": 0,
        "ProjectId": 0,
        "ModelType": 1,
        "PrimaryLanguage": 1,
        "SampleRate": SAMPLE_RATE,
        "Codec": "wav",
    }).encode("utf-8")

    for attempt in range(max_retries):
        timestamp = int(time.time())
        auth = tc3_sign(secret_id, secret_key, timestamp, payload)
        request = urllib.request.Request(
            "https://%s/" % TTS_HOST,
            data=payload,
            headers={
                "Content-Type": "application/json; charset=utf-8",
                "Host": TTS_HOST,
                "X-TC-Action": TTS_ACTION,
                "X-TC-Version": TTS_VERSION,
                "X-TC-Timestamp": str(timestamp),
                "X-TC-Nonce": str(uuid.uuid4().hex[:16]),
                "X-TC-Region": TTS_REGION,
                "Authorization": auth,
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as resp:
                data = json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="ignore")
            if e.code in (429, 500, 502, 503, 504) and attempt < max_retries - 1:
                time.sleep(2 ** (attempt + 1))
                continue
            sys.exit("TTS HTTP %d: %s" % (e.code, body))
        except urllib.error.URLError as e:
            if attempt < max_retries - 1:
                time.sleep(2 ** (attempt + 1))
                continue
            sys.exit("TTS 网络错误: %s" % e)

        response = data.get("Response", {})
        if "Error" in response:
            code = response["Error"].get("Code")
            message = response["Error"].get("Message")
            if code in ("LimitExceeded.AccessLimit", "InternalError.ExceedMaxLimit") and attempt < max_retries - 1:
                time.sleep(2 ** (attempt + 1))
                continue
            sys.exit("TTS 业务错误 %s: %s" % (code, message))
        audio_b64 = response.get("Audio")
        if not audio_b64:
            sys.exit("TTS 响应缺少 Audio 字段: %s" % response)
        return base64.b64decode(audio_b64)
    sys.exit("TTS 重试耗尽")


# ---------------- 音频与 tres 回填 ----------------

def wav_duration_seconds(wav_path):
    with wave.open(wav_path, "rb") as w:
        return w.getnframes() / float(w.getframerate())


def to_ogg(wav_path, ogg_path):
    subprocess.run(
        ["ffmpeg", "-y", "-i", wav_path, "-c:a", "libvorbis", "-q:a", "3", ogg_path],
        check=True, capture_output=True,
    )


def update_tres(line, speaker_id, audio_id, duration):
    """把 speaker_id / audio_id / duration 回填到对应 NarrativeLine 块。"""
    path = os.path.join(NARRATIVE_DIR, line.seq + ".tres")
    with open(path, encoding="utf-8") as f:
        src = f.read()

    blocks = re.split(r"(?=\[sub_resource)", src)
    line_index = 0
    for i, block in enumerate(blocks):
        if "NarrativeLine" not in block:
            continue
        if not re.search(r'^\s*text = ', block, re.M):
            # 与 scan_tres 的行号定义一致：只统计含 text 的台词块
            continue
        line_index += 1
        if line_index != line.index:
            continue
        new_block = block
        if speaker_id and re.search(r'^\s*speaker_id = &"[^"]*"', new_block, re.M):
            new_block = re.sub(
                r'^\s*speaker_id = &"[^"]*"', 'speaker_id = &"%s"' % speaker_id,
                new_block, count=1, flags=re.M)
        elif speaker_id:
            new_block = re.sub(
                r'^\s*script = ExtResource',
                'speaker_id = &"%s"\nscript = ExtResource' % speaker_id,
                new_block, count=1, flags=re.M)
        if audio_id and re.search(r'^\s*audio_id = &"[^"]*"', new_block, re.M):
            new_block = re.sub(
                r'^\s*audio_id = &"[^"]*"', 'audio_id = &"%s"' % audio_id,
                new_block, count=1, flags=re.M)
        elif audio_id:
            new_block = re.sub(
                r'^\s*(text = )', 'audio_id = &"%s"\n\\1' % audio_id,
                new_block, count=1, flags=re.M)
        if duration > 0.0 and re.search(r'^\s*duration = [\d.]+', new_block, re.M):
            new_block = re.sub(
                r'^\s*duration = [\d.]+', "duration = %.2f" % duration,
                new_block, count=1, flags=re.M)
        elif duration > 0.0:
            new_block = re.sub(
                r'^\s*(audio_id = )', "duration = %.2f\n\\1" % duration,
                new_block, count=1, flags=re.M)
        blocks[i] = new_block
        break

    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("".join(blocks))


# ---------------- 主流程 ----------------

def main():
    parser = argparse.ArgumentParser(description="腾讯云 TTS 批量生成叙事语音")
    parser.add_argument("--dry-run", action="store_true", help="只预览，不调用 API 不写文件")
    parser.add_argument("--limit", type=int, default=0, help="最多合成 N 句（0=不限）")
    parser.add_argument("--include-unused", action="store_true", help="也合成未被引用的文本")
    args = parser.parse_args()

    voice_map = load_voice_map()
    manifest = load_manifest()
    overrides = load_ssml_overrides()

    if not os.path.exists(NARRATIVE_DIR):
        sys.exit("未找到 assets/narrative 目录")

    plan_synthesize = []
    plan_skip = []
    plan_unreferenced = []

    for name in sorted(os.listdir(NARRATIVE_DIR)):
        if not name.endswith(".tres"):
            continue
        seq = name[:-5]
        referenced = is_referenced(seq)
        for line in scan_tres(seq):
            speaker_id = resolve_speaker_id(line)
            text = clean_text(line.text)
            if not text:
                continue
            if not referenced:
                plan_unreferenced.append((seq, line.index, speaker_id, text))
                continue
            if is_skip(line):
                plan_skip.append((seq, line.index, speaker_id, text))
                continue
            plan_synthesize.append((line, speaker_id, text))

    print("== 合成计划 ==")
    total_chars = 0
    for line, speaker_id, text in plan_synthesize:
        audio_id = line.audio_id_value
        synth = synth_text_for(audio_id, text, overrides)
        known = manifest.get(audio_id, {})
        config = voice_map.get(speaker_id, {})
        changed = known.get("text_hash") != text_hash(synth) \
                or known.get("voice_type") != config.get("voice_type") \
                or known.get("speed", config.get("speed")) != config.get("speed") \
                or not os.path.exists(os.path.join(VOICE_DIR, audio_id + ".ogg"))
        status = "CHANGED" if changed else "skip"
        total_chars += len(text)
        mark = " [ssml]" if audio_id in overrides else ""
        print("  [%s] %-28s %-14s %3d字 %s%s" % (
            status, audio_id, speaker_id, len(text), text[:24], mark))
    print("  合计: %d 句, %d 字符" % (len(plan_synthesize), total_chars))
    print("== 跳过（不配音） ==")
    for seq, index, speaker_id, text in plan_skip:
        print("  %-28s #%02d %-14s %s" % (seq, index, speaker_id, text[:30]))
    if plan_unreferenced:
        print("== 未引用文本（默认不合成，--include-unused 强制） ==")
        for seq, index, speaker_id, text in plan_unreferenced:
            print("  %-28s #%02d %-14s %s" % (seq, index, speaker_id, text[:30]))

    if args.dry_run:
        return

    budget = args.limit if args.limit > 0 else len(plan_synthesize)
    processed = 0
    for line, speaker_id, text in plan_synthesize:
        if processed >= budget:
            break
        processed += 1
        audio_id = line.audio_id_value
        ogg_path = os.path.join(VOICE_DIR, audio_id + ".ogg")
        known = manifest.get(audio_id, {})
        config = voice_map.get(speaker_id, {})
        synth = synth_text_for(audio_id, text, overrides)
        if known.get("text_hash") == text_hash(synth) \
                and known.get("voice_type") == config.get("voice_type") \
                and known.get("speed", config.get("speed")) == config.get("speed") \
                and os.path.exists(ogg_path):
            print("[skip] %s (文本/音色/语速均未变化)" % audio_id)
            continue
        plain_length = len(re.sub(r"<[^>]+>", "", synth))
        if plain_length > MAX_TEXT_LENGTH:
            print("[SKIP] %s 超 %d 字: %s" % (audio_id, MAX_TEXT_LENGTH, text[:30]))
            continue
        voice_config = voice_map.get(speaker_id)
        if not voice_config:
            print("[SKIP] %s 无音色配置 speaker=%s" % (audio_id, speaker_id))
            continue

        print("[TTS ] %s 角色=%s 音色=%s 文本=%s%s" % (
            audio_id, speaker_id, voice_config["voice_type"], text[:24],
            " [ssml]" if audio_id in overrides else ""))
        wav_data = call_tts(voice_config, synth, str(uuid.uuid4()))
        wav_path = os.path.join(VOICE_DIR, audio_id + ".wav")
        with open(wav_path, "wb") as f:
            f.write(wav_data)
        duration = wav_duration_seconds(wav_path) + DURATION_PADDING
        to_ogg(wav_path, ogg_path)
        os.remove(wav_path)

        manifest[audio_id] = {
            "file": audio_id + ".ogg",
            "text": synth,
            "text_hash": text_hash(synth),
            "speaker_id": speaker_id,
            "voice_type": voice_config["voice_type"],
            "speed": voice_config.get("speed", 0.0),
            "duration": round(duration, 2),
            "purpose": "narrative_line",
        }
        save_manifest(manifest)
        update_tres(line, speaker_id, audio_id, round(duration, 2))
        print("[OK  ] %s duration=%.2f" % (ogg_path, duration))

    print("完成: 处理 %d 句" % processed)


if __name__ == "__main__":
    main()
