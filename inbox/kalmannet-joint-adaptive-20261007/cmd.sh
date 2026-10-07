#!/bin/bash
sequence=56
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
Q = {'sequence': 56, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '059bfef8cc2c563cb8b6bd30899f358e9017a07841a5868ac1871530650de562', 'ciphertext': 'MIIQ/QYJKoZIhvcNAQcDoIIQ7jCCEOoCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGAPNDhOKqelhZ/9Vufbx6MtNLZ5mPYklG5uf2ImmOMcswKXUtE5NyObs/Pt86FGjaBUpQi5uOyw8bMFo5gAQ3PPbU4nMlK1kywVk1zA0rzRxW2JRorGRCGy04Ke3eO/KmUW8mxgsJ5Vlyh5KeXvRFHoz2mrL4HTNbvNxqKszaJGom5rejiUQd6SiXRyD7cSTIp/osQLPZpiirZQa2w3hhCAOziZC8YrMr6jPG6J98kjCS+8kHp8gFA+V74QDUwmERFZ6RyJTFQXpfVq1kgstG6H2HcsB/5uZH+a/48bly58GSzMpee6C0rQ91couMWs4IE05bTTyu/7XDDoXCvKLUkFgQaEP2GFA9Yac3dmuTDOl44UGe16WbakmWx2/G2F3nsL7ZVZpFuIylOBeb7GcvB8mssxeYWG7h9nCP7+UmgGkX+LWVj8JKOREQi8ILZRfl/kn/4zSReeN5NufpckjPPNGk8v5w0+i+EMK7eN5zcvynxgV2QL4uYEZ25CjagECkAMIIPDgYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQEkB+Rp+EXnU4IzzHIaPdfICCDuDVhEfFYp5bcACYzXSfRGyUZO/3GFkXzYx3cTJSGk7Q9AC+hcCUo4nJEeizm9zb1ZDnKQh0RartLH1Y2/7uOWh1VmqIdCGm4+s/c10WHmpwBt+YToCAbKcyh6L9dA9TStjKVxFH4Ez+NVwXrkqSJZSScgTZfPlr2270VvTCrPOOJShBlP8MidVCa7IBBVwp0fHCF5crm2jDkG4d6YBN7YWhzfCIEfETTR9aSD0YqH4uH/BnmQ5kMrQOxTVceLeTOpXQJpFcvceePhY/eVCIbAzYVVmJVbN/oYF8OMJh9xo4KZ/DKYzPH09A3So6geNoZWh6VFBO7MI15DRB4I8sFPBqKBDoSW/KFkaQLIFjHSskjrV2bF1w57QwUn61YHVQwwI0jtG7GGW4+C+Df6Tw0oUoFitieSanYdzVcXsXGDix7j5gHyhThVNdWP225MUAxfGFetYeZFpdsZMo2jEmL0hXkd7aNHVpMIoVrVRGSQEDgZ/Ve05NGVSZ6nFgT1GjgC0/ZHHKXrykAFKt8na0VI7zG7PudZGc6hQ4+Vw6MV6HldD1KukXEZCZvBXelCPI4Gz8ghCTdqlPYGetfCya5Q/61QFFH4Imt3+O1lRbjx37pFH6hMRPuE7Cvtl+zgeokPV4mE+ycBLGPuQ5tFqOxWmxIgOixA1eVuUj0wuACId+J+MyyB0RGCbHWi7SG4lDThyYQ3EqdXsm546TxsWE50Q9mS5oHz9wdh/ogM5G8IjjCsdQfHyt0G1YctopPyy4SDQwmovDzCEdI4d3mYNC1gK0shFUTxWUIHwbprZtUf9ukrwFv/duApeg5x6dkcgREZSn5qVRGunvLlXS/4tHmRRB37CgjMdAHtr6iFXmEh3+iZ7CaLI1b/0QdDrc/2m5mVDhBemFI63UH5vePcAIUdR16gDrWtgm/unzi3H6NcZCEBWT2hx9KFN1uIAlN1Q3w7rSbpTrAa+QufEmUpfCSj6sahYBzKJU2QXwIeP5FHvEZWUu2M0JIKvXvCTMdvRZuQaCUtLASfT7F154+nmDWzWp18kbOkeLLMWxuJo8I9VVroCKMfEn9dVcibHFWlqLZug59iqi/9l+3GUp9ZF+hgUMchQEq/EumevV1re1L/4GFPOmVc4EF7+6EmdWRRd0ODOPFxUgfhAllgNuU/z98lNHdlNWIgMDox/ch9BVxAP1QuU7RL++F6vtHIv58MMYYasdqIW/m8zEH+YpEi2ySPHfsE71FHpKsbbICsdLnXCpPZgrYB0aeb9YX5mvei8JJLDw5ffD9bFnfyZUvtLos/D564KzFrhSwitD9D38WjbKQ2owHCFbjpKSXsHs+pa2zTxF5be4DRQdVrt70fxbRZDP0kB4sFE/gIwpYxMSFby6ryDMCSx/KlX67tcWYZ2pj7TXBoSZOqLze4aH8Q7x4/pB5emKUlNQGP8RrWULlgmJCvnj397VrODPDswlX4SJQiIwnhU2oQaeKSSbxbRYH+XvJE4m5UrAK6ioSeucBrP9FoUfxSrMDwTxZPfGw6qi5nkKbaC9k0mqupESRSHyMjV/vYjMP3DoPd3EYvVnNfIZQCIOG0Xp3drRhgIF11kNvcL42q5aQUWMopb+2HM0pTB/nn1qExpZrXzOphddRYSd1w2U2IURKxYtc1OW3kJstIpWDRsNaRHzdMYfO6vDIsv4vEuYuuFWnOc0CNjx7NSw2qd4/Uh3UJPB5LjCJGk27LTPs8YoWIVdI7dLjAGg0C03tTr4hc/WoNpYTKsIX9SbxLXTcAvZnks7ChjS+JlJTvCAfxP1FROqAmSDTR/tCxH9AOMMiDIJxnDKYvOfT9aX8jSmrNPXwGwKcSe1Mue9YjOqawkrqjQiyg1fIRgEVVp19YSuh9cW7OTlSJXOVYPu5rqtJaqVKIGfclIJS6bM8RX+OhK9LwMczQAylqspcY0+AS5fF+SH9Czt5+8gckSZwo98XMiOHPjuLrLako4dScJnVxTi1uGat/kuC/yQGZY+snx4IEleeQLm55n+WXKdOCIRW5LY/ykCpthg4CyKylbzkH6NOPWn4Wxu3Ee0fAb+6rkegsNWYX3iqmtkDrNp8mQOYzYPzZnwIEOp1+5yP4uIag7tgntT4/sCDyzsNxxWtj0PsEjffzsrldbxfoURkhneGZCsRFHmMcoR5APsT7P6U57pXN4wLxiLPTCcJDZL/NqgmXsj7K9h/T3tQqPq2djbZIe++VLpkOM9Q1zl6Fb9R1HgJs4SLPZj9hddlLTkoWn0ldCa8UX3Ho2zf7Qhf/y/7aLdK5AKhjZOCYV4GD0/ycHGVExXLQ6qp/VNK+XNwSsoHjTWUbDDCUpkTGGd8rUeYvJzMKsYv/NyB7gTBuNwFYoAj5jfEdf+ziHzzwo5p23YDxZ5RUe+R2fwXn5u2JkTez4RN9ow+SvDEDQvrgTqMLVKeniUGH5jim3IpQrCaoO6qXN0vV8jKvFR8oxNpq3AA8eOL5FSPHqyS2aWhY8to1zIw4ZXs+Ga1fSCo0TBoF2t+6cxF/CZ/XlXUj6hSysZ8k/kNjGOecYIBeiPn00JlLGLBoiLrj9MamO0j0lOIwF2QpJ/bODH8h5rvaO/Y7c9I9vgA7Pem9TuOg4G23NLFvjUqYbcLuAqsUPxdov+Foys5BRNlIwlaOjtCrSjhpwK3nwl94vt7oUwdz5HHflHpOMyQCvkyhSoPsgmuHJz/q9GUgaCallUoqNWS3qR81FKKb+s/NipZcuOZzwOkGwgUAWIWzEq3L92E/ZzQm0vFFy7lMwEhGOBo2I8Cu/cOFiZoYzloOthlXlHIb2v034c3efisRctiCENWWfy4cVRSmQe+6sfmLKAL1RBaMjrCvLZXq8BQiTrxiwutRLOFQw4ICkY6jzRZfq3yxsLttkNnUYzf0JxplMqbEqg0JfzKuOBHzDO4EvJIYqmJiehDnCHTpFeTd8uoxgaE1AEXafYhqV9MdsiQiTtPo4VUheqUZGK8GULwhCjsWFgLtyZCYLLhe4XaWsaWnu1d19ydvwXx/9DOaDcKrXAD675U1bwA4QSTo9rcpUjuPYCPXfEVqV+HvStui1hJU/huO4B0StlnlbQFegR7fu2+cmLaxX4uJ8iLIuCLg4H8cbe7jJeYmTvRFcrqkZzcsb7/L1M08ZROs/GU3SzoOHUcbQ+svJtrbCUGzHCPk865atn48T9Wvnr/SSDWLhy4AHy8Qw7HQ+aDD+rHTRujryQkEdU09rxU9qZcWhov0AvCM+YTQyZdERm1Sg61s8ufhwqQymzZDpdpRKvOfmpDX56PXzWMiE1Nz8xLuIGejzWAFZD2J7V/nBxJTHwzMHgkzG8L0iNrWOpuPcLMLJSgPPFZc4HMWxWrNl4VYJZGfwTdy38s2O++y9KBk0CFkUqjFBhyf9q6prmlABP/iCADcImr5KUelPf+UpRbx9qMgHmBel9dUpBNIJWu3fEywXbz24dW02ZQ8P71GHMkM4khz1Pqn3vVwzN45YTfCesDxFkAdkK5BCgJlu/SXMNTIsyZlMKVlKpUst0pasJr7qeAuGYaSnfY1aH68CZwZbHzqGIFu4q2oMjgnyix7zGBgT/pv7qZBYEjgMsWZ5suFmrFCIIKWZFmlgUFKaNVztV6q5fm4tZEqyajMyE+oAUtYfR4quImNyej++nNzoDzYZ7ObS9oPg+alUzsKX56qb8Doyi4r+Stilyw2dmTqrq0w48k4tQfgPhdjutXkXDEcB2B4z6wYVvwpIgmHogCDB8TAhpsQyWnOSka7XIM0Xm9TGqEawtLgBXEEnA8JEXyMUewWCnY/odpFGfUn8/XnRLN9HOPfbvZ0q3ck8YUzYvvUFCXTn0uQRLwJ8hAligRmivQXZxrySyqtyirjeaged2oyG9N6SfuHGZmhhlRPombUTbh/zYu237TXzXs7Iwy/vzY/OUhMJqjPqHLML5K4WnEkI+xZxExbA+xAXf8Bzcs5/E/Kd9+9+KqDxyuyU5YkSXmyyMLaj5bc3JvgPjbJXRgSeemL4WMgBNLYhhCDN7Y1yTmAvHD6D+cwTn5TDoFfvP5IN6iDsaH4Hf5VNt64WHB2U9mmYUF2HGFYPO14VYON9w4BscG+PWgAmd7ILRNLv/iLIat3Kc+sD7e4qbzoFBxfEiG1f98Teho1ASk17qJ67wG1JMVpyLFPiI3PAKUzz+FIbYjRIn4wNd8ih1Kaggx2AZ2AYw6rjsvEFTgQUyYe2ZH5ZXT/Jt3cNRN1myazig6drZ4fKV1CyngliYFsbmALcuMkejxrlSyBwOxzRr8L/LvMsU6cV3QcFdYZz978nzf167su/bpmcM1RTW077Dfq6GMnvi4zproWo9+35dGcnmmYaIZEm57BSGlDSRilQS0ZUaJ6teWXkga9FP63huhN72Qg3j2SFeoboc13AN6Vz9zbrty7gyx5VDV6FT6n8BCf87fpNhcvjISZu6NV742SsMMkrVFG3IZI1UdKPgm8wO7sKIjqJiD44mvXTvjYHxDDuc9x/4vsTOaJY+TnpY+yd18mam/i9ZXQuYMCQX6qImAv8vXQ5ChdoJjIDU8ymG8PHdqJ2ozHtZP2ZBtpMq2uGwi1Gkvvsn10CdggpsLseLQenh9AZoVV4WAo2oGjuQI/WkeIv4qutcRxY578q3Bax38q667iyz97jAFZQBKaQ+z2Ig1LGWAdUaRv+efuEIiZQfHVykhieXkdahE7n01VnDtCTkWFU7GAirr71HZmtfxyptfDwy8R2jM2Y2+8Y39heLzNWWLM69tZ03UBJrOmtq8yGDPDMpOQO7yhFpPN2ojL4RSCFylJaljp+LuQGmFKAXl4AUol9jAXgU+mXsiv9xMmdUxaW4U5+KoAxhQsd6K6ROfnJSb41BR6yHfvH6Q1udGWoj4ZXf5Euc9C/kP9NiI0vp8RZYxxR+biybBYAIHcQfNUuN2hxhew41KUG+RrMOxUqvV+ni4DLfikENc0Mg/C8n7E93YND43ROf6XbkJEBLcWMz1VHGLlW4kvHwlXy1yNsOleib90BGLlqKvQoCEuZdqxSTgTx16yq7bMKOznR6ZNIWmAxm'}}

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
