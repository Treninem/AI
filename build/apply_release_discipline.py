from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8", newline="\n")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def patch_update_manager() -> None:
    path = "update/update_manager.gd"
    text = read(path)
    marker = 'releases/download/aurorafox-stable/update.json'
    if marker in text:
        return

    text = replace_once(
        text,
        'const MANIFEST_URL := "https://github.com/Treninem/AI/releases/latest/download/update.json"\n'
        'const MANIFEST_SIG_URL := "https://github.com/Treninem/AI/releases/latest/download/update.sig"\n'
        'const RELEASE_PAGE_URL := "https://github.com/Treninem/AI/releases/latest"',
        'const MANIFEST_URL := "https://github.com/Treninem/AI/releases/download/aurorafox-stable/update.json"\n'
        'const MANIFEST_SIG_URL := "https://github.com/Treninem/AI/releases/download/aurorafox-stable/update.sig"\n'
        'const LEGACY_MANIFEST_URL := "https://github.com/Treninem/AI/releases/latest/download/update.json"\n'
        'const LEGACY_MANIFEST_SIG_URL := "https://github.com/Treninem/AI/releases/latest/download/update.sig"\n'
        'const RELEASE_PAGE_URL := "https://github.com/Treninem/AI/releases"',
        "updater channel constants",
    )

    old_fetch = '''\tvar req := HTTPRequest.new()\n\treq.timeout = 25.0\n\tadd_child(req)\n\tvar headers := PackedStringArray(["Accept: application/json", "User-Agent: AuroraFox-Updater/%s" % current_version])\n\tvar err := req.request(MANIFEST_URL, headers, HTTPClient.METHOD_GET)\n\tif err != OK:\n\t\tchecking = false\n\t\treq.queue_free()\n\t\treturn _fail("Не удалось запустить проверку обновлений: %s" % error_string(err), manual)\n\tvar result: Array = await req.request_completed\n\treq.queue_free()\n\tsettings["last_check_unix"] = Time.get_unix_time_from_system()\n\t_save_settings()\n\tvar code := int(result[1])\n\tif code == 404:\n\t\tchecking = false\n\t\t_log("no published update manifest yet")\n\t\tif manual: no_update.emit(current_version)\n\t\treturn {"ok": true, "available": false, "version": current_version}\n\tif code < 200 or code >= 300:\n\t\tchecking = false\n\t\treturn _fail("Сервер обновлений ответил кодом %d" % code, manual)\n\n\tvar manifest_bytes: PackedByteArray = result[3]\n'''
    new_fetch = '''\tvar manifest_result := await _fetch_manifest_with_legacy_fallback()\n\tsettings["last_check_unix"] = Time.get_unix_time_from_system()\n\t_save_settings()\n\tvar code := int(manifest_result.get("code", 0))\n\tif not bool(manifest_result.get("ok", false)):\n\t\tchecking = false\n\t\tif code == 404:\n\t\t\t_log("no published update manifest on stable or legacy channel")\n\t\t\tif manual: no_update.emit(current_version)\n\t\t\treturn {"ok": true, "available": false, "version": current_version}\n\t\treturn _fail(str(manifest_result.get("error", "Сервер обновлений недоступен")), manual)\n\n\tvar manifest_bytes: PackedByteArray = manifest_result.get("body", PackedByteArray())\n\tvar signature_url := str(manifest_result.get("signature_url", MANIFEST_SIG_URL))\n\t_log("update manifest source=%s url=%s" % [str(manifest_result.get("source", "stable_channel")), str(manifest_result.get("url", MANIFEST_URL))])\n'''
    text = replace_once(text, old_fetch, new_fetch, "updater manifest fetch")
    text = replace_once(
        text,
        'var signature_result := await _fetch_manifest_signature()',
        'var signature_result := await _fetch_manifest_signature(signature_url)',
        "updater signature source",
    )

    old_sig = '''func _fetch_manifest_signature() -> Dictionary:\n\tif not FileAccess.file_exists(PUBLIC_KEY_PATH):\n\t\treturn {"ok": false, "error": "В этой сборке отсутствует публичный ключ обновлений AuroraFox"}\n\tvar req := HTTPRequest.new()\n\treq.timeout = 25.0\n\tadd_child(req)\n\tvar headers := PackedStringArray(["Accept: application/octet-stream", "User-Agent: AuroraFox-Updater/%s" % current_version])\n\tvar err := req.request(MANIFEST_SIG_URL, headers, HTTPClient.METHOD_GET)\n\tif err != OK:\n\t\treq.queue_free()\n\t\treturn {"ok": false, "error": "Не удалось запросить подпись update.sig: %s" % error_string(err)}\n\tvar result: Array = await req.request_completed\n\treq.queue_free()\n\tvar code := int(result[1])\n\tif code < 200 or code >= 300:\n\t\treturn {"ok": false, "error": "Подпись update.sig недоступна: HTTP %d" % code}\n\tvar signature: PackedByteArray = result[3]\n\tif signature.size() < 128:\n\t\treturn {"ok": false, "error": "Файл update.sig слишком короткий"}\n\treturn {"ok": true, "signature": signature}\n'''
    new_sig = '''func _fetch_manifest_with_legacy_fallback() -> Dictionary:\n\tvar primary := await _fetch_update_bytes(MANIFEST_URL, "application/json")\n\tprimary["signature_url"] = MANIFEST_SIG_URL\n\tprimary["source"] = "stable_channel"\n\tif bool(primary.get("ok", false)):\n\t\treturn primary\n\t_log("stable update channel unavailable; trying legacy latest bridge code=%d" % int(primary.get("code", 0)))\n\tvar legacy := await _fetch_update_bytes(LEGACY_MANIFEST_URL, "application/json")\n\tlegacy["signature_url"] = LEGACY_MANIFEST_SIG_URL\n\tlegacy["source"] = "legacy_latest"\n\treturn legacy\n\nfunc _fetch_update_bytes(url: String, accept: String) -> Dictionary:\n\tvar req := HTTPRequest.new()\n\treq.timeout = 25.0\n\tadd_child(req)\n\tvar headers := PackedStringArray(["Accept: " + accept, "User-Agent: AuroraFox-Updater/%s" % current_version])\n\tvar err := req.request(url, headers, HTTPClient.METHOD_GET)\n\tif err != OK:\n\t\treq.queue_free()\n\t\treturn {"ok": false, "code": 0, "url": url, "error": "Не удалось запросить канал обновлений: %s" % error_string(err)}\n\tvar result: Array = await req.request_completed\n\treq.queue_free()\n\tvar code := int(result[1])\n\tif code < 200 or code >= 300:\n\t\treturn {"ok": false, "code": code, "url": url, "body": result[3], "error": "Сервер обновлений ответил кодом %d" % code}\n\treturn {"ok": true, "code": code, "url": url, "body": result[3]}\n\nfunc _fetch_manifest_signature(signature_url: String) -> Dictionary:\n\tif not FileAccess.file_exists(PUBLIC_KEY_PATH):\n\t\treturn {"ok": false, "error": "В этой сборке отсутствует публичный ключ обновлений AuroraFox"}\n\tvar fetched := await _fetch_update_bytes(signature_url, "application/octet-stream")\n\tif not bool(fetched.get("ok", false)):\n\t\treturn {"ok": false, "error": "Подпись update.sig недоступна: %s" % str(fetched.get("error", "unknown error"))}\n\tvar signature: PackedByteArray = fetched.get("body", PackedByteArray())\n\tif signature.size() < 128:\n\t\treturn {"ok": false, "error": "Файл update.sig слишком короткий"}\n\treturn {"ok": true, "signature": signature, "url": signature_url}\n'''
    text = replace_once(text, old_sig, new_sig, "updater signature helper")
    write(path, text)


def patch_update_smoke() -> None:
    path = "tests/update_smoke.gd"
    text = read(path)
    if "aurorafox-stable/update.json" in text:
        return
    anchor = '''\tvar source := FileAccess.get_file_as_string("res://update/update_manager.gd")\n'''
    regression = '''\tif updater._compare_versions("1.3.1.0", "1.3.0.0") != 1:\n\t\tpush_error("Four-part PATCH update is not visible from V1.3.0.0")\n\t\tquit(34)\n\t\treturn\n\tif updater._compare_versions("1.3.0.1", "1.3.0.0") != 1:\n\t\tpush_error("Four-part REVISION update is not visible from V1.3.0.0")\n\t\tquit(35)\n\t\treturn\n\tif updater._compare_versions("1.3.1.0", "1.2.0.0") != 1:\n\t\tpush_error("V1.2.0.0 cannot discover a newer four-part version")\n\t\tquit(36)\n\t\treturn\n\n\tvar source := FileAccess.get_file_as_string("res://update/update_manager.gd")\n'''
    text = replace_once(text, anchor, regression, "four-part version regression tests")

    old_urls = '''\tif not source.contains('const MANIFEST_URL := "https://github.com/Treninem/AI/releases/latest/download/update.json"'):\n\t\tpush_error("Permanent update manifest URL changed")\n\t\tquit(22)\n\t\treturn\n\tif not source.contains('const MANIFEST_SIG_URL := "https://github.com/Treninem/AI/releases/latest/download/update.sig"'):\n\t\tpush_error("Signed manifest sidecar URL changed")\n\t\tquit(23)\n\t\treturn\n'''
    new_urls = '''\tif not source.contains('const MANIFEST_URL := "https://github.com/Treninem/AI/releases/download/aurorafox-stable/update.json"'):\n\t\tpush_error("Stable update manifest is not pinned to the permanent channel release")\n\t\tquit(22)\n\t\treturn\n\tif not source.contains('const MANIFEST_SIG_URL := "https://github.com/Treninem/AI/releases/download/aurorafox-stable/update.sig"'):\n\t\tpush_error("Stable signed manifest sidecar is not pinned")\n\t\tquit(23)\n\t\treturn\n\tif not source.contains('const LEGACY_MANIFEST_URL := "https://github.com/Treninem/AI/releases/latest/download/update.json"'):\n\t\tpush_error("Legacy releases/latest bridge was removed")\n\t\tquit(37)\n\t\treturn\n\tif not source.contains("_fetch_manifest_with_legacy_fallback"):\n\t\tpush_error("Stable channel does not fall back to the legacy latest bridge")\n\t\tquit(38)\n\t\treturn\n'''
    text = replace_once(text, old_urls, new_urls, "updater URL smoke contract")
    write(path, text)


def patch_set_version() -> None:
    path = "build/set_version.ps1"
    text = read(path)
    if "AURORA_VERIFIED_HEAD" in text:
        return
    text = replace_once(
        text,
        "    [ValidateSet('major','minor','patch','build')][string]$Bump = '',\n    [string]$Reason = 'AuroraFox evolution update'",
        "    [ValidateSet('major','minor','patch','revision','build')][string]$Bump = '',\n    [string]$Reason = 'AuroraFox evolution update',\n    [string]$VerifiedHead = $env:AURORA_VERIFIED_HEAD",
        "version parameters",
    )
    text = replace_once(
        text,
        "    throw 'Specify either -Version V<Major>.<Minor>.<Patch>.<Build> or -Bump major|minor|patch|build.'",
        "    throw 'Specify either -Version V<Major>.<Minor>.<Patch>.<Revision> or -Bump major|minor|patch|revision|build.'",
        "version usage",
    )
    anchor = "$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path\n"
    verified = '''$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path\n$gitHead = (& git -C $root rev-parse HEAD 2>$null).Trim()\nif ([string]::IsNullOrWhiteSpace($gitHead)) { throw 'Cannot resolve git HEAD for version verification.' }\nif ([string]::IsNullOrWhiteSpace($VerifiedHead) -or $VerifiedHead.Trim() -ne $gitHead) {\n    throw "Version bump blocked: tests must pass first for exact HEAD $gitHead. Set -VerifiedHead $gitHead (or AURORA_VERIFIED_HEAD) only after verification."\n}\n'''
    text = replace_once(text, anchor, verified, "verified HEAD gate")
    text = replace_once(
        text,
        "        'patch' { $patch++; $build++ }\n        'build' { $build++ }",
        "        'patch' { $patch++; $build = 0 }\n        'revision' { $build++ }\n        'build' { $build++ }",
        "four-part bump semantics",
    )
    text = replace_once(text, "$state.status = 'evolving'", "$state.status = 'verified'", "verified status")
    state_anchor = "$state.reason = $Reason\n"
    state_new = "$state.reason = $Reason\n$state | Add-Member -NotePropertyName verified_head -NotePropertyValue $gitHead -Force\n$state | Add-Member -NotePropertyName verification_policy -NotePropertyValue 'tests-before-version-bump' -Force\n"
    text = replace_once(text, state_anchor, state_new, "version verification metadata")
    write(path, text)


def patch_release_workflow() -> None:
    path = ".github/workflows/release.yml"
    text = read(path)
    if "aurorafox-stable" in text:
        return
    final = '''      - name: Publish verified GitHub Release\n        env:\n          GH_TOKEN: ${{ github.token }}\n        shell: bash\n        run: |\n          set -euo pipefail\n          gh release edit "$GITHUB_REF_NAME" --draft=false\n'''
    expanded = final + '''\n      - name: Refresh permanent stable update channel and legacy latest bridge\n        env:\n          GH_TOKEN: ${{ github.token }}\n        shell: bash\n        run: |\n          set -euo pipefail\n          version="${GITHUB_REF_NAME#v}"\n          stable_tag='aurorafox-stable'\n          notes="AuroraFox stable update channel. Current verified version: ${version}. This release intentionally carries only signed channel metadata; platform packages remain on immutable v${version}."\n          if gh release view "$stable_tag" >/dev/null 2>&1; then\n            gh release upload "$stable_tag" dist/update.json dist/update.sig dist/release_verification.json --clobber\n            gh release edit "$stable_tag" --title 'AuroraFox Stable Update Channel' --notes "$notes" --latest\n          else\n            gh release create "$stable_tag" dist/update.json dist/update.sig dist/release_verification.json \\\n              --target main \\\n              --title 'AuroraFox Stable Update Channel' \\\n              --notes "$notes" \\\n              --latest\n          fi\n          echo "Stable channel refreshed for ${version}; releases/latest now remains a manifest-compatible legacy bridge."\n'''
    text = replace_once(text, final, expanded, "stable release channel publish")
    text = replace_once(
        text,
        "            tests/test_core_candidate_promotion.py\n",
        "            tests/test_core_candidate_promotion.py \\\n            tests/test_release_channel_contract.py\n",
        "release contract gate",
    )
    write(path, text)


def patch_voice_ci() -> None:
    path = ".github/workflows/voice-ci.yml"
    text = read(path)
    if "tests/test_release_channel_contract.py" in text:
        return
    text = replace_once(
        text,
        "          tests/test_project_master_contract.py\n          tests/test_standalone_core_contract.py",
        "          tests/test_project_master_contract.py\n          tests/test_standalone_core_contract.py\n          tests/test_release_channel_contract.py",
        "core CI release discipline gate",
    )
    write(path, text)


def patch_master_log() -> None:
    path = "docs/PROJECT_MASTER_LOG.md"
    text = read(path)
    if "### 1.3. ОБЯЗАТЕЛЬНАЯ ДИСЦИПЛИНА ВЕРСИЙ" in text:
        return
    section = '''### 1.3. ОБЯЗАТЕЛЬНАЯ ДИСЦИПЛИНА ВЕРСИЙ И РЕЛИЗОВ\n\nВерсия AuroraFox имеет **ровно четыре числовых компонента**: `MAJOR.MINOR.PATCH.REVISION`. Версия меняется не по факту начала работы, а **только после того, как законченный блок изменений прошёл относящиеся к нему тесты и проверки на точном HEAD**. Непроверенные/незаконченные изменения не получают новый номер и не публикуются как релиз.\n\nОбязательная классификация:\n\n- `MAJOR` (`2.0.0.0`) — несовместимая архитектурная ступень, смена поколения Core/форматов/контрактов, требующая явной миграции;\n- `MINOR` (`1.4.0.0`) — крупная новая возможность или законченный большой блок без обязательной несовместимости;\n- `PATCH` (`1.3.1.0`) — заметное совместимое улучшение существующего блока: интерфейс, голос, updater, память, Core, Knowledge, Computer Agent и т. п.;\n- `REVISION` (`1.3.0.1`) — небольшой проверенный фикс/полировка без нового крупного поведения.\n\nПравило для всех Chat/Work/Codex/агентов: после завершения блока сначала тесты/CI, затем version bump соответствующего уровня, синхронизация `project/version.json`, `project.godot`, Android `version/name` + монотонного `version/code`, `update/manifest.template.json`, `CHANGELOG.md` и `evolution.log`. `build/set_version.ps1` обязан отклонять bump, если ему не передан exact verified HEAD. После version bump release pipeline повторно выполняет blocking release gates; публикация разрешена только при зелёных gates.\n\nСтабильный updater использует постоянный подписанный канал `aurorafox-stable`; `releases/latest` сохраняется только как совместимый legacy bridge для уже установленных старых сборок. Вспомогательные repair/debug releases не имеют права ломать stable update discovery.\n\n'''
    text = replace_once(text, "## 2. Текущий baseline\n", section + "## 2. Текущий baseline\n", "master version policy")
    write(path, text)


def create_policy_doc() -> None:
    write(
        "docs/VERSIONING_POLICY.md",
        """# AuroraFox Versioning Policy\n\nCanonical version format: `MAJOR.MINOR.PATCH.REVISION` (four numeric components).\n\n- `MAJOR`: incompatible architecture/generation migration.\n- `MINOR`: large completed feature/subsystem.\n- `PATCH`: compatible subsystem improvement such as UI, voice, updater, Core, memory or Knowledge.\n- `REVISION`: small verified correction/polish. `build` is accepted as a legacy alias for `revision`.\n\n## Non-negotiable release order\n\n1. Finish one coherent change block.\n2. Run relevant tests/CI on the exact Git HEAD.\n3. Only after those checks pass, call `build/set_version.ps1` with the exact verified HEAD.\n4. Commit synchronized version metadata.\n5. Create `v<version>` tag and run the blocking release workflow.\n6. Publish only if release gates pass.\n7. Refresh the signed `aurorafox-stable` manifest pointer.\n\nA version number is evidence of a tested state, not a progress counter. Failed or incomplete work must not consume a release version.\n\n## Compatibility\n\nModern builds read the signed manifest from `releases/download/aurorafox-stable/update.json`. The release workflow also marks that channel release as GitHub Latest, so historical builds that still request `releases/latest/download/update.json` continue to discover updates. Manifest assets always point to immutable versioned releases.\n""",
    )


def create_release_contract_test() -> None:
    write(
        "tests/test_release_channel_contract.py",
        '''from pathlib import Path\n\nROOT = Path(__file__).resolve().parents[1]\n\n\ndef test_permanent_stable_channel_and_legacy_bridge():\n    updater = (ROOT / "update/update_manager.gd").read_text(encoding="utf-8")\n    assert "releases/download/aurorafox-stable/update.json" in updater\n    assert "releases/download/aurorafox-stable/update.sig" in updater\n    assert "releases/latest/download/update.json" in updater\n    assert "_fetch_manifest_with_legacy_fallback" in updater\n\n\ndef test_release_refreshes_stable_channel_and_latest_bridge():\n    workflow = (ROOT / ".github/workflows/release.yml").read_text(encoding="utf-8")\n    assert "aurorafox-stable" in workflow\n    assert "dist/update.json" in workflow\n    assert "dist/update.sig" in workflow\n    assert "--latest" in workflow\n\n\ndef test_version_bump_requires_verified_exact_head_and_has_four_levels():\n    script = (ROOT / "build/set_version.ps1").read_text(encoding="utf-8")\n    assert "AURORA_VERIFIED_HEAD" in script\n    assert "Version bump blocked: tests must pass first for exact HEAD" in script\n    assert "'patch' { $patch++; $build = 0 }" in script\n    assert "'revision' { $build++ }" in script\n    assert "'minor' { $minor++; $patch = 0; $build = 0 }" in script\n    assert "'major' { $major++; $minor = 0; $patch = 0; $build = 0 }" in script\n\n\ndef test_master_log_contains_non_negotiable_version_policy():\n    log = (ROOT / "docs/PROJECT_MASTER_LOG.md").read_text(encoding="utf-8")\n    assert "ОБЯЗАТЕЛЬНАЯ ДИСЦИПЛИНА ВЕРСИЙ" in log\n    assert "MAJOR.MINOR.PATCH.REVISION" in log\n    assert "только после" in log\n    assert "aurorafox-stable" in log\n''',
    )


def create_finalize_workflow() -> None:
    write(
        ".github/workflows/verified-version-finalize.yml",
        '''name: AuroraFox Verified Version Finalize\n\non:\n  push:\n    branches: [main]\n    paths:\n      - 'project/release_request.json'\n  workflow_dispatch:\n\npermissions:\n  contents: write\n  actions: write\n\nconcurrency:\n  group: aurorafox-version-finalize\n  cancel-in-progress: false\n\njobs:\n  verify-bump-tag-dispatch:\n    runs-on: ubuntu-latest\n    timeout-minutes: 35\n    steps:\n      - uses: actions/checkout@v4\n        with:\n          fetch-depth: 0\n\n      - name: Read release request\n        id: request\n        shell: bash\n        run: |\n          set -euo pipefail\n          python3 - <<'PY' >> "$GITHUB_OUTPUT"\n          import json\n          from pathlib import Path\n          r = json.loads(Path('project/release_request.json').read_text(encoding='utf-8'))\n          active = bool(r.get('active', False))\n          bump = str(r.get('bump', '')).strip().lower()\n          reason = str(r.get('reason', '')).strip()\n          if active and bump not in {'major','minor','patch','revision','build'}:\n              raise SystemExit('active release request has invalid bump')\n          if active and not reason:\n              raise SystemExit('active release request requires a reason')\n          print(f"active={'true' if active else 'false'}")\n          print(f"bump={bump}")\n          print('reason<<EOF')\n          print(reason)\n          print('EOF')\n          PY\n\n      - name: Stop on inactive request\n        if: steps.request.outputs.active != 'true'\n        run: echo 'Release request is inactive; nothing to finalize.'\n\n      - name: Install Python test dependencies\n        if: steps.request.outputs.active == 'true'\n        run: python3 -m pip install --disable-pip-version-check pytest==8.4.1 numpy==2.2.6 requests==2.32.5\n\n      - name: Run contract tests before version changes\n        if: steps.request.outputs.active == 'true'\n        shell: bash\n        run: |\n          set -euo pipefail\n          python3 -m compileall -q agent api voice/python file_intelligence build tests\n          PYTHONPATH="$PWD" python3 -m pytest -q \\\n            tests/test_autonomous_evolution_contract.py \\\n            tests/test_project_master_contract.py \\\n            tests/test_standalone_core_contract.py \\\n            tests/test_release_channel_contract.py\n          pwsh -NoProfile -File tests/version_sync_test.ps1\n\n      - name: Install Godot 4.7.1\n        if: steps.request.outputs.active == 'true'\n        shell: bash\n        run: |\n          set -euo pipefail\n          curl -fL --retry 3 -o godot.zip https://github.com/godotengine/godot/releases/download/4.7.1-stable/Godot_v4.7.1-stable_linux.x86_64.zip\n          unzip -q godot.zip\n          godot="$(find . -maxdepth 1 -type f -name 'Godot_v4.7.1-stable_linux.x86_64*' | head -n1)"\n          test -n "$godot"\n          mv "$godot" godot\n          chmod +x godot\n\n      - name: Run blocking product smoke before version bump\n        if: steps.request.outputs.active == 'true'\n        shell: bash\n        run: |\n          set -euo pipefail\n          timeout 90s ./godot --headless --editor --path . --quit\n          for script in \\\n            tests/voice_smoke.gd \\\n            tests/self_reliance_smoke.gd \\\n            tests/desktop_ui_smoke.gd \\\n            tests/update_smoke.gd \\\n            tests/autonomy_learning_smoke.gd \\\n            tests/local_semantic_memory_smoke.gd \\\n            tests/local_model_failover_smoke.gd \\\n            tests/core_candidate_benchmark_smoke.gd\n          do\n            test -f "$script"\n            timeout 60s ./godot --headless --path . --script "$script"\n          done\n          echo 'AURORA_PRE_VERSION_GATES_OK'\n\n      - name: Bump synchronized version only after green tests\n        if: steps.request.outputs.active == 'true'\n        id: bump\n        shell: pwsh\n        env:\n          AURORA_VERIFIED_HEAD: ${{ github.sha }}\n          BUMP_KIND: ${{ steps.request.outputs.bump }}\n          BUMP_REASON: ${{ steps.request.outputs.reason }}\n        run: |\n          ./build/set_version.ps1 -Bump $env:BUMP_KIND -Reason $env:BUMP_REASON -VerifiedHead $env:AURORA_VERIFIED_HEAD\n          $state = Get-Content project/version.json -Raw | ConvertFrom-Json\n          "numeric=$($state.numeric)" >> $env:GITHUB_OUTPUT\n\n      - name: Resolve release request\n        if: steps.request.outputs.active == 'true'\n        shell: bash\n        env:\n          NEW_VERSION: ${{ steps.bump.outputs.numeric }}\n        run: |\n          set -euo pipefail\n          python3 - <<'PY'\n          import json, os\n          from datetime import datetime, timezone\n          from pathlib import Path\n          p = Path('project/release_request.json')\n          r = json.loads(p.read_text(encoding='utf-8'))\n          r['active'] = False\n          r['resolved_version'] = os.environ['NEW_VERSION']\n          r['resolved_at'] = datetime.now(timezone.utc).isoformat()\n          p.write_text(json.dumps(r, ensure_ascii=False, indent=2) + '\\n', encoding='utf-8')\n          PY\n\n      - name: Commit verified version and create tag\n        if: steps.request.outputs.active == 'true'\n        shell: bash\n        env:\n          VERSION: ${{ steps.bump.outputs.numeric }}\n        run: |\n          set -euo pipefail\n          git config user.name 'AuroraFox Version Bot'\n          git config user.email 'aurorafox-version@users.noreply.github.com'\n          git add project/version.json project/release_request.json project.godot export_presets.cfg update/manifest.template.json CHANGELOG.md evolution.log\n          git diff --cached --check\n          git commit -m "release: verified V${VERSION}"\n          git push origin HEAD:main\n          git tag -a "v${VERSION}" -m "AuroraFox verified V${VERSION}"\n          git push origin "v${VERSION}"\n\n      - name: Dispatch blocking release pipeline on verified tag\n        if: steps.request.outputs.active == 'true'\n        shell: bash\n        env:\n          GH_TOKEN: ${{ github.token }}\n          VERSION: ${{ steps.bump.outputs.numeric }}\n        run: |\n          set -euo pipefail\n          gh workflow run release.yml --ref "v${VERSION}"\n          echo "Dispatched release.yml for v${VERSION}"\n''',
    )


def create_release_request() -> None:
    path = ROOT / "project/release_request.json"
    if path.exists():
        return
    write(
        "project/release_request.json",
        '''{\n  "active": false,\n  "bump": "patch",\n  "reason": "",\n  "requested_by": "",\n  "request_id": "",\n  "resolved_version": "",\n  "resolved_at": ""\n}\n''',
    )


def main() -> None:
    patch_update_manager()
    patch_update_smoke()
    patch_set_version()
    patch_release_workflow()
    patch_voice_ci()
    patch_master_log()
    create_policy_doc()
    create_release_contract_test()
    create_finalize_workflow()
    create_release_request()
    print("AURORA_RELEASE_DISCIPLINE_MIGRATION_OK")


if __name__ == "__main__":
    main()
