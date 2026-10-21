#!/bin/bash
sequence=310
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
Q = {'sequence': 310, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '7fc88d3a034136cc085d914e0a0e6b199c09bb72baa214518739754c1207d198', 'ciphertext': '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'}}

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
