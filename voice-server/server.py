#!/usr/bin/env python3
"""
Local neural voice server for Clicky (Qwen3-TTS 0.6B via mlx-audio, runs on the Apple GPU).

  POST /speak   {"text": "one sentence or phrase"}  ->  audio/wav (mono, 24 kHz)
  GET  /health  ->  {"ok": true, ...}

Privacy / safety:
  * Binds to 127.0.0.1 only, so nothing outside this Mac can reach it.
  * Requires the custom header `x-thambi-client: 1` (a web page cannot send it cross-origin
    without a CORS preflight, which this server never approves).
  * Runs with HF_HUB_OFFLINE=1 so it never phones home once the model is cached.
  * Does not log the text it speaks, only its length and timings.

Voice, speed and style live in config.json next to this file and are re-read on every request,
so you can change them without restarting.
"""
import io
import json
import os
import sys
import threading
import time
import wave

os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY", "1")

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np
from mlx_audio.tts.utils import load_model

MODEL_ID = "mlx-community/Qwen3-TTS-12Hz-0.6B-CustomVoice-8bit"
HOST, PORT = "127.0.0.1", 8789
MAX_TEXT_CHARS = 600
CONFIG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "config.json")

DEFAULT_CONFIG = {
    "voice": "ryan",          # serena, vivian, uncle_fu, ryan, aiden, ono_anna, sohee, eric, dylan
    "speed": 1.12,            # 1.0 = model's natural pace; 1.12 = a little faster, same pitch (applied by the server)
    "temperature": 0.7,       # lower = steadier, higher = more varied intonation
    "style": ("Speak like a warm, relaxed tutor chatting one-to-one. Natural conversational pace "
              "with small breaths and brief pauses between ideas, not a flat reading voice."),
}

generation_lock = threading.Lock()  # the GPU model handles one request at a time
model = None


def load_config():
    config = dict(DEFAULT_CONFIG)
    try:
        with open(CONFIG_PATH) as config_file:
            config.update(json.load(config_file))
    except FileNotFoundError:
        pass
    except Exception as error:  # a bad edit must never take the voice down
        print(f"[tts] config.json unreadable, using defaults: {error}", flush=True)
    return config


def trim_silence(audio, sample_rate, threshold=0.01, margin_seconds=0.04):
    """Remove the model's own leading/trailing silence so the app controls the gap between sentences."""
    loud_sample_indexes = np.flatnonzero(np.abs(audio) > threshold)
    if loud_sample_indexes.size == 0:
        return audio
    margin = int(margin_seconds * sample_rate)
    start = max(0, loud_sample_indexes[0] - margin)
    end = min(len(audio), loud_sample_indexes[-1] + margin)
    return audio[start:end]


def speed_up(audio, sample_rate, rate):
    """
    Pitch-preserving time stretch (WSOLA). rate 1.12 = 12% faster, same voice pitch.
    This model version ignores its own `speed` and style settings, so pace is applied here.
    """
    if rate is None or abs(rate - 1.0) < 0.01 or len(audio) < sample_rate // 2:
        return audio
    frame_length = int(0.030 * sample_rate)
    synthesis_hop = frame_length // 2
    analysis_hop = synthesis_hop * rate
    search_radius = int(0.008 * sample_rate)
    window = np.hanning(frame_length).astype(np.float32)
    padded = np.concatenate([np.zeros(search_radius, np.float32), audio,
                             np.zeros(frame_length + search_radius * 2, np.float32)])
    frame_count = int((len(audio) - frame_length) / analysis_hop) + 1
    output = np.zeros(int(frame_count * synthesis_hop + frame_length + 1), np.float32)
    weight = np.zeros_like(output)
    previous_start = search_radius
    for frame_index in range(frame_count):
        nominal_start = int(round(frame_index * analysis_hop)) + search_radius
        if frame_index == 0:
            chosen_start = nominal_start
        else:
            # Pick the nearby segment that best continues the previously chosen one (keeps waveform phase).
            reference = padded[previous_start + synthesis_hop: previous_start + synthesis_hop + frame_length]
            first_candidate = max(0, nominal_start - search_radius)
            candidates = padded[first_candidate: nominal_start + search_radius + frame_length]
            if len(candidates) < frame_length + 1 or len(reference) < frame_length:
                chosen_start = nominal_start
            else:
                correlation = np.correlate(candidates, reference, mode="valid")
                chosen_start = first_candidate + int(np.argmax(correlation))
        segment = padded[chosen_start: chosen_start + frame_length]
        if len(segment) < frame_length:
            break
        out_start = frame_index * synthesis_hop
        output[out_start: out_start + frame_length] += segment * window
        weight[out_start: out_start + frame_length] += window
        previous_start = chosen_start
    weight[weight < 1e-3] = 1.0
    stretched = output / weight
    return stretched[: int(len(audio) / rate)]


def level_audio(audio, target_rms=0.09, max_gain=4.0):
    """Consistent loudness from sentence to sentence without clipping."""
    root_mean_square = float(np.sqrt(np.mean(np.square(audio)))) if audio.size else 0.0
    peak = float(np.max(np.abs(audio))) if audio.size else 0.0
    if root_mean_square < 1e-6 or peak < 1e-6:
        return audio
    gain = min(max_gain, target_rms / root_mean_square, 0.98 / peak)
    return np.clip(audio * gain, -1.0, 1.0)


def synthesize(text):
    config = load_config()
    segments, sample_rate = [], 24000
    with generation_lock:
        for result in model.generate(
            text,
            voice=config["voice"],
            instruct=config["style"],
            lang_code="english",
            temperature=float(config["temperature"]),
            speed=float(config["speed"]),
        ):
            segments.append(np.array(result.audio, dtype=np.float32).reshape(-1))
            sample_rate = getattr(result, "sample_rate", sample_rate) or sample_rate
    audio = np.concatenate(segments) if segments else np.zeros(1, dtype=np.float32)
    audio = level_audio(speed_up(trim_silence(audio, sample_rate), sample_rate, float(config["speed"])))
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes((audio * 32767).astype(np.int16).tobytes())
    return buffer.getvalue(), len(audio) / sample_rate


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):  # silence default per-request logging (it would include the path only, but stay quiet)
        pass

    def _send(self, status, body, content_type="application/json"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _forbidden(self):
        return self.headers.get("x-thambi-client") != "1"

    def do_GET(self):
        if self.path == "/health":
            self._send(200, json.dumps({"ok": True, "model": MODEL_ID, "voice": load_config()["voice"]}).encode())
        else:
            self._send(404, b'{"error":"not found"}')

    def do_POST(self):
        if self._forbidden():
            return self._send(403, b'{"error":"forbidden"}')
        if self.path != "/speak":
            return self._send(404, b'{"error":"not found"}')
        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length) or b"{}")
            text = str(payload.get("text", "")).strip()[:MAX_TEXT_CHARS]
            if not text:
                return self._send(400, b'{"error":"empty text"}')
            started = time.time()
            wav_bytes, audio_seconds = synthesize(text)
            print(f"[tts] {len(text)} chars -> {audio_seconds:.1f}s audio in {time.time() - started:.1f}s", flush=True)
            self._send(200, wav_bytes, "audio/wav")
        except Exception as error:
            print(f"[tts] ERROR: {error}", flush=True)
            self._send(500, json.dumps({"error": str(error)}).encode())


def exit_when_parent_app_quits(parent_pid):
    """If Thambi started this server, stop as soon as Thambi is gone (even after a crash)."""
    def watch():
        while True:
            time.sleep(2)
            try:
                os.kill(parent_pid, 0)          # signal 0 = "are you still alive?"
            except OSError:
                print("[tts] Thambi has quit; stopping the voice server", flush=True)
                os._exit(0)
    threading.Thread(target=watch, daemon=True).start()


def main():
    global model
    if "--parent-pid" in sys.argv:
        exit_when_parent_app_quits(int(sys.argv[sys.argv.index("--parent-pid") + 1]))
    print(f"[tts] loading {MODEL_ID} ...", flush=True)
    started = time.time()
    model = load_model(MODEL_ID)
    print(f"[tts] loaded in {time.time() - started:.1f}s; warming up the GPU ...", flush=True)
    started = time.time()
    synthesize("hello there, this is a quick warm up.")  # first run compiles GPU kernels (slow); do it now
    print(f"[tts] warm-up done in {time.time() - started:.1f}s. Voice: {load_config()['voice']}. "
          f"Listening on http://{HOST}:{PORT}", flush=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()


if __name__ == "__main__":
    sys.exit(main())
