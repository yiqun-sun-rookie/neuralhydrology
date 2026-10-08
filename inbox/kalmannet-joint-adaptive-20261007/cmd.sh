#!/bin/bash
sequence=70
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
Q = {'sequence': 70, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '596261c8daf160ac101ca3603f4adf84ecf11ae8f295394af7c3d1bee8f4c004', 'ciphertext': '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'}}

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
