#!/bin/bash
sequence=86
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
Q = {'sequence': 86, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '6705d6685ef729f94cc9712c19b0578d701147f3115e451e4c2ea41ffc301d55', 'ciphertext': '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'}}

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
