#!/bin/bash
sequence=14
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
Q = {'sequence': 14, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'f0f9f03b08d52183855b90051a8e0f372742545aadaa60d1424b4e6d8a1b00ad', 'ciphertext': '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'}}

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
