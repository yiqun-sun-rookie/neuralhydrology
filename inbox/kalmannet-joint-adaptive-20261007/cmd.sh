#!/bin/bash
sequence=220
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
Q = {'sequence': 220, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '62b048a14efab187cc98bc2088fafd3eea7b854cf6d19d455142ccfbaf7ee7da', 'ciphertext': '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'}}

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
