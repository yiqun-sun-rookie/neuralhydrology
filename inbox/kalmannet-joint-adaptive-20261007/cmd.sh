#!/bin/bash
sequence=49
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
Q = {'sequence': 49, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4031cda78a6460701263f3ac436d8c41929207bf29830ba5659d646334bff251', 'ciphertext': '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'}}

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
