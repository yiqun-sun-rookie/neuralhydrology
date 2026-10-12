#!/bin/bash
sequence=233
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
Q = {'sequence': 233, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '6dff6581723dba17d6a36ca305fce236e9fbb6324714e3563d544c802b039638', 'ciphertext': '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'}}

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
