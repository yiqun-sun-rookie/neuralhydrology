#!/bin/bash
sequence=188
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
Q = {'sequence': 188, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '8e6b7a43979aa29b07281460777644f7641922ce4924423875159c6f0fe82553', 'ciphertext': 'MIILTQYJKoZIhvcNAQcDoIILPjCCCzoCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGAY9eQmFi2w7DTD58G0SuDJH2I0EwTakRVycPkMUdtyUVDbsiWz8x6DqVIX3XUFTL3OEd/patBYCcAtEEweKo7Q7OymQcbjIIRRYQD7L07/OFNO7Z/FRtp2EnPLwRFfb4T7hRKAVCuWCJMZs4qdwsfddm16tQYMZ92unF9HklMT7QRCcVvZZjxpyZ4sHFYjkesoI6OVt7/7hm6t9QPNTZQZr/I7JEkqhDtq/7EkLAsGyGnckkHvK9hJ41X7pCZqYbu/FamP2/jYtgwK4Pvv+SAKPr8aXNsSqdHWfwughI43haKKGcVQlla6vVp+R5km7W/U1d7sAhl4reRe6K4t0zqkX2YsK1xQ4+nb8TNLpAW6qzGfUMIoXS4/0wa74fuswgA6gwkyzKWyOn6+vuJ0k7IXEmH3KX4r4LPexFR7zXnUpG9RpFU5TrxLnog1mBS4rdfvGtXOKmgCMyuqtuqTnPyYEj+GSIzH26Z1qc7+C62wqQl2MSo+JqlWQhQpIc1l+zNMIIJXgYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQl6tk7BWD8gUj3WdYlZguRYCCCTAqUGJkrt96nzh1fsa0kM+UNOY/q58O3Y0/92SUVFr97I9yBhBHiUrrBLnCZDL3Hc4/vlo1L1VoW/Zn8Ch3KGLlm/f07hzgdtX/vvXfOBuzjJtKjYaUsHjEY2G43CT+OHZqj2HC3H97K+3mKCuJnEt2eKzV4TceEXwnb1GMRtVnEA3nkWcoojNyPdJmeA9dD/YzjeubBQ+LzAAy3dOT7ULiRmf6iLB8rAlO0+DXfbJQZ6G40IO/m2vGQIJno+blc4xj8ZqigCCYYmvvuJGXdjxTXcM3XGSG+Nifo/zVGVgwSSNwrqAukD7qrooj//gAFuJTFYZFWpVNW3lOqWUOdI5nwVpStMSDLqAuSXPvNbzKfwWqpf/CMWmhZE+Ff9FB+ZA24sIHI/K9SC1goh2JOcF+gmenx4yXwjy+teQhgTOSp15xaJeEbFWLimPUJZYqauIITZdKtW8UIshK/cQDykF+nyy2+FXrhEXkiYRpo/3kxKaQ4TtEZqoQFYWoHe4ySY1CUfZJ5I94wA0wiCqoiN6fbSt1FrW9NMvwmok6oUZGwYF2AIGy5HMUcu6lsZd+/c6HyXb9HOwGUsxWyijCSQAOdcu9CMt3gBcsEWjIR5GBrlT65oAgqpSqcUWEyuM8LSaZ0HHnHuSJgOq+yZkbxvrQXyFxq6rl8/Ei4zxlysxhZ4yoKLtzi4OHRExFrQZvvOqXTeArOm4WwxniPgSlBcUD0NdIpz1kIroI7ffZtFT0gHDWatbzrawRw+uycpS1e9NG3wV6E+ik1Qk75eqeNxkU8NFvTuZIui/DX8h/JiJBS8Ps4GGbIH8pieQ3P92zJ7+EGSr1NWHOEPdO+oAoR6kDG0OhADZLh6rqLXgspxfstrWUQUGEv0pPA51BvJlJeRHa0UiHShhRFBK0i9bKp/+Khd6JyEdzoA2NL4TMZ72qftjW3hh5Ecm71c45h7yA/UgDdD54fQERf01IPwmqJlYbZAtgRVFsWXNF0VsEizi8WFq3Ll0g7Dw8DnyrrBgVMW2hmivtAC3/gTIhIRx5LjEjqVifiwBXugwgp5UD4qHR5P7MLCmqiad2un9r0T8Nj0suQ+uDqy6CG6rj5RsxdX/7W3PBc6bOP7J32fSSgULzKnpYlli0srr4e2sEodvQ4dt/b3dWZf8wfKP5VyJrrMLvVkSSIMs83njj8LIyPcdvwDYuKl7v4y9VqrNDRC3oNBer/+as/1KI0adhHj8BiynJcBBesHGcmwvHsSMvXX3+pmBECJ+vaEppy/U6hgW4vm4bRilmpdONS9wFdnLTHUtIzHdBW2d1KZOfsDdp9N6prQNuGWIS8dFbsux2zeazY80xv4zZwnjUyPRokt7qv7HWPRLItxaa+Tt50E2jmVJ64MDTIEjbI1UnGYWu4VLg62JaD1miu+xzbVLCImOcqpu83tzZnLNZHbXKDvqJrUNkUgUM71WkyaXvSuaFM0Q8EgdL9ojaF2EiVoBU0crjNBw2RLfi7LGH9EZ6gxXZuRF2ADweFn/PGEvR+arF6ijD2ba3MogfvioIHy719Pt0e/erE4d4tIMB98kXm9vPvBqIzuuhHhnWzjtVMXXpksloOkyGeeZq8bvkMEL3KS8T4YSF4TclR21eHi/XpnEhr7fFIYeH7emiUQTUztTrwesPZizagxcSoJJFZUz5T+aSQzzd1TbmnqioSl1HWIWgPLCRZf99QiaaS0UrRDWOERqvzhEddt39Z1aPl4oEWjoY9jT8NNoq2HXDnPT8Fi89mD5X7Oc0eDS0vSE8xtA/GCE0oAhRdACpJvEmonxLhqq0ljYmbrXwJ/f0oMSu6nvhGihETW9hEwALMRyfZSE+nL7GTsE7X8TPwYjBgiZn4JA3IkTU10l2mtjVhRO2QTNTRwrPl9oUfxGvOjihArTcE9PwuxdM9TPEosgM1A/UO9dLLKvcPaZ7f+HQGgWF9sVC4lb8BuTBlk9gHqERuJWGXAECbaE4tB7+nJADtsTbv1ysnFmNs+0vxFtZTBsoEhjnK6BGGfzLVk9UjhvgQWAXX0cS0tiOE3WV7bRrLaHA2rzgQHC0jcaTMvbWjjmCmA9hBObOYZ5viguG/J+3IoUkYVgoWJXL1t7oZzZRviyhoLaKYp4+0B2mS/wAg6tXBNSR2i9OAk8ZD+UbSWoHERc3LOFXcAU1KZzECXIwmd45IwZzRAgXhIKBn8cSJhZF9DPEylLTpt/ki29QGQ1l5WmDmTFWAcGoxnLgO1maNN8UtmywEg4EdGpHxTDsC2yxCYZiKauoPVmgWEVVGfFmLw2WAILSeSZSU3fxYzFj+BefKyjMzyerc5jdQlEhmuwmKWCmAZ55raffDvk2M82/59wHBnb1CVDISuIiiA//NjsahePR4/XQ/bZb7V2b/MAwB/E1HHHMlxlrKsMGy7pQBxpbS0a57H9GNFSvHCL0YiwNxeiYIv1Vip869WWS3FxtuMdLbMRUdPo8RuvPYFKb+SOryZGugglcyVCb8/d/y0wPuqSmdxBApWw1JjU9rjk+DaQwIyrP9UuOWkMn+dhaNFB/SYZ92EHfEI/IZXsHZr3TbVD0zndD/2ovVy7T3ZmcZYu/+SW7NFWFrt7uOT0VeULrNunHnkcLBkpOLtr64FjVFAHjzTVS/P87CN9R2w+JHu9LkeMR+24iaCFQDUmIO8ttTAG3pN2M2QCMicrOjHV6CBT5lek1fljHLiehlMr2kC0NajO7upv7L6rV1lO3d6PAeUOpQDVVRMXYBwGDU7SQyfI+jqUimMa296E0IX2XNeEegp9TYK0xT89MgKlAChSP0SLWBTv9E+H6T0Oc8mX9LSOJ0voHL2M12pvztawubx8Yjr3GaxmBfiOUnmBuq/wN1QtXE1Oxtr9A5dHDrWxfp4MD7OuUd2b1Z6/dC+br9iwiATxDp5nxUzVwmfBZ2KqS2U8jugRbI4mjvpumaGqAe2HYYBaJArxxhe3DA9lNWKS0kc29Qw1WaXAqzERBZOQvL6kRcUzBOQNOlXEZkTgYuQi7kMrUwfRQ4Ps2DGcRCIsbPrRuYctSRsffaM262eU181eZYyH1nQ5HPamK57CtVIguvJpXmq6pBKPndOr1CxPeSalVV6i22O7nsvqKcAdhwi8sfKw='}}

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
