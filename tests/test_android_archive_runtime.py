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
    count = len(descriptors)
    types_offset = 112 + count*4
    classes_offset = types_offset + count*4
    data = bytearray(classes_offset + (count*32 if defined else 0))
    data[:8] = b"dex\n035\0"
    struct.pack_into("<II", data, 56, count, 112)
    struct.pack_into("<II", data, 64, count, types_offset)
    struct.pack_into("<II", data, 96, count if defined else 0, classes_offset)
    for index, descriptor in enumerate(descriptors):
        struct.pack_into("<I", data, 112 + index * 4, len(data))
        struct.pack_into("<I", data, types_offset + index * 4, index)
        if defined:
            struct.pack_into("<I", data, classes_offset + index * 32, index)
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


@pytest.mark.parametrize("compression", [zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED])
def test_real_apk_core_storage_gate(tmp_path, compression):
    path = tmp_path / "core.apk"
    apk(path)
    with zipfile.ZipFile(path, "a") as output:
        output.writestr("assets/models/aurorafox-core.gguf", b"GGUF real zip fixture", compress_type=compression)
    if compression == zipfile.ZIP_STORED:
        module.verify_apk(path, require_stored_core=True)
    else:
        with pytest.raises(ValueError, match="without asset compression"):
            module.verify_apk(path, require_stored_core=True)

def test_missing_core_asset_is_rejected(tmp_path):
    path = tmp_path / "missing-core.apk"
    apk(path)
    with pytest.raises(ValueError, match="Missing bundled Core"):
        module.verify_apk(path, require_stored_core=True)
