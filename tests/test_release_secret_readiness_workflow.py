from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "release.yml"


def _text() -> str:
    return WORKFLOW.read_text(encoding="utf-8")


def test_preflight_has_a_manual_secrets_only_mode() -> None:
    text = _text()
    assert "workflow_dispatch:" in text
    assert "secrets_only:" in text
    assert "type: boolean" in text
    assert "default: false" in text
    assert "secret-readiness:" in text
    assert "github.event_name == 'workflow_dispatch' && inputs.secrets_only" in text
    assert "github.event_name != 'workflow_dispatch' || !inputs.secrets_only" in text


def _job_condition(text: str, job: str) -> str:
    import re
    block = re.search(r"^  " + re.escape(job) + r":\n(.*?)(?=^  [\w-]+:|\Z)", text, re.M | re.S)
    assert block, job
    lines = block.group(1).splitlines()
    for index, line in enumerate(lines):
        if line.startswith("    if: "):
            condition = line.removeprefix("    if: ")
            if condition != "|":
                return condition
            continuation = []
            for following in lines[index + 1:]:
                if not following.startswith("      "):
                    break
                continuation.append(following.strip())
            return " ".join(continuation)
    raise AssertionError("Missing job condition: " + job)


def _evaluate(condition: str, values: dict) -> bool:
    # Evaluate only the boolean/comparison subset used by these guards.
    # Unknown syntax fails the test rather than executing Python or workflow code.
    import ast
    import re
    replacements = dict(values, **{
        "always()": True,
        "startsWith(github.ref, 'refs/tags/v')": values["tag"],
    })
    for key in sorted(replacements, key=len, reverse=True):
        condition = condition.replace(key, repr(replacements[key]))
    condition = condition.replace("&&", " and ").replace("||", " or ")
    condition = re.sub(r"!(?!=)", " not ", condition)

    def visit(node):
        if isinstance(node, ast.Constant):
            return node.value
        if isinstance(node, ast.BoolOp):
            args = [bool(visit(value)) for value in node.values]
            if isinstance(node.op, ast.And):
                return all(args)
            if isinstance(node.op, ast.Or):
                return any(args)
        if isinstance(node, ast.UnaryOp) and isinstance(node.op, ast.Not):
            return not visit(node.operand)
        if isinstance(node, ast.Compare) and len(node.ops) == 1:
            left, right = visit(node.left), visit(node.comparators[0])
            if isinstance(node.ops[0], ast.Eq):
                return left == right
            if isinstance(node.ops[0], ast.NotEq):
                return left != right
        raise AssertionError("Unsupported guard syntax: " + ast.dump(node))

    return bool(visit(ast.parse(condition.strip(), mode="eval").body))


def test_secrets_only_mode_cannot_reach_build_or_publish_jobs() -> None:
    from itertools import product
    text = _text()
    core = _job_condition(text, "core-gates")
    publish = _job_condition(text, "publish")
    for event, secrets_only, recovery, tag, windows, android in product(
        ("workflow_dispatch", "push"), (False, True), ("", "123"),
        (False, True), ("success", "failure", "skipped"),
        ("success", "failure", "skipped"),
    ):
        values = {
            "github.event_name": event, "inputs.secrets_only": secrets_only,
            "inputs.publish_run_id": recovery, "tag": tag,
            "needs.windows.result": windows, "needs.android.result": android,
        }
        preflight = event == "workflow_dispatch" and secrets_only
        expected_core = not preflight and (event != "workflow_dispatch" or recovery == "")
        expected_publish = not preflight and (
            (tag and windows == "success" and android == "success")
            or (event == "workflow_dispatch" and recovery != "")
        )
        assert _evaluate(core, values) == expected_core, values
        assert _evaluate(publish, values) == expected_publish, values
    for job in ("windows", "android"):
        block = text.split("  " + job + ":", 1)[1].split("    steps:", 1)[0]
        assert "needs: core-gates" in block
        assert "    if:" not in block  # Preserve default dependency-success gating.


def test_release_identity_ci_executes_the_preflight_guard_regression() -> None:
    ci = (ROOT / ".github/workflows/release-identity-ci.yml").read_text(encoding="utf-8")
    path = "tests/test_release_secret_readiness_workflow.py"
    assert ci.count("      - '" + path + "'") == 2  # Push and PR filters.
    assert any("python -m pytest" in line and path in line for line in ci.splitlines())


def test_all_release_secrets_are_required_without_printing_values() -> None:
    text = _text()
    for name in (
        "AURORA_UPDATE_SIGNING_PRIVATE_KEY_BASE64",
        "AURORA_ANDROID_KEYSTORE_BASE64",
        "AURORA_ANDROID_KEYSTORE_USER",
        "AURORA_ANDROID_KEYSTORE_PASSWORD",
    ):
        assert f"secrets.{name}" in text
        assert f"missing+=({name})" in text
    assert "Missing required secret: %s" in text
    assert '"${missing[@]}"' in text
    assert "set -x" not in text
    assert '::add-mask::$KEYSTORE_USER' in text
    assert '::add-mask::$KEYSTORE_PASSWORD' in text


def test_private_keys_must_match_the_pinned_release_identity() -> None:
    text = _text()
    assert "update/release_identity.json" in text
    assert "openssl pkey" in text
    assert "update_signing_public_key_sha256" in text
    assert "keytool -list" in text
    assert "keytool -exportcert" in text
    assert "android_signing_cert_sha256" in text
    assert "AURORAFOX_RELEASE_SIGNING_SECRETS_READY" in text
