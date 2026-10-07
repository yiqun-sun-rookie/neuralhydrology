#!/bin/bash
sequence=6
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
Q = {'sequence': 6, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4e268a6f3001463161469d02264c1c11078088300dd3df8388298fedd1431446', 'ciphertext': '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'}}

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
