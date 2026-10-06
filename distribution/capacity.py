"""Deterministic report-only retention. There is deliberately no delete API."""
from .manifest import DistributionError


def report(objects,metadata,*,total=10_000_000_000,threshold=0.75):
    if type(total) is not int or total <= 0 or not 0.70 <= threshold <= 0.75:
        raise DistributionError('invalid_capacity_policy')
    seen = set()
    used = 0
    artifacts = []
    for obj in sorted(objects,key=lambda x:x['object_key']):
        key = obj['object_key']
        if key in seen or type(obj['bytes']) is not int or obj['bytes'] < 0:
            raise DistributionError('invalid_inventory')
        seen.add(key)
        used += obj['bytes']
        info = metadata.get(key,{})
        protected = any(info.get(k,False) for k in ('stable','previous_known_good','release_required','rollback_required','active_candidate'))
        status = info.get('status','unknown')
        prune = not protected and status in {'abandoned','expired','unreferenced','superseded'}
        artifacts.append({'object_key':key,'id':info.get('id'),'version':info.get('version'),
            'bytes':obj['bytes'],'status':status,'required_for_rollback':bool(info.get('rollback_required') or info.get('previous_known_good')),
            'safe_to_prune':prune})
    return {'total':total,'used':used,'free':max(0,total-used),'percentage':100*used/total,
        'over_capacity':used>total,'review_required':used/total>=threshold,'threshold':threshold,
        'dry_run':True,'artifacts':artifacts}
