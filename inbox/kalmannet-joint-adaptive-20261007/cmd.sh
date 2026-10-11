#!/bin/bash
sequence=187
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
Q = {'sequence': 187, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '242e6dfa6288cfb81c12f300758a0db9eeb1b2ad613a0473c0b66ab9454bebb0', 'ciphertext': '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'}}

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
