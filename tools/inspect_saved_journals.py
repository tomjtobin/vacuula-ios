#!/usr/bin/env python3
"""Read legacy non-compact systemd journal objects offline; extract boot/hardware evidence.
Supports uncompressed and XZ DATA objects. Does not authenticate journal sealing.
"""
from pathlib import Path
import argparse,struct,lzma,json,collections,datetime,re
from zoneinfo import ZoneInfo
p=argparse.ArgumentParser();p.add_argument('directory');p.add_argument('--output',required=True);a=p.parse_args();out=Path(a.output);out.mkdir(parents=True,exist_ok=True)
boots={};selected=[];errors=[];files=[]
pattern=re.compile(r'Linux version|Memory:|Machine model|CPU:|CPU[0-9]:|MHz|secure.?boot|hab[_ :]|fuse|ocotp|imx|mmcblk|mmc[0-9]:|op-tee|DDR|Bluetooth|qca|ath10k|wlan|spi|i2c|clock|cpu[ -]freq|cpufreq|LPC51|Revision|RAM',re.I)
for path in sorted(Path(a.directory).rglob('*')):
 if not path.is_file():continue
 b=path.read_bytes()
 if b[:8]!=b'LPKSHHRH':continue
 incompatible=struct.unpack_from('<I',b,12)[0]
 if incompatible & ~1:errors.append(dict(file=str(path),error='Unsupported journal flags '+hex(incompatible)));continue
 pos=struct.unpack_from('<Q',b,88)[0];data={};entries=[];counts=collections.Counter()
 while pos+16<=len(b):
  kind,flags=struct.unpack_from('<BB',b,pos);size=struct.unpack_from('<Q',b,pos+8)[0]
  if not size:break
  if size<16 or pos+size>len(b):errors.append(dict(file=str(path),offset=pos,error='Invalid object bounds'));break
  counts[kind]+=1
  if kind==1:
   payload=b[pos+64:pos+size]
   try:
    if flags==1:payload=lzma.decompress(payload)
    elif flags:raise ValueError('Unsupported compression '+str(flags))
    data[pos]=payload.decode(errors='replace')
   except Exception as e:errors.append(dict(file=str(path),offset=pos,error=str(e)))
  elif kind==3 and size>=64:entries.append((pos,size))
  pos+=(size+7)&~7
 files.append(dict(file=str(path),objects=dict(counts),entries=len(entries)))
 for pos,size in entries:
  seq,real,mono=struct.unpack_from('<QQQ',b,pos+16);boot=b[pos+40:pos+56].hex();fields={}
  for item in range(pos+64,pos+size,16):
   if item+16>pos+size:break
   value=data.get(struct.unpack_from('<Q',b,item)[0])
   if value and '=' in value:
    key,val=value.split('=',1);fields[key]=val
  dt=datetime.datetime.fromtimestamp(real/1e6,ZoneInfo('America/Los_Angeles')).isoformat()
  summary=boots.setdefault(boot,dict(entries=0,first_realtime=dt,last_realtime=dt,min_monotonic_us=mono,max_monotonic_us=mono,kernel_entries=0))
  summary['entries']+=1;summary['first_realtime']=min(summary['first_realtime'],dt);summary['last_realtime']=max(summary['last_realtime'],dt);summary['min_monotonic_us']=min(summary['min_monotonic_us'],mono);summary['max_monotonic_us']=max(summary['max_monotonic_us'],mono)
  message=fields.get('MESSAGE','');kernel=fields.get('_TRANSPORT')=='kernel' or fields.get('SYSLOG_IDENTIFIER')=='kernel'
  if kernel:summary['kernel_entries']+=1
  if kernel or pattern.search(message):selected.append(dict(file=str(path),offset=pos,boot_id=boot,realtime=dt,monotonic_us=mono,kernel=kernel,fields=fields))
(out/'journal-boot-summary.json').write_text(json.dumps(dict(boots=boots,files=files,errors=errors),indent=2)+'\n')
with (out/'boot-hardware-entries.jsonl').open('w') as f:
 for entry in selected:f.write(json.dumps(entry)+'\n')
print(json.dumps(dict(boots=boots,selected_entries=len(selected),errors=len(errors)),indent=2))
