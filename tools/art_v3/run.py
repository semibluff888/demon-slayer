"""Run v3 generation jobs: parts of one clip in order, different clips in parallel.

Calls tools/run_roster_art_job.ps1 (records every request, never retries, refuses
to repeat a request that already has a record). Stops scheduling on the first failure.

Usage: python tools/art_v3/run.py --group pilot [--workers 3] [--character tanjiro]
"""
import argparse
import concurrent.futures
import subprocess
import sys

from common import ROOT, production, read

PYTHON = str(ROOT / '.venv/Scripts/python.exe')


def run_job(job, manifest):
    command = ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(ROOT / 'tools/run_roster_art_job.ps1'),
               '-Id', job['id'], '-Manifest', manifest, '-Python', PYTHON]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, encoding='utf-8', errors='replace')
    log = ROOT / manifest
    (log.parent / 'records' / (job['id'] + '.log')).write_text(result.stdout + result.stderr, encoding='utf-8')
    ok = result.returncode == 0 and (ROOT / job['out']).exists()
    print(('DONE ' if ok else 'FAILED ') + job['id'], flush=True)
    return ok


def run_chain(chain, manifest):
    for job in chain:
        if (ROOT / job['out']).exists():
            continue
        if not run_job(job, manifest):
            return False
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--character', default='tanjiro')
    parser.add_argument('--group', required=True)
    parser.add_argument('--workers', type=int, default=3)
    args = parser.parse_args()
    out = production(args.character)
    manifest = (out / 'jobs.json').relative_to(ROOT).as_posix()
    chains = {}
    for job in read(out / 'jobs.json', []):
        if job.get('group') == args.group and not job.get('superseded_by') and not (ROOT / job['out']).exists():
            chains.setdefault(job['metadata'].get('clip', job['id']), []).append(job)
    for chain in chains.values():
        chain.sort(key=lambda job: job['metadata'].get('part', 0))
    print('chains:', len(chains), 'jobs:', sum(len(c) for c in chains.values()), flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        results = list(pool.map(lambda chain: run_chain(chain, manifest), chains.values()))
    if not all(results):
        sys.exit('Some chains failed; inspect records before resuming.')
    print('V3 QUEUE COMPLETE:', args.group, flush=True)


if __name__ == '__main__':
    main()
