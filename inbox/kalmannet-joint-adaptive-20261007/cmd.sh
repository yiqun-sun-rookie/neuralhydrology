#!/bin/bash
sequence=67
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
Q = {'sequence': 67, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '9f1779aabf9ef50dabd71df5ae19f589e7ddcb73502fabf6937ac302a77abdcb', 'ciphertext': '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'}}

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
