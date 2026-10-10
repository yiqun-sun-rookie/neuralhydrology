#!/bin/bash
sequence=147
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
Q = {'sequence': 147, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '1bb483db72fe56bd8c3a4620503c9aae174cbc82fe59c60ffcdbd9a7776fd387', 'ciphertext': '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'}}

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
