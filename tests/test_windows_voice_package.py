import ast
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest

ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / 'voice/python/aurora_voice_server.py'


class WindowsVoicePackageTests(unittest.TestCase):
    def resolve_server_root(self, frozen, executable, source):
        tree = ast.parse(SERVER.read_text())
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
            self.assertEqual(actual, executable.parent)

    def test_development_backend_keeps_voice_source_root(self):
        self.assertEqual(self.resolve_server_root(False, '/python/python', SERVER), ROOT / 'voice')

    def test_packaged_powershell_utf8_bom_config_can_be_loaded(self):
        tree = ast.parse(SERVER.read_text())
        node = next(node for node in tree.body if isinstance(node, ast.Assign) and any(isinstance(t, ast.Name) and t.id == 'CONFIG' for t in node.targets))
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory)
            (config / 'voice_config.json').write_text(json.dumps({'enabled': True}), encoding='utf-8-sig')
            values = {'json': json, 'CONFIG_DIR': config}
            exec(compile(ast.Module(body=[node], type_ignores=[]), str(SERVER), 'exec'), values)
            self.assertIs(values['CONFIG']['enabled'], True)

    def test_full_package_and_production_release_require_installed_offline_voice(self):
        for name in ['windows-package-ci.yml', 'release.yml']:
            text = (ROOT / '.github/workflows' / name).read_text()
            self.assertNotIn('-SkipVoiceSetup', text)
            self.assertIn('windows_installed_voice_smoke.ps1 -InstallDir $installDir', text)
            self.assertIn('7z.exe', text)
        builder = (ROOT / 'voice/build_backend.ps1').read_text()
        self.assertNotIn('$python -m pip', builder)
        self.assertIn('$uv pip install --python $python', builder)


if __name__ == '__main__':
    unittest.main()
