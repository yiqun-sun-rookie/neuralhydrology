#!/bin/bash
sequence=9
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
Q = {'sequence': 9, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4e268a6f3001463161469d02264c1c11078088300dd3df8388298fedd1431446', 'ciphertext': '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'}}

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
