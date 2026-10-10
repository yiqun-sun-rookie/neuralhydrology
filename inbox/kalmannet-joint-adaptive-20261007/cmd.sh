#!/bin/bash
sequence=117
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
Q = {'sequence': 117, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4b6cdb3508374cef60f22800e3c301a2cd26a4645214d0882b77e7fb2199d5d5', 'ciphertext': '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'}}

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
