#!/bin/bash
sequence=7
umask 077
exec 2>/dev/null
openssl version >/dev/null 2>&1 || { printf '%s\n' TRANSPORT_PREREQUISITES_FAILED; exit 1; }
transport_python=''
for candidate in /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -B -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' >/dev/null 2>&1; then
        transport_python="$candidate"
        break
    fi
done
if [ -z "$transport_python" ]; then printf '%s\n' TRANSPORT_PREREQUISITES_FAILED; exit 1; fi
"$transport_python" -B - <<'TRANSPORT_PY'
Q = {'sequence': 7, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '31e4e66d29749810a816b60c804027f7e8e8c105aa294b987cd37471d5fd571a', 'ciphertext': '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'}}

import base64, hashlib, json, os, pathlib, subprocess, sys
R = pathlib.Path('/data1/home/sunyiq/kalmannet_joint_adaptive_comparison_20261006_v1')
M = 64*1024*1024
def digest(x): return hashlib.sha256(x).hexdigest()
def write(p,x):
    with p.open('xb') as f: f.write(x)
def run(a, **kw):
    p=subprocess.run(a, capture_output=True, **kw)
    if p.returncode:
        failures.append({'argv':a,'code':p.returncode,'stderr':p.stderr.decode(errors='replace')})
    return p
failures=[]
def main():
    os.umask(0o077)
    boot = Q['kind']=='bootstrap'
    if boot:
        if R.exists() or R.is_symlink(): raise RuntimeError('occupied')
        R.mkdir()
        D=R/'transport'; D.mkdir()
    else:
        if R.is_symlink() or not R.is_dir() or (R/'transport').is_symlink(): raise RuntimeError('root')
        D=R/'transport'/('sequence_'+str(Q['sequence'])); D.mkdir()
    log=D/'controller.log'
    try:
        local=D/'local.cert.pem'; write(local,base64.b64decode(Q['local_cert']))
        if boot:
            p=run(['openssl','req','-x509','-newkey','rsa:3072','-nodes','-keyout',str(D/'remote.key.pem'),'-out',str(D/'remote.cert.pem'),'-days','365','-subj','/CN=isolated-transport'])
            write(D/'key_generation.log',p.stdout+p.stderr)
            if p.returncode: raise RuntimeError('key generation')
            checks=[['bash','-lc','for c in matlab octave python python3 openssl sbatch; do command -v "$c" || true; done; module -t avail matlab octave python cuda 2>&1 || true'], ['sinfo','-o','%P %a %l %D %G'], ['df','-h',str(R)], ['/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python','-B','-c','import sys,importlib.metadata as m; print(sys.version); print([(n,m.version(n)) for n in ("numpy","scipy","torch")])']]
            details=[]
            for a in checks:
                try:
                    p=run(a,timeout=60); details.append({'command':a,'code':p.returncode,'stdout':p.stdout.decode(errors='replace'),'stderr':p.stderr.decode(errors='replace')})
                except Exception as e: details.append({'command':a,'error':str(e)})
            raw=json.dumps({'readiness':details}).encode(); code=0
        else:
            for name in ('script','payload'):
                if name not in Q: continue
                encrypted=base64.b64decode(Q[name]['ciphertext']); write(D/(name+'.der'),encrypted)
                p=run(['openssl','smime','-decrypt','-binary','-inform','DER','-inkey',str(R/'transport'/'remote.key.pem')],input=encrypted)
                if p.returncode or len(p.stdout)>M or digest(p.stdout)!=Q[name]['sha256']: raise RuntimeError('input integrity')
                write(D/name,p.stdout)
            env=dict(os.environ); env['TRANSPORT_PAYLOAD_PATH']=str(D/'payload') if 'payload' in Q else ''
            # File capture preserves full output; only bounded output is exported.
            with (D/'stdout').open('xb') as out, (D/'stderr').open('xb') as err:
                p=subprocess.run(['bash',str(D/'script')],cwd=str(D),env=env,stdout=out,stderr=err)
            code=p.returncode
            a,b=D/'stdout',D/'stderr'
            if a.stat().st_size+b.stat().st_size>M: raise RuntimeError('output limit; full output retained')
            raw=json.dumps({'inner_exit_code':code,'stdout_base64':base64.b64encode(a.read_bytes()).decode(),'stderr_base64':base64.b64encode(b.read_bytes()).decode()}).encode()
        if len(raw)>M: raise RuntimeError('result limit')
        write(D/'result.json',raw)
        p=run(['openssl','smime','-encrypt','-aes256','-binary','-outform','DER',str(local)],input=raw)
        if p.returncode: raise RuntimeError('output encryption')
        write(D/'result.der',p.stdout)
        envelope={'kind':Q['kind'],'sequence':Q['sequence'],'ciphertext_sha256':digest(p.stdout),'ciphertext_base64':base64.b64encode(p.stdout).decode()}
        if boot: envelope['remote_certificate']=base64.b64encode((D/'remote.cert.pem').read_bytes()).decode()
        print('BEGIN_ENCRYPTED_TRANSPORT'); print(json.dumps(envelope)); print('END_ENCRYPTED_TRANSPORT')
        return 0 if code==0 else 1
    except Exception as e:
        error=json.dumps({'transport_error':str(e),'process_failures':failures}).encode()
        write(log,error)
        try:
            p=run(['openssl','smime','-encrypt','-aes256','-binary','-outform','DER',str(local)],input=error)
            if p.returncode: raise RuntimeError('error encryption')
            write(D/'failure.der',p.stdout)
            print('BEGIN_ENCRYPTED_TRANSPORT'); print(json.dumps({'kind':Q['kind'],'sequence':Q['sequence'],'ciphertext_sha256':digest(p.stdout),'ciphertext_base64':base64.b64encode(p.stdout).decode()})); print('END_ENCRYPTED_TRANSPORT')
        except Exception: print('TRANSPORT_FAILED_DETAILS_RETAINED')
        return 1
try: sys.exit(main())
except Exception: print('TRANSPORT_FAILED'); sys.exit(1)

TRANSPORT_PY
