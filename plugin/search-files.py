#!/usr/bin/env python3
"""Bounded, local filename search; never traverses hidden or dependency folders."""
import json, os, sys, time
from pathlib import Path
query=(sys.argv[1] if len(sys.argv)>1 else '').casefold().strip()
home=Path.home()
roots=[home/n for n in ('Desktop','Documents','Downloads','Pictures','Music','Videos')]
blocked={'node_modules','vendor','target','build','dist','__pycache__','.git','.cache'}
rows=[]; started=time.monotonic(); scanned=0
for root in roots:
    if not root.is_dir(): continue
    for base,dirs,files in os.walk(root,followlinks=False):
        dirs[:]=[d for d in dirs if not d.startswith('.') and d not in blocked]
        if len(Path(base).relative_to(root).parts)>=5: dirs[:]=[]
        for name in dirs+files:
            scanned+=1
            if name.startswith('.') or (query and query not in name.casefold()): continue
            p=Path(base)/name
            if not query and p.parent!=root: continue
            rows.append({'name':name,'path':str(p),'folder':p.is_dir(),
                         'detail':str(p.parent).replace(str(home),'~',1)})
        if len(rows)>=300 or scanned>=30000 or time.monotonic()-started>1.2: break
    if len(rows)>=300 or scanned>=30000 or time.monotonic()-started>1.2: break
rows.sort(key=lambda r:(not r['name'].casefold().startswith(query),r['name'].casefold()))
print(json.dumps(rows[:80]))
