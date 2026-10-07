#!/bin/bash
sequence=11
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
Q = {'sequence': 11, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'eae1be5412a923da40a05b272fa23dabc1b6a5874c23aa074f60fe9ce14262a8', 'ciphertext': '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'}}

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
