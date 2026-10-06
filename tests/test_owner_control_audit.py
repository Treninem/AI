import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("owner_control_audit", ROOT / "tools" / "owner_control_audit.py")
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def test_audit_is_machine_readable_and_does_not_claim_incomplete_inventory_is_done():
    report = MODULE.audit()
    assert report["schema"] == "aurorafox.owner-control-audit.v1"
    assert report["files_scanned"] > 100
    assert report["findings"] > 0
    assert report["complete"] is (report["counts"].get("unclassified", 0) == 0)


def test_web_limits_and_security_boundaries_have_explicit_different_classes():
    report = MODULE.audit()
    web = [item for item in report["items"] if item["path"] == "scripts/public_web_manager.gd"]
    assert any(item["class"] == "owner_adjustable" for item in web)
    assert any(item["class"] == "hard_boundary" for item in web)


def test_policy_explains_the_small_set_allowed_to_be_hard_boundaries():
    policy = MODULE.load_policy()
    principle = policy["principle"].lower()
    for required in ["authorization", "access control", "cryptographic", "master-stop", "secret", "untrusted-code"]:
        assert required in principle


def test_fixture_classification_does_not_hide_product_limits():
    policy = MODULE.load_policy()
    assert MODULE.classify("tests/example.gd", "var limit = 2", policy)[0] == "test_evidence"
    assert MODULE.classify("scripts/example.gd", "var limit = 2", policy)[0] == "unclassified"
    assert MODULE.classify("file_intelligence/file_service.py", 'MAX_FILE_BYTES = int(os.getenv("AURORAFOX_FILE_MAX_BYTES", "1024"))', policy)[0] == "owner_adjustable"


def test_reviewed_named_budgets_do_not_hide_remaining_literal_limits():
    policy = MODULE.load_policy()
    assert MODULE.classify("file_intelligence/file_service.py", "if size > MAX_FILE_BYTES:", policy)[0] == "owner_adjustable"
    assert MODULE.classify("file_intelligence/file_service.py", "for r in range(min(sheet.nrows, 10000)):", policy)[0] == "unclassified"
    assert MODULE.classify("security_workspace/runner.py", 'timeout = float(scope.get("timeout_seconds", 10))', policy)[0] == "owner_adjustable"
    assert MODULE.classify("scripts/public_web_manager.gd", 'if bytes.slice(0, 5) == signature:', policy)[0] == "format_structure"
    assert MODULE.classify("scripts/example.gd", '# LIMIT describes a control', policy)[0] == "documentation"
    assert MODULE.classify("scripts/example.gd", 'var LIMIT = 123 # explanatory comment', policy)[0] == "unclassified"


def test_native_reader_budgets_are_reviewed_without_hiding_arbitrary_literals():
    policy = MODULE.load_policy()
    base = "android_plugin/plugin/src/main/java/com/aurorafox/runtime/"
    for reader in ["ArchiveTextReader.kt", "EpubTextReader.kt", "TarTextReader.kt"]:
        assert MODULE.classify(base+reader, "val cap = limits.memberBytes", policy)[0] == "owner_adjustable"
        assert MODULE.classify(base+reader, "val x = Long.MAX_VALUE", policy)[0] == "format_structure"
        assert MODULE.classify(base+reader, "val LIMIT = 17", policy)[0] == "unclassified"
    assert MODULE.classify("android_plugin/plugin/src/test/java/Fixture.kt", "val limit = 2", policy)[0] == "test_evidence"
    assert MODULE.classify(base+"Unreviewed.kt", "val limit = 2", policy)[0] == "unclassified"


def test_native_limit_propagation_preserves_security_and_unknown_literals():
    policy = MODULE.load_policy()
    base = "android_plugin/plugin/src/main/java/com/aurorafox/runtime/"
    for name in ["AndroidFileRuntime.kt", "AndroidOcrRuntime.kt", "GodotAndroidPlugin.kt"]:
        assert MODULE.classify(base+name, "analyze(file, limits)", policy)[0] == "owner_adjustable"
        assert MODULE.classify(base+name, "val LIMIT = 17", policy)[0] == "unclassified"
        assert MODULE.classify(base+name, "val timeout = 99", policy)[0] == "unclassified"
    assert MODULE.classify(base+"AndroidFileRuntime.kt", "files.tree(path, maxItems)", policy)[0] == "owner_adjustable"
    assert MODULE.classify(base+"FileAnalysisLimits.kt", "val x = Int.MAX_VALUE", policy)[0] == "format_structure"
    assert MODULE.classify(base+"FileAnalysisLimits.kt", "require(limit >= 0)", policy)[0] == "owner_adjustable"
    assert MODULE.classify(base+"Example.kt", "/** budget documentation */", policy)[0] == "documentation"
    assert MODULE.classify(base+"Example.kt", "/** comment */ val LIMIT = 17", policy)[0] == "unclassified"
    assert MODULE.classify("scripts/public_web_manager.gd", "private_network_denied", policy)[0] == "hard_boundary"
    assert MODULE.classify("evolution_engine/tests/fixture.gd", "var limit = 2", policy)[0] == "test_evidence"
    assert MODULE.classify("evolution_engine/core/runtime.gd", "var limit = 2", policy)[0] == "unclassified"
