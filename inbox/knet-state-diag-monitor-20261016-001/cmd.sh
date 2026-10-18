#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'KNET_PERFORMANCE'
"""Bounded Slurm, saved-log, and existing-PID observations; never trains."""
import bisect
import collections
import datetime
import hashlib
import json
from pathlib import Path
import shlex
import socket
import statistics
import subprocess
import time

NODE_CODE='"""Five-second existing-process observation only; no process or policy mutation."""\nimport datetime\nimport json\nimport os\nfrom pathlib import Path\nimport socket\nimport time\n\nPID=28625\nEXPECTED_START=1792217223.92\nP=Path(\'/proc\')/str(PID)\nERRORS=[]\n\ndef read(path):\n    try:return Path(path).read_text()\n    except Exception as exc:\n        ERRORS.append({\'path\':str(path),\'error\':type(exc).__name__})\n        return None\n\ndef kv(text):\n    return {k.strip():v.strip() for k,v in (l.split(\':\',1) for l in (text or \'\').splitlines() if \':\' in l)}\n\ndef stat_fields(text):\n    # Index zero here is documented field 3, after the parenthesized comm.\n    a=text[text.rfind(\')\')+2:].split()\n    return {\'state\':a[0],\'ppid\':int(a[1]),\'minflt\':int(a[7]),\'majflt\':int(a[9]),\n            \'utime_ticks\':int(a[11]),\'stime_ticks\':int(a[12]),\'nice\':int(a[16]),\n            \'threads\':int(a[17]),\'starttime_ticks\':int(a[19]),\'processor\':int(a[36]),\n            \'blkio_delay_ticks\':int(a[39]) if len(a)>39 else None}\n\ndef numeric_lines(text):\n    out={}\n    for l in (text or \'\').splitlines():\n        a=l.replace(\':\',\'\').split()\n        if len(a)==2:\n            try:out[a[0]]=int(a[1])\n            except ValueError:pass\n    return out\n\ndef cpu_lines():\n    text=read(\'/proc/stat\') or \'\'\n    return {a[0]:list(map(int,a[1:])) for a in (l.split() for l in text.splitlines())\n            if a and (a[0]==\'cpu\' or a[0] in CPU_NAMES)}\n\ndef cgroup_locations():\n    rows=[]\n    memberships=[]\n    for l in (read(P/\'cgroup\') or \'\').splitlines():\n        _,controllers,rel=l.split(\':\',2);memberships.append((set(controllers.split(\',\')),rel))\n    for l in (read(\'/proc/mounts\') or \'\').splitlines():\n        a=l.split()\n        if len(a)<4 or a[2] not in (\'cgroup\',\'cgroup2\'):continue\n        mount=Path(a[1]);opts=set(a[3].split(\',\'))\n        for controllers,rel in memberships:\n            if a[2]==\'cgroup2\' or opts&controllers:\n                if \'..\' in Path(rel).parts:continue\n                folder=mount/rel.lstrip(\'/\')\n                for _ in range(3):\n                    rows.append(folder)\n                    if folder==mount:break\n                    folder=folder.parent\n    return list(dict.fromkeys(rows))\n\ndef cgroups():\n    files=(\'cpu.max\',\'cpu.stat\',\'cpu.cfs_quota_us\',\'cpu.cfs_period_us\',\'cpu.shares\',\n           \'cpuset.cpus\',\'memory.current\',\'memory.max\',\'memory.usage_in_bytes\',\n           \'memory.limit_in_bytes\',\'memory.failcnt\')\n    return {str(folder):{name:(read(folder/name) or \'\').strip() for name in files if (folder/name).is_file()}\n            for folder in CGROUPS}\n\ndef threads():\n    out={}\n    for folder in sorted((P/\'task\').iterdir(),key=lambda p:int(p.name))[:64]:\n        text=read(folder/\'stat\');sched=read(folder/\'schedstat\')\n        if text:out[folder.name]={\'stat\':stat_fields(text),\'schedstat_ns\':list(map(int,sched.split())) if sched else None}\n    return out\n\ndef sample():\n    return {\'utc\':datetime.datetime.now(datetime.timezone.utc).isoformat(),\'monotonic\':time.monotonic(),\n            \'process\':stat_fields(read(P/\'stat\')),\'status\':{k:v for k,v in kv(read(P/\'status\')).items()\n                if k in (\'Uid\',\'Gid\',\'VmRSS\',\'VmHWM\',\'VmSize\',\'VmSwap\',\'Threads\',\'Cpus_allowed_list\',\n                          \'voluntary_ctxt_switches\',\'nonvoluntary_ctxt_switches\')},\n            \'wchan\':read(P/\'wchan\'),\'io\':numeric_lines(read(P/\'io\')),\n            \'threads\':threads(),\'node_cpu_ticks\':cpu_lines(),\'cgroups\':cgroups(),\n            \'meminfo\':{k:v for k,v in kv(read(\'/proc/meminfo\')).items()\n                if k in (\'MemTotal\',\'MemFree\',\'MemAvailable\',\'SwapTotal\',\'SwapFree\',\'Dirty\',\'Writeback\')},\n            \'loadavg\':read(\'/proc/loadavg\'),\n            \'pressure\':{k:(Path(\'/proc/pressure\')/k).read_text().strip() for k in (\'cpu\',\'io\',\'memory\')\n                        if (Path(\'/proc/pressure\')/k).is_file()}}\n\ndef main():\n    global CPU_NAMES,CGROUPS\n    assert socket.gethostname().split(\'.\')[0]==\'ngu104\',\'Unexpected node; do not inspect another host\'\n    status=kv(read(P/\'status\'));assert int(status[\'Uid\'].split()[0])==os.getuid(),\'PID not owned by current user\'\n    hz=os.sysconf(\'SC_CLK_TCK\');first=stat_fields(read(P/\'stat\'))\n    btime=int(next(l.split()[1] for l in Path(\'/proc/stat\').read_text().splitlines() if l.startswith(\'btime \')))\n    start=btime+first[\'starttime_ticks\']/hz\n    assert abs(start-EXPECTED_START)<2,\'PID creation identity differs; no other PID is inspected\'\n    affinity=sorted(os.sched_getaffinity(PID));cpus=set(affinity);topology={}\n    for cpu in affinity:\n        f=Path(\'/sys/devices/system/cpu\')/(\'cpu\'+str(cpu))/\'topology/thread_siblings_list\'\n        if f.is_file():\n            text=f.read_text().strip();topology[str(cpu)]=text\n            for part in text.split(\',\'):\n                a=part.split(\'-\');cpus.update(range(int(a[0]),int(a[-1])+1))\n    CPU_NAMES={\'cpu\'+str(c) for c in cpus};CGROUPS=cgroup_locations()\n    a=sample();time.sleep(5);b=sample();assert a[\'process\'][\'starttime_ticks\']==b[\'process\'][\'starttime_ticks\']\n    wall=b[\'monotonic\']-a[\'monotonic\'];cpu=(b[\'process\'][\'utime_ticks\']+b[\'process\'][\'stime_ticks\']\n        -a[\'process\'][\'utime_ticks\']-a[\'process\'][\'stime_ticks\'])/hz\n    thread_deltas=[]\n    for tid,t in b[\'threads\'].items():\n        old=a[\'threads\'].get(tid)\n        if old and old[\'schedstat_ns\'] and t[\'schedstat_ns\']:\n            d=[new-prev for new,prev in zip(t[\'schedstat_ns\'],old[\'schedstat_ns\'])]\n            thread_deltas.append({\'tid\':int(tid),\'runtime_seconds\':d[0]/1e9,\n                \'runqueue_wait_seconds\':d[1]/1e9,\'timeslices\':d[2],\'state\':t[\'stat\'][\'state\']})\n    cores={}\n    for core,new in b[\'node_cpu_ticks\'].items():\n        old=a[\'node_cpu_ticks\'][core];d=[x-y for x,y in zip(new,old)];total=sum(d[:8])\n        cores[core]={\'ticks_delta\':d,\'busy_percent\':100*(total-d[3]-d[4])/total if total else None,\n                     \'iowait_percent\':100*d[4]/total if total else None}\n    report={\'status\':\'KNET_NODE_READONLY_PROBE\',\'host\':socket.gethostname(),\'pid\':PID,\n        \'identity_verified\':True,\'observed_start_epoch\':start,\'affinity\':affinity,\'smt_siblings\':topology,\n        \'clock_ticks_per_second\':hz,\'sample_wall_seconds\':wall,\'cpu_seconds_delta\':cpu,\n        \'cpu_single_core_percent\':100*cpu/wall,\'major_faults_delta\':b[\'process\'][\'majflt\']-a[\'process\'][\'majflt\'],\n        \'blkio_delay_ticks_delta\':None if a[\'process\'][\'blkio_delay_ticks\'] is None else\n            b[\'process\'][\'blkio_delay_ticks\']-a[\'process\'][\'blkio_delay_ticks\'],\n        \'io_deltas\':{k:v-a[\'io\'].get(k,v) for k,v in b[\'io\'].items()},\n        \'thread_schedstat_deltas\':thread_deltas,\'node_cpu_deltas\':cores,\'samples\':[a,b],\n        \'errors\':ERRORS,\'processes_modified\':False,\'settings_modified\':False,\'training_executed\':False}\n    print(json.dumps(report,sort_keys=True))\n\nif __name__==\'__main__\':\n    try:main()\n    except Exception as exc:print(json.dumps({\'status\':\'KNET_NODE_READONLY_UNAVAILABLE\',\n        \'error\':type(exc).__name__+\': \'+str(exc)[:500],\'errors\':ERRORS,\n        \'processes_modified\':False,\'settings_modified\':False}))\n'
TRANSPORT_NONCE='252b5c5e587847e8ba3db0a8cb9f5d5a'
ROOT=Path('/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/state_channel_scratch_20261017_001')

def command(args,timeout=25):
    try:
        p=subprocess.run(args,capture_output=True,text=True,timeout=timeout)
        return {'returncode':p.returncode,'stdout':p.stdout[:200000],'stderr':p.stderr[:2000]}
    except Exception as exc:return {'error':type(exc).__name__+': '+str(exc)[:400]}

def timestamp(value):return datetime.datetime.fromisoformat(value).timestamp()

def log_summary():
    path=ROOT/'logs/diagnostic-244228_0.out';size=path.stat().st_size
    with path.open('rb') as stream:raw=stream.read(min(size,64*1024*1024))
    stages=[];resources=[];epochs=[];failures=[];invalid=0
    for line in raw.decode('utf-8',errors='replace').splitlines():
        try:e=json.loads(line)
        except ValueError:invalid+=1;continue
        if not isinstance(e,dict):continue
        kind=e.get('event')
        if kind=='training_segment_progress':
            key=(e['arm'],e['step'],e['label'],e['gradient'])
            row={k:e[k] for k in ('utc','elapsed_seconds','segments','total','optimizer_calls')}
            if not stages or stages[-1]['key']!=key:
                stages.append({'key':key,'first':row,'last':row,'event_count':1})
            else:stages[-1]['last']=row;stages[-1]['event_count']+=1
        elif kind=='resource_sample' and e.get('scientific_pid')==28625 and e.get('job_id')=='244229':
            resources.append({k:e[k] for k in ('utc','child_cpu_seconds','combined_rss_bytes','scientific_pid','job_id')})
        elif kind=='epoch_complete':epochs.append({k:e.get(k) for k in ('utc','elapsed_seconds','arm','step','optimizer_calls','effective_nonzero_steps','parameter_changed')})
        elif kind in ('training_failure','resource_stop','basin_complete'):
            failures.append({k:e.get(k) for k in ('event','utc','type','message','arm','step')})
    resources.sort(key=lambda r:timestamp(r['utc']));times=[timestamp(r['utc']) for r in resources]
    def duration(row):
        a,b=row['first'],row['last'];segments=b['segments']-a['segments']
        out={'arm':row['key'][0],'step':row['key'][1],'label':row['key'][2],
             'gradient':row['key'][3],'first_segment':a['segments'],'last_segment':b['segments'],
             'total':b['total'],'first_utc':a['utc'],'last_utc':b['utc'],
             'observed_wall_span_seconds':b['elapsed_seconds']-a['elapsed_seconds'],
             'recorded_complete':b['segments']==b['total'],'events':row['event_count']}
        if segments>0:
            out['wall_seconds_per_segment']=out['observed_wall_span_seconds']/segments
            left=bisect.bisect_left(times,timestamp(a['utc']));right=bisect.bisect_right(times,timestamp(b['utc']))-1
            if 0<left<len(resources) and 0<=right<len(resources)-1 and right>=left:
                lower=resources[right]['child_cpu_seconds']-resources[left]['child_cpu_seconds']
                upper=resources[right+1]['child_cpu_seconds']-resources[left-1]['child_cpu_seconds']
                if 0<=lower<=upper:
                    out['cpu_span_seconds_bracket']=[lower,upper]
                    out['cpu_seconds_per_segment_bracket']=[lower/segments,upper/segments]
        return out
    rows=[duration(r) for r in stages]
    def window(seconds):
        if not resources:return None
        end=resources[-1];target=timestamp(end['utc'])-seconds
        start=resources[max(0,bisect.bisect_left(times,target))]
        wall=timestamp(end['utc'])-timestamp(start['utc'])
        return {'start_utc':start['utc'],'end_utc':end['utc'],'wall_seconds':wall,
                'cpu_seconds':end['child_cpu_seconds']-start['child_cpu_seconds'],
                'single_core_cpu_percent':100*(end['child_cpu_seconds']-start['child_cpu_seconds'])/wall if wall else None,
                'rss_bytes_start':start['combined_rss_bytes'],'rss_bytes_end':end['combined_rss_bytes']}
    reference=[r for r in rows if r['gradient'] and r['recorded_complete'] and 55<=r['step']<=65]
    recent=[r for r in rows if r['gradient'] and r['step']>=66]
    return {'path':str(path),'bytes_at_start':size,'bytes_read':len(raw),
        'sha256_of_read_bytes':hashlib.sha256(raw).hexdigest(),'truncated':len(raw)<size,
        'invalid_or_incomplete_json_lines':invalid,'resource_samples':len(resources),
        'resource_windows':{str(n):window(n) for n in (300,900,3600,7200)},
        'reference_gradients_steps55_65':reference,'recent_gradients_steps66_onward':recent,
        'last_stage_records':rows[-12:],'last_epoch_completions':epochs[-12:],
        'failure_or_terminal_events':failures[-8:],
        'duration_limit':'first-to-last reported segment span excludes work before first completed segment; CPU brackets use adjacent existing resource samples',
        'science_values_or_arrays_output':False}

def main():
    report={'status':'KNET_READONLY_PERFORMANCE_DIAGNOSTIC',
        'transport_nonce':TRANSPORT_NONCE,
        'checked_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'array_job_id':'244228','scientific_job_id':'244229','pid':28625,'node':'ngu104',
        'node_snapshot':command(['scontrol','-o','show','node','ngu104']),
        'allocation_detail':command(['scontrol','-d','show','job','244229']),
        'partition':command(['scontrol','-o','show','partition','hgpu4']),
        'batch_usage':command(['sstat','-j','244229.batch','--noheader','--parsable2','--format=JobID,AveCPU,MaxRSS,AveRSS']),
        'read_only':True,'new_allocation_or_training':False,'resource_or_priority_changes':False}
    q=command(['squeue','-w','ngu104','-h','-o','%i|%T|%C'])
    if q.get('returncode')==0:
        rows=[r.split('|') for r in q['stdout'].splitlines() if r]
        report['node_queue_aggregate']={'jobs_by_state':dict(collections.Counter(r[1] for r in rows)),
            'running_requested_cpus':sum(int(r[2]) for r in rows if r[1]=='RUNNING'),
            'owned_array_element_rows':[r for r in rows if r[0] in ('244229','244228_0')]}
    else:report['node_queue_aggregate']=q
    try:report['saved_log_analysis']=log_summary()
    except Exception as exc:report['saved_log_error']=type(exc).__name__+': '+str(exc)[:500]
    ssh=['ssh','-o','BatchMode=yes','-o','ConnectionAttempts=1','-o','ConnectTimeout=6',
         '-o','StrictHostKeyChecking=yes','-o','UpdateHostKeys=no','-o','ControlMaster=no',
         '-o','ControlPath=none','ngu104','/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B -c '+shlex.quote(NODE_CODE)]
    result=command(ssh,timeout=30)
    if result.get('returncode')==0:
        try:report['node_process_probe']=json.loads(result['stdout'])
        except ValueError:report['node_process_probe']={'status':'NON_JSON_NODE_REPLY',**result}
    else:report['node_process_probe']={'status':'EXISTING_NODE_ACCESS_UNAVAILABLE',**result}
    report['finished_at_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
    print('KNET_PERFORMANCE_JSON='+json.dumps(report,sort_keys=True))

if __name__=='__main__':
    try:main()
    except Exception as exc:print('KNET_PERFORMANCE_JSON='+json.dumps({
        'status':'READONLY_PERFORMANCE_DIAGNOSTIC_UNAVAILABLE','error':type(exc).__name__+': '+str(exc)[:500],
        'read_only':True,'new_allocation_or_training':False}))

KNET_PERFORMANCE
