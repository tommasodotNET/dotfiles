#!/usr/bin/env python3
"""Run ONLY via unshare --user --map-root-user --net; never with sudo."""
import subprocess
assert __import__('os').geteuid() == 0, 'Use a rootless user/network namespace'
uid_map = __import__('pathlib').Path('/proc/self/uid_map').read_text().split()
assert len(uid_map) == 3 and uid_map[0] == '0' and int(uid_map[1]) != 0 and uid_map[2] == '1', 'Require rootless single-user mapping, never sudo'
# The fresh namespace must have only a DOWN loopback: a real host never qualifies.
links = __import__('json').loads(subprocess.check_output(['ip', '-j', 'link'], text=True))
assert len(links) == 1 and links[0]['ifname'] == 'lo' and 'UP' not in links[0]['flags'], 'Require a fresh network namespace'
assert len(subprocess.check_output(['ip', '-j', 'link'], text=True).split('ifname')) == 2, 'Expected only loopback in a fresh namespace'
import pathlib,tempfile,json,os,subprocess,runpy
p=pathlib.Path(__file__).resolve().parent/'dispatcher.py'
s=p.read_text();s=s[:s.index('def entrypoint():')];ns={'__name__':'test'};exec(compile(s,str(p),'exec'),ns)
t=pathlib.Path(tempfile.mkdtemp());ns['C']=t/'config';ns['S']=t/'state';ns['C'].write_text(json.dumps({'uuid':'test','exclusions':['10.2.0.0/16','203.0.113.8/32']}))
def r(*a):return subprocess.run(a,check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True).stdout
for n,a in [('uplink0','192.0.2.2/24'),('vpn0','198.51.100.2/24')]:r('ip','link','add',n,'type','dummy');r('ip','link','set',n,'up');r('ip','addr','add',a,'dev',n)
r('ip','route','add','default','via','192.0.2.1','dev','uplink0');r('ip','route','add','10.0.0.0/8','dev','vpn0')
r('ip','route','add','203.0.113.9/32','via','192.0.2.1','dev','uplink0','proto','198')
baseline=r('ip','-j','route','show','table','all')
os.environ.update(CONNECTION_UUID='test',DEVICE_IP_IFACE='uplink0');ns['sys'].argv=['helper','uplink0','vpn-up'];assert ns['main']()==0
assert json.loads(r('ip','-j','route','get','10.2.3.4'))[0]['dev']=='uplink0'
ns['sys'].argv[2]='vpn-down';assert ns['main']()==0;assert r('ip','-j','route','show','table','all')==baseline
os.environ['CONNECTION_UUID']='other';ns['sys'].argv[2]='vpn-up';assert ns['main']()==0;assert r('ip','-j','route','show','table','all')==baseline
assert ns['exact']({'dst':'203.0.113.8','gateway':'192.0.2.1','dev':'uplink0','protocol':197},{'dst':'203.0.113.8/32','gateway':'192.0.2.1','dev':'uplink0','protocol':197,'metric':0})
assert not ns['exact']({'dst':'203.0.113.8','gateway':'192.0.2.1','dev':'uplink0','protocol':198},{'dst':'203.0.113.8/32','gateway':'192.0.2.1','dev':'uplink0','protocol':197,'metric':0})
print('PASS /32 canonicalization and foreign route preservation;  scoped up/down routing, exact restoration, foreign UUID ignored')

# Canonical host conflict is detected before any additions, even own protocol.
os.environ['CONNECTION_UUID']='test'
r('ip','route','add','203.0.113.8/32','via','192.0.2.1','dev','uplink0','proto','197')
conflict=r('ip','-j','route','show','table','all')
ns['sys'].argv[2]='vpn-up'
try:ns['main']();raise AssertionError('conflict accepted')
except ValueError:pass
ns['sys'].argv[2]='vpn-down';assert ns['main']()==0
assert r('ip','-j','route','show','table','all')==conflict
r('ip','route','del','203.0.113.8/32','via','192.0.2.1','dev','uplink0','proto','197')
# Simulate concurrent identical route appearing immediately before failed add.
original=ns['run'];injected=[]
def fail_add(a,check=True):
 if 'add' in a and not injected:
  original(a);injected.append(a);return subprocess.CompletedProcess(a,2,'','exists')
 return original(a,check)
ns['run']=fail_add;ns['sys'].argv[2]='vpn-up'
try:ns['main']();raise AssertionError('failed add accepted')
except ValueError:pass
assert json.loads((ns['S']/'journal.json').read_text())==[]
concurrent=r('ip','-j','route','show','table','all')
ns['run']=original;ns['sys'].argv[2]='vpn-down';assert ns['main']()==0
assert r('ip','-j','route','show','table','all')==concurrent
print('PASS canonical preexisting same-protocol conflict and concurrent failed-add foreign preservation')
