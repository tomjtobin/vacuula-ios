#!/usr/bin/env python3
"""Inspect a local FAT16/FAT32 image and extract root-directory verification-key blobs."""
import argparse,hashlib,json,struct
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('image');p.add_argument('--output',required=True);a=p.parse_args();b=Path(a.image).read_bytes();dest=Path(a.output);dest.mkdir(parents=True,exist_ok=True)
u16=lambda pos:struct.unpack_from('<H',b,pos)[0]
u32=lambda pos:struct.unpack_from('<I',b,pos)[0]
bps=u16(11);spc=b[13];reserved=u16(14);nfats=b[16];nroot=u16(17);spf=u16(22);fat32=spf==0
if fat32:spf=u32(36)
fat=reserved*bps;root=(reserved+nfats*spf)*bps;rootlen=((nroot*32+bps-1)//bps)*bps;data=root+rootlen;clustersize=bps*spc

def chain(cluster):
 parts=[];seen=set();limit=0x0ffffff8 if fat32 else 0xfff8
 while 2<=cluster<limit:
  if cluster in seen:raise RuntimeError('Cluster cycle')
  seen.add(cluster);start=data+(cluster-2)*clustersize;parts.append(b[start:start+clustersize]);cluster=(u32(fat+cluster*4)&0x0fffffff) if fat32 else u16(fat+cluster*2)
 return b''.join(parts)
rootbytes=chain(u32(44)) if fat32 else b[root:root+rootlen]
lfn=[];result=[]
for pos in range(0,len(rootbytes),32):
 e=rootbytes[pos:pos+32]
 if not e[0]:break
 if e[0]==0xe5:lfn=[];continue
 if e[11]==0x0f:lfn.insert(0,e[1:11]+e[14:26]+e[28:32]);continue
 name=(b''.join(lfn).decode('utf-16le').split('\x00')[0].rstrip('\uffff') if lfn else e[:8].decode().rstrip()+('.'+e[8:11].decode().rstrip() if e[8:11].strip() else ''));lfn=[]
 if e[11]&0x18:continue
 size=struct.unpack_from('<I',e,28)[0];cluster=struct.unpack_from('<H',e,26)[0]
 if fat32:cluster|=struct.unpack_from('<H',e,20)[0]<<16
 content=chain(cluster)[:size]
 if len(content)!=size:raise RuntimeError('Truncated file')
 result.append(dict(name=name,size=size,sha256=hashlib.sha256(content).hexdigest()))
 if name in ('swu-pubk.pem.enc','key_blob.enc'):(dest/name).write_bytes(content)
(dest/'root-files.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
