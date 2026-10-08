#!/bin/zsh
# run.sh <mode>: put a clipboard, paste it into the local page in Chrome
./put $1 >/dev/null
perl -e 'alarm 60; exec @ARGV' node cdp.mjs 9334 file://$PWD/index.html 2>&1 | python3 -c "
import sys,json;t=sys.stdin.read();i=t.find('[\n');print(t[:i if i>=0 else 600])
recs=json.loads(t[i:]) if i>=0 else []
for r in recs:
  l=r.get('landed',{})
  print(r['box'],'types',r['types'],'files',[f['type'] for f in r['files']],'text',repr(r['textPlain'][:50]),'landed imgs',l.get('images'),'text',repr(l.get('text','')[:50]))"
