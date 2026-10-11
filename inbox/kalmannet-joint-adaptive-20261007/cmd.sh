#!/bin/bash
sequence=159
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
Q = {'sequence': 159, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '746b95303ba6b4c11727efb3675cdd5a899f0c6f25c0ca0b8b673ac90cf1db56', 'ciphertext': 'MIIQ3QYJKoZIhvcNAQcDoIIQzjCCEMoCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGAfNrtFM4lV7XgclwYLdsq/kDdiRarDJtfezoOMiJtLX6iTuPJ4Dj/HZghhcUErfTHhjkCAFNgf2wkP10cBU96Ew0DXbFaPVSp6Or9ByUXvJPOuVHxF03wUOdUEBQwKb9eQ1u1t+MLIuVVkM1973Lb8/K5gGE1iYc8se+Ecy5LeXkG9WTiawJxpVfmUxd8hdefEGX3Fny0OcC1jB0yuGOh/B1+U+6iaVVMNlrQ0YtvYKatnyGFJq6d3hhiSgRzu+jcigoMKkUUACjyIsdsepXhvxQEEZxWSaZu4Cceomn4vqRjmBgTUK6btdH7FaeqyObMOng+uFLFB9bljx45qk7mENn4n5VaEjhobokGlKq/GCLjZBGxfgTHGWRXZcCEYTcHQDufRqo14IVYXHViuhTPu8crCu5RvdreS3irm7rERXyQVAe7tVgbWy289wc3roVvzxRBY1sOCznMiJ1EesCKmj7ky6L95yxASJg4NZa4i6S+423sDL9Q4NX0whCittJYMIIO7gYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQWWxxB0ysxWiz7Oi6sbeC14CCDsCDBzGWzznMLK8ITkm5dUcnRUZS+4LGlJETByS7Tog9ihMpwgfTOF13FGmeXUhVuB1eDTnB1qT3mrloefc941QHSN54Y90otkoUq8FzvoWyfxarPGu2DWqSRO0LeWqQc8wXAP5TV01TY5mvMMNySZ1cZUvRDcJG5D8KwREZkyhL8433kfDbantRqjGt72bI3ug1KNUg5jQz3HxktDxSRn9lCwymDhxHAT5Fzj9vdq4FwLP9576dkZ+pFO8t387IVQ/fbVQXADUKMCylzP+OO8fy/QF9hjgDY3uzVvSuYnlmMAin2NMeZbvJZAIAfqagxDenmJbTbytm+C01NLQhB8tBGB6StNVg6124wL1qvvWvt11Og4S9EKUmdIxa5Ejy7LpKlvzg/ulaFGMmjodWnDbpFqNPhOfrex1nmm8M4AhQAKjg0nWzOUGr8ZkUquUfcyyWdLVK1x4UGBlD9q8kugtoRRWfXTQZkuJMAl+kQ7Xf6kUELAuiuzE5dcQ2hEHLHZWs/VTz1Smv+2MwaaVjJIX4+L95ND4raNt0uEThSOP34TMRHFMh3G1z4RFP5iqpBhw6EfihWKnwJMYRsAYGkO8cmVA9vUt6yiFaPFKl1HuJsmW8pa5NaOepVM01LR7evUf4W+6qVNsCzfFYk+UHAT5VPcT2xK9SciIHBfAeVHJHhPss7YQqQmWtDbKVq1gIYDwgM/OlYYnJ9f2WlkquUDlpnCtLtZfp1PsfpGFC51VWLVgDpyvQu/wLwxwDnmdzrnrQKTx3vbVOseJGlYHt2SrA2LTDZTgoboHwhkeOvAsm14PnKZugy1OdtUJqOH0XOOyHe4DBpgQLA68XEoQT47wny5Y73SIWwyVlUMIlzoFey+xc9Q+uOnkv8XhvYmGakRh5BG6M4T3VWNwYOCYrMr07iDgTRrbXlZ4BILWxW2IPWEy9y11Duv8G6ktpBnGQTQaGeBznW4xbwDjv6gB74EogNSEED9EQy+uOAQ+2AH9fow/4fZstYeguH5/P61NBVnQNer0asct8zAahLmsHvROr6YsW1OeuSxFlmGaXYHJJGP9A6sCcoym/k6+fJFBENkW+vfrnzx/s8NNk9Z5MmEtCaQRt1G30Xqz5LD3QgwyeLJDAdjcMQtTUhUb82QSP5WzwFh3c5kXV7o84c6thmV8YzvWW6q4OSZGfa78jq81J7WHIB6TmlTzUFn+uv7ukmCLIzIXE4k2v6DYZ4+sNrVc3MzmTEse9R7pXuwQKqRAbu2uOpMNaAdYSQh6XUdLFkymE8f/eURFoggtnD4H3kyDhm8OBTP0WqrDwfu05sI0JShU1XKJVbnbci0OQ+7Mwww/arNf9TN22GRbJgly0V8eupQncnJj/txk0hTP1l9qCfMYuI25VLBvzhTIylWfdhDt66H6bdG4pd/2BkKRfVuAqEUcm7BQuBi6Hk97auQ2I5YN62dOXThF3PhV+vDO5pXv8RE+5rtbsuOD7IP4GH0D51Wtv33HianiG6pzeMArvOh5BBAFlAWs/BRPzODl8xMSv8EZwZUm/NyzixEAx1rZhXjmBHKkpx1aHrt4vGHpQ3p/J7CQuzVPvBnxTGwiWhUsRxEmwGcbwo2KfgVO6mDa7fD6SzQEipRG5QG91xuL7P0kpBL72kJkF72eQw5Rqh5GziqilzMldJNdmqoMUmmjnjYR+/JakiYwvoB5rlz8ntbBPOrFF+JrET9+C9behz3MK+P4Sn9GhDzyYBRLDKEdflKE52pwVT7enq0zPQGEeDj4NQVTSrm0XAzvBSUBVf+htmc1UVle9QTk9edDLijDbKLCyZMGBXUYV7qBYBV5YXt3Gu6NMyHV/ARKx3WUWbf0CusZ8wlCnt84bLC+AzK67/BozpRlsxAvFYdYV0xOsX8sFyrk17mkvPJirbDSRuO04lhpVQaT9scA5NjfDXrW6Bf6x6ksjSP3IZhfpF55A9Qq7sQ8XtEj0LCYVXZO80qXahNa2JRcKGGI1k2SLSu4B+Mdhy03d2T69WN6BWC8BuWPeB1uJRqsasZVNX8jKoRulheTdw9KCRyMTA6Nw9LIz6fCG94MkBvFBsZ+WWPe8imxRsM3Y1gJU3n96Ul60BNZ8Wxh41wWoFoszWBpQGzqaD0MhuQ1Zd3FWhJJoNFdsSGxflrIuxpeO1gG0yk90luC4IjjZLrjkvmL6YAUh+pwDFV9GCsU4vs87SV5L5w2ZHLUVGSLCv8HxQSbhkOGJOkgdMFbRY4q8zXkCVjRurWvH5I79qvHTdG3AN6LEiOS5XcKYWhFupDGYiKK2BqgIgU0itKY8rKnEsywt5HlyLrRbm17Yp8BAT0lChnKD1bhUbtxteGm4Dv+GYc1PHM6bFQvviiXhSyh29RTAtsUdivuVE2OUArxr0rGDaRqCiLg2XtJlWa9BZAXwBRToM5Kj7G61n/beEQ1YeNYWR76IAcmpnc4A+U2Fj1i7muUzhN2fFg4SOxu7qTeH9Jw0Hy/BLtwEowgzxw1ctGiABmK40UeCm8qj/K3EySP5acSvIcXXGhj9aV4DuVvMxtw9EensOUXblj920oDCAJmR9sQTVQ3XjqoysHkIreI752iQasA1CI14qSm5Q1U9I/yAfZEjTmyIJMzfAUFRJxlE9yLJ56ucZ8EtbRuyFbpDzivoLxTMWTbLacIOSI7xW2UxvYEvd+1SrZeenbfJU+FgpXT2kD/nV10+yXk1OJ+Zme1p42WxJ10vWCGXujMFdIYrwPjOwmFYmed5LTKIJ3KyazVOPBUwsE+hFXjQE9uz+SKZSlHR7rSPL++E/u7k4kFCmKga8pc7Sv40ftZPTwlc5s/YFHQTx9R+d69of9dhTkupgtzZmhoUYEHMb7r7rxhRcRAj8YvYe8CF3G1HL1266VYm784BKS89xbhajDMUOhMrBF96K4136+xe1v53amFIfhIduGIHIxIY+g9GPwCECYoaBbcayQiSIh3nPHeZg0JVw+8i9Qkw5jItAb8Jb98ogTW2uWORsjzmHCY70uqCxB0coyY7dssabmyHNxhNjh1g22NC6ETE6pLmHQKOQY1fxU77MkVYwctdzyVaD4yrON/rHoh7/P2wOP7SZp+rUqVsekpYpmSOUJABIDkv1LAozTwso6WSpyQZMPhMgGiXg2GtwoQDn5wQzYTzNP4aJPldYsYMm9DG1sDAL279d9PD3LJz3qKE5WUEw/f/h7YoMt6Px6R6f7AzHqkb+rquNKxE0qgoz2PGhqaPK1wbUI7nzjrH1Tnk7P12X1ANyKC9UFCMaRA8Y88yITQzX8EZse5tm18ffRfy5a0bxYTE4cOTaQZYL4Iq7mK6TQilkdrgkGPoWMm8jKJ3q5Knlck8Nwr4VZiBuW/Q8cFnrr6sqXX7Qh8ctA8c/zf9xbRDGt73GupjklAEyp/5zngs+MT32IKFqWuQg4tT+RChYm4eGztq21XqpHudoa7dOmH7KTPRok4mtYl37XSYrHTx/vXIVxLM+a9p3AbIc7lnwgtAaiVWhkRKUxoJTLh/6MUCXwN6wxra83zByr/t2MWZLOGUYsXlgNUikNo/H5k7XdxmwXcVZLdS3giL+bDDbi8bHS0Iy05AafW+dbxGHY6wCZW9PTAPtAaPB710TjBEeJk7yjizIe3UurQaQJny0WuEq6o+D5nlijM/280CV7RcH/v1p3GOI5Bwc+YBZlSDouXCLhy2oD3fqjHiKEquxGQKlV0BLg9OOipZ3bOgj5XchWjoZjWfA3Ux+LsiWMGpKeQdgrTfekWOP2G6O4HolIOaU29PFnqq3meNa+iWGCCUrHYP5UbS6cEqnIMgOlbrxBb0gSCR6YMSsG+DCluNYVNK494ryUy4As+5u7HH5kgTKno4JWmBFWtEgsyuBBoPhd6mI+4ZJysMX9tdeTJi0yE7zzYK39FSgfzboFx4KiVxGkARGPyL/wu18xVh2hxF1YQtFNvQ9SJXi4/dXDKF3swfX/9sQa3RLQgWSu+WNRwtIQoMQ7Dru0CLDDq9ELm82qz32DfiCR5WTNmF3Mdve7Jfn3mpxwdkKdNSVAPjiqVLFeA7GeKLAEJ9fogdVxtHVUBgJJ+vk9aIHJpxvXVn5o+jjGAd3/Hmte2Mk68o53BUiyas/N/Inby9IES/XCu+RJX/rWI2ZV9Wm6Gx2/koadvSWMDsuYw3TYDeMXyfC8iTUK8gT0prAR8EDRzoJyoV7FBJYAPi8BO+7yYYv056+gJS/mDLYQijG/MAzqlVs6kSXPMcWX8J9UThHJM97x6KIzpcmN+VAXuAjBOZPLfCkl/Mb27Q6iOsWre9xf+aJOh+7l/DlV1oUtY8/0o0ObDUyoJRIC/mOOo0KWFnEcp2atxYU9eGxp+jr6ryxJUYgxt/SwHeDQjOgo7EZE1bL0UAb4rrcKIvegfkDcp8KJKsvGFPppxyX7SUU7BZUNAeWYK+k/dopR+UaBuIKLhz5jFZfk7Ae6cSjI6o7wtKwlRpjRhjHDTfFtxNxdW0czrEen2crsIJXxq11SdXaQoHzxbnz2OF3SBWLNmwTchWT08plIXe+BhflRXQamUy3LxXa+cMiTMArrbOGFLum2UpAPHaKZRVUbSmXNniLa1kaNyizKABLQHMSwOzeCtBnzuDIWKvScCSWiQveZHJcKmi/AoCwmbkZC/ZGXL39b7nhB0EqpGH0PG/+SNgnMfesoor85cxLVmRCf3q5rNqTS/FEnVn1N++MXRlAAHGbpFMVXxgYMgs4ZW5MxeyY65NlbCTsV94KQzZBkrhBp0pUsAuy7dPZRGh9dL2oJ3CWP3pzGxHkBLBhUXMJFgzCAXu7/9m9dTCfRGnTKMMJ6QNLYaaiUzAfNgGnjkA8upa9LNdVWrcSfvSqa2bjdYss4wlimAgOlAgyfzMPyr45w3QnbuslbvwwBlIscPak2/DxBuCAxM14DPwM1LQ9twWhmhRfkrtLIgKXSqEMu7Dw0XvU4OfJVtPNHVJUcSI8LbifhuRRQ8XHfqqLQbhmsdJdli8E6dABW7dmw6ZbSuL6LemuA=='}}

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
