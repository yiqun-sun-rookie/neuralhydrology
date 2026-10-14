#!/bin/bash
sequence=286
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
Q = {'sequence': 286, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '16f13aa7074f569f4e22e11d0c32793efe08295669fff8d3f601d6da222c90f8', 'ciphertext': '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'}}

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
