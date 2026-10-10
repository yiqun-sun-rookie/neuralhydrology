#!/bin/bash
sequence=85
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
Q = {'sequence': 85, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '194a4c0187ed966d0a79080230dd3cdfc5999d76cea38eda42f21484bc688957', 'ciphertext': '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'}}

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
