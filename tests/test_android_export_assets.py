"""Exercise actual template updates without downloading/building the full Core."""
from pathlib import Path
import importlib.util
import pytest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("asset_policy", ROOT / "tools/configure_android_export.py")
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)


def test_template_configuration_is_idempotent_and_preserves_existing_build(tmp_path):
    source = "plugins { id 'com.android.application' }\nandroid { namespace 'com.godot.game' }\n"
    (tmp_path / "build.gradle").write_text(source)
    policy.configure(tmp_path)
    policy.configure(tmp_path)
    content = (tmp_path / "build.gradle").read_text()
    assert content.startswith(source) and content.count(policy.MARKER) == 1
    assert (tmp_path / "aurorafox_assets.gradle").read_text() == policy.ASSET_POLICY
    assert "noCompress += ['gguf']" in policy.ASSET_POLICY


def test_wrong_template_is_rejected_without_modification(tmp_path):
    source = "plugins { id 'com.android.library' }"
    (tmp_path / "build.gradle").write_text(source)
    with pytest.raises(ValueError, match="application template"):
        policy.configure(tmp_path)
    assert (tmp_path / "build.gradle").read_text() == source
    assert not (tmp_path / "aurorafox_assets.gradle").exists()


def test_export_configures_installed_template_before_gradle_and_verifies_storage():
    source = (ROOT / "build/build_android.ps1").read_text()
    assert source.index('--install-android-build-template') < source.index('tools/configure_android_export.py') < source.index('--export-release "Android"')
    assert '$archiveVerifier $apkPath --require-stored-core' in source
