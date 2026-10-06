"""Keep the bundled Core out of AGP's in-memory asset compression."""
from pathlib import Path
import argparse

MARKER = "apply from: 'aurorafox_assets.gradle'"
ASSET_POLICY = """// AuroraFox: quantized Core is already dense; store it directly in the APK.
android {
    androidResources {
        noCompress += ['gguf']
    }
}
"""


def configure(template: Path) -> None:
    build = template / "build.gradle"
    content = build.read_text(encoding="utf-8")
    if "com.android.application" not in content:
        raise ValueError("Expected the installed Godot Android application template")
    (template / "aurorafox_assets.gradle").write_text(ASSET_POLICY, encoding="utf-8")
    if MARKER not in content:
        build.write_text(content + "\n" + MARKER + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("template", type=Path)
    configure(parser.parse_args().template)
    print("Android bundled Core asset policy: configured")
