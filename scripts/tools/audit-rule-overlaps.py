#!/usr/bin/env python3
from __future__ import annotations
import argparse, ipaddress, json
from collections import defaultdict
from pathlib import Path
from domain_rules import compact_domain_rules, parse_classical_domain_file
from ip_rules import parse_classical_ip_file
from platform_capabilities import load_platform_capabilities


def domain_audit(root: Path):
    owners=defaultdict(list); lists={}; internal={}
    for path in sorted(root.glob('*.list')):
        rules,errors=parse_classical_domain_file(path,allow_single_label_suffix=True)
        if errors: raise ValueError('\n'.join(errors))
        compacted,removed=compact_domain_rules(rules)
        if removed: internal[path.stem]=removed
        keys={(r.kind,r.value) for r in compacted}; lists[path.stem]=len(keys)
        for key in keys: owners[key].append(path.stem)
    pairs=defaultdict(int)
    for names in owners.values():
        for i,a in enumerate(names):
            for b in names[i+1:]: pairs[(a,b)]+=1
    top=[{'left':a,'right':b,'exact_rules':n} for (a,b),n in sorted(pairs.items(),key=lambda x:(-x[1],x[0]))[:100]]
    return {'lists':len(lists),'rules':sum(lists.values()),'internal_redundancy':internal,'top_exact_overlaps':top}


def ip_audit(root: Path):
    lists={}; internal={}; owners=defaultdict(list)
    for path in sorted(root.glob('*.list')):
        rules,errors=parse_classical_ip_file(path,require_canonical=True)
        if errors: raise ValueError('\n'.join(errors))
        values=[ipaddress.ip_network(r.value) for r in rules]
        compact=[]
        for version in (4,6): compact.extend(ipaddress.collapse_addresses(n for n in values if n.version==version))
        if len(values)!=len(compact): internal[path.stem]=len(values)-len(compact)
        keys={str(n) for n in compact}; lists[path.stem]=len(keys)
        for key in keys: owners[key].append(path.stem)
    pairs=defaultdict(int)
    for names in owners.values():
        for i,a in enumerate(names):
            for b in names[i+1:]: pairs[(a,b)]+=1
    top=[{'left':a,'right':b,'exact_prefixes':n} for (a,b),n in sorted(pairs.items(),key=lambda x:(-x[1],x[0]))[:100]]
    return {'lists':len(lists),'prefixes':sum(lists.values()),'internal_redundancy':internal,'top_exact_overlaps':top}


def platform_loss_audit(root: Path):
    capabilities = load_platform_capabilities().platforms
    by_platform = {
        name: {'unsupported_rules': 0, 'affected_lists': 0, 'by_kind': {}}
        for name in capabilities
    }
    for path in sorted((root / 'domain').glob('*.list')):
        rules, errors = parse_classical_domain_file(path, allow_single_label_suffix=True)
        if errors: raise ValueError('\n'.join(errors))
        for platform, capability in capabilities.items():
            counts = defaultdict(int)
            for rule in rules:
                if rule.kind in capability.domain.unsupported_kinds:
                    counts[rule.kind] += 1
            if counts:
                entry = by_platform[platform]
                entry['affected_lists'] += 1
                entry['unsupported_rules'] += sum(counts.values())
                for kind, count in counts.items():
                    entry['by_kind'][kind] = entry['by_kind'].get(kind, 0) + count
    return by_platform


def main():
    p=argparse.ArgumentParser(description='Audit canonical rule-set redundancy and cross-list overlap.')
    p.add_argument('canonical_root');p.add_argument('--output',required=True);p.add_argument('--fail-internal',action='store_true')
    a=p.parse_args();root=Path(a.canonical_root)
    result={
        'schema_version':1,
        'domain':domain_audit(root/'domain'),
        'ip':ip_audit(root/'ip'),
        'platform_conversion_losses':platform_loss_audit(root),
    }
    out=Path(a.output);out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(result,ensure_ascii=False,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    print(f"overlap audit: domain_lists={result['domain']['lists']} ip_lists={result['ip']['lists']} domain_internal={sum(result['domain']['internal_redundancy'].values())} ip_internal={sum(result['ip']['internal_redundancy'].values())}")
    if a.fail_internal and (result['domain']['internal_redundancy'] or result['ip']['internal_redundancy']): return 1
    return 0
if __name__=='__main__': raise SystemExit(main())
