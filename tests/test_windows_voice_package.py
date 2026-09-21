import ast
import json
import ipaddress
import os
import re
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / 'voice/python/aurora_voice_server.py'


class WindowsVoicePackageTests(unittest.TestCase):
    def resolve_file_service_port(self, environment):
        path = ROOT / 'file_intelligence/file_service.py'
        tree = ast.parse(path.read_text(encoding='utf-8'))
        node = next(node for node in tree.body if isinstance(node, ast.Assign) and
                    any(isinstance(target, ast.Name) and target.id == 'PORT' for target in node.targets))
        values = {'os': os}
        with patch.dict(os.environ, environment, clear=True):
            exec(compile(ast.Module(body=[node], type_ignores=[]), str(path), 'exec'), values)
        return values['PORT']

    def test_file_service_port_has_one_canonical_value_with_compatible_aliases(self):
        self.assertEqual(self.resolve_file_service_port({'AURORAFOX_LOCAL_SERVICES_PORT': '18867',
                                                         'AURORAFOX_FILES_PORT': '8767',
                                                         'AURORAFOX_API_PORT': '9999'}), 18867)
        self.assertEqual(self.resolve_file_service_port({'AURORAFOX_FILES_PORT': '18868'}), 18868)
        self.assertEqual(self.resolve_file_service_port({'AURORAFOX_API_PORT': '18869'}), 18869)
        self.assertEqual(self.resolve_file_service_port({}), 8767)

    def test_file_service_txt_contract_preserves_content_and_uses_canonical_kind(self):
        path = ROOT / 'file_intelligence/file_service.py'
        tree = ast.parse(path.read_text(encoding='utf-8'))
        nodes = [node for node in tree.body
                 if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and
                 node.name in {'_read_text', '_analyze'}]
        values = {
            'Path': Path,
            'Any': object,
            'MAX_TEXT_CHARS': 10000,
            'TEXT_EXT': {'.txt'},
            'IMAGE_EXT': set(),
            'AUDIO_EXT': set(),
            'VIDEO_EXT': set(),
            'ARCHIVE_EXT': set(),
            'zipfile': SimpleNamespace(is_zipfile=lambda _path: False),
            'tarfile': SimpleNamespace(is_tarfile=lambda _path: False),
        }
        exec(compile(ast.Module(body=nodes, type_ignores=[]), str(path), 'exec'), values)
        expected = 'AuroraFox локальный разбор файлов'
        with tempfile.TemporaryDirectory() as directory:
            sample = Path(directory) / 'installed-file-sample.txt'
            sample.write_bytes(expected.encode('utf-8'))
            actual = values['_analyze'](sample, '', False, 10000)
        self.assertEqual(actual['kind'], 'text/code')
        self.assertEqual(actual['text'], expected)

    def resolve_server_root(self, frozen, executable, source):
        tree = ast.parse(SERVER.read_text(encoding="utf-8"))
        node = next(node for node in tree.body if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'ROOT' for t in node.targets))
        values = {'Path': Path, 'sys': SimpleNamespace(frozen=frozen, executable=str(executable)), '__file__': str(source)}
        exec(compile(ast.Module(body=[node], type_ignores=[]), str(SERVER), 'exec'), values)
        return values['ROOT']

    def test_frozen_backend_uses_staged_config_next_to_executable(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            executable = base / 'voice/AuroraVoiceBackend/AuroraVoiceBackend.exe'
            source = base / 'voice/AuroraVoiceBackend/_internal/aurora_voice_server.py'
            actual = self.resolve_server_root(True, executable, source)
            self.assertEqual(actual, executable.parent.resolve())

    def test_development_backend_keeps_voice_source_root(self):
        self.assertEqual(self.resolve_server_root(False, '/python/python', SERVER), ROOT / 'voice')

    def test_packaged_powershell_utf8_bom_config_can_be_loaded(self):
        tree = ast.parse(SERVER.read_text(encoding="utf-8"))
        node = next(node for node in tree.body if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'CONFIG' for t in node.targets))
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory)
            (config / 'voice_config.json').write_text(json.dumps({'enabled': True}), encoding='utf-8-sig')
            values = {'json': json, 'CONFIG_DIR': config}
            exec(compile(ast.Module(body=[node], type_ignores=[]), str(SERVER), 'exec'), values)
            self.assertIs(values['CONFIG']['enabled'], True)


    def test_packaged_stt_baseline_fits_single_installer_contract(self):
        config = json.loads((ROOT / 'voice/config/voice_config.json').read_text(encoding="utf-8"))
        sources = '\n'.join([
            (ROOT / 'voice/install_voice.ps1').read_text(encoding="utf-8"),
            (ROOT / 'voice/python/aurora_voice_server.py').read_text(encoding="utf-8"),
        ])
        self.assertEqual(config['stt']['model'], 'openai/whisper-small')
        self.assertIn('openai/whisper-small', sources)
        self.assertNotIn('whisper-large-v3-turbo', sources)

    def test_packaged_silero_loads_local_package_without_network_manifest(self):
        path = ROOT / 'voice/python/tts_engine.py'
        tree = ast.parse(path.read_text())
        engine = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == 'SileroEngine')
        load = next(n for n in engine.body if isinstance(n, ast.FunctionDef) and n.name == '_load')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = root / 'models/silero/aurorafox-silero.pt'
            package.parent.mkdir(parents=True)
            package.write_bytes(b'local fixture')
            calls = []
            model = SimpleNamespace(to=lambda device: calls.append(('device', device)))
            def importer(filename):
                calls.append(('package', filename))
                return SimpleNamespace(load_pickle=lambda group, name: model)
            def forbidden(**kwargs):
                self.fail('Packaged TTS attempted online Silero manifest lookup')
            values = {'VOICE_ROOT': root, 'torch': SimpleNamespace(package=SimpleNamespace(PackageImporter=importer)),
                      'silero_tts': forbidden}
            exec(compile(ast.Module(body=[load], type_ignores=[]), str(path), 'exec'), values)
            state = SimpleNamespace(config={'package_path': 'models/silero/aurorafox-silero.pt'}, device='cpu', model=None)
            self.assertIs(values['_load'](state), model)
            self.assertIs(values['_load'](state), model)
            self.assertEqual(calls, [('package', str(package)), ('device', 'cpu')])
            state.model = None
            package.unlink()
            with self.assertRaisesRegex(FileNotFoundError, 'Packaged local Silero'):
                values['_load'](state)

    def test_voice_firewall_covers_external_addresses_and_excludes_loopback(self):
        text = (ROOT / 'tests/windows_installed_voice_smoke.ps1').read_text()
        self.assertIn('-RemoteAddress ($externalIpv4 + $externalIpv6)', text)
        ranges = []
        for family in ('externalIpv4', 'externalIpv6'):
            literal = re.search(r'\$' + family + r" = @\(([^\n]+)\)", text).group(1)
            for value in re.findall(r"'([^']+)'", literal):
                first, last = value.split('-')
                ranges.append((ipaddress.ip_address(first), ipaddress.ip_address(last)))
        for address, blocked in [('127.0.0.1', False), ('127.255.255.254', False),
                                 ('::1', False), ('1.1.1.1', True), ('192.168.1.1', True),
                                 ('2001:db8::1', True), ('fe80::1234', True)]:
            ip = ipaddress.ip_address(address)
            actual = any(ip.version == first.version and first <= ip <= last for first, last in ranges)
            with self.subTest(address=address):
                self.assertEqual(actual, blocked)

    def test_full_package_and_production_release_require_installed_offline_voice(self):
        for name in ['windows-package-ci.yml', 'release.yml']:
            text = (ROOT / '.github/workflows' / name).read_text(encoding="utf-8")
            self.assertNotIn('-SkipVoiceSetup', text)
            self.assertIn('windows_installed_voice_smoke.ps1 -InstallDir $installDir', text)
            self.assertIn('windows_installed_local_services_smoke.ps1 -InstallDir $installDir', text)
            self.assertIn('windows_installed_knowledge_pack_smoke.ps1 -InstallDir $installDir', text)
            self.assertIn('artifacts/windows-offline-services/**', text)
            self.assertIn('artifacts/windows-offline-knowledge-pack/**', text)
            self.assertIn('7z.exe', text)
        builder = (ROOT / 'voice/build_backend.ps1').read_text(encoding="utf-8")
        self.assertNotIn('$python -m pip', builder)
        self.assertIn('$uv pip install --python $python', builder)

    def test_computer_agent_is_built_as_a_portable_offline_runtime(self):
        installer = (ROOT / 'computer/install_computer.ps1').read_text(encoding='utf-8')
        builder = (ROOT / 'build/build_windows.ps1').read_text(encoding='utf-8')
        client = (ROOT / 'scripts/computer_client.gd').read_text(encoding='utf-8')
        self.assertIn('[switch]$PreparePortable', installer)
        self.assertIn('--target $PortableVendor', installer)
        self.assertIn("AURORA_COMPUTER_PORTABLE_READY", installer)
        self.assertIn('$computerInstaller -PreparePortable', builder)
        self.assertIn('computerOut "python\\python.exe"', builder)
        self.assertIn('computerOut "vendor\\fastapi"', builder)
        self.assertLess(client.index('root.path_join("python/python.exe")'),
                        client.index('root.path_join(".venv/Scripts/python.exe")'))
        self.assertIn('OS.set_environment("PYTHONPATH", vendor)', client)
        self.assertIn('OS.unset_environment("PYTHONPATH")', client)

    def test_installed_files_and_computer_smoke_is_external_network_isolated(self):
        path = ROOT / 'tests/windows_installed_local_services_smoke.ps1'
        text = path.read_text(encoding='utf-8')
        self.assertIn('-RemoteAddress ($externalIpv4 + $externalIpv6)', text)
        self.assertIn("AURORA_WINDOWS_INSTALLED_OFFLINE_FILES_COMPUTER_OK", text)
        self.assertIn("$localServicesPort = '18867'", text)
        self.assertIn("'AURORAFOX_LOCAL_SERVICES_PORT'", text)
        self.assertIn("SetEnvironmentVariable('AURORAFOX_FILES_PORT', $localServicesPort", text)
        self.assertIn("SetEnvironmentVariable('AURORAFOX_API_PORT', $localServicesPort", text)
        self.assertIn("'file_service:app'", text)
        self.assertIn("'--port',$localServicesPort", text)
        self.assertIn('$filesHealthUrl = "http://127.0.0.1:$localServicesPort/health"', text)
        self.assertIn('$filesAnalyzeUrl = "http://127.0.0.1:$localServicesPort/analyze"', text)
        self.assertIn('Get-NetTCPConnection -LocalPort $ExpectedPort -State Listen', text)
        self.assertIn('ProcessExited:', text)
        self.assertIn("$expectedFileKind = 'text/code'", text)
        self.assertIn('$actualFileContent = [string]$fileAnalysis.content', text)
        self.assertIn('$actualFileContent -cne $fileText', text)
        self.assertIn('Expected kind:', text)
        self.assertIn('Actual content length:', text)
        self.assertIn('Response:', text)
        service = (ROOT / 'file_intelligence/file_service.py').read_text(encoding='utf-8')
        self.assertIn('os.getenv("AURORAFOX_LOCAL_SERVICES_PORT")', service)
        self.assertIn('or os.getenv("AURORAFOX_FILES_PORT")', service)
        self.assertIn('or os.getenv("AURORAFOX_API_PORT")', service)
        self.assertIn("/sandbox/write'", text)
        self.assertIn("/sandbox/read?path=installed-proof.txt'", text)
        self.assertIn('Invoke-RestMethod $filesAnalyzeUrl', text)
        self.assertIn("local_core_planning_required", text)
        ranges = []
        for family in ('externalIpv4', 'externalIpv6'):
            literal = re.search(r'\$' + family + r" = @\(([^\n]+)\)", text).group(1)
            for value in re.findall(r"'([^']+)'", literal):
                first, last = value.split('-')
                ranges.append((ipaddress.ip_address(first), ipaddress.ip_address(last)))
        for address, blocked in [('127.0.0.1', False), ('::1', False),
                                 ('8.8.8.8', True), ('10.0.0.1', True),
                                 ('2001:db8::5', True), ('fe80::5', True)]:
            ip = ipaddress.ip_address(address)
            actual = any(ip.version == first.version and first <= ip <= last for first, last in ranges)
            with self.subTest(installed_service_address=address):
                self.assertEqual(actual, blocked)

    def test_installed_windows_knowledge_pack_runs_embedded_offline_smoke(self):
        path = ROOT / 'tests/windows_installed_knowledge_pack_smoke.ps1'
        text = path.read_text(encoding='utf-8')
        self.assertIn("'--headless','--script','res://tests/knowledge_pack_installer_smoke.gd'", text)
        self.assertIn('$fixtureComplete = $false', text)
        self.assertIn("'AURORAFOX_KNOWLEDGE_SMOKE_RESULT'", text)
        self.assertRegex(
            text,
            r"\$(?:candidate|proof)\.schema\s+-eq\s+'aurorafox\.installed-knowledge-smoke\.v1'",
        )
        self.assertIn('$proof = $candidate', text)
        self.assertIn("$proof.shard_sha256 -ne $shardHash", text)
        self.assertIn('durable_completion_observed = $fixtureComplete', text)
        self.assertIn('stdout:', text)
        self.assertNotIn('$process.WaitForExit(120000)', text)
        self.assertIn('-RemoteAddress ($externalIpv4 + $externalIpv6)', text)
        self.assertIn("$statePath = [string]$proof.state_path", text)
        gdscript = (ROOT / 'tests/knowledge_pack_installer_smoke.gd').read_text(encoding='utf-8')
        self.assertIn('OS.get_environment("AURORAFOX_KNOWLEDGE_SMOKE_RESULT")', gdscript)
        self.assertIn('"schema": "aurorafox.installed-knowledge-smoke.v1"', gdscript)
        self.assertRegex(
            gdscript,
            r'_write_(?:result|json)_atomic\(result_path,\s*(?:JSON\.stringify\(proof\)|proof)\)',
        )
        self.assertIn("$state.status -ne 'ready'", text)
        self.assertIn('@($state.completed_shards).Count -ne 1', text)
        self.assertIn("$manifest.schema -ne 'aurorafox.knowledge-pack.v1'", text)
        self.assertIn("$manifest.pack_id -ne 'aurorafox-smoke'", text)
        self.assertIn('-not [bool]$manifest.production', text)
        self.assertRegex(
            text,
            r'\[string\]\s*\(?@\(\$state\.completed_shards\)\[0\]\)?\s+-ne\s+\$shardHash',
        )
        self.assertIn('AURORA_WINDOWS_INSTALLED_OFFLINE_KNOWLEDGE_PACK_OK', text)
        self.assertIn('outbound_firewall_block = $true', text)
        self.assertIn('external_ai_required = $false', text)

    def test_windows_installer_excludes_generated_api_venv_and_preflights_payload(self):
        iss = (ROOT / 'build/AuroraFox.iss').read_text(encoding='utf-8')
        workflow = (ROOT / '.github/workflows/windows-package-ci.yml').read_text(encoding='utf-8')
        self.assertIn('Source: "windows\\*"', iss)
        self.assertIn('Excludes: "api\\.venv\\*"', iss)
        self.assertIn("$iss = (Resolve-Path 'build\\AuroraFox.iss').Path", workflow)
        self.assertIn("$packageRoot = (Resolve-Path 'build\\windows').Path", workflow)
        self.assertIn('Installer source missing:', workflow)
        self.assertIn("'api\\server.py'", workflow)
        self.assertIn("'core_runtime\\engine\\aurorafox-core.gguf'", workflow)
        self.assertIn('& $iscc "/DMyAppVersion=$version" $iss', workflow)


if __name__ == '__main__':
    unittest.main()
