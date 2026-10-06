"""Strict provider-neutral schema and signed transfer contract."""
import base64
import hashlib
import json
import re
from pathlib import Path

class DistributionError(Exception):
    """Safe diagnostic code; never carries provider exceptions or URLs."""


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True, allow_nan=False).encode('ascii')


def load_json(path):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise DistributionError('duplicate_json_key')
            result[key] = value
        return result
    with open(path,'rb') as stream:
        raw = stream.read(16*1024*1024+1)
    if len(raw) > 16*1024*1024:
        raise DistributionError('metadata_too_large')
    return json.loads(raw.decode('utf-8'), object_pairs_hook=pairs,
                      parse_constant=lambda _: (_ for _ in ()).throw(DistributionError('invalid_number')))


def safe_component(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,127}', value):
        raise DistributionError('unsafe_component')
    if value.endswith('.') or value.split('.')[0].upper() in {'CON','PRN','AUX','NUL', *(f'COM{i}' for i in range(1,10)), *(f'LPT{i}' for i in range(1,10))}:
        raise DistributionError('unsafe_component')
    return value


def safe_key(value):
    if not isinstance(value, str) or len(value) > 1024 or not value.startswith('aurorafox/'):
        raise DistributionError('unsafe_object_key')
    for component in value.split('/'):
        safe_component(component)
    return value


PREFIXES = {'model': 'models/core', 'knowledge': 'knowledge', 'capability': 'capabilities',
            'experience': 'experience/shared', 'skill': 'experience/shared', 'release': 'releases'}


def object_key(m):
    return f"aurorafox/{PREFIXES[m['artifact_type']]}/{m['profile']}/{m['artifact_id']}/{m['version']}/{m['sha256']}/{m['filename']}"


def _schema(value, rule):
    # Deliberately implements only the vocabulary used by the bundled JSON schema.
    # Unsupported keywords fail closed instead of silently becoming validation gaps.
    known = {'$schema','$id','title','description','type','properties','required','additionalProperties',
             'items','enum','const','pattern','minimum','maximum','minItems','maxItems','minLength','maxLength','uniqueItems'}
    if set(rule) - known:
        raise DistributionError('unsupported_schema_keyword')
    kind = rule.get('type')
    types = kind if isinstance(kind, list) else [kind]
    matches = {'object': isinstance(value,dict), 'array': isinstance(value,list), 'string': isinstance(value,str),
               'integer': type(value) is int, 'boolean': type(value) is bool, 'null': value is None}
    if not any(matches.get(t, False) for t in types):
        raise DistributionError('schema_type')
    if 'const' in rule and value != rule['const'] or 'enum' in rule and value not in rule['enum']:
        raise DistributionError('schema_enum')
    if isinstance(value, dict):
        properties = rule.get('properties', {})
        if not set(rule.get('required', ())) <= value.keys():
            raise DistributionError('schema_required')
        if rule.get('additionalProperties') is False and value.keys() - properties.keys():
            raise DistributionError('schema_unknown_field')
        for key, item in value.items():
            if key in properties:
                _schema(item, properties[key])
    if isinstance(value, list):
        if len(value) < rule.get('minItems',0) or len(value) > rule.get('maxItems', len(value)):
            raise DistributionError('schema_array_length')
        if rule.get('uniqueItems') and len({canonical(x) for x in value}) != len(value):
            raise DistributionError('schema_duplicate_item')
        for item in value:
            _schema(item, rule['items'])
    if isinstance(value, str):
        if len(value) < rule.get('minLength',0) or len(value) > rule.get('maxLength',len(value)):
            raise DistributionError('schema_string_length')
        if 'pattern' in rule and re.search(rule['pattern'], value) is None:
            raise DistributionError('schema_pattern')
    if type(value) is int and (value < rule.get('minimum',value) or value > rule.get('maximum',value)):
        raise DistributionError('schema_number_range')


def validate(m, *, transfer=True):
    _schema(m, load_json(Path(__file__).with_name('manifest.schema.json')))
    for field in ('artifact_id','version','filename','profile','provider_id'):
        safe_component(m[field])
    safe_key(m['object_key'])
    if m['object_key'] != object_key(m):
        raise DistributionError('object_identity_mismatch')
    if m['required'] == m['optional']:
        raise DistributionError('required_optional_conflict')
    lo, hi = m['compatibility']['min_aurorafox_version'], m['compatibility']['max_aurorafox_version']
    if hi is not None and tuple(map(int, lo.split('.'))) > tuple(map(int, hi.split('.'))):
        raise DistributionError('compatibility_order')
    if m['resources']['recommended_ram'] < m['resources']['minimum_ram']:
        raise DistributionError('resource_order')
    if m['resources']['minimum_disk'] < m['bytes']:
        raise DistributionError('disk_contract')
    for ref in m['dependencies'] + [r for r in (m['previous_known_good'],m['rollback_target']) if r]:
        safe_key(ref)
        if ref == m['object_key']:
            raise DistributionError('self_reference')
    # URLs are public provenance only: no credentials, query tokens or fragments.
    from urllib.parse import urlsplit
    for url in m['source']['urls']:
        p = urlsplit(url)
        if p.scheme != 'https' or not p.hostname or p.username or p.password or p.query or p.fragment:
            raise DistributionError('unsafe_provenance_url')
    if m['status'] == 'EXTERNAL_ARTIFACT_PENDING':
        if transfer or m['chunks'] or m['signature'] is not None:
            raise DistributionError('external_artifact_pending')
        return m
    offset = 0
    for index, chunk in enumerate(m['chunks']):
        if chunk['index'] != index or chunk['offset'] != offset or chunk['bytes'] != min(m['part_size'],m['bytes']-offset):
            raise DistributionError('chunk_coverage')
        offset += chunk['bytes']
    if offset != m['bytes'] or not m['chunks']:
        raise DistributionError('chunk_coverage')
    return m


def signed_payload(m):
    return canonical({k:v for k,v in m.items() if k != 'signature'})


def sign(m, private_key, key_id):
    validate(m)
    result = dict(m)
    result['signature'] = {'algorithm':'Ed25519','key_id':safe_component(key_id),
                           'value':base64.b64encode(private_key.sign(signed_payload(m))).decode('ascii')}
    return result


def verify_signature(m, trusted_keys):
    validate(m)
    signature = m['signature']
    if signature is None or signature['key_id'] not in trusted_keys:
        raise DistributionError('untrusted_manifest')
    try:
        trusted_keys[signature['key_id']].verify(base64.b64decode(signature['value'],validate=True),signed_payload(m))
    except Exception:
        raise DistributionError('invalid_signature') from None
    return m


def file_digest(path):
    h = hashlib.sha256()
    size = 0
    with open(path,'rb') as stream:
        for data in iter(lambda:stream.read(1024*1024), b''):
            h.update(data)
            size += len(data)
    return size, h.hexdigest()


def verify_file(path, size, digest):
    if file_digest(path) != (size,digest):
        raise DistributionError('artifact_integrity')


def describe(path, metadata, part_size=4*1024*1024):
    if type(part_size) is not int or not 1 <= part_size <= 16*1024*1024:
        raise DistributionError('invalid_part_size')
    m = dict(metadata)
    m['filename'] = Path(path).name
    m['bytes'],m['sha256'] = file_digest(path)
    m['part_size'],m['chunks'],m['signature'],m['status'] = part_size,[],None,'READY'
    with open(path,'rb') as stream:
        offset = 0
        for index,data in enumerate(iter(lambda:stream.read(part_size), b'')):
            m['chunks'].append({'index':index,'offset':offset,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
            offset += len(data)
    m['object_key'] = object_key(m)
    return validate(m)
