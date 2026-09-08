#!/usr/bin/env bash
# Read-only observation, never an admission certificate or submission command.
set -euo pipefail
python3 -B - <<'PY'
import base64, collections, datetime, gzip, hashlib, json, pathlib, re, subprocess
root = pathlib.Path('/data1/home/sunyiq/kalmannet_wrr_model_selection_20260908/stages/A')
assert root.is_dir() and not root.is_symlink()
job_file = root / 'array_job_id.txt'
assert job_file.is_file() and not job_file.is_symlink()
job = job_file.read_text().strip()
assert re.fullmatch(r'[0-9]+', job), 'Invalid submitted job identity'
assert job == '223848', 'Stage-A ID differs from the unique accepted submission receipt'
exp = root / 'repo/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902'
combos = [json.loads(line) for line in (exp / 'combos.jsonl').read_text().splitlines() if line.strip()]
assert len(combos) == 18 and [x['index'] for x in combos] == list(range(18))
assert [x['run_id'] for x in combos] == ['NGF-SELECT-20260908-A%02d' % (i+1) for i in range(18)]

def command(args):
    response = subprocess.run(args, capture_output=True, text=True, check=False, timeout=45)
    return {'command': args, 'returncode': response.returncode,
            'stdout': response.stdout, 'stderr': response.stderr}

def read_json(path):
    try:
        return json.loads(path.read_text())
    except (json.JSONDecodeError, FileNotFoundError) as exc:
        return {'observation_error': str(exc), 'path': str(path)}

queue = command(['squeue','-r','-j',job,'-h','-o','%i|%T|%M|%R'])
accounting = command(['sacct','-j',job,'-X','-n','-P','--format=JobID,State,ExitCode,Elapsed,Start,End,NodeList'])
state_counts = collections.Counter()
accounting_rows = []
for line in accounting['stdout'].splitlines():
    fields = line.split('|')
    if fields and re.fullmatch(re.escape(job) + r'_([0-9]+)', fields[0]):
        accounting_rows.append(fields)
        state_counts[fields[1]] += 1

audits = [(p,read_json(p)) for p in exp.glob('audits/*_formal_*.json')]
runs = []
for combo in combos:
    index, seed = combo['index'], combo['seed']
    item = {'index':index,'run_id':combo['run_id'],'seed':seed,'combo':combo}
    claim = root / 'claims' / ('index%04d.json' % index)
    item['claim'] = read_json(claim) if claim.is_file() else None
    directories = list(exp.glob('runs/formal_seed%d_gpu/idx%04d_*' % (seed,index)))
    item['run_directory_count'] = len(directories)
    if len(directories) == 1:
        run = directories[0]
        item['run_directory'] = str(run)
        epochs = run / 'results/epoch_log.jsonl'
        if epochs.is_file():
            complete_lines = [line for line in epochs.read_text().splitlines(keepends=True)
                              if line.strip() and line.endswith('\n')]
            try:
                records = [json.loads(line) for line in complete_lines]
                item['completed_epochs'] = len(records)
                if records:
                    item['first_epoch'] = records[0]
                    item['last_epoch'] = records[-1]
            except json.JSONDecodeError as exc:
                item['epoch_observation_error'] = str(exc)
        cell = run / 'cell_metrics.json'
        item['cell_metrics'] = read_json(cell) if cell.is_file() else None
        item['failed_marker_present'] = (run/'FAILED').is_file()
        error = run/'error.txt'
        if error.is_file():
            item['error_tail'] = error.read_text(errors='replace')[-4000:]
    item['launcher_audits'] = [dict(path=str(path), **record) for path,record in audits
                               if record.get('run_id') == combo['run_id']]
    runs.append(item)

receipt_names = ['DEPLOYMENT_RECEIPT.json','SUBMISSION_RECEIPT.json','SUBMISSION_INTENT.json',
                 'SUBMISSION_RESPONSE.json','CACHE_ENVIRONMENT_PREFLIGHT.json']
receipts = {}
receipt_hashes = {}
for name in receipt_names:
    path = root / name
    assert path.is_file() and not path.is_symlink()
    receipt_hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()
    receipts[name] = read_json(path)
assert receipts['SUBMISSION_RECEIPT.json']['job_id'] == job
before = json.loads((root/'PROTECTED_FILES_BEFORE.json').read_bytes())
after = json.loads((root/'PROTECTED_FILES_AFTER.json').read_bytes())
baseline = json.loads((root/'REMOTE_BASELINE.json').read_bytes())
assert before == after == baseline['protected_files']
for name in ['PROTECTED_FILES_BEFORE.json','PROTECTED_FILES_AFTER.json','REMOTE_BASELINE.json']:
    receipt_hashes[name] = hashlib.sha256((root/name).read_bytes()).hexdigest()

report = {'kind':'READ_ONLY_OBSERVATION_NOT_ADMISSION','stage':'A','job_id':job,
          'observed_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'root':str(root),'squeue':queue,'sacct':accounting,'accounting_rows':accounting_rows,
          'accounting_state_counts':dict(state_counts),'runs':runs,
          'deployment_receipts':receipts,'deployment_receipt_sha256':receipt_hashes,
          'protected_before_after_baseline_equal':True,'protected_files_count':len(after),
          'training_or_evaluation_started_by_observer':False,'new_jobs_submitted':0}
blob = json.dumps(report,sort_keys=True,separators=(',',':')).encode()
print('STAGE_STATUS_GZIP_BASE64=' + base64.b64encode(gzip.compress(blob,mtime=0)).decode())
print('STATUS_SUMMARY=' + json.dumps({'job_id':job,'stage':'A','accounting_state_counts':dict(state_counts),
    'claimed_runs':sum(x['claim'] is not None for x in runs),
    'runs_with_completed_epochs':sum(x.get('completed_epochs',0)>0 for x in runs),
    'completed_metric_files':sum(x.get('cell_metrics') is not None and 'observation_error' not in x['cell_metrics'] for x in runs),
    'new_jobs_submitted':0}))
PY
