import base64
import copy
import hashlib
import io
import json
import os
import pickle
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from unittest.mock import patch
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from distribution.manifest import (DistributionError, canonical, describe, file_digest, load_json, object_key,
                                   sign, validate, verify_signature)
from distribution.providers import LocalProvider, S3DistributionProvider, AuthorizedHTTPProvider
from distribution.service import ArtifactDownloader, ArtifactStaging, atomic_write, upload, workspace
from distribution.capacity import report
from distribution.bootstrap import plan


class DistributionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.private = Ed25519PrivateKey.generate()
        self.keys = {'test':self.private.public_key()}
        self.data = bytes(range(256))*23 + b'AuroraFox genuine deterministic fixture\n'
        self.path = self.root/'fixture.bin'
        self.path.write_bytes(self.data)
        self.metadata = {
            'schema':'aurorafox.distribution-manifest.v1','artifact_id':'fixture','artifact_type':'knowledge',
            'version':'1.0.0','channel':'fixture','provider_id':'local-fixture','content_type':'application/octet-stream',
            'compatibility':{'min_aurorafox_version':'1.6.0.0','max_aurorafox_version':None,
                             'platform':['any'],'architecture':['any']},
            'profile':'seed','required':True,'optional':False,
            'resources':{'minimum_ram':0,'recommended_ram':0,'minimum_disk':100000,'vram_requirement':0},
            'capabilities':['knowledge.retrieve'],'dependencies':[],
            'source':{'name':'AuroraFox deterministic fixture','version':'1','urls':['https://github.com/Treninem/AI']},
            'license':{'identifier':'fixture-only','attribution':'AuroraFox test fixture'},
            'provenance':{'record':'tests/distribution/test_distribution.py','content_bytes':len(self.data),'shard_count':0},
            'previous_known_good':None,'rollback_target':None}
        self.m = sign(describe(self.path,self.metadata,part_size=1024),self.private,'test')
        self.provider = LocalProvider(self.root/'objects')
        self.download_root = self.root/'download'

    def publish(self):
        return upload(self.provider,self.path,self.m,self.keys)

    def resign(self,m):
        m['signature'] = None
        return sign(m,self.private,'test')

    def test_manifest_and_signature(self):
        self.assertIs(validate(self.m),self.m)
        verify_signature(self.m,self.keys)

    def test_standard_json_schema(self):
        try:
            import jsonschema
        except ImportError:
            self.skipTest('optional standard-schema crosscheck requires isolated test dependency')
        schema = load_json(Path('distribution/manifest.schema.json'))
        jsonschema.Draft202012Validator.check_schema(schema)
        jsonschema.validate(self.m,schema)

    def test_invalid_manifest_fields(self):
        for mutation in ({'unknown':1},{'bytes':True},{'optional':True},{'sha256':'bad'}, {'status':'bogus'}):
            with self.subTest(mutation=mutation),self.assertRaises(DistributionError):
                validate({**self.m,**mutation})

    def test_duplicate_json_keys(self):
        path = self.root/'duplicate.json'
        path.write_text('{"bytes":1,"bytes":2}')
        with self.assertRaises(DistributionError):
            load_json(path)

    def test_nan_json_rejected(self):
        path = self.root/'nan.json'
        path.write_text('{"bytes":NaN}')
        with self.assertRaises(DistributionError):
            load_json(path)

    def test_required_fields_missing(self):
        for field in self.m:
            with self.subTest(field=field),self.assertRaises(DistributionError):
                validate({k:v for k,v in self.m.items() if k != field})

    def test_path_traversal_and_windows_names(self):
        for field,value in [('filename','../escape'),('filename','CON.txt'),('filename','name.'),
                            ('artifact_id','a/b'),('object_key','aurorafox/../x'),('object_key','aurorafox/a%2fb'),
                            ('object_key','/absolute'),('object_key','aurorafox/a\\b')]:
            with self.subTest(value=value),self.assertRaises(DistributionError):
                validate({**self.m,field:value})

    def test_signed_url_provenance_rejected(self):
        for url in ('https://host/file?token=x','https://user:pass@host/file','http://host/file'):
            m = copy.deepcopy(self.m)
            m['source']['urls'] = [url]
            with self.assertRaises(DistributionError):
                validate(m)

    def test_chunk_coverage_duplicate_missing_order(self):
        for chunks in (self.m['chunks'][:-1],self.m['chunks']+[self.m['chunks'][0]],list(reversed(self.m['chunks']))):
            with self.subTest(chunks=chunks),self.assertRaises(DistributionError):
                validate({**self.m,'chunks':chunks})

    def test_empty_artifact_rejected(self):
        self.path.write_bytes(b'')
        with self.assertRaises(DistributionError):
            describe(self.path,self.metadata)

    def test_signature_tampering_and_unknown_key(self):
        for m,keys in (({**self.m,'channel':'beta'},self.keys),(self.m,{})):
            with self.assertRaises(DistributionError):
                verify_signature(m,keys)

    def test_artifact_size_mismatch(self):
        self.path.write_bytes(self.data[:-1])
        with self.assertRaises(DistributionError):
            self.publish()
        self.assertEqual(self.provider.inventory(),[])

    def test_artifact_sha_mismatch(self):
        self.path.write_bytes(b'x'*len(self.data))
        with self.assertRaises(DistributionError):
            self.publish()

    def test_upload_download_exact_bytes(self):
        receipt = self.publish()
        self.assertEqual(receipt['status'],'UPLOADED_VERIFIED')
        staged = ArtifactDownloader(self.provider,self.keys).download(self.m,self.download_root)
        self.assertEqual(staged.read_bytes(),self.data)
        self.assertFalse((self.download_root/'active.json').exists())

    def test_idempotent_upload(self):
        first = self.publish()
        before = self.provider.inventory()
        self.assertEqual(first,self.publish())
        self.assertEqual(before,self.provider.inventory())

    def test_same_id_version_different_bytes_rejected(self):
        self.publish()
        self.path.write_bytes(b'changed bytes')
        other = sign(describe(self.path,self.metadata,part_size=4),self.private,'test')
        with self.assertRaisesRegex(DistributionError,'immutable_identity_collision'):
            upload(self.provider,self.path,other,self.keys)
        self.assertIsNone(self.provider.size(other['object_key']))

    def test_existing_object_collision(self):
        bad = self.root/'bad.bin'
        bad.write_bytes(b'x'*len(self.data))
        self.provider.put_new(self.m['object_key'],bad,'application/octet-stream')
        with self.assertRaisesRegex(DistributionError,'remote_part_integrity'):
            self.publish()
        self.assertEqual(self.provider.read(self.m['object_key'],0,1),b'x')

    def test_upload_success_is_not_verification(self):
        provider = self.provider
        original = provider.put_new
        def corrupt(key,path,kind):
            result = original(key,path,kind)
            if key == self.m['object_key']:
                provider._path(key).write_bytes(b'bad')
            return result
        with patch.object(provider,'put_new',side_effect=corrupt),self.assertRaises(DistributionError):
            self.publish()

    def test_interrupted_restart_resume(self):
        self.publish()
        original = self.provider.read
        def fail(key,offset,count):
            if offset == 2048:
                raise DistributionError('simulated_network_loss')
            return original(key,offset,count)
        downloader = ArtifactDownloader(self.provider,self.keys)
        with patch.object(self.provider,'read',side_effect=fail),self.assertRaises(DistributionError):
            downloader.download(self.m,self.download_root)
        self.assertEqual(len(list(self.download_root.rglob('*.part'))),2)
        offsets = []
        def track(key,offset,count):
            offsets.append(offset)
            return original(key,offset,count)
        with patch.object(self.provider,'read',side_effect=track):
            staged = ArtifactDownloader(self.provider,self.keys).download(self.m,self.download_root)
        self.assertEqual(offsets[0],2048)
        self.assertEqual(staged.read_bytes(),self.data)

    def test_corrupt_cached_part_is_redownloaded(self):
        self.publish()
        stage = self.download_root/'staging'/self.m['sha256']
        stage.mkdir(parents=True)
        (stage/'00000000.part').write_bytes(b'x'*1024)
        staged = ArtifactDownloader(self.provider,self.keys).download(self.m,self.download_root)
        self.assertEqual(staged.read_bytes(),self.data)

    def test_remote_corrupt_part_rejected(self):
        self.publish()
        with patch.object(self.provider,'read',return_value=b'x'*1024),self.assertRaises(DistributionError):
            ArtifactDownloader(self.provider,self.keys).download(self.m,self.download_root)
        self.assertFalse(list(self.download_root.rglob('*.verified')))

    def test_corrupt_final_artifact_rejected(self):
        self.publish()
        m = copy.deepcopy(self.m)
        m['sha256'] = 'a'*64
        m['object_key'] = object_key(m)
        m = self.resign(m)
        self.provider.put_new(m['object_key'],self.path,m['content_type'])
        with self.assertRaisesRegex(DistributionError,'artifact_integrity'):
            ArtifactDownloader(self.provider,self.keys).download(m,self.download_root)
        self.assertFalse(list(self.download_root.rglob('*.verified')))

    def test_corrupt_previously_verified_staging_rejected(self):
        self.publish()
        downloader = ArtifactDownloader(self.provider,self.keys)
        staged = downloader.download(self.m,self.download_root)
        staged.write_bytes(b'bad')
        with self.assertRaises(DistributionError):
            downloader.download(self.m,self.download_root)

    def test_insufficient_disk(self):
        self.publish()
        with patch.object(self.provider,'read') as read,self.assertRaisesRegex(DistributionError,'insufficient_disk'):
            ArtifactDownloader(self.provider,self.keys,free_space=lambda _:0).download(self.m,self.download_root)
        read.assert_not_called()

    def test_cancel_preserves_completed_parts_and_progress(self):
        self.publish()
        progress = []
        with self.assertRaisesRegex(DistributionError,'cancelled'):
            ArtifactDownloader(self.provider,self.keys).download(self.m,self.download_root,
                cancel=lambda:bool(progress and progress[-1][0]>=1024),progress=lambda a,b:progress.append((a,b)))
        self.assertEqual(len(list(self.download_root.rglob('*.part'))),1)
        self.assertFalse(list(self.download_root.rglob('*.verified')))
        staged = ArtifactDownloader(self.provider,self.keys).download(self.m,self.download_root)
        self.assertEqual(staged.read_bytes(),self.data)

    def test_atomic_activation_and_previous_good_preserved(self):
        root = self.root/'installed'
        staging = ArtifactStaging(root,self.keys)
        first = staging.activate(self.path,self.m,lambda p:p.read_bytes()==self.data)
        self.path.write_bytes(b'new-version')
        m = sign(describe(self.path,{**self.metadata,'version':'2.0.0'},part_size=4),self.private,'test')
        staging.activate(self.path,m,lambda _:True)
        good = load_json(root/'known-good.json')
        self.assertEqual(good['previous'],first)
        self.assertEqual((root/'versions'/first['sha256']).read_bytes(),self.data)

    def test_rollback_on_failed_health(self):
        root = self.root/'installed'
        staging = ArtifactStaging(root,self.keys)
        first = staging.activate(self.path,self.m,lambda _:True)
        self.path.write_bytes(b'new-version')
        m = sign(describe(self.path,{**self.metadata,'version':'2.0.0'},part_size=4),self.private,'test')
        with self.assertRaisesRegex(DistributionError,'activation_rolled_back'):
            staging.activate(self.path,m,lambda _:False)
        self.assertEqual(load_json(root/'active.json'),first)
        self.assertEqual(load_json(root/'known-good.json')['current'],first)

    def test_first_activation_failure_has_no_active(self):
        root = self.root/'installed'
        with self.assertRaises(DistributionError):
            ArtifactStaging(root,self.keys).activate(self.path,self.m,lambda _:False)
        self.assertFalse((root/'active.json').exists())

    def test_crash_recovery_restores_previous_pointer(self):
        class Crash(BaseException): pass
        root = self.root/'installed'
        staging = ArtifactStaging(root,self.keys)
        first = staging.activate(self.path,self.m,lambda _:True)
        self.path.write_bytes(b'new-version')
        m = sign(describe(self.path,{**self.metadata,'version':'2.0.0'},part_size=4),self.private,'test')
        def crash(_): raise Crash()
        with self.assertRaises(Crash):
            staging.activate(self.path,m,crash)
        self.assertNotEqual(load_json(root/'active.json'),first)
        staging.recover()
        self.assertEqual(load_json(root/'active.json'),first)

    def test_partial_cannot_activate(self):
        self.path.write_bytes(self.data[:1024])
        with self.assertRaises(DistributionError):
            ArtifactStaging(self.root/'installed',self.keys).activate(self.path,self.m,lambda _:True)

    def test_single_writer_lock(self):
        if os.name == 'nt':
            self.skipTest('Windows same-process lock semantics differ; covered by CI platform smoke')
        with workspace(self.download_root),self.assertRaisesRegex(DistributionError,'workspace_busy'):
            with workspace(self.download_root): pass

    def test_symlink_escape(self):
        if os.name == 'nt':
            self.skipTest('requires Windows symlink privilege')
        root = self.root/'linked'
        root.symlink_to(self.root/'objects',target_is_directory=True)
        with self.assertRaisesRegex(DistributionError,'workspace_symlink'):
            with workspace(root): pass

    def test_retention_protects_stable_rollback_release_and_active_candidate(self):
        objects = [{'object_key':str(i),'bytes':10} for i in range(6)]
        metadata = {str(i):{'status':'superseded',field:True} for i,field in enumerate(
            ('stable','previous_known_good','release_required','rollback_required','active_candidate'))}
        metadata['5']={'status':'superseded'}
        r = report(objects,metadata,total=100)
        self.assertEqual([x['safe_to_prune'] for x in r['artifacts']],[False]*5+[True])
        self.assertTrue(r['dry_run'])
        self.assertFalse(report(objects,{},total=100)['artifacts'][0]['safe_to_prune'])

    def test_capacity_threshold(self):
        for used,review in ((69,False),(74,False),(75,True),(101,True)):
            r = report([{'object_key':'x','bytes':used}],{},total=100)
            self.assertEqual(r['review_required'],review)
            self.assertEqual(r['used'],used)
            self.assertEqual(r['free'],max(0,100-used))
        with self.assertRaises(DistributionError):
            report([{'object_key':'x','bytes':1}]*2,{})

    def test_credentials_never_serialized(self):
        provider = S3DistributionProvider(object(),'private-bucket')
        self.assertNotIn('private-bucket',repr(provider))
        with self.assertRaisesRegex(DistributionError,'credentials_not_serializable'):
            pickle.dumps(provider)
        with patch.dict(os.environ,{},clear=True),self.assertRaisesRegex(DistributionError,'external_setup_pending'):
            S3DistributionProvider.from_environment()

    def test_s3_errors_redacted_and_conditional_put(self):
        class Error(Exception):
            response = {'Error':{'Code':'NotImplemented'}}
        class Client:
            args = None
            def put_object(c,**kwargs):
                c.args = kwargs
                raise Error('private signed URL and credentials must stay hidden')
        client = Client()
        with self.assertRaisesRegex(DistributionError,'^s3_conditional_write_failed$'):
            S3DistributionProvider(client,'bucket').put_new(self.m['object_key'],self.path,'application/octet-stream')
        self.assertEqual(client.args['IfNoneMatch'],'*')
        self.assertNotIn('ACL',client.args)

    def test_s3_sdk_model_has_required_conditional_contract(self):
        try:
            import boto3
        except ImportError:
            self.skipTest('isolated admin SDK not installed')
        client = boto3.client('s3',region_name='us-east-1',aws_access_key_id='fixture',aws_secret_access_key='fixture')
        self.assertIn('IfNoneMatch',client.meta.service_model.operation_model('PutObject').input_shape.members)
        self.assertIn('Range',client.meta.service_model.operation_model('GetObject').input_shape.members)

    def test_s3_range_size_and_content_range(self):
        class Client:
            def get_object(c,**kwargs):
                return {'Body':io.BytesIO(b'abc'),'ContentLength':3,'ContentRange':'bytes 0-2/3'}
        p = S3DistributionProvider(Client(),'bucket')
        self.assertEqual(p.read(self.m['object_key'],0,3),b'abc')
        with self.assertRaisesRegex(DistributionError,'s3_range_mismatch'):
            p.read(self.m['object_key'],1,3)

    def test_genuine_http_range_download(self):
        data = self.data
        class Handler(BaseHTTPRequestHandler):
            def log_message(self,*args): pass
            def do_GET(handler):
                start,end = map(int,handler.headers['Range'][6:].split('-'))
                body = data[start:end+1]
                handler.send_response(206)
                handler.send_header('Content-Range',f'bytes {start}-{end}/{len(data)}')
                handler.send_header('Content-Length',str(len(body)))
                handler.end_headers()
                handler.wfile.write(body)
        server = ThreadingHTTPServer(('127.0.0.1',0),Handler)
        thread = threading.Thread(target=server.serve_forever,daemon=True)
        thread.start()
        try:
            provider = AuthorizedHTTPProvider(lambda _:f'http://127.0.0.1:{server.server_port}/fixture?bounded=fixture',test_loopback=True)
            staged = ArtifactDownloader(provider,self.keys).download(self.m,self.download_root)
            self.assertEqual(staged.read_bytes(),data)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_http_diagnostics_redacted(self):
        provider = AuthorizedHTTPProvider(lambda _:'http://user:secret@host/file?token=private')
        with self.assertRaisesRegex(DistributionError,'^unsafe_download_authorization$'):
            provider.read(self.m['object_key'],0,1)
        with self.assertRaises(DistributionError):
            pickle.dumps(provider)

    def test_offline_after_download_reference_contract(self):
        self.publish()
        staged = ArtifactDownloader(self.provider,self.keys).download(self.m,self.download_root)
        with patch.object(self.provider,'read',side_effect=AssertionError('network used')):
            ArtifactStaging(self.root/'installed',self.keys).activate(staged,self.m,lambda p:p.read_bytes()==self.data)
            again = ArtifactDownloader(self.provider,self.keys).download(self.m,self.download_root)
            self.assertEqual(again.read_bytes(),self.data)

    def test_pending_production_manifest_has_no_fake_chunks(self):
        m = load_json(Path('distribution/knowledge.production.pending.json'))
        validate(m,transfer=False)
        self.assertEqual(m['bytes'],429588529)
        self.assertEqual(m['sha256'],'bc0f312448f70a650435af8f30e853ca0a81a58f69c61802de7095bed9e24614')
        self.assertEqual(m['chunks'],[])
        with self.assertRaisesRegex(DistributionError,'external_artifact_pending'):
            validate(m)

    def test_bootstrap_requires_local_baseline_and_compatibility(self):
        hardware = {'platform':'windows','architecture':'x86_64','ram':8*1024**3,'vram':0,'free_disk':1000000}
        with self.assertRaisesRegex(DistributionError,'usable_local_baseline_missing'):
            plan([self.m],self.keys,hardware,'1.6.0.0','seed')
        metadata = {**self.metadata,'artifact_id':'core','artifact_type':'model','capabilities':['core.chat']}
        core = sign(describe(self.path,metadata,part_size=1024),self.private,'test')
        result = plan([core,self.m],self.keys,hardware,'1.6.0.0','seed')
        self.assertEqual(len(result['artifacts']),2)
        with self.assertRaisesRegex(DistributionError,'required_profile_incompatible'):
            plan([core,self.m],self.keys,hardware,'1.5.0.0','seed')

    def test_bootstrap_missing_dependency(self):
        m = copy.deepcopy(self.m)
        m['dependencies'] = ['aurorafox/knowledge/missing/version']
        m = self.resign(m)
        core = sign(describe(self.path,{**self.metadata,'artifact_id':'core','artifact_type':'model','capabilities':['core.chat']}),self.private,'test')
        hardware = {'platform':'windows','architecture':'x86_64','ram':8*1024**3,'vram':0,'free_disk':1000000}
        with self.assertRaisesRegex(DistributionError,'bootstrap_dependency_missing_or_cycle'):
            plan([core,m],self.keys,hardware,'1.6.0.0','seed')

    def test_recovery_after_known_good_written_before_commit(self):
        root = self.root/'installed'
        staging = ArtifactStaging(root,self.keys)
        first = staging.activate(self.path,self.m,lambda _:True)
        old_good = load_json(root/'known-good.json')
        candidate = {**first,'version':'2.0.0'}
        atomic_write(root/'activation.json',canonical({'previous':first,'candidate':candidate,
                     'previous_known_good':old_good,'committed':False}))
        atomic_write(root/'active.json',canonical(candidate))
        atomic_write(root/'known-good.json',canonical({'current':candidate,'previous':first}))
        staging.recover()
        self.assertEqual(load_json(root/'active.json'),first)
        self.assertEqual(load_json(root/'known-good.json'),old_good)

    def test_recovery_after_committed_before_cleanup(self):
        root = self.root/'installed'
        staging = ArtifactStaging(root,self.keys)
        first = staging.activate(self.path,self.m,lambda _:True)
        atomic_write(root/'activation.json',canonical({'previous':None,'candidate':first,
                     'previous_known_good':None,'committed':True}))
        staging.recover()
        self.assertEqual(load_json(root/'active.json'),first)
        self.assertFalse((root/'activation.json').exists())

    def test_bootstrap_skips_incompatible_optional_capability(self):
        core = sign(describe(self.path,{**self.metadata,'artifact_id':'core','artifact_type':'model',
            'capabilities':['core.chat']}),self.private,'test')
        optional = copy.deepcopy(self.m)
        optional.update(artifact_id='vision',artifact_type='capability',provider_id='optional-vision',
                        required=False,optional=True,capabilities=['vision.analyze'])
        optional['resources']['minimum_ram'] = 16*1024**3
        optional['resources']['recommended_ram'] = 16*1024**3
        optional['object_key'] = object_key(optional)
        optional = self.resign(optional)
        hardware = {'platform':'windows','architecture':'x86_64','ram':8*1024**3,'vram':0,'free_disk':1000000}
        result = plan([core,self.m,optional],self.keys,hardware,'1.6.0.0','seed',['vision.analyze'])
        self.assertEqual(len(result['artifacts']),2)

    def test_cancel_already_verified_staging(self):
        self.publish()
        downloader = ArtifactDownloader(self.provider,self.keys)
        downloader.download(self.m,self.download_root)
        with self.assertRaisesRegex(DistributionError,'cancelled'):
            downloader.download(self.m,self.download_root,cancel=lambda:True)

    def test_new_paths_secret_scan(self):
        import re
        patterns = [r'AKIA[0-9A-Z]{16}',r'ASIA[0-9A-Z]{16}',r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
                    r'gh[pousr]_[A-Za-z0-9]{30,}',r'X-Amz-Signature=[0-9a-fA-F]{64}']
        for folder in ('distribution','tools/distribution'):
            for path in Path(folder).rglob('*'):
                if path.is_file() and '__pycache__' not in path.parts:
                    content = path.read_text('utf-8')
                    for pattern in patterns:
                        self.assertIsNone(re.search(pattern,content),str(path))

if __name__ == '__main__':
    unittest.main()
