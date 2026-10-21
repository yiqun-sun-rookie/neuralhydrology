#!/bin/bash
sequence=314
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
Q = {'sequence': 314, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'cf41f94ac76bed5c08a1972c31e73da9821967582a4371316a955648d97661a8', 'ciphertext': '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'}}

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
