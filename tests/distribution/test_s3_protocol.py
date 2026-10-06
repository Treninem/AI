"""Real boto3 HTTP serialization against a tiny local S3 protocol fixture.

This is NOT evidence of access to the owner's real S3 provider.
"""
import io
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlsplit
from xml.sax.saxutils import escape
from pathlib import Path
import tempfile
import hashlib
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from distribution.manifest import DistributionError, describe, sign
from distribution.providers import S3DistributionProvider
from distribution.service import upload, ArtifactDownloader
import test_distribution as fixture


class S3ProtocolTests(unittest.TestCase):
    def test_real_sdk_conditional_upload_range_download_and_inventory(self):
        import boto3
        from botocore.config import Config
        objects = {}
        headers = []
        lock = threading.Lock()
        class Handler(BaseHTTPRequestHandler):
            def log_message(self,*args): pass
            def key(self):
                return unquote(urlsplit(self.path).path).removeprefix('/fixture-bucket/')
            def do_HEAD(self):
                key = self.key()
                if key not in objects:
                    self.send_response(404)
                    self.end_headers()
                else:
                    self.send_response(200)
                    self.send_header('Content-Length',str(len(objects[key])))
                    self.end_headers()
            def do_PUT(self):
                # Consume all body bytes, test ordinary SigV4 headers independently
                # of request logging. The fixture never records authorization.
                payload = self.rfile.read(int(self.headers['Content-Length']))
                key = self.key()
                with lock:
                    headers.append(self.headers.get('If-None-Match'))
                    if key in objects:
                        self.send_response(412)
                        self.send_header('Content-Length','0')
                        self.end_headers()
                        return
                    objects[key] = payload
                self.send_response(200)
                self.send_header('Content-Length','0')
                self.end_headers()
            def do_GET(self):
                if 'list-type=2' in self.path:
                    content = ''.join(f'<Contents><Key>{escape(k)}</Key><Size>{len(v)}</Size></Contents>' for k,v in sorted(objects.items()))
                    data = (f'<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Name>fixture-bucket</Name><IsTruncated>false</IsTruncated>{content}</ListBucketResult>').encode()
                    self.send_response(200)
                    self.send_header('Content-Length',str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
                    return
                data = objects[self.key()]
                start,end = map(int,self.headers['Range'][6:].split('-'))
                self.send_response(206)
                self.send_header('Content-Length',str(end-start+1))
                self.send_header('Content-Range',f'bytes {start}-{end}/{len(data)}')
                self.end_headers()
                self.wfile.write(data[start:end+1])
        server = ThreadingHTTPServer(('127.0.0.1',0),Handler)
        thread = threading.Thread(target=server.serve_forever,daemon=True)
        thread.start()
        case = fixture.DistributionTests()
        case.setUp()
        try:
            client = boto3.client('s3',endpoint_url=f'http://127.0.0.1:{server.server_port}',region_name='us-east-1',
                aws_access_key_id='protocol-fixture',aws_secret_access_key='protocol-fixture',
                config=Config(signature_version='s3v4',connect_timeout=2,read_timeout=2,
                    retries={'max_attempts':0},s3={'addressing_style':'path'},
                    request_checksum_calculation='when_required',response_checksum_validation='when_required'))
            provider = S3DistributionProvider(client,'fixture-bucket')
            receipt = upload(provider,case.path,case.m,case.keys)
            self.assertEqual(receipt['status'],'UPLOADED_VERIFIED')
            staged = ArtifactDownloader(provider,case.keys).download(case.m,case.download_root)
            self.assertEqual(staged.read_bytes(),case.data)
            self.assertEqual(len(provider.inventory()),3)
            self.assertTrue(headers and all(h=='*' for h in headers))
            self.assertFalse(provider.put_new(case.m['object_key'],case.path,case.m['content_type']))
            case.path.write_bytes(b'different same version')
            other = sign(describe(case.path,case.metadata,part_size=4),case.private,'test')
            with self.assertRaisesRegex(DistributionError,'immutable_identity_collision'):
                upload(provider,case.path,other,case.keys)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
            case.temp.cleanup()
