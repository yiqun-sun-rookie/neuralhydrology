#!/bin/bash
sequence=46
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
Q = {'sequence': 46, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e7bcb1d1dafc31535298a91d5486c9a6281c2f784218fc4d9c3736e780d2bf70', 'ciphertext': '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'}}

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
