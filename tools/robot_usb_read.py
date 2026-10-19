#!/usr/bin/env python3
"""Run an explicitly supplied read-only shell command on the robot USB console."""
import argparse, os, select, termios, time, uuid
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--quiet',action='store_true');p.add_argument('command');p.add_argument('--output',required=True);p.add_argument('--timeout',type=float,default=30);p.add_argument('--port',default='/dev/cu.usbmodem144202');args=p.parse_args()
fd=os.open(args.port,os.O_RDWR|os.O_NOCTTY|os.O_NONBLOCK)
a=termios.tcgetattr(fd);a[0]=0;a[1]=0;a[2]=termios.CS8|termios.CREAD|termios.CLOCAL;a[3]=0;a[4]=termios.B115200;a[5]=termios.B115200;a[6][termios.VMIN]=0;a[6][termios.VTIME]=0;termios.tcsetattr(fd,termios.TCSANOW,a)
def read_until_idle(seconds=1):
 end=time.monotonic()+seconds;out=b''
 while time.monotonic()<end:
  if select.select([fd],[],[],.1)[0]:
   b=os.read(fd,65536);out+=b
   if b'\x1b[6n' in b:os.write(fd,b'\x1b[24;80R')
 return out
os.write(fd,b'\x1b[24;80R\r');pre=read_until_idle()
marker='USB_DONE_'+uuid.uuid4().hex
wire='HISTFILE=; set +o history; '+args.command+"; printf '\\n"+marker+":%s\\n' \"$?\"\r"
encoded=wire.encode()
for pos in range(0,len(encoded),256):
 chunk=encoded[pos:pos+256]
 while chunk:
  select.select([],[fd],[],1)
  try:written=os.write(fd,chunk)
  except BlockingIOError:continue
  chunk=chunk[written:]
 time.sleep(.01)
data=b'';end=time.monotonic()+args.timeout
while time.monotonic()<end:
 if select.select([fd],[],[],.2)[0]:
  b=os.read(fd,65536);data+=b
  if b'\x1b[6n' in b:os.write(fd,b'\x1b[24;80R')
  if (b'\n'+marker.encode()+b':') in data:break
else:
 Path(args.output).write_bytes(pre+data);os.close(fd);raise SystemExit('Timed out; partial output saved')
Path(args.output).write_bytes(pre+data);os.close(fd)
if not args.quiet:print(data.decode(errors='replace'))
