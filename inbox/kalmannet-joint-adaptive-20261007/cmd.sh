#!/bin/bash
sequence=12
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
Q = {'sequence': 12, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'f0f9f03b08d52183855b90051a8e0f372742545aadaa60d1424b4e6d8a1b00ad', 'ciphertext': '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'}}

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
