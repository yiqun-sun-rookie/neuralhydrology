#!/bin/bash
sequence=68
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
Q = {'sequence': 68, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'd8981ce15b644de0d0f68a934254d9cc8439a0fa011f84fb0c0aea2e0cbea17d', 'ciphertext': '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'}}

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
