#!/bin/bash
sequence=176
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
Q = {'sequence': 176, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '953012738feea4c295ed3c8395b2304f8695d16f59091fbec75e4d8676d7d968', 'ciphertext': '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'}}

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
