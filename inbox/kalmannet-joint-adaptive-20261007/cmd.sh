#!/bin/bash
sequence=237
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
Q = {'sequence': 237, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '82d75438e75513410287900c792873c1f030dac5809733bd8d1990209b519f57', 'ciphertext': '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'}}

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
