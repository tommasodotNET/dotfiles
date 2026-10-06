#!/usr/bin/python3 -I
"""Accepted-risk fixed-uplink VPN only. No shell evaluation or route replacement."""
import os,sys,json,pathlib,subprocess,ipaddress,fcntl,re
C=pathlib.Path('/etc/NetworkManager/dotfiles-azure-vpn.json')
S=pathlib.Path('/run/dotfiles-azure-vpn')
def run(a,check=True):
 return subprocess.run(a,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,check=check)
def routes():return json.loads(run(['/usr/sbin/ip','-j','-4','route','show','table','main']).stdout)
def command(r,verb):return ['/usr/sbin/ip','-4','route',verb,r['dst'],'table','main','via',r['gateway'],'dev',r['dev'],'proto','197','metric','0']
def exact(a,b):
 # ip -j emits host destinations without /32; compare canonical networks.
 try:
  if ipaddress.ip_network(a.get('dst',''),strict=False)!=ipaddress.ip_network(b.get('dst',''),strict=False):return False
 except ValueError:return False
 return all(str(a.get(k,0 if k=='metric' else ''))==str(v) for k,v in b.items() if k!='dst')
def save(rows):
 t=S/'journal.tmp';t.write_text(json.dumps(rows));t.chmod(0o600);os.replace(t,S/'journal.json')
def main():
 if os.geteuid()!=0:return 1
 c=json.loads(C.read_text())
 if os.environ.get('CONNECTION_UUID')!=c['uuid']:return 0
 action=sys.argv[2] if len(sys.argv)>2 else ''
 if action not in ('vpn-up','vpn-down'):return 0
 os.umask(0o077);S.mkdir(mode=0o700,exist_ok=True)
 with (S/'lock').open('w') as lock:
  fcntl.flock(lock,fcntl.LOCK_EX)
  j=S/'journal.json';owned=json.loads(j.read_text()) if j.exists() else []
  if action=='vpn-down':
   current=routes();remaining=[]
   for r in owned:
    if any(exact(x,r) for x in current):
     if run(command(r,'del'),False).returncode:remaining.append(r)
   save(remaining);return bool(remaining)
  if owned:raise ValueError('existing VPN journal; disconnect and inspect')
  dev=os.environ.get('DEVICE_IP_IFACE','')
  if not re.fullmatch(r'[A-Za-z0-9_.:-]{1,15}',dev):raise ValueError('invalid parent')
  current=routes();defaults=[x for x in current if x.get('dst')=='default' and x.get('dev')==dev and x.get('gateway')]
  if not defaults:raise ValueError('no parent default')
  d=min(defaults,key=lambda x:x.get('metric',0));gateway=str(ipaddress.IPv4Address(d['gateway']))
  wanted=[]
  for n in c['exclusions']:
   dst=str(ipaddress.IPv4Network(n,strict=True))
   if any(x.get('dst')!='default' and str(ipaddress.IPv4Network(x['dst'],strict=False))==dst and x.get('metric',0)==0 for x in current):raise ValueError('route priority conflict')
   wanted.append(dict(dst=dst,gateway=gateway,dev=dev,protocol=197,metric=0))
  for r in wanted:
   # Only successful additions confer ownership. Never journal a failed add.
   # A crash before save can leave an unjournaled route for explicit recovery,
   # but cannot cause deletion of a concurrent/preexisting foreign route.
   if run(command(r,'add'),False).returncode:raise ValueError('route addition failed')
   owned.append(r);save(owned)
 return 0
def entrypoint():
 try:sys.exit(main())
 except Exception:
  # Do not log input values/secrets. NM dispatcher exit is not an activation veto.
  print('NM Azure VPN routing failed; disconnect VPN and inspect private state',file=sys.stderr)
  try:
   c=json.loads(C.read_text());subprocess.Popen(['/usr/bin/nmcli','connection','down','uuid',c['uuid']],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,start_new_session=True)
  except Exception:pass
  sys.exit(1)

if __name__ == "__main__":
 entrypoint()
