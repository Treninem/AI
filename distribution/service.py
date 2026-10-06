"""Verified transfer and crash-recoverable atomic pointer activation."""
import contextlib
import hashlib
import os
import shutil
import tempfile
from pathlib import Path
from .manifest import (DistributionError, canonical, file_digest, load_json, safe_component,
                       safe_key, validate, verify_file, verify_signature)


def sync_directory(path):
    if os.name != 'nt':
        fd = os.open(path,os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)


def atomic_write(path,data):
    path = Path(path)
    fd,temp = tempfile.mkstemp(dir=path.parent,prefix='.atomic-')
    try:
        with os.fdopen(fd,'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp,path)
        if os.name != 'nt':
            directory = os.open(path.parent,os.O_RDONLY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


@contextlib.contextmanager
def workspace(root):
    """One writer per private work root; OS releases the lock after crash."""
    root = Path(root).absolute()
    for p in (root,*root.parents):
        if p.is_symlink():
            raise DistributionError('workspace_symlink')
    root.mkdir(parents=True,exist_ok=True,mode=0o700)
    if any(p.is_symlink() for p in root.rglob('*')):
        raise DistributionError('workspace_symlink')
    with open(root / '.lock','a+b') as lock:
        if os.name == 'nt':
            import msvcrt
            lock.seek(0)
            lock.write(b'0')
            lock.flush()
            lock.seek(0)
            try:
                msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
            except OSError:
                raise DistributionError('workspace_busy') from None
        else:
            import fcntl
            try:
                fcntl.flock(lock.fileno(),fcntl.LOCK_EX | fcntl.LOCK_NB)
            except OSError:
                raise DistributionError('workspace_busy') from None
        try:
            yield root
        finally:
            if os.name == 'nt':
                lock.seek(0)
                msvcrt.locking(lock.fileno(),msvcrt.LK_UNLCK,1)
            else:
                fcntl.flock(lock.fileno(),fcntl.LOCK_UN)


def remote_verify(provider,m):
    if provider.size(m['object_key']) != m['bytes']:
        raise DistributionError('remote_size_mismatch')
    digest = hashlib.sha256()
    for part in m['chunks']:
        data = provider.read(m['object_key'],part['offset'],part['bytes'])
        if len(data) != part['bytes'] or hashlib.sha256(data).hexdigest() != part['sha256']:
            raise DistributionError('remote_part_integrity')
        digest.update(data)
    if digest.hexdigest() != m['sha256']:
        raise DistributionError('remote_artifact_integrity')


def upload(provider,path,m,trusted_keys):
    # Manifest authenticity is checked before any storage-side write.
    verify_signature(m,trusted_keys)
    verify_file(path,m['bytes'],m['sha256'])
    identity = f"aurorafox/metadata/identities/{m['artifact_id']}/{m['version']}.json"
    record = canonical({'artifact_id':m['artifact_id'],'version':m['version'],
                        'object_key':m['object_key'],'sha256':m['sha256'],'bytes':m['bytes']})
    def identity_matches():
        size = provider.size(identity)
        if size is None:
            return False
        if size != len(record) or provider.read(identity,0,size) != record:
            raise DistributionError('immutable_identity_collision')
        return True
    if not identity_matches():
        with tempfile.TemporaryDirectory() as temp:
            reservation = Path(temp)/'identity.json'
            reservation.write_bytes(record)
            provider.put_new(identity,reservation,'application/json')
        if not identity_matches():
            raise DistributionError('identity_reservation_failed')
    if provider.size(m['object_key']) is None:
        provider.put_new(m['object_key'],path,m['content_type'])
    # A successful PUT, matching metadata or ETag is not evidence of SHA256.
    remote_verify(provider,m)
    manifest_key = f"aurorafox/bootstrap/manifests/{m['artifact_id']}/{m['version']}/{m['sha256']}.json"
    data = canonical(m)
    with tempfile.TemporaryDirectory() as temp:
        manifest = Path(temp)/'manifest.json'
        manifest.write_bytes(data)
        provider.put_new(manifest_key,manifest,'application/json')
    if provider.size(manifest_key) != len(data) or provider.read(manifest_key,0,len(data)) != data:
        raise DistributionError('immutable_manifest_collision')
    return {'status':'UPLOADED_VERIFIED','object_key':m['object_key'],'manifest_key':manifest_key,
            'bytes':m['bytes'],'sha256':m['sha256']}


class ArtifactDownloader:
    def __init__(self,provider,trusted_keys,*,free_space=None):
        self.provider,self.trusted_keys = provider,trusted_keys
        self.free_space = free_space or (lambda p:shutil.disk_usage(p).free)

    def download(self,m,root,*,cancel=lambda:False,progress=lambda received,total:None):
        verify_signature(m,self.trusted_keys)
        with workspace(root) as root:
            stage = root / 'staging' / m['sha256']
            stage.mkdir(parents=True,exist_ok=True)
            ready = stage / 'artifact.verified'
            if cancel():
                raise DistributionError('cancelled')
            if ready.exists():
                verify_file(ready,m['bytes'],m['sha256'])
                progress(m['bytes'],m['bytes'])
                return ready
            received = 0
            valid = set()
            for chunk in m['chunks']:
                part = stage / f"{chunk['index']:08d}.part"
                if part.exists() and file_digest(part) == (chunk['bytes'],chunk['sha256']):
                    valid.add(chunk['index'])
                    received += chunk['bytes']
                elif part.exists():
                    part.unlink()
            # Cached parts + assembled artifact + declared expanded/install reserve.
            needed = m['bytes'] - received + m['bytes'] + m['resources']['minimum_disk']
            if self.free_space(root) < needed:
                raise DistributionError('insufficient_disk')
            progress(received,m['bytes'])
            for chunk in m['chunks']:
                if cancel():
                    raise DistributionError('cancelled')
                if chunk['index'] in valid:
                    continue
                data = self.provider.read(m['object_key'],chunk['offset'],chunk['bytes'])
                if len(data) != chunk['bytes'] or hashlib.sha256(data).hexdigest() != chunk['sha256']:
                    raise DistributionError('download_part_integrity')
                if cancel():
                    raise DistributionError('cancelled')
                atomic_write(stage / f"{chunk['index']:08d}.part",data)
                received += len(data)
                progress(received,m['bytes'])
            assembled = stage / 'artifact.partial'
            with assembled.open('wb') as out:
                for chunk in m['chunks']:
                    if cancel():
                        raise DistributionError('cancelled')
                    part = stage / f"{chunk['index']:08d}.part"
                    verify_file(part,chunk['bytes'],chunk['sha256'])
                    with part.open('rb') as source:
                        shutil.copyfileobj(source,out,1024*1024)
                out.flush()
                os.fsync(out.fileno())
            verify_file(assembled,m['bytes'],m['sha256'])
            if cancel():
                raise DistributionError('cancelled')
            os.replace(assembled,ready)
            sync_directory(stage)
            return ready


class ArtifactStaging:
    """Reference activation of a verified opaque package, never executes content.

    Health checks must be supplied by future platform integration. Active pointer
    is provisional until health passes; recovery restores the recorded old pointer.
    """
    def __init__(self,root,trusted_keys):
        self.root,self.trusted_keys = Path(root),trusted_keys

    def _restore(self,root,old):
        pointer = root / 'active.json'
        if old is None:
            pointer.unlink(missing_ok=True)
        else:
            atomic_write(pointer,canonical(old))

    def _recover(self,root):
        transaction = root / 'activation.json'
        if transaction.exists():
            record = load_json(transaction)
            if not record.get('committed',False):
                self._restore(root,record['previous'])
                if record.get('previous_known_good') is None:
                    (root / 'known-good.json').unlink(missing_ok=True)
                else:
                    atomic_write(root / 'known-good.json',canonical(record['previous_known_good']))
            transaction.unlink()
            sync_directory(root)

    def recover(self):
        with workspace(self.root) as root:
            self._recover(root)

    def activate(self,staged,m,health_check):
        verify_signature(m,self.trusted_keys)
        verify_file(staged,m['bytes'],m['sha256'])
        with workspace(self.root) as root:
            self._recover(root)
            pointer = root / 'active.json'
            previous = load_json(pointer) if pointer.exists() else None
            versions = root / 'versions'
            versions.mkdir(exist_ok=True)
            target = versions / m['sha256']
            if not target.exists():
                # Copy into same-filesystem staging before atomic version install.
                fd,temp = tempfile.mkstemp(dir=versions)
                try:
                    with os.fdopen(fd,'wb') as out, open(staged,'rb') as source:
                        shutil.copyfileobj(source,out,1024*1024)
                        out.flush()
                        os.fsync(out.fileno())
                    verify_file(temp,m['bytes'],m['sha256'])
                    os.replace(temp,target)
                    sync_directory(versions)
                finally:
                    if os.path.exists(temp):
                        os.unlink(temp)
            verify_file(target,m['bytes'],m['sha256'])
            current = {'artifact_id':m['artifact_id'],'version':m['version'],'sha256':m['sha256'],
                       'object_key':m['object_key'],'bytes':m['bytes']}
            previous_good = load_json(root / 'known-good.json') if (root / 'known-good.json').exists() else None
            transaction = {'previous':previous,'candidate':current,'previous_known_good':previous_good,'committed':False}
            atomic_write(root / 'activation.json',canonical(transaction))
            try:
                atomic_write(pointer,canonical(current))
                if health_check(target) is not True:
                    raise DistributionError('health_check_failed')
                atomic_write(root / 'known-good.json',canonical({'current':current,'previous':previous}))
                transaction['committed'] = True
                atomic_write(root / 'activation.json',canonical(transaction))
            except Exception:
                self._restore(root,previous)
                if previous_good is None:
                    (root / 'known-good.json').unlink(missing_ok=True)
                else:
                    atomic_write(root / 'known-good.json',canonical(previous_good))
                (root / 'activation.json').unlink()
                sync_directory(root)
                raise DistributionError('activation_rolled_back') from None
            (root / 'activation.json').unlink()
            sync_directory(root)
            return current
