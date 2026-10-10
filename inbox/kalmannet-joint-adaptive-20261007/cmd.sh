#!/bin/bash
sequence=119
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
Q = {'sequence': 119, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '0d1201b7e9eaa838c5aa00acc99a2f843e49f2a6fcca13227529e17dedb8d288', 'ciphertext': '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'}}

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
