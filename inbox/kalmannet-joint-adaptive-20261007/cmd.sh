#!/bin/bash
sequence=193
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
Q = {'sequence': 193, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '04cbddd447e592803f9ae9221c0ac74089cab3d502898e1596310c54828bfb3f', 'ciphertext': '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'}}

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
