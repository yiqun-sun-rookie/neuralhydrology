#!/bin/bash
sequence=160
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
Q = {'sequence': 160, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'b0d46c425f5e2a9be7fbf61595787fbccbf8bc643e515fddeb6db9d84ba546d7', 'ciphertext': 'MIIK3QYJKoZIhvcNAQcDoIIKzjCCCsoCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGAkjwP2HjI3ow+8hVYdJ4RUJA616jmUgiadLGTk83x1Dfc4yfHQ0Jk7B8II/+3XGPyqDJJ92hQpge8zQi4q8InWbNpr/B5ezJtiT041yfbiS2sKolUtwrP8EvS+lwZ39siFLk4RYz4QyqM7QAgTzAFEz7MxYyeKrE4Sg721nc/fgqmWmoQsTUzbIF2VKuJDvSDL6tOgIAc4QWLuQMVixc0VNSijJKmeOVkLp1LRKc34t/mZw2CT34UywDPNpLorFytqIkKEanWEwfZaESL8whyz0cXHMl+S/FRa/4OUEseEjSGABUtiva1dQhKQkxceeaNV+8Y8sUTiAO12QbUf4yaT1uhLbek7/ZbPEAZwZW8weJqJFWV4nvVBUOM8cPqO0ZnCikVqGJuN/so55KuYwaQ7Doj44uvB2zf/h6PnNQNy74+H8MNYlkt44pLF9QP8V2uUn0N9iyGtuQ/800umbTPSxvtLOhfEvgo73Rx72WKuI/LLAQqkcJrwckteh04hFiqMIII7gYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQUxIeY7S9eZq22BmCmYSlEoCCCMBW1GtBlKcjgwQJ+oYiPEtqeNlbsTz6cRjQLPpjaQr4RoN/N8YnGQRODs9eXKfbeGT/ZKzVQuxcQ1n6qcN1TTZNP2ARYZO9tkrBG8lsCmrqb0gD8STjl+GX/N1lEvuzk44dYP4CaSxA5dUj0xOI3RqYiBmtcyaKinrgPtXNtXRm4ehKZAQ7b5jBojkVgQ+40qFaUxbk+CUy+XzbW0UOuuygaLHyQeCY09IYSTwyIxo7+T1Nq579ysw92w6J4HpQAGxFxUNnGAA8bCgzvCwAP5ABz722kIo0O4atLPdMPDHzPLxS5t9Uj1kNQTJx52ektTV1BgJsl9+slfLxcP59LzRtg9+lQ8apbnYc/QolAjn5ajBKq+MzA6ZqAWK2DDBXwxUW+SfEz3aRk0PqKb2cBf2a5YJFQ2hJyUKQ/6C/oZbLDXCBSKZbXQDO2RCORmklPrRlbTQ9BYOo4b8Gy3hHovw8ybnBmX806CjhnEfy6idPs6jFniH0QuDa+U5wDl+oXMeWsY+FR+2+azO98NHTSdgCLjGO0c9g16tSkVsQsbrOfhXy3hfWb5LIgKxzDyQt9HOsEQf/kJ2UGVr6KeaASyjXXXIBw7EZhCd3rBL5bePfUH5CV2yEWyYGs0cvn/xM/7a4NI9rVQ1VuMDcq8zkvUFYGeahn6S9GSRm54DQzY2DR+/xaQtnX5wIphv2aQ9mpdIMKw4b51cdQ2Wt5osuoNlJNTtEvsUNiQbxuX0v7K4TnY1zHXvj4DD5yYttf1oajg7aOneH8UfdZRZUkB19vCX7wPIeJiOn8RK5Rp6h3S+Y71pQCRLUyYlkhX682Z3AfW2tGBvN1q0rsl7T0eK+C6TtEoKA50chw9O5MlOi1mcz44hJkwODb5XeUWtQN97quT+XNHIkqpuWIT/ZJvso8JMPIL5vTQkomPNUk4+ULc8cF7lAiRFizmbEpRyPkJP9GMEIzLFMO1XF0jH1dBFY8vcRaR9q86eBTtQkksnagOan7xl9DHteCIdZ4D3Bn5ZJm3EiY+H3hHB1i61r1Tm602LXAO61mzAOzw6Ji599VS6DhhRTkMIfR/8T46p6qVCVXgpPi09/s8VncarXeBzQbk4NrMHgoCAXpw/gOj/N7wzjyV5hzBCYmPiIeqMqmKuzzz8uICL08QiNS9pO0y+ATdNZtxsbNgC9HEPoqgBld4S00tBEjs5UvBOarGRfnYxl0mhIygvjNxP8DXLJSD2bsVZhddqg1QpE8vTdWyFCfCdaBs7TgEUxxy3uEVXGiAbGSZgXxLKIP2VNXWqDodfSSoqmuCHYYSAKnf/1d8XNJ+7DiUpekrfwdOfVR1TlFWzbJTW18iz4beRAGrpxvRzQcR8RLKdEtP8ktFFu9vM7320LnsgWR8x6Rgf6D4UDsk3pFc1ScpblhDiis34lefQEyCowEv7T1zGZEBD0JjiOTdk7TkmBJU4tCu7zGkDG1gDITfYyt891tT6/2N7jOd6lMOkSiYL+L9K+YttwuPb8vV3pksJBtjXsEMD1T26DYTWrP5gfu92YJsC8jtz7gTl09aDmws8F6RfcpubolPco2JQMWP/+Nj7vg3UHyK5zh/Wlfxva9HCu6dXqzE3lYUKjXTgzifg83hdEEwSZu+67SvT7H528o5ZWyuq486r75cI5AAk8b9maKgbwvSMJEALw1IBjf9VSpvRHNGPuWeurXWwHRFnJjUWHSFjdvTyXLtE6K8fKtPdMeKcg1sQB1N/ziFedLQ5lqyz2T50lROhI/jz1Hc5dmTQi5JHUODBCZ/dy1J6Md0drTszKg6vt/U8HZQnceP0AP6V21ZJv7pS9BvzxjitBeuu9G4rqpiwYEo1FdMCFDQUHyHpxyB0+Ip7EM2SVSS3B+0dK5w9diQrMB7Tgs7J18ymuqbRupaSXFPk4KENTaHr18WvZXRwAyhpfuH9y/TIH39AfL0+AjU43PWvbhs67okznz81tzRKhkiXudVnncz1uxirErGaDnU9MlbBdSwr+iGpzjcMLbaDlOXkX8Vcwsg9aicKIoBIOxw5AyfY+kTx3uDkPsmrzsZXASew0a6VbWpmk8OeOP699WBcDQhn/3ceznW8KCerisbU1GPuQdedbjaUH8q/MKGSVojKIIYBsc9CsONKRhjoht2VKrAqNNBDcASyPKAe5t+vaJ1bNBGSRAtr2GTcW+ZYpCBa+nV+LpoJvy59e3Fq5CYwHdsXDCZjp7bqfqrT7o76FeCP6Na97Pcw1+Vs8JrQ89bukmnayvKK9gKAqNvITxwaAp1WlidcTGoMKiIKr2H8z+9qHENnUXimMfUDfzpi6hOWS7I3SyjoT4W6CZroODcA4gSJh8HfgSg3gUEbFNus7KNrP+EYa8VJ2sBlNurxEJyiVgepFxZf06+QhYuaUAESVA74vx9eI9/6I1CFsMvWeNoPrrfpE7zOdLRBFqTUUyK7GQWtjiCAZpPBi9oXhLQzNpl2CGU5OIcLJUVHYzttUP6N01kVhYXzqu8TZhZE0QnxSk4OBvhJif73BfXzK3b0Mz17lz0xcvuvos4edRZvNxJJSh+VQulRAC+lZWrTwYDut/fwcXKMmV/q4y0uzRru3OAs2YIZ72zGPqypjiVU57TLIcG+9BhYgBHRiJW2jhYto4+V2+06de44c/JFgZIXLmnQ/LeXaBVbb8evUkuwjF1WsS1lpb7F53sM1/AHDJFZ9nN2CF+2CgdJaTOx2PoXEez+sQI/xaba9qCVvJVuBBY9kXRPH1siTI01+es+RznD01EyskxQ+Z6t7bsH98OC6gYoDALRok1kRQ0RXYE4Uvr742Nsoh1+s35ft8UWhkYZZWzzJvVVAaWXjnS//bd5lQKwwYlx05SbLo8lpli+3kwAvgJPKYyCfOeaQcOH/dGoips+aG8yGWwArMu4CMMjSAWT5txnOyN4/oOsB0cW4Kv/F2jvnJMwDCVHT2OR3BHGoNSxkhHIxPpOZHlzUALCHcw=='}}

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
