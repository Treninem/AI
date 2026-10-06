"""Pure future bootstrap planner, not called by V1.5 installer/runtime."""
from .manifest import DistributionError, verify_signature


def plan(manifests,trusted_keys,hardware,version,profile,capabilities=()):
    import re
    if not isinstance(version,str) or not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+',version):
        raise DistributionError('invalid_client_version')
    if any(type(hardware.get(k)) is not int or hardware[k] < 0 for k in ('ram','vram','free_disk')):
        raise DistributionError('invalid_hardware')
    current = tuple(map(int,version.split('.')))
    if len(current) != 4:
        raise DistributionError('invalid_client_version')
    selected = []
    for m in manifests:
        verify_signature(m,trusted_keys)
        c,r = m['compatibility'],m['resources']
        lo = tuple(map(int,c['min_aurorafox_version'].split('.')))
        hi = tuple(map(int,c['max_aurorafox_version'].split('.'))) if c['max_aurorafox_version'] else None
        eligible = (lo <= current and (hi is None or current <= hi)
            and (hardware['platform'] in c['platform'] or 'any' in c['platform'])
            and (hardware['architecture'] in c['architecture'] or 'any' in c['architecture'])
            and hardware['ram'] >= r['minimum_ram'] and hardware['vram'] >= r['vram_requirement'])
        selected_profile = profile.get(m['artifact_type']) if isinstance(profile,dict) else profile
        wanted = m['profile'] == selected_profile and (m['required'] or bool(set(m['capabilities']) & set(capabilities)))
        if wanted:
            if not eligible:
                if m['optional']:
                    continue
                raise DistributionError('required_profile_incompatible')
            selected.append(m)
    keys = {m['object_key'] for m in selected}
    if len(keys) != len(selected):
        raise DistributionError('duplicate_bootstrap_artifact')
    available = {c for m in selected for c in m['capabilities']}
    if not {'core.chat','knowledge.retrieve'} <= available:
        raise DistributionError('usable_local_baseline_missing')
    # Dependency order is explicit and cycles/missing dependencies fail closed.
    ordered = []
    remaining = list(selected)
    while remaining:
        ready = [m for m in remaining if set(m['dependencies']) <= {x['object_key'] for x in ordered}]
        if not ready:
            raise DistributionError('bootstrap_dependency_missing_or_cycle')
        for m in sorted(ready,key=lambda x:x['object_key']):
            ordered.append(m)
            remaining.remove(m)
    disk = sum(2*m['bytes'] + m['resources']['minimum_disk'] for m in ordered)
    if hardware['free_disk'] < disk:
        raise DistributionError('insufficient_disk')
    return {'profile':profile,'artifacts':[m['object_key'] for m in ordered],
            'reserved_disk':disk,'offline_after_download':True,'normal_launch_requires_verified_baseline':True}
