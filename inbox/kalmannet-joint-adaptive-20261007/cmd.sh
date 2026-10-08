#!/bin/bash
sequence=66
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
Q = {'sequence': 66, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '511189203a4e73dcd6ec7978356db151fe1b907689bf05915d19b2ed7e37e966', 'ciphertext': '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'}}

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
