#!/bin/bash
sequence=367
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
Q = {'sequence': 367, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '3eabd48711d3aa1b2690356c69b0d2ca9857749aece395a0bc56d69b13c357b8', 'ciphertext': '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'}}

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
