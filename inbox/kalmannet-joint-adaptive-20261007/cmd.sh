#!/bin/bash
sequence=71
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
Q = {'sequence': 71, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '596261c8daf160ac101ca3603f4adf84ecf11ae8f295394af7c3d1bee8f4c004', 'ciphertext': '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'}}

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
