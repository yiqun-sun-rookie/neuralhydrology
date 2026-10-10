#!/bin/bash
sequence=114
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
Q = {'sequence': 114, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '53d35b1553cf8c345cd0651497924b296a6f19440ab57eb6c921ce721b845e52', 'ciphertext': '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'}}

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
