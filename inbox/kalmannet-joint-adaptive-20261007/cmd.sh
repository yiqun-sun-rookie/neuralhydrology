#!/bin/bash
sequence=156
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
Q = {'sequence': 156, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '454ec634cb0477b06400263e1cb9b13093df5462dbe5cd217ecc0b2586141d5e', 'ciphertext': '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'}}

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
