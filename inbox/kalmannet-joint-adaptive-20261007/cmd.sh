#!/bin/bash
sequence=111
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
Q = {'sequence': 111, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'ea9f3c84040909fbbbbecbf5f2e02ab2e01bbbaec9bb2b0850e564d178443425', 'ciphertext': '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'}}

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
