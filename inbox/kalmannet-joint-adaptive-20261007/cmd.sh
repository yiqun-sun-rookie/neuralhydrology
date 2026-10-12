#!/bin/bash
sequence=236
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
Q = {'sequence': 236, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'fac0baf2752a57904c5855ed7d24209b7c6f5adf1e29297275fd19410a314429', 'ciphertext': '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'}}

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
