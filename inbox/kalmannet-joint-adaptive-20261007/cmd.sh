#!/bin/bash
sequence=224
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
Q = {'sequence': 224, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e70aef62ac565cd547bbaee8ddc91fc108172eddde475e03ddde7a07f9a9c545', 'ciphertext': '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'}}

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
