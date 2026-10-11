#!/bin/bash
sequence=197
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
Q = {'sequence': 197, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '7fa17e2c525ab603f8eef2b0b67acdbd88dbc547aa9567656785cad59b097049', 'ciphertext': 'MIIM7QYJKoZIhvcNAQcDoIIM3jCCDNoCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGAZq7iCuGK4AdtALaAasKDZD7h/WMxWwkLPwcg7iObWDpMSEsVMs4LgU623Re5a4FNExynC9yWTQW6ZfcXRAVEEtRdlnHakVbnGPfLEEBxacBrdLlhkPF9f4DhJRWQ6ljGXhqofsWydTAe1nPsQn3nTJMKKyYuYdzlWtIDU0kSZoX1PupvTvVpVgmhKpZNgxNf8N/abdcluL4/kGU3SQphoqeKcmMbPuyCubGt9ar0rJAaAPDWCTHaKZuiaf2h4rBRtnEDNyv9qhEqfa5yNuD1hMWOpu9JRFgqGbJRfr6HYD9n5XN6gCrU8JwLSfCZx/EolbBfB+rZFyuI3uCi1CG+qZ6QnJ+GTWqxbamPYeZPveQbrAERE/TPehWO4OgSkiZp4mxPR8LLe1nXyzyPYNI8sfZu+W4NKZzErEHIu+KI6R21eVZVAcR/jOVmRTVo9EsAJBh7VmaFCySTdQ4XCaXO/zDnzwOPNVHfqzt0ox6PQ8Hk2kuohNC2JjFm7JJwonixMIIK/gYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQoXoVfrOKzEwrpl1/z2xNe4CCCtB32DWBFCXw7Z+n/gupEuGLw0RXUcCElF1vl/b/f/Wcg+8OoyqycGtLOHuXMCzofVPv1AkTQIVZaemorOTWCqIKDvYXEQU7UOv5D/PMjdKnfOvCBijt/4OUCToq2Ym5by4fiI0IFqsLT1jJpBC1tKn94YzJbAyL6EB4kSJLpq108LQOGW2I2rjU3GDpSJiLsOMPGsrkFImQe38ijdZWmGcE7esqJWnl6Kzx/TN4hQ7+JCVrJvTJkeCTFKXfuM9tWs5F2cO2L4NWPntqdYwBDa5PSq/lZPMNNoPzBZwJ6ueDV85KuD1nL/OgkOeunwyKnHRT9RoGMSe3XLex0/EL4oH7lzZh2jdVcezLwdTv6tJq/rz9RnkawsD+wpAmPiq87kXjgzJpblQq/HZk1KM6IV/MHtkb/6UUj1y62g2Cp5TtEf2PXjzlBOlqbrNYdiagz21yGR3XHT6I+nH2y2GgevY0uLzNNl4Mbkcsw9H2LEachpd5RznxebgOZaKeNAcM+Hg+0i0lgFv3uiZCbHVKWME9TFgS3ob0kBI8Er8JfICoA5lr0kEGDNcmVMgQl/E3BXvKQIrQZKf5KvllyV10x9HuA00+di2yc/fvZZmSC/nfCyuPx34eUl2+G5LuP+hlSNeLEZKEwu6hTbGCGFfXRDjiqmi6NlimYN2j64896zblja5I4uJQd5vvbU80EA4Sl/NbxQpSFwNxfpV9+qzbGbzLrs0SrPx9VWegyNFZwCYfTDX6/j88gXQOAE7Ezhs+kGoKeKbH3yglbxcJnjOpeRSpgM1ACzRNzCWqMLZnbyxH/GH9s//HcXQxZDOV0GM8+QRMChSdGXlB89GnObePH4z48fg5kE2ZiPQHG1mDNUnrVnmhHaOMUXp26uC2s+nsj3cTafhGGDBU+hCCbfSjO5fa6jgomdz/XQRTtHGKn3a+Km8LIDCiec7K53McT2DQBo7cuGQcRQVbGapyDrk3aADoQ//JTdLo3/OyVWw2Wqhbhi7qYwV2uvv6lS1O4DLt+dTb87eNIA+ZVIZ1UrerHY6rtZBKXmGr6b0Q3hdlFWZqNHfZ50PbwtK/9ZbovpX/fw9v22rh0lK5LPsMJWaYgW2mXZLhYbWbBSrlWOa+LOVX/lyZ19e87MwrpuxYjmLl/BieeCPEKy/Hx9sfNoTCxVGIjdgatQhTlCbamebpRXJg9uRgLHeaABMN5zGB7GcVRX7dvjjHwr6NSlcYkAv5CrfUCT2jQCjL7lK9coGn4Fat8zHKo1fj4mvE2iQelhL9yeXw0EhM0vF434p9a5uxTiHQEUnscDz0UZgWRi3Ai804CVGTXZ8hzNiDeNMV+s48BUYyhr0ec6nHe8CbGtR/89Rk/ifzA7UH7ieT7Bhi2uxO6yIoiNj7jc6Zc0dZND1BUpciIXHXiii2+ZaKbjDguIO3vp8Hjf+/eOs1l/hlLds33nQS66gvgUQHhdQu8iKvA/4U0Bziqj5fuxbQI7q5hLT8zmBnvSIIyvg9tUE892J+YlNPiK80Gc6ybidhVCguOW/8pRK4dcxfgCWWd0IO6D3M8SzbSr8r+49axxr4wwytBD6L/c4wl2l7+9NO36zZSUqKMFEN3BFvPyDiqt9NBe7FZfiJeFSLENnlv5h6+KLWRR8mCShjL0UrMmhDMVYmyN8c0j4Gfh0TR0oP9/jx5IBs+JJl1wQ1maHmDbgIhVZ6cdy39MpeI30kZEvvVJi4FYuF8Y6UFFev+piz6cJ/VeIGz6/qTSHORjvjw89dUifUSiY2AO/Fg4D2iN9HjYlb+Tnh+kZGDKaZS4nsprEJ1OoWdrP0+K/5oSKyCzcr9EVQB5vXCuW5SModAody9C1+gV+iZ4kARQMp0cfVgq6LgZoVtU19Ha38zwIUHkxa8QE50fEu7iVoUzaHjTi/eCy1W+UyHb/V54FXrOX7uzs8EOv2TflXg/ZbWW09VPlLorqvJbq/pEqy0jK+ZckO+83+gwGK1Gbe8o2WUk3RFoWsUAaULeeiLGQYZJJ4Qu4hxgWiuB4hXD++QDfJ6WFo6MSuVAYgTj8uH/Y1B6Y7jo7/YGTSOa7QCvfElpVRlokDF1/LN1xzTCgNORu1arbzBCV329nvkcfNJWstOUZ0/cfShO2EX/QfyT2nQXPuOVya/ND3O+vDSZ1gZ1r2JTCgsNZ9EcQKuA6TRzFbBA+lLACzl2AAvJqQHlHhsuQoirDHmcoKNl93XBUzaJ7f4t+pAq134bFC1WmHTDyakbam4WLhYw3nsVOiAyqmU8fXUVCfEjmC4gUW3PhY3iDYPLoXk/K8oYNFO7DqpCuxM6rTd0WQ6Clbx90+HOc2uDjjaiXmHgOiUgVif9/W7DeZnO/oY+dvIuQglXvHeRdDdvwOV7nR1dH+np4NIfARoxD1q1yUACBIaM3eT5PniV+psIlLALStGWlyqLzagndksUHOk39YSzAfogs8CubC9OFGAXBknjrX6MV19v5Hia5BSaQCBsFEgQ5oIP7e+pDqFYl0KOhL3kapOgh/PbsrSdrZTG6GR2m0A3e3SRUyBVDO2bouQN1jLQt1e1YR2/1NWFK2e1L6mXdSaNl+fGX4TFkcfctR7waYyYzOY9C6buWCw2d+9dHdv1yChrnVnT1FvW24i5dcTuW9yUR5yuOxHNHikVmfx6NamyINNr8kuKSs3aErBsC+4ORMRQld+roK8lPJuuYu3+bpGYPixCFue7ETyk5feyI/MX7ydQYBUv8/myGVkw6qSpY6YeDeSCfxIoVDvjoYJfenBHOTDubBiJJh4ttbvmsoTSmjE/tU5fRFOynL+s4wV9aBm8oc6gNrG4wVm7tI0pH7VxNb4IYwFVRu1yOgX9uE5Wb/kZ1MyZ53KJ5OZxu706we5xAynK70pTow4YLsvEWvslqnuh1XGRncotRqNqz8qEs9IxaT9W7qa5lhJKeuiiLPQPVwo7aCpb007BEwyymYT0pL1QgZJEhKfCktIto+eQBZTnmZDQtBXMa9mYtPJLr0sefHVziyk0YDpvHtZXYKDE7evMmr/4d0vIxoJ+yHWVFbrlq5xV2jwoeg7oZWWpHqT052LiibEVKFsWyZtGem8+MbGKSvuLkm8rMaSsefT8GdU7SVU69HA1BcWdmYPLAeRBKRv2xroSodLYBoh9zGObqoMhYvhwxNRVeQYkRpptZLAFiQLjfic0mjXigBgmziWpdQKt1lyfSbKidWP7zUuFRAZFbnLt7gl5gTQTCsw/Wt1jJHlM7eFmCCClnpzjakf92PQ+HWuCoDefJQMhr7U5ZEOySYWS/eaznWSYjX5jNu6CLCroEGK31pS4TvvHp2potZ7zhqPl0spY9ke0v5f7kAjMiOOjVQq37Yak0UnUcS/qcnDhr0BLJrfrAzN2aAKn/Iqw4UCWb5HvklAs0QBr+l+Fn/ucfmqYthHLxJEbifDUivS841zG5IQ6+m0LTdna/g4G51JicoplGvTjuvQ0u3uIb9nav1nClozkuqaDaKWNpESnNK9gakgu8e9mfK9HKw2wnOR/Jg6xoyvj2m2ve92lsbClRwhxjdoBm70lRDXFWlWpwv9x/YzUn6IUy/boW5keQHCYM4dAzwKFf6lnmEXtYZI/BlXwTOIo+NGwG5DaN0dOvjh1K375ccUZooFefNNN1DZqwdzoqtUIGVuoMRN0E4+Xi/aKGh2HKmdA=='}}

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
