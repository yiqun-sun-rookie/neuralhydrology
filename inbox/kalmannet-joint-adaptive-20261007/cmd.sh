#!/bin/bash
sequence=254
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
Q = {'sequence': 254, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'c637bd26ae090cab1a95550a25ae862029c18f3a916789408f7028953455a00b', 'ciphertext': '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'}}

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
