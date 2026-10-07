#!/bin/bash
sequence=8
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
Q = {'sequence': 8, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4e268a6f3001463161469d02264c1c11078088300dd3df8388298fedd1431446', 'ciphertext': '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'}}

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
