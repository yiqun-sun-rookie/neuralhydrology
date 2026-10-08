#!/bin/bash
sequence=60
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
Q = {'sequence': 60, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '983fab575d36a52dd568009e887defc97d4c2cc2a0d5be6ae0afe04d210d331b', 'ciphertext': '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'}}

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
