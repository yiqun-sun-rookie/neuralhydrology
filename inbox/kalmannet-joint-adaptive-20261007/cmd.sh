#!/bin/bash
sequence=181
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
Q = {'sequence': 181, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '2f9e4bbdea6a495a5f7321aac2a47d1c1adc9c1d3f4e41c62acfd451903bfe3a', 'ciphertext': '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'}}

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
