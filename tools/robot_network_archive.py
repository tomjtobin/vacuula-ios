#!/usr/bin/env python3
"""Use USB root shell to stream a read-only tar backup to a temporary Mac LAN listener."""
import argparse,hashlib,json,re,secrets,shlex,socket,subprocess,sys,time
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--output',required=True);p.add_argument('--host',required=True);p.add_argument('--device');p.add_argument('tar_args',nargs=argparse.REMAINDER);a=p.parse_args();args=a.tar_args
if args and args[0]=='--':args=args[1:]
out=Path(a.output);partial=Path(str(out)+'.partial');token=secrets.token_hex(32)
server=socket.socket();server.bind((a.host,0));server.listen(1);server.settimeout(30);port=server.getsockname()[1]
remote="""import socket,subprocess,hashlib,json
s=socket.create_connection((HOST,PORT),15);s.sendall(TOKEN.encode()+b'\\n')
p=subprocess.Popen(TAR,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
h=hashlib.sha256();n=0
while True:
 b=p.stdout.read(262144)
 if not b:break
 h.update(b);n+=len(b);s.sendall(b)
s.close();err=p.stderr.read();rc=p.wait()
print('ARCHIVE_RESULT '+json.dumps(dict(sha256=h.hexdigest(),bytes=n,tar_exit=rc,stderr=err.decode(errors='replace'))))
""".replace('HOST',repr(a.host)).replace('PORT',str(port)).replace('TOKEN',repr(token)).replace('TAR',repr(['tar','-czf','-']+args))
if a.device:
 remote="""import socket,zlib,hashlib,json
s=socket.create_connection((HOST,PORT),15);s.sendall(TOKEN.encode()+b'\\n')
c=zlib.compressobj(1,zlib.DEFLATED,31);h=hashlib.sha256();rawhash=hashlib.sha256();n=0;rawbytes=0
def send(b):
 global n
 if b:h.update(b);n+=len(b);s.sendall(b)
with open(DEVICE,'rb',buffering=0) as f:
 while True:
  b=f.read(1048576)
  if not b:break
  rawhash.update(b);rawbytes+=len(b);send(c.compress(b))
send(c.flush());s.close()
print('ARCHIVE_RESULT '+json.dumps(dict(sha256=h.hexdigest(),bytes=n,tar_exit=0,stderr='',source_bytes=rawbytes,source_sha256=rawhash.hexdigest())))
""".replace('HOST',repr(a.host)).replace('PORT',str(port)).replace('TOKEN',repr(token)).replace('DEVICE',repr(a.device))
# repr wraps the source into one physical shell line.
command='python3 -c '+shlex.quote('exec('+repr(remote)+')')
transcript=str(out)+'.serial.txt'
proc=subprocess.Popen([sys.executable,str(Path(__file__).with_name('robot_usb_read.py')),command,'--output',transcript,'--timeout','1800'],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
h=hashlib.sha256();n=0;last=time.monotonic()
try:
 conn,peer=server.accept();conn.settimeout(120)
 with conn,partial.open('xb') as f:
  handshake=b''
  while not handshake.endswith(b'\n'):
   b=conn.recv(1)
   if not b:raise RuntimeError('EOF before token')
   handshake+=b
   if len(handshake)>65:raise RuntimeError('Bad token')
  if handshake!=token.encode()+b'\n':raise RuntimeError('Bad token')
  while True:
   b=conn.recv(1048576)
   if not b:break
   f.write(b);h.update(b);n+=len(b)
   if time.monotonic()-last>15:print(f'{n/1048576:.1f} MiB received',flush=True);last=time.monotonic()
 stdout,stderr=proc.communicate(timeout=60)
 if proc.returncode:raise RuntimeError(stderr.decode())
 matches=re.findall(r'^ARCHIVE_RESULT (\{.*\})\r?$',stdout.decode(),re.M)
 if not matches:raise RuntimeError('No source result: '+stdout.decode())
 m=json.loads(matches[-1]);m.update(local_sha256=h.hexdigest(),local_bytes=n,tar_args=args,device=a.device,transport='USB-commanded TCP stream',peer=peer[0])
 Path(str(out)+'.json').write_text(json.dumps(m,indent=2)+'\n')
 if not n or m['sha256']!=h.hexdigest() or m['bytes']!=n or m['tar_exit'] != 0:raise RuntimeError('Archive failed: '+str(m))
 partial.rename(out);print(json.dumps(m,indent=2))
finally:server.close()
