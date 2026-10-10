#!/bin/bash
sequence=120
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
Q = {'sequence': 120, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '0765ccedb1456f89f56dabf8a0ded52b55b7a13c2785eb5ae582f2918af2a90b', 'ciphertext': 'MIIInQYJKoZIhvcNAQcDoIIIjjCCCIoCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGAf7XNsXVuzC0nnUTro35oiubmoldb+prs/eUEQf2qa+zD7cvDdujY3oJi+6eAp68Oi5709CmD/HH3AJ6v5dtmSaITtYokfKbpv1N+8pTcO/hxxHvMBzsKAnfOR1I6IN+I0ns7AS/1Vb9upjBGRuOrY6u0yXve8A1/beZc7WywfezYUod77Sf+UyQEWIiG1n94WLJpYDP0mr+jmMl/2ykaG1lIuxziocQAYJ2y5+q68IKR+SO+zrbe/8tSYqGgWWGmC9rEitC+z25ML0c42xlcr8/hYxLxWu9iCBfv8DJcGlBb9bEL/ps0ugJcUZogFr06a21MysJnurSRiLwrKhPwRZE61ODrGG2ddZkKdSj9cfHspls8311puJNUaRva5ltwffSltW2izDN3VMp8rnNDkBNg+6z/DVKUdtfDKnVhTrTv3szTRaY8jZz4ZMrKZEK+LOhoKjb2yj+FLDzI5eKC/X5KfRVj683jHsoZEHiWRKNN/4kIFruYaEC02JtS7vGJMIIGrgYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQKtxWJoyoVl2adcyMIlZ1w4CCBoAQ1EczGF7Vb30w9U2XnRU83atJIVt/7c6vkq6LQh7FIb5r/wbSQMqM7zfY5jyVln5fdFyJjsCbIFjJ5KhB7cDUFVcKo/hqe4lm05TnMuT5jC6lCZl/APpXDa0Ze4AcZ+CgLhogCWYYvHIpJW55uL7UkSKgjQyEVKtuyY52KlAdHn/lNajhpwZtw9UvNapXwGcV+NKZ7vvBoApDtVTqdnJNajRSM1zrrEgWF4I66EzK4RK55qEo082+cpQxoOoj3z7HCqQx9cuSggj8n2hFCKZkUmZtqT5HdVDilyknlDPOaZmpl6QL8dFYVVotp1Ic9zm6GBHzEExOUmvu7Ya7cYmAphWZ8WBcl5gMy0k9wFJKoSFrC07EW53y/AcPib94E5L93oJmtO1adinF3xc8rJ43nR5l7pt7TLB1QLtz/9KgvjkQLsg//75Eb7PQ3s9BT46hrGI8Leo57Ke0xY7vkh2GRM7xecIe97sqyXN/wuIvspbDma4RkbwQlBNlOen7aQMnWbIo++jbKhMaOVe8JXsptDoxYAy0HUw+nSRrO1lObU1n/8Fw7d7v/g2erky0qLrK7i8lmzYL+/e5pG+ktTlg3e6F3pJnhHxyhF8aZUUyaDOY4qqWi9t3oK503QthrPyPYefOn5J4lmRdHR6vzCP60ADzVAgIIqvgtStl/zu3r51h/zv94v4tQHN6dVfUuBMedCdo4L0eIL3n6IJd1UQgToaMBxE9t7gOMIWVnGMS8burFQ1MO4qsnsluiYeYCFETLPNz1vivvzvXnQEBOEL6YKX4ScQxnrL2+VzUed8hTky8uhB9J9t7Ka+JBtI6iwG55LI+VD/CNz2kTCci2BasxduMQjr04gNgu2tqBxBMj7a6rQlyt366BUrace1M6ExRdCvb+nld9Ndah7Im4uPYLt9HLGNrwzTPd+sdUlFdx192T5rDReWlm7LWxd5MYiQ7po5/n8NnHwkCVEu81Suthd8iIiPrCyAfePyscNyYVdXhOiiFg2yG5ipK2Zfo23OZanYWm1C1+KHq+WEZHP+D5uX1iZBZyKQA5Mditc4CQPsVQBXidk1HcT8/NRjsTaE4eeCrkBD+05H9rU2UZxrHjEkNkEUj0mmFTYzK9QMKQgH/63mvgtVwZI57B0MHBu9YY7a1z7XrfAZj3TPxzJtBAznN7oQF40bdR/8vnQQwl5N/Af/Zu7PUsX1dOi3xnKaIRdgnUbrQxt7wKU1rAi+b69s00W7wbmpYz76h+uwhnBJ8h6sKcBkQzcVciuLz1ZsidcYosjkw0IlTK/hR+Dzf8TgWyujfowYJFVkdN7dKHWqz7rdxmcuk7ioSOeuorNd9sgJBWaoopK9xuEUaLu5yahW7udAy2ixFdU5uASTSpfRFA4aU1Zmu1BV6j79AMoLWg1aQsaIi1bKLvnW3NmUmGHRxNMKdHVIrivAZnbvcXGuh/jqYofxbbemUg5AjX0bn3+Sf9jOts+hYxGBbxYYYDPfXKPXa+Z72JjRWhHayhdd6LLZ2Tfv9DOb4rl3w+KudtHaPqwVvRXKhaENhCwhSi2MER8ssCjMoOAk1HDwp2i+HfgI/PsyZwz/i/iPNmvZ1P7aJddVbXUO21GoJ+OIA3tLk9p9P2UEgo01I3DaXT+rA94UdAJW5LMRuaEslo99vOoy0B9Dc10y5dVioeCcW1/JVXdObvT+/dRHWyLgtxepm0Jq/r7SFF9x5fL2gcdj5a6jVfHWbNqMk//FdhUiBRIR40tUDNtM11kdMiY3ljGgCYEPqyFSEU+b4HwYZue2xbq6ueFkuTqmPsV+kOXTxeP1x81zhqzbC3PA2Lnm9PedQeDpeUzRQ8gBb5KCHp2TgHOWSa6p38xRCx1pbe8OcEjabuMRN9k8mFWmLqvN0J5evHIhuqsOudOJ/RbUIonTrOK5180ho7oeUJ9GAhHGN6o7hQwk35NIxGhpau5v7BrGXmcbsiMNit7zMtauqTgwVy5lB11FUOAr7Gyv6UH1o++NyIhIeAMkNmXtgsc03WSgCBm9Byn902axpRQBBWbbyJ+j2l35vJWqhpXqxaTAmrxdiEhKgj4VWtqYFSu3m+9w2uZmZfB5o9cm+HuNPrep2izOvxz2xVsxWSLdQj6zYnhqHHCXvCidvTNYAPb0vnAglH5VlBM7mpb1m2FzVH9SORVErJT0mNkRkUlae4hz9go0oeptfsIOsh/viLdkyRQ=='}}

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
