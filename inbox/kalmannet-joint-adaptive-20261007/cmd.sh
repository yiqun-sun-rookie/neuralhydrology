#!/bin/bash
sequence=208
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
Q = {'sequence': 208, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '99046c51320dc2513239fcb9192c54fcdf70492c1e5aa6c9372a9f04ef8957fc', 'ciphertext': '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'}}

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
