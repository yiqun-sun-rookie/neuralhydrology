#!/bin/bash
sequence=13
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
Q = {'sequence': 13, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'f0f9f03b08d52183855b90051a8e0f372742545aadaa60d1424b4e6d8a1b00ad', 'ciphertext': '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'}}

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
