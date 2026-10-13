#!/bin/bash
sequence=246
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
Q = {'sequence': 246, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '7986cb2b99d44bf4907368ae15951d3ae106d08b01e779c3ce4ce13d53789dcd', 'ciphertext': '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'}}

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
