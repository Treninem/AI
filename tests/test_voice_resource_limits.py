"""Execute production budget consumers without loading acoustic model runtimes."""
import ast
import hashlib
import json
import logging
from pathlib import Path
import queue
import sys
import threading
from types import SimpleNamespace

import numpy as np
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from pydantic import BaseModel, Field

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'voice/python'))
from voice_resource_policy import VoiceResourceLimits
from processor import AuroraVoiceProcessor


def consumers(limits, cache):
    source = ROOT / 'voice/python/aurora_voice_server.py'
    tree = ast.parse(source.read_text())
    selected = []
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.ClassDef)) and node.name in {'SayRequest', 'PathRequest', 'cache_key', 'trim_cache', 'MicMonitor', 'health'}:
            node.decorator_list = []
            selected.append(node)
    namespace = dict(VOICE_LIMITS=limits, CACHE_DIR=cache, BaseModel=BaseModel, Field=Field, np=np, queue=queue, threading=threading, log=logging.getLogger('voice-budget'), DEVICE='budget-fixture', router=SimpleNamespace(engines={}), _stt_pipe=None, json=json, hashlib=hashlib, CONFIG={'processor': {'stft_n_fft': limits.stft_n_fft, 'stft_hop_length': limits.stft_hop_length}}, EMOTIONS={})
    exec(compile(ast.Module(body=selected, type_ignores=[]), str(source), 'exec'), namespace)
    return namespace


def test_trusted_voice_policy_defaults_independent_zero_and_invalid_values():
    assert VoiceResourceLimits.from_environment({}, {}) == VoiceResourceLimits(16000, 512 * 1024 * 1024, 128)
    for field in ['TTS_INPUT_CHARS', 'CACHE_BYTES', 'MIC_QUEUE_CHUNKS', 'PATH_CHARS']:
        policy = VoiceResourceLimits.from_environment({}, {'AURORAFOX_VOICE_' + field: '0'})
        assert getattr(policy, field.lower()) == 0
        for bad in ['-1', '1.5', 'nan', '', 'true']:
            with pytest.raises(ValueError):
                VoiceResourceLimits.from_environment({}, {'AURORAFOX_VOICE_' + field: bad})
    with pytest.raises(ValueError):
        VoiceResourceLimits.from_environment({'cache_limit_mb': -1}, {})


def test_voice_stft_settings_preserve_exact_owner_values_and_reject_invalid_structure():
    config = {'processor': {'stft_n_fft': 1024, 'stft_hop_length': 256}}
    assert VoiceResourceLimits.from_environment(config, {}).stft_n_fft == 1024
    for fft, hop in [(2, 1), (4096, 1024), (8192, 1)]:
        env = {'AURORAFOX_VOICE_STFT_N_FFT': str(fft), 'AURORAFOX_VOICE_STFT_HOP_LENGTH': str(hop)}
        policy = VoiceResourceLimits.from_environment(config, env)
        assert (policy.stft_n_fft, policy.stft_hop_length) == (fft, hop)
        assert AuroraVoiceProcessor({'stft_n_fft': fft, 'stft_hop_length': hop})._stft_sizes(128) == (fft, hop)
    for fft, hop in [(0, 1), (3, 1), (1024, 0), (1024, 513)]:
        env = {'AURORAFOX_VOICE_STFT_N_FFT': str(fft), 'AURORAFOX_VOICE_STFT_HOP_LENGTH': str(hop)}
        with pytest.raises(ValueError):
            VoiceResourceLimits.from_environment(config, env)
    with pytest.raises(ValueError):
        VoiceResourceLimits.from_environment(config, {'AURORAFOX_VOICE_STFT_N_FFT': '1.5'})


def test_voice_cache_identity_changes_with_effective_stft_profile(tmp_path):
    low = consumers(VoiceResourceLimits(16000, 0, 0, stft_n_fft=1024, stft_hop_length=256), tmp_path)
    high = consumers(VoiceResourceLimits(16000, 0, 0, stft_n_fft=4096, stft_hop_length=1024), tmp_path)
    request = SimpleNamespace(emotion='neutral', intensity=0.5, speed=None, pitch=None, mechanical_amount=None)
    assert low['cache_key'](request, 'Привет', 'silero') != high['cache_key'](request, 'Привет', 'silero')


@pytest.mark.parametrize('cap', [2, 20000, 0])
def test_actual_voice_request_validator_over_http(tmp_path, cap):
    namespace = consumers(VoiceResourceLimits(cap, 0, 0), tmp_path)
    model = namespace['SayRequest']
    app = FastAPI()

    def probe(request):
        return {'chars': len(request.text)}

    probe.__annotations__['request'] = model
    app.post('/probe')(probe)
    with TestClient(app) as client:
        exact = cap if cap else 20001
        assert client.post('/probe', json={'text': 'А' * exact}).json() == {'chars': exact}
        if cap:
            assert client.post('/probe', json={'text': 'А' * (cap + 1), 'tts_input_chars': 0}).status_code == 422
        assert client.post('/probe', json={'text': ''}).status_code == 422
        assert client.post('/probe', json={'text': 'x', 'intensity': 2}).status_code == 422


@pytest.mark.parametrize('cap', [3, 6, 0])
def test_actual_voice_cache_files_exact_raised_and_unlimited(tmp_path, cap):
    for i in range(2):
        path = tmp_path / f'{i}.wav'
        path.write_bytes(b'abc')
        path.with_suffix('.json').write_text('{}')
    namespace = consumers(VoiceResourceLimits(2, cap, 2), tmp_path)
    namespace['trim_cache']()
    assert len(list(tmp_path.glob('*.wav'))) == (1 if cap == 3 else 2)
    assert len(list(tmp_path.glob('*.json'))) == (1 if cap == 3 else 2)


@pytest.mark.parametrize('cap', [2, 129, 0])
def test_actual_microphone_queue_and_visible_overflow(tmp_path, cap):
    namespace = consumers(VoiceResourceLimits(2, 0, cap), tmp_path)
    mic = namespace['MicMonitor']()
    namespace['mic'] = mic
    for _ in range(129):
        mic._callback(np.ones((2, 1), dtype=np.float32), 2, None, None)
    expected = min(cap, 129) if cap else 129
    assert mic.q.qsize() == expected
    assert mic.dropped_chunks == 129 - expected
    status = namespace['health']()
    assert status['mic_queue_limit'] == cap
    assert status['mic_queue_chunks'] == expected
    assert status['mic_dropped_chunks'] == 129 - expected
    assert not status['stt_loaded']


@pytest.mark.parametrize('cap', [2, 8000, 0])
def test_actual_voice_path_definition_preserves_full_identity(tmp_path, cap):
    model = consumers(VoiceResourceLimits(2, 0, 0, cap), tmp_path)['PathRequest']
    value = 'x' * (cap if cap else 8001)
    assert model(path=value).path == value
    if cap:
        with pytest.raises(ValueError):
            model(path=value + 'x')
    with pytest.raises(ValueError):
        model(path='')
