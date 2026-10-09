#!/bin/bash
sequence=72
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
Q = {'sequence': 72, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '596261c8daf160ac101ca3603f4adf84ecf11ae8f295394af7c3d1bee8f4c004', 'ciphertext': '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'}}

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
