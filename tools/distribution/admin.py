"""Explicit standalone commands. No raw tracebacks, credential values or URLs."""
import argparse
import json
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[2]))
from distribution.manifest import DistributionError, canonical, describe, load_json, sign, validate
from distribution.providers import LocalProvider, S3DistributionProvider
from distribution.service import ArtifactDownloader, ArtifactStaging, upload
from distribution.capacity import report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--local-store',type=Path,help='Use deterministic local object store instead of S3')
    parser.add_argument('--public-key',type=Path,help='Externally pinned Ed25519 PEM public key')
    parser.add_argument('--key-id',default='distribution-owner')
    commands = parser.add_subparsers(dest='command',required=True)
    p = commands.add_parser('describe')
    p.add_argument('artifact',type=Path)
    p.add_argument('metadata',type=Path)
    p.add_argument('output',type=Path)
    p.add_argument('--private-key',type=Path,required=True,help='Owner-controlled key OUTSIDE repository')
    p = commands.add_parser('validate')
    p.add_argument('manifest',type=Path)
    p = commands.add_parser('upload')
    p.add_argument('manifest',type=Path)
    p.add_argument('artifact',type=Path)
    p = commands.add_parser('download')
    p.add_argument('manifest',type=Path)
    p.add_argument('staging',type=Path)
    p = commands.add_parser('capacity')
    p.add_argument('--retention',type=Path)
    p.add_argument('--total',type=int,default=10_000_000_000)
    args = parser.parse_args()
    try:
        if args.command == 'validate':
            m = validate(load_json(args.manifest),transfer=False)
            print(json.dumps({'status':m['status'],'schema_valid':True,'signature_verified':False}))
            return 0
        if args.command == 'describe':
            from cryptography.hazmat.primitives.serialization import load_pem_private_key
            from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
            key_path = args.private_key.resolve()
            repo = Path(__file__).resolve().parents[2]
            if key_path.is_relative_to(repo):
                raise DistributionError('private_key_must_be_external')
            key = load_pem_private_key(key_path.read_bytes(),password=None)
            if not isinstance(key,Ed25519PrivateKey):
                raise DistributionError('ed25519_key_required')
            m = sign(describe(args.artifact,load_json(args.metadata)),key,args.key_id)
            args.output.write_bytes(canonical(m))
            print(json.dumps({'status':'SIGNED_MANIFEST_CREATED','bytes':m['bytes'],'sha256':m['sha256']}))
            return 0
        provider = LocalProvider(args.local_store) if args.local_store else S3DistributionProvider.from_environment()
        if args.command == 'capacity':
            objects = provider.inventory()
            metadata = load_json(args.retention) if args.retention else {}
            # Count ALL bucket bytes. Unknown/non-AuroraFox keys are never printed.
            r = report(objects,metadata,total=args.total)
            for item in r['artifacts']:
                try:
                    from distribution.manifest import safe_key
                    safe_key(item['object_key'])
                except DistributionError:
                    item['object_key'] = '<existing-unmanaged-object>'
                    item['safe_to_prune'] = False
            print(json.dumps(r,indent=2))
            return 0
        if args.public_key is None:
            raise DistributionError('pinned_public_key_required')
        from cryptography.hazmat.primitives.serialization import load_pem_public_key
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
        public = load_pem_public_key(args.public_key.read_bytes())
        if not isinstance(public,Ed25519PublicKey):
            raise DistributionError('ed25519_key_required')
        keys = {args.key_id:public}
        m = load_json(args.manifest)
        if args.command == 'upload':
            result = upload(provider,args.artifact,m,keys)
        else:
            ArtifactDownloader(provider,keys).download(m,args.staging)
            result = {'status':'STAGED_VERIFIED','sha256':m['sha256'],'bytes':m['bytes']}
        print(json.dumps(result))
        return 0
    except KeyboardInterrupt:
        print('{"error":"cancelled_completed_parts_retained"}',file=sys.stderr)
        return 130
    except DistributionError as error:
        print(json.dumps({'error':str(error)}),file=sys.stderr)
        return 2
    except Exception:
        print('{"error":"operation_failed_private_details_redacted"}',file=sys.stderr)
        return 2

if __name__ == '__main__':
    raise SystemExit(main())
