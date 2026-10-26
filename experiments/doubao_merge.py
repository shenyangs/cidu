"""Local experiment, not a supported live writer. Never logs dictionary contents.
Codec layout corroborated against MIT ime-lexicon; see THIRD_PARTY.md.
"""
from pathlib import Path
import struct, json, collections, re, time, os
PRIVATE=Path(os.environ.get('CIDU_EXPERIMENT_DIR', str(Path.home()/'Library/Application Support/Cidu/live-merge')))

def parse(b):
 h=list(struct.unpack_from('<16I',b)); assert h[:3]==[12001,20230630,64]
 assert h[3]==len(b) and h[7]==h[8]*4 and h[10]==h[6]+h[7] and h[10]+h[11]==len(b)
 offsets=struct.unpack_from('<%dI'%h[8],b,h[6]); assert not any(offsets[h[9]:])
 out=[]
 # Offset zero IS valid inside the contiguous used index, unlike community reader.
 for slot,off in enumerate(offsets[:h[9]]):
  p=h[10]+off; attrs=struct.unpack_from('<4I',b,p); sl=struct.unpack_from('<H',b,p+16)[0]
  assert sl and sl%2==0
  syll=struct.unpack_from('<%dH'%(sl//2),b,p+18); key=b[p+18:p+18+sl]
  plen=struct.unpack_from('<H',b,p+18+sl)[0]; q=p+20+sl; end=q+plen
  assert end<=len(b)
  pyl=struct.unpack_from('<H',b,q)[0]; py=bytes((((v>>5)|(v<<3))&255)^0xa5 for v in b[q+2:q+2+pyl]).decode('utf8')
  wn=struct.unpack_from('<H',b,q+2+pyl)[0]; assert plen==4+pyl+wn*2
  wd=b[q+4+pyl:end]; wd=b''.join(struct.pack('<H',(((v>>9)|(v<<7))&65535)^0x65c9) for (v,) in struct.iter_unpack('<H',wd)).decode('utf-16le')
  assert wd and py
  out.append(dict(word=wd,pinyin=py,syll=syll,key=key,attrs=attrs,raw=b[p:end],off=off,end=end-h[10],slot=slot))
 assert len(set(offsets[:h[9]]))==h[9]
 return h,out

def source():
 return json.loads((PRIVATE.parent/'词渡-完整档案.json').read_text())['entries']

def encode(word,py,syll,attrs):
 p=py.encode('utf8');w=word.encode('utf-16le')
 ep=bytes((((v^0xa5)<<5)|((v^0xa5)>>3))&255 for v in p)
 ew=b''.join(struct.pack('<H',(((v^0x65c9)<<9)|((v^0x65c9)>>7))&65535) for (v,) in struct.iter_unpack('<H',w))
 payload=struct.pack('<H',len(p))+ep+struct.pack('<H',len(w)//2)+ew
 assert len(payload)<65536 and len(syll)*2<65536
 return struct.pack('<4IH',*attrs,len(syll)*2)+struct.pack('<%dH'%len(syll),*syll)+struct.pack('<H',len(payload))+payload

def build():
 import os
 os.umask(0o077)
 original=(PRIVATE/'initial-usr.dat').read_bytes();h,items=parse(original);src=source()
 native=json.loads((PRIVATE/'native-map.json').read_text())
 mapping={k:v[1] for k,v in native.items() if v[0]}
 def codes(e):
  result=[]
  for s in e['syllables']:
   s=s.lower()
   if s in mapping:result.append(mapping[s])
   else:
    assert all(c in 'abcdefghijklmnopqrstuvwxyz0123456789' for c in s)
    result.extend((ord(c)-97+10) if c.isalpha() else int(c) for c in s)
  return tuple(result)
 existing={(i['word'],i['syll']) for i in items}
 data=bytearray(original[h[10]:h[10]+h[12]])
 added=[];fallback=[];overlap=0;now=int(time.time());pt=max(i['attrs'][1] for i in items)
 for e in src:
  syll=codes(e);py=''.join(e['syllables']).lower()
  if (e['word'],syll) in existing:overlap+=1;continue
  if any(s.lower() not in mapping for s in e['syllables']):fallback.append(e)
  raw=encode(e['word'],py,syll,(1,pt,now,0));off=len(data);data.extend(raw)
  added.append(dict(word=e['word'],pinyin=py,syll=syll,raw=raw,off=off));existing.add((e['word'],syll))
 merged=sorted(items+added,key=lambda i:i['syll']);slots=max(h[8],((len(merged)+9999)//10000)*10000)
 cursor=len(data);data.extend(bytes(max(65536,len(data)//5)))
 h[7]=slots*4;h[8]=slots;h[9]=len(merged);h[10]=h[6]+h[7];h[11]=len(data);h[12]=cursor;h[3]=h[10]+h[11]
 out=struct.pack('<16I',*h)+original[64:h[6]]+struct.pack('<%dI'%slots,*([i['off'] for i in merged]+[0]*(slots-len(merged))))+data
 _,check=parse(out);keys={(i['word'],i['syll']) for i in check}
 assert all((e['word'],codes(e)) in keys for e in src)
 by_offset={c['off']:c for c in check}
 assert all(i['raw']==by_offset[i['off']]['raw'] for i in items)
 (PRIVATE/'merged-usr.dat').write_bytes(out)
 (PRIVATE/'fallback-entries.json').write_text(json.dumps(fallback,ensure_ascii=False))
 stats={'source':len(src),'original':len(items),'overlap':overlap,'added':len(added),'merged':len(check),'index_slots':slots,'fallback_entries':len(fallback),'all_source_present':True,'original_records_unchanged':True}
 (PRIVATE/'merge-report.json').write_text(json.dumps(stats,indent=2));print(json.dumps(stats))

def analyze():
 h,items=parse((PRIVATE/'initial-usr.dat').read_bytes()); src=source()
 groups=collections.defaultdict(list)
 for it in items: groups[(it['word'],it['pinyin'].lower().replace("'",''))].append(it)
 votes=collections.defaultdict(collections.Counter); matched=0
 for e in src:
  parts=[s.lower() for s in e['syllables']]
  for it in groups.get((e['word'],''.join(parts)),[]):
   if len(parts)==len(it['syll']):
    matched+=1
    for s,sid in zip(parts,it['syll']): votes[s][sid]+=1
 mapping={s:c.most_common(1)[0][0] for s,c in votes.items() if len(c)==1}
 missing=collections.Counter(s.lower() for e in src for s in e['syllables'] if s.lower() not in mapping)
 print(json.dumps({'parsed':len(items),'zero_record_valid':any(i['off']==0 for i in items),'cursor':h[12],'max_record_end':max(i['end'] for i in items),'raw_bytes_sorted':all(a['key']<=b['key'] for a,b in zip(items,items[1:])),'numeric_syll_sorted':all(a['syll']<=b['syll'] for a,b in zip(items,items[1:])),'matched':matched,'mapping_count':len(mapping),'conflicting_syllables':{s:dict(c) for s,c in votes.items() if len(c)>1},'missing_syllables':missing,'attributes':{k:collections.Counter(i['attrs'][n] for i in items).most_common(6) for n,k in enumerate(['freq','ptime','stamp','flags'])}},ensure_ascii=False))
 (PRIVATE/'syll-map.json').write_text(json.dumps(mapping));(PRIVATE/'syll-map.json').chmod(0o600)

if __name__=='__main__':
 import sys
 build() if '--build' in sys.argv else analyze()
