import struct
import sys
import zipfile
import zlib
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'file_intelligence'))
import extended_formats as formats


def epub(path):
    with zipfile.ZipFile(path, 'w') as z:
        z.writestr('META-INF/container.xml', '<container><rootfile full-path="OPS/book.opf"/></container>')
        z.writestr('OPS/book.opf', '''<package xmlns="http://www.idpf.org/2007/opf">
        <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Книга</dc:title>
        <dc:creator>Автор</dc:creator><dc:language>ru</dc:language></metadata>
        <manifest><item id="a" href="a.xhtml"/><item id="b" href="b.xhtml"/>
        <item id="nav" href="nav.xhtml" properties="nav"/></manifest>
        <spine><itemref idref="a"/><itemref idref="b"/></spine></package>''')
        z.writestr('OPS/b.xhtml', '<p>SECOND CHAPTER</p>')
        z.writestr('OPS/a.xhtml', '<script>SECRET SCRIPT</script><p>FIRST CHAPTER</p>')
        z.writestr('OPS/nav.xhtml', '<nav><a href="a.xhtml">Начало</a></nav>')


def test_epub_real_spine_metadata_and_budget(tmp_path):
    path = tmp_path / 'book.epub'
    epub(path)
    text, metadata, warnings = formats.analyze_epub(path)
    assert text.index('FIRST CHAPTER') < text.index('SECOND CHAPTER')
    assert 'SECRET SCRIPT' not in text
    assert metadata['title'] == 'Книга'
    assert metadata['authors'] == ['Автор']
    assert metadata['language'] == 'ru'
    assert metadata['toc'] == [{'title': 'Начало', 'href': 'a.xhtml'}]
    assert not warnings
    assert len(formats.analyze_epub(path, 12)[0]) <= 12
    assert formats.analyze_epub(path, 0)[0] == ''


@pytest.mark.parametrize('name', ['../escape', '%2e%2e/escape', '/absolute', 'C:/drive', '\\absolute'])
def test_archive_rejects_unsafe_paths(tmp_path, name):
    path = tmp_path / 'unsafe.epub'
    epub(path)
    with zipfile.ZipFile(path, 'a') as z:
        z.writestr(name, 'untrusted')
    with pytest.raises(ValueError, match='Unsafe archive path'):
        formats.analyze_epub(path)


def test_epub_bounds_member_before_read(tmp_path, monkeypatch):
    path = tmp_path / 'large.epub'
    epub(path)
    monkeypatch.setattr(formats, 'MAX_EMBEDDED_TEXT_BYTES', 20)
    with pytest.raises(ValueError, match='bounded read limit'):
        formats.analyze_epub(path)


def rar(path, name='notes.txt', data=b'OWN LOCAL TEXT', method=0x30):
    # Real RAR3 stored-file fixture: CRC-checked main/file/end headers.
    def header(kind, flags, payload):
        body = struct.pack('<BHH', kind, flags, 7 + len(payload)) + payload
        return struct.pack('<H', zlib.crc32(body) & 0xffff) + body
    encoded = name.encode('ascii')
    payload = struct.pack('<IIBIIBBHI', len(data), len(data), 2,
                          zlib.crc32(data), 0, 20, method, len(encoded), 0x20) + encoded
    path.write_bytes(b'Rar!\x1a\x07\x00' + header(0x73, 0, b'\x00' * 6)
                     + header(0x74, 0x8000, payload) + data + header(0x7b, 0, b''))


def test_real_rar_stored_text_without_external_tools(tmp_path, monkeypatch):
    import subprocess
    def forbidden(*args, **kwargs):
        raise AssertionError('External extractor must never run')
    monkeypatch.setattr(subprocess, 'Popen', forbidden)
    path = tmp_path / 'stored.rar'
    rar(path)
    text, metadata, warnings = formats.analyze_rar(path)
    assert 'OWN LOCAL TEXT' in text
    assert metadata['entries'] == metadata['text_entries_extracted'] == 1
    assert metadata['rar_backend'] == 'stored-entry-reader'
    assert not warnings
    assert len(formats.analyze_rar(path, 8)[0]) <= 8


def test_rar_compressed_text_is_reported_without_execution(tmp_path, monkeypatch):
    import subprocess
    monkeypatch.setattr(subprocess, 'Popen', lambda *a, **k: pytest.fail('External process'))
    path = tmp_path / 'compressed.rar'
    rar(path, method=0x33)
    text, metadata, warnings = formats.analyze_rar(path)
    assert 'notes.txt' in text
    assert metadata['text_entries_extracted'] == 0
    assert any('separately bounded' in warning for warning in warnings)


def test_rar_rejects_traversal(tmp_path):
    path = tmp_path / 'unsafe.rar'
    rar(path, '../escape.txt')
    with pytest.raises(ValueError, match='Unsafe archive path'):
        formats.analyze_rar(path)


def test_file_service_dispatches_epub_and_rar(tmp_path):
    from file_service import _analyze
    book = tmp_path / 'book.epub'
    epub(book)
    result = _analyze(book, '', False, max_chars=2000)
    assert result['kind'] == 'ebook'
    assert 'FIRST CHAPTER' in result['text']
    archive = tmp_path / 'stored.rar'
    rar(archive)
    result = _analyze(archive, '', False, max_chars=2000)
    assert result['kind'] == 'archive'
    assert 'OWN LOCAL TEXT' in result['text']
