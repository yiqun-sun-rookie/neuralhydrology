#!/bin/bash
sequence=108
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
Q = {'sequence': 108, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '656aa719bf5379816d04fff204761498f20349ba51c562b8f48da4c132534712', 'ciphertext': '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'}}

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
