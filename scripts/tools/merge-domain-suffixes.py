#!/usr/bin/env python3
from __future__ import annotations
import argparse
from pathlib import Path
from domain_rules import domain_value_errors, parse_classical_domain_file

_TERMINAL = ""

class SuffixTrie:
    def __init__(self, values=()):
        self.root: dict = {}
        for value in values: self.add(value)

    def covers(self, value: str) -> bool:
        node = self.root
        for label in reversed(value.split('.')):
            if _TERMINAL in node: return True
            node = node.get(label)
            if node is None: return False
        return _TERMINAL in node

    def add(self, value: str) -> None:
        node = self.root
        for label in reversed(value.split('.')):
            if _TERMINAL in node: return
            node = node.setdefault(label, {})
        node.clear(); node[_TERMINAL] = True

def load_plain(path: Path) -> tuple[list[str], int]:
    values=set(); invalid=0
    for raw in path.read_text(encoding='utf-8').splitlines():
        value=raw.split('#',1)[0].strip().lower().rstrip('.')
        if not value: continue
        if domain_value_errors('DOMAIN-SUFFIX',value,require_canonical=True): invalid+=1; continue
        values.add(value)
    return sorted(values,key=lambda x:(x.count('.'),x)),invalid

def merge_target(target: Path, candidates: list[str]) -> tuple[int,int]:
    rules,errors=parse_classical_domain_file(target,require_canonical=True,allow_single_label_suffix=True)
    if errors: raise ValueError('\n'.join(errors))
    trie=SuffixTrie(r.value for r in rules if r.kind=='DOMAIN-SUFFIX')
    additions=[]
    for value in candidates:
        if trie.covers(value): continue
        trie.add(value); additions.append(value)
    target.write_text('\n'.join([r.text for r in rules]+[f'DOMAIN-SUFFIX,{x}' for x in additions])+'\n',encoding='utf-8')
    return len(additions),len(candidates)-len(additions)

def main() -> int:
    p=argparse.ArgumentParser(description='Merge a plain domain suffix source into classical rule files in one pass.')
    p.add_argument('plain_source');p.add_argument('targets',nargs='+');p.add_argument('--normalized-output')
    a=p.parse_args();candidates,invalid=load_plain(Path(a.plain_source))
    if a.normalized_output:
        Path(a.normalized_output).write_text('\n'.join(f'DOMAIN-SUFFIX,{x}' for x in candidates)+'\n',encoding='utf-8')
    print(f'candidate={len(candidates)} invalid={invalid}')
    for name in a.targets:
        added,covered=merge_target(Path(name),candidates)
        print(f'target={name} added={added} covered_or_duplicate={covered}')
    return 0
if __name__=='__main__':raise SystemExit(main())
