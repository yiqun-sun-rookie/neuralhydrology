#!/bin/bash
sequence=38
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
Q = {'sequence': 38, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '616722854151ebb01b4da5ef84cea8c9274514b8cbea8140004143fa8467c1a3', 'ciphertext': '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'}}

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
