from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Owner-approved immutable source masters landed in c41a9996692d4588592ecf5735e2c72a10ceb9f2.
# Pin Git blob identity so a byte-level replacement cannot silently pass as the same branding.
EXPECTED_MASTER_BLOBS = {
    "assets/ui/aurorafox_avatar_master.png": "89ff783b171733f88b5153acd24c6a28fb2953dd",
    "assets/ui/aurorafox_background_master.png": "ed17e933244b7ce0f520b28897c0ca1ad50a5347",
}


def _git_blob_sha(path: Path) -> str:
    payload = path.read_bytes()
    header = f"blob {len(payload)}\0".encode("ascii")
    return hashlib.sha1(header + payload).hexdigest()


def test_owner_approved_branding_masters_are_byte_exact() -> None:
    for relative, expected in EXPECTED_MASTER_BLOBS.items():
        path = ROOT / relative
        assert path.is_file(), f"missing owner-approved branding master: {relative}"
        assert _git_blob_sha(path) == expected, f"branding master changed byte-for-byte: {relative}"


def test_active_runtime_compat_layer_uses_owner_approved_branding() -> None:
    scene = (ROOT / "main.tscn").read_text(encoding="utf-8")
    compat = (ROOT / "scripts/main_compat.gd").read_text(encoding="utf-8")

    # main.tscn is the product entrypoint and intentionally attaches main_compat.gd.
    # The base main.gd may still construct legacy placeholder textures first; the
    # active compatibility layer must replace them before the final UI is shown.
    assert 'res://scripts/main_compat.gd' in scene
    assert 'preload("res://assets/ui/aurorafox_avatar_master.png")' in compat
    assert 'preload("res://assets/ui/aurorafox_background_master.png")' in compat
    assert "func _build_ui()" in compat
    assert "super._build_ui()" in compat
    assert "_apply_owner_background()" in compat
    assert "_apply_owner_brand_art()" in compat
    assert "owner.texture = OWNER_AVATAR_MASTER" in compat
    assert "rect.texture = _owner_background_texture()" in compat
    assert "cropped.atlas = OWNER_BACKGROUND_MASTER" in compat

    # Legacy source assets may appear only as selectors used to find and remove
    # base placeholders. They must not be assigned as final owner artwork here.
    assert "image.queue_free()" in compat
    assert 'owner.texture = preload("res://assets/ui/fox_logo.svg")' not in compat
    assert 'rect.texture = preload("res://assets/ui/aurora_background.svg")' not in compat


def test_owner_art_runtime_smoke_locks_final_tree_when_lane_has_landed() -> None:
    smoke_path = ROOT / "tests/ui_owner_assets_smoke.gd"
    if not smoke_path.is_file():
        # UI lane has not landed yet; the active-runtime contract above remains
        # the release blocker and deliberately fails until main_compat is wired.
        return
    smoke = smoke_path.read_text(encoding="utf-8")
    assert 'res://assets/ui/aurorafox_avatar_master.png' in smoke
    assert 'res://assets/ui/aurorafox_background_master.png' in smoke
    assert 'Legacy placeholder fox is visible together with owner artwork' in smoke
    assert 'Owner background must render with neutral modulate' in smoke


def test_integration_gate_executes_branding_identity_contract() -> None:
    workflow = (ROOT / ".github/workflows/integration-gate.yml").read_text(encoding="utf-8")
    assert "Owner-approved branding identity contract" in workflow
    assert "tests/test_release_branding_contract.py" in workflow
