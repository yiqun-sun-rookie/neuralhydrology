#!/bin/bash
sequence=144
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
Q = {'sequence': 144, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '0d3db0559929dc4fb829625cbc5aa69821efaafe32a41fa178ff77a140540cda', 'ciphertext': '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'}}

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
