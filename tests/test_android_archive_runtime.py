"""Reject reference-only dependencies and missing per-ABI native payloads."""
import importlib.util
import struct
import tempfile
import zipfile
from pathlib import Path
import pytest

spec = importlib.util.spec_from_file_location("archive_verifier", Path(__file__).resolve().parents[1] / "tools/verify_android_archive_runtime.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def dex(defined=True):
    descriptors = sorted(module.REQUIRED_CLASSES)
    data = bytearray(112 + 8 + 8 + (64 if defined else 0))
    data[:8] = b"dex\n035\0"
    struct.pack_into("<II", data, 56, 2, 112)
    struct.pack_into("<II", data, 64, 2, 120)
    struct.pack_into("<II", data, 96, 2 if defined else 0, 128)
    for index, descriptor in enumerate(descriptors):
        struct.pack_into("<I", data, 112 + index * 4, len(data))
        struct.pack_into("<I", data, 120 + index * 4, index)
        if defined:
            struct.pack_into("<I", data, 128 + index * 32, index)
        data.extend(bytes([len(descriptor)]) + descriptor.encode() + b"\0")
    return bytes(data)


def apk(path, defined=True, abis=module.REQUIRED_ABIS):
    with zipfile.ZipFile(path, "w") as output:
        output.writestr("classes.dex", dex(defined))
        for abi in abis:
            output.writestr(f"lib/{abi}/libzstd-jni-1.5.7-3.so", b"native fixture")


def test_complete_package():
    with tempfile.TemporaryDirectory() as directory:
        path = str(Path(directory) / "complete.apk")
        apk(path)
        module.verify_apk(path)


def test_references_are_not_definitions():
    with tempfile.TemporaryDirectory() as directory:
        path = str(Path(directory) / "reference-only.apk")
        apk(path, defined=False)
        with pytest.raises(ValueError, match="class definitions"):
            module.verify_apk(path)


def test_missing_native_abi():
    with tempfile.TemporaryDirectory() as directory:
        path = str(Path(directory) / "missing.apk")
        apk(path, abis=("arm64-v8a",))
        with pytest.raises(ValueError, match="x86_64"):
            module.verify_apk(path)


def test_truncated_dex_rejected():
    with pytest.raises(ValueError, match="truncated"):
        module.dex_classes(b"dex\n035\0")
