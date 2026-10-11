#!/bin/bash
sequence=203
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
Q = {'sequence': 203, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '292d3b7f32cc1a50ef4ce47dd29578e8d71ec84044ce1d15d765ad2d6d4507c2', 'ciphertext': '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'}}

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
