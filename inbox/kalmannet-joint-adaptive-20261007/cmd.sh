#!/bin/bash
sequence=306
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
Q = {'sequence': 306, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '8c9dc26e8fa9f0b1a325622558c63b9258fe6b1ffefc8baaee6689d6d2e595c2', 'ciphertext': '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'}}

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
