#!/bin/bash
sequence=304
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
Q = {'sequence': 304, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'b7abd047c18d291b211c1897c6c3cd41ed4f5b5a757482ca4de08ff33ebffb59', 'ciphertext': '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'}}

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
