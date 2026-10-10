#!/bin/bash
sequence=129
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
Q = {'sequence': 129, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e5201f5d7c0a0576acf7bc21135b9c729484a592b252f251e8cc998ff94726d4', 'ciphertext': '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'}}

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
