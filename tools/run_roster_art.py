"""Bounded artwork queue; invokes existing CPA helper, never auto-retries."""
import argparse,concurrent.futures,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/imagegen/roster-v1'
MANIFEST='output/imagegen/roster-v1/jobs.json'
def run(j):
 print('GENERATING '+j['id'],flush=True)
 r=subprocess.run(['pwsh','-NoProfile','-File',str(ROOT/'tools/run_roster_art_job.ps1'),'-Id',j['id'],'-Manifest',MANIFEST],cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace')
 (OUT/'records'/(j['id']+'.log')).write_text(r.stdout+r.stderr,encoding='utf-8')
 print(('DONE ' if r.returncode==0 else 'FAILED ')+j['id'],flush=True)
 return r.returncode==0
def main():
 global OUT,MANIFEST
 p=argparse.ArgumentParser();p.add_argument('--group',default='foundation');p.add_argument('--workers',type=int,default=3);p.add_argument('--manifest',default=MANIFEST);p.add_argument('--id');a=p.parse_args();MANIFEST=a.manifest;OUT=(ROOT/MANIFEST).parent
 jobs=[j for j in json.loads((ROOT/MANIFEST).read_text(encoding='utf-8')) if not j.get('skip_reason') and j['group'] in a.group.split(',') and (not a.id or j['id']==a.id) and not (ROOT/j['out']).exists()]
 jobs.sort(key=lambda j: ({"portraits":0,"effects":1,"animation":2,"stage-detail":3}.get(j["group"],0),({"awakening_start":0,"idle":1}.get(j["metadata"].get("clip",""),2) if j["group"]=="awakening" else 2),j["id"].split("-",1)[-1]))
 for j in jobs:
  if (OUT/'records'/(j['id']+'.json')).exists():raise SystemExit('Inspect prior request: '+j['id'])
  for ref in j['references']:
   if not (ROOT/ref).exists():raise SystemExit('Missing reference: '+ref)
 failed=False
 with concurrent.futures.ThreadPoolExecutor(max_workers=a.workers) as pool:
  pending={}
  while jobs or pending:
   while jobs and len(pending)<a.workers and not failed:
    j=jobs.pop(0);pending[pool.submit(run,j)]=j['id']
   if not pending:break
   done,_=concurrent.futures.wait(pending,return_when=concurrent.futures.FIRST_COMPLETED)
   for f in done:
    if not f.result():failed=True
    del pending[f]
  if failed:raise SystemExit('Queue stopped; inspect records before resuming.')
 print('ART QUEUE COMPLETE',flush=True)
if __name__=='__main__':main()
