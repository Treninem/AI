import ast
import json
import ipaddress
import re
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / 'voice/python/aurora_voice_server.py'


class WindowsVoicePackageTests(unittest.TestCase):
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
            self.assertIn('7z.exe', text)
        builder = (ROOT / 'voice/build_backend.ps1').read_text(encoding="utf-8")
        self.assertNotIn('$python -m pip', builder)
        self.assertIn('$uv pip install --python $python', builder)


if __name__ == '__main__':
    unittest.main()
