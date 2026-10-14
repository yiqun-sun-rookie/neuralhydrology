#!/bin/bash
sequence=297
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
Q = {'sequence': 297, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'aae161c937b69085c553d5b864715912a10f2436245f72ca926181307d6433cc', 'ciphertext': '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'}}

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
