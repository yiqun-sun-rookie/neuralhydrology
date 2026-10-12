#!/bin/bash
sequence=238
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
Q = {'sequence': 238, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '6ae66142f4722c80f72f87a8730aad7abf96712da2188b44b6713b18cda42955', 'ciphertext': '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'}}

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
