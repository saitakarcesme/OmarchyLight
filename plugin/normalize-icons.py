#!/usr/bin/env python3
"""Remove transparent margins from installed originals; do not redraw brands."""
import hashlib,json,subprocess,sys
from pathlib import Path
from urllib.parse import urlparse,unquote
cache=Path.home()/'.cache/omarchylight/icons';cache.mkdir(parents=True,exist_ok=True)
result={}
for raw in json.loads(sys.argv[1]):
 try:
  p=Path(unquote(urlparse(raw).path));st=p.stat()
  key=hashlib.sha256(f'{p}:{st.st_mtime_ns}:{st.st_size}:1'.encode()).hexdigest()[:24]
  target=cache/(key+'.png')
  if not target.exists():
   subprocess.run(['magick','-background','none',str(p),'-bordercolor','none','-border','1','-trim','+repage','-resize','128x128',str(target)],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,timeout=10)
  result[raw]=target.as_uri()
 except (OSError,subprocess.SubprocessError):pass
print(json.dumps(result))
