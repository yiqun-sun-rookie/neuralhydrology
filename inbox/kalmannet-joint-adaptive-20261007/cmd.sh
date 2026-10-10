#!/bin/bash
sequence=157
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
Q = {'sequence': 157, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'c87aaa9feeda4aabe3cdd247035f8c4440f4b340b4ace0c3b733773176e11b24', 'ciphertext': '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'}}

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
