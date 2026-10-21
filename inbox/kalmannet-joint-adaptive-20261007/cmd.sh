#!/bin/bash
sequence=312
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
Q = {'sequence': 312, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4c3469b2b17de1f4e51533831b34089d0d7ba246fad9b2fd19bb27414b7e6a2d', 'ciphertext': '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'}}

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
