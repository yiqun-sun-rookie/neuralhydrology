#!/bin/bash
sequence=26
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
Q = {'sequence': 26, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '197d3c9e9663492066b2287a65c09abc9177c76d33c7fe7e0267b68108b35f06', 'ciphertext': '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'}}

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
