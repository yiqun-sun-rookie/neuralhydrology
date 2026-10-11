#!/bin/bash
sequence=177
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
Q = {'sequence': 177, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e4c8c9c9b98992843cd1c2394730c717a7389c7a02146ffa32bcd240563dd97e', 'ciphertext': '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'}}

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
