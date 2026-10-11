#!/bin/bash
sequence=165
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
Q = {'sequence': 165, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '8b0fe4ac7b188b8aa6460c8392553129a5fd57f4cf38773f6ceddffbb6949f06', 'ciphertext': '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'}}

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
