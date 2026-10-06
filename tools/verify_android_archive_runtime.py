"""Verify archive runtime definitions and Android JNI in an actual APK."""
from __future__ import annotations
import argparse
import struct
import zipfile

REQUIRED_CLASSES = {
    "Lcom/github/junrar/Archive;",
    "Lorg/apache/poi/poifs/filesystem/POIFSFileSystem;",
    "Lorg/apache/poi/hssf/record/SSTRecord;",
    "Lorg/tukaani/xz/LZMA2InputStream;",
    "Lorg/apache/commons/compress/archivers/sevenz/SevenZFile;",
    "Lcom/github/luben/zstd/ZstdInputStream;",
    "Lorg/apache/commons/compress/archivers/tar/TarArchiveInputStream;",
}
REQUIRED_ABIS = ("arm64-v8a", "x86_64")


def dex_classes(data: bytes) -> set[str]:
    if len(data) < 112 or data[:4] != b"dex\n" or data[4:8] not in (b"035\0", b"037\0", b"038\0", b"039\0", b"040\0"):
        raise ValueError("Unsupported or truncated DEX header")
    def word(offset: int) -> int:
        return struct.unpack_from("<I", data, offset)[0]
    def table(count_offset: int, width: int) -> tuple[int, int]:
        count, offset = word(count_offset), word(count_offset + 4)
        if offset + count * width > len(data):
            raise ValueError("DEX table outside file")
        return count, offset
    strings, strings_offset = table(56, 4)
    types, types_offset = table(64, 4)
    classes, classes_offset = table(96, 32)
    result = set()
    for index in range(classes):
        type_index = word(classes_offset + index * 32)
        if type_index >= types:
            raise ValueError("Invalid DEX class type")
        string_index = word(types_offset + type_index * 4)
        if string_index >= strings:
            raise ValueError("Invalid DEX descriptor index")
        offset = word(strings_offset + string_index * 4)
        for _ in range(5):
            if offset >= len(data):
                raise ValueError("Truncated DEX string")
            byte = data[offset]
            offset += 1
            if not byte & 128:
                break
        else:
            raise ValueError("Invalid DEX string length")
        end = data.find(b"\0", offset)
        if end < 0:
            raise ValueError("Unterminated DEX descriptor")
        result.add(data[offset:end].decode("utf-8", errors="replace"))
    return result


def verify_apk(path: str, require_stored_core: bool = False) -> None:
    with zipfile.ZipFile(path) as apk:
        names = set(apk.namelist())
        if require_stored_core:
            model = "assets/models/aurorafox-core.gguf"
            if model not in names or apk.getinfo(model).file_size == 0:
                raise ValueError("Missing bundled Core model asset")
            if apk.getinfo(model).compress_type != zipfile.ZIP_STORED:
                raise ValueError("Bundled Core model must be stored without asset compression")
        for abi in REQUIRED_ABIS:
            native = f"lib/{abi}/libzstd-jni-1.5.7-3.so"
            if native not in names or apk.getinfo(native).file_size == 0:
                raise ValueError(f"Missing Android archive runtime: {native}")
        definitions = set()
        for name in names:
            if name.startswith("classes") and name.endswith(".dex") and "/" not in name:
                definitions.update(dex_classes(apk.read(name)))
        missing = REQUIRED_CLASSES - definitions
        if missing:
            raise ValueError(f"Missing archive runtime class definitions: {sorted(missing)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk")
    parser.add_argument("--require-stored-core", action="store_true")
    args = parser.parse_args()
    verify_apk(args.apk, args.require_stored_core)
    print("Android archive runtime packaging: PASS")
