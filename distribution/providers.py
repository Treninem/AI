"""Provider interface. S3 SDK is admin-only, lazy loaded, with safe errors."""
import contextlib
import hashlib
import os
import shutil
import tempfile
from pathlib import Path
from typing import Protocol
from .manifest import DistributionError, safe_key

class DistributionProvider(Protocol):
    def size(self, key): ...
    def read(self, key, offset, count): ...
    def put_new(self, key, path, content_type): ...
    def inventory(self): ...

class LocalProvider:
    """Genuine disk-backed store with create-if-absent atomic hard links."""
    def __init__(self, root):
        self.root = Path(root).resolve()
        self.root.mkdir(parents=True,exist_ok=True)

    def _path(self,key):
        path = self.root / safe_key(key)
        if not path.resolve().is_relative_to(self.root):
            raise DistributionError('provider_path_escape')
        if any(p.is_symlink() for p in (path,*path.parents) if p.is_relative_to(self.root)):
            raise DistributionError('provider_symlink')
        return path

    def size(self,key):
        path = self._path(key)
        return path.stat().st_size if path.exists() else None

    def read(self,key,offset,count):
        with self._path(key).open('rb') as stream:
            stream.seek(offset)
            return stream.read(count)

    def put_new(self,key,path,content_type):
        target = self._path(key)
        target.parent.mkdir(parents=True,exist_ok=True)
        fd,temp = tempfile.mkstemp(dir=target.parent)
        try:
            with os.fdopen(fd,'wb') as out, open(path,'rb') as source:
                shutil.copyfileobj(source,out,1024*1024)
                out.flush()
                os.fsync(out.fileno())
            try:
                os.link(temp,target)
            except FileExistsError:
                return False
            return True
        finally:
            os.unlink(temp)

    def inventory(self):
        return sorted([{'object_key':p.relative_to(self.root).as_posix(),'bytes':p.stat().st_size}
                       for p in self.root.rglob('*') if p.is_file() and not p.is_symlink()],key=lambda x:x['object_key'])

class S3DistributionProvider:
    """Never serializes credentials. Requires conditional-write compatible provider."""
    __slots__ = ('_client','_bucket')
    def __init__(self, client, bucket):
        self._client,self._bucket = client,bucket

    def __repr__(self):
        return 'S3DistributionProvider(<private configuration>)'

    def __getstate__(self):
        raise DistributionError('credentials_not_serializable')

    @classmethod
    def from_environment(cls):
        names = ['ENDPOINT','REGION','BUCKET','ACCESS_KEY_ID','SECRET_ACCESS_KEY']
        values = {n:os.environ.get('AURORAFOX_S3_'+n) for n in names}
        if not all(values.values()):
            raise DistributionError('external_setup_pending')
        from urllib.parse import urlsplit
        p = urlsplit(values['ENDPOINT'])
        if p.scheme != 'https' or not p.hostname or p.username or p.password or p.query or p.fragment:
            raise DistributionError('invalid_endpoint')
        try:
            import boto3
            from botocore.config import Config
            client = boto3.client('s3',endpoint_url=values['ENDPOINT'],region_name=values['REGION'],
                aws_access_key_id=values['ACCESS_KEY_ID'],aws_secret_access_key=values['SECRET_ACCESS_KEY'],
                aws_session_token=os.environ.get('AURORAFOX_S3_SESSION_TOKEN'),
                config=Config(signature_version='s3v4',connect_timeout=15,read_timeout=60,
                              retries={'max_attempts':2,'mode':'standard'},s3={'addressing_style':'path'}))
            return cls(client,values['BUCKET'])
        except Exception:
            raise DistributionError('s3_initialization_failed') from None

    @staticmethod
    def _code(error):
        return str(getattr(error,'response',{}).get('Error',{}).get('Code',''))

    def size(self,key):
        try:
            return self._client.head_object(Bucket=self._bucket,Key=safe_key(key))['ContentLength']
        except DistributionError:
            raise
        except Exception as error:
            if self._code(error) in {'404','NoSuchKey','NotFound'}:
                return None
            raise DistributionError('s3_head_failed') from None

    def read(self,key,offset,count):
        try:
            result = self._client.get_object(Bucket=self._bucket,Key=safe_key(key),Range=f'bytes={offset}-{offset+count-1}')
            with contextlib.closing(result['Body']) as body:
                data = body.read(count+1)
            if len(data) != count or result.get('ContentLength') != count or not str(result.get('ContentRange','')).startswith(f'bytes {offset}-{offset+count-1}/'):
                raise DistributionError('s3_range_mismatch')
            return data
        except DistributionError:
            raise
        except Exception:
            raise DistributionError('s3_read_failed') from None

    def put_new(self,key,path,content_type):
        # Conditional single PUT supports the 429 MB Knowledge artifact and <=5 GB
        # payloads. Larger artifacts must be published as independent immutable parts.
        if Path(path).stat().st_size > 5_000_000_000:
            raise DistributionError('split_large_artifact_required')
        try:
            with open(path,'rb') as body:
                self._client.put_object(Bucket=self._bucket,Key=safe_key(key),Body=body,
                    ContentLength=Path(path).stat().st_size,ContentType=content_type,IfNoneMatch='*')
            return True
        except DistributionError:
            raise
        except Exception as error:
            if self._code(error) in {'412','PreconditionFailed'}:
                return False
            # Never fall back to an unconditional write if provider lacks support.
            raise DistributionError('s3_conditional_write_failed') from None

    def inventory(self):
        try:
            out = []
            for page in self._client.get_paginator('list_objects_v2').paginate(Bucket=self._bucket):
                out.extend({'object_key':item['Key'],'bytes':item['Size']} for item in page.get('Contents',[]))
            return sorted(out,key=lambda x:x['object_key'])
        except Exception:
            raise DistributionError('s3_inventory_failed') from None

class AuthorizedHTTPProvider:
    """Client-side bounded URL authorization; no permanent S3 credentials.

    URL resolver stays in memory and can renew authorization on each chunk/retry.
    HTTPS only in production; loopback HTTP is explicitly test-only.
    """
    def __init__(self,resolver,*,test_loopback=False):
        self._resolver,self._test_loopback = resolver,test_loopback

    def __repr__(self):
        return 'AuthorizedHTTPProvider(<bounded authorization>)'

    def __getstate__(self):
        raise DistributionError('authorization_not_serializable')

    def read(self,key,offset,count):
        import urllib.request
        from urllib.parse import urlsplit
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self,*args,**kwargs):
                return None
        try:
            url = self._resolver(safe_key(key))
            p = urlsplit(url)
            local = self._test_loopback and p.scheme == 'http' and p.hostname in {'127.0.0.1','::1'}
            if (p.scheme != 'https' and not local) or not p.hostname or p.username or p.password or p.fragment:
                raise DistributionError('unsafe_download_authorization')
            request = urllib.request.Request(url,headers={'Range':f'bytes={offset}-{offset+count-1}',
                                                         'Accept-Encoding':'identity'})
            with urllib.request.build_opener(NoRedirect).open(request,timeout=60) as response:
                data = response.read(count+1)
                expected = f'bytes {offset}-{offset+count-1}/'
                if response.status != 206 or len(data) != count or not response.headers.get('Content-Range','').startswith(expected):
                    raise DistributionError('http_range_mismatch')
            return data
        except DistributionError:
            raise
        except Exception:
            raise DistributionError('http_transfer_failed') from None
