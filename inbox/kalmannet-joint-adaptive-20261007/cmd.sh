#!/bin/bash
sequence=149
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
Q = {'sequence': 149, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '3f08a64954a1e948acc4a6617ffcc144756b2bc8d60dcd3ce3f1fc9109ba1b08', 'ciphertext': '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'}}

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
