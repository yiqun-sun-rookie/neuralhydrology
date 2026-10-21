#!/bin/bash
sequence=340
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
Q = {'sequence': 340, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e03c83d3978dfc53007714e8b585b89536f362b00845aedcb95f657f8b86d6d2', 'ciphertext': 'MIIRzQYJKoZIhvcNAQcDoIIRvjCCEboCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGAZKepY1Gbrs6PEBqkj8/RG3DMX/BSzBS0bK64VisqBtWYu+h0ITMXoyB7/ehcgZVE92qyKU09E6Rt+jVfU8QbONs8QTq7ym/f3SgmKNfv3Vcf4P1NQOsdXCfm/THtRMheLghsSnvNJxwon/iWDH1UJfUxQER2vYiuNidKuwj7wDOh6i9zUzPqjuoaXbcJFrwVCMvUWiQuh6IbH1c9xbjXOj7WMlh9jkgWgjJPvbTUN6O+z/P9qsuFne8vVlNjPGa7aUbb5ogOOl5kkPP3HdknXyBrd1oAjGTzQVnfb/WBOxFvaOpcO4+9wKZ9PPbGUwEjW3CeUHvDREns3mRDCShcUt9lT1JhghQPQYj+tVWsjmXH609YbvSkfeKarO6SNLtlfvxPLp2eKM1vdr5EuFiXtekjNvDWmXt87EaIRzRe9xCj//13/qqF9TzN4XATbA4YoQnMymGPZx9SR+WVoGymyTR/eDslqDCoeQne1vQjWxA0Odm+4+gGt+vSKinU4+0jMIIP3gYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQfhrg/J4aGjj+40H0jwlWdoCCD7Cksy//P/yl5VNieB7UPTmd4ca/uC5tKOhSZgtOWgj3r97C4ZKEkHLLrt70pAMHBPM1O5QswVbS4eQ9iLQjAsrcY5hoUcc0vF3nTmswCLf/zZqrZ1mZP7HwBclBEsi9RdqFg4o+DF9iTdycICl7VKC3nzldYABLJev1uQZ3gu32doMwBuCyyYireQGI24wgahcL7iZYX0OVedfz2hQ1tVKpYSFq4VLj/7RBASsgV8dE4yqYOIP9s/cS0HnOXKGsOBsdE+mWb0QUuusvvR3kI+RRUPJtkaKtHmYx3DRa5s/FJ1MFPHyCwEhAZi5cUZEHZmkKMoDRg6p7zosAetJJCVCBuw+uDtKg+yzxZobuorrzINjFNzMpNoinzCpHufgk60wouGoYrLSD524C/xmZxj1hGuRnUYxDl7jpV6Yb4jbAUJmTUo8zb6oZwxTBvKLfmm51qQqwJcmyc6yBNpxAj05pTwH32az26cHxbs5yxTS7Xszw/iyMcvfbLOQmurd59boTyAdYdP+y2dTiNA5oyX4sLedBfspjEqwLjvNKOpEm4VDFCDP+wRtumu9dISlQoBZz/9u4p2Fg0Q7a6pV9WyXSDk5aI0pXveECr5kFMjU2PChEFtDc/lV+FPRQGSzn4udCq7ko1hmdPn3rt6igiUGwpsRSHCpJdV5joKEh+zIUYfqQxbzviHx4JESguCXNzPO3MDCsryJuXtdD7/cLEW8T7Fgj+nWxy02KTNkE83cExi11t8pgS17MPDqDDH/6Lo4pSr8hHxtSH2lwSUU/cH3ladZLzCLOvVuNN+cI/Tiwhbe8tavITqkja+fZZg2ikbvSMBuxmRrDW/12gx1MxdJfyHt+IFcTl/plGWC3AxLqAisLXmsOi6eqepHiDEYBePrPdQxkqOry25Nkv59IZv//LlyPoqKlgdu5tQG+K4R8R/LnSSFtpzhp+0n2cdBoDRltIzrRr0ttL2Irq2HxF9kYUdPgFzemYwrlzf5ynYm9wcBYBDhllBmPw/USCmAEQ281zHtUhtqH0AAXbCLYm2ReVqjZ0Bi1EVUuY6FnlDeiqY55Wurj9jLy5p/Y9Ohm241Zn4kZu4AwLFsU3Haazt4K1cXw2g5Q1we5XHFTjsC8+nIMtQZCxKO9CKQMWyXkxUaSKk6aeH4cN2BuKj0LZNHAkvSzVVi6UoACAdCbdMm8Dkt8K6WtDOtVFoCFvWddjIh37eVFa4l5nU5umfDLW/5DZ/E76jQhAz66GuXAofgMNVnpZgtDRld2HZh2cZXa0eWdfGqoKqTLNKpGVb4VBUyqQ7RlOvNSxiCwQY5v9/ioLSaKJ2aY3wDUuplGpvltnBNOYU5PX0gD7fZ6cGilA2IEgu6p2/472QSN0HsXF75K8LLoegiyzm6WziuqmbWEd5+CNTDBXFl+JTOPuzkE/IH5xoozYbv+cZVacM1VRp8lwZ/m+si9BvV5Umsgxhrd+TCmfwIvzBNGhpfnkSiOE6rTdGC1pFK9oiRrys4d6qciUZFgQ100hUxuLeoG+JhdRkhwo8BDC+hrSZshj0gZexD4S52c2UBvvF/tR7SnOtuTq0kUh95LrjZwfJpHANQTiuJ0L+ukziozdEfI8nTgPbPKWS2wv8D80w4jAzIjZg8Xn0exjcE62Q9IVSoyGDoVPgt0jOLYAWZ/KNzecWT57qQ1JkelHwSRSCKkCeVwpHUD6jbRUcnCuvAqgF+/WeeGEeCnAXV8xe769cknRPYpzj3GOxaKF1ZbF4MNJXicweadSToxlCBaZqc8V2GuXYqOzflSH1cyMJrnKEQJLCZjudC7vnR/ULjHMwfLAA1bYKEYlnwis8Y/xNeN2bGL+FpstetZkOMKqKglXr8bjNco+hI+Wa8tw5sDhzamtRs9CN0qDCdKmVgXtHwyALa8iCjDs6t8/5ATo04JRX1ekxna4JvvmjtNYSSzgP5STXkQ0NpEe4INCf3uBfHEvIJvyVqYBEgxQ5is5XgjVg2Te4ksIh0zyKntEyNc3WD7ZG83THbfEnfODJ8N7UFg0OPXZIiEd8PeSTZXIkEffzq83TGLTBehot+jCFCJJiHN+II7Yt6jJt2fvUINPGt9klygsgcuuFKvN3fZ9qI38KSZ0G1f6s1zP8kcK8jflgpHs/0NoCMtFnWkKSPri81IDS4jHgDhITf85hXeXyEqpVfxmxhqtelbHr8i/uKMekjZPm8UrSofcApV/jHEjrER7ZyfdLRS4XuzjU4D3aZv+6elSU4vDoGA8gATev8Ftftrn6K0O4CtgCcaBdxnmqpjRtTzcQ1fpRfO4EnCoJhZxBlJb/8meBqXriGBe5pGjYZXtCoxkfsN8gXKbs8QptDyoJlnvJb08NeQGVs49dKllePE2Fof8Q4yeFa6+9ngdST0GGO5BBPpkuZc1SbLCxbWhnxYo9VGbNixV7zEmveid4gdienJsZfJoCTdxO8dyitfco9eR7/2Oq57i6SRIHLSaD9HYB4mgiWdGfWAbIUlfpbTxY2594JUEhgyeVZY6+vLCdOL1zCPM9pJ/uiRfadO98d0yxlT9+hZRN0l81O51C46GUhi1OSyqTTsNdmguoxMJ48F78Jidmm36vNfKqIDEfBPN/HsswfKJJ8zXRfLPRvqbBK/ABiyiHGe5e4acW7A5DUVGGVFVq9/tRk7gPZMFMomlBLS1KzloDLHXpGPAqa8qDJ4EPKb710yJc/zW/ztHudZhoaeTD8f1EEO2rfg/QxmW6t0zKpch6Erz+B1gCMfradLPWuet1kTrR5qgYn8gMdL3qev7A2GCz+u4MqxGthh2Ds3RZD8dTQeYTWl+6x4snDAcevt2GwH3npMwqYIZeeKisEvKDMKnG7haDp6ung8C9CEaMrjL/qvGagujfRxzFQLUbrSy4KX/ALOb141zir7AxBj+MD36EeNlFPSrGffI1cqOFcJMAUJLtCMQ9EEwKd8KUL5ad1IcOTclrPzjPzG4o5fzrgvzZiz2JzQSjRkrogpNiY92R1oQAGe4MEjtLydlxFNLcVMQ0o8ctCVUf+5cXzBGWfZrYRc/2lD0IPM+AFYaAp6DMU1pqDrCVO/D/0cLgzcB7FT3C1pjtPtFmfHiYKNeRVHSM43NPoeyXLeuEM69fiiI5uqM/3HhAYhVIjYPU3DDB8Kwj9a6f7PU9cfgw4V/kmpSkmzy7+bbkkTcCWgsrcdb2TjljArCLWQDGfN+kW+IeWpw2Eb9w4ZoKuBc2woYViT3R+2XVNv8nM9tpuDulnpZyB377bM1YK3FW81bkgGsUpDjTelTJ47Xx42l+jey0zsaWsg87JreKyJJDc+34D+m/jcwwiLrO0oKkbgUmiPSNQdWU9pHUJq+xXbOy+fB2QmSGY+iVQo58QYz1cFLJbyAQkreWjxA7YCzI0x6YMFZVhntU6jo8KjZvZc8vAGLTAhMhxaJGylXSTNzTSpgoSbst3lK6ZzjWcwk/lyuHvGD3c1RqGbhrSDJhitLavXO11q+CtVYrsG62luBZwLBRX7yJqlUCwMScaDmPpfwprBl9CaaVq7iUQEmYBtfKnAgKJQdYNZSNQR1q5Z7Nsf3ofauyZsHCJl9zI4W6/n73/maXlmYQU06cwcgItc3uP8FfvA+bsQYGQKwjbSVEMaktHLBg7AEaeSBwvWydkshkV3DY6djS2Oyh0Z+e6+vXfEDiGwd57flYEn809Qd5rRd6lSGiHStztWXwrKFjyY548Gcma44kpJ6f240Y9ku/cCqrB6eA9u5hmEW71YKNx0NFl5mOXPwn9UbYerK5tkzwEyg7Ou+Ghr0r+4ETAwTqbRKDl7Kst1IINkHGQ7FXewU0HAGb7qClAI0QITUmFXaD5aasXHuRISvJHhwErifUmsE+hzzdhG0ZbfNJl0TkHKCV71SUCEaPxdrdzMXOjJVbX5xlKffapMW3TrPf5BAikj5VRu9RjxkxVVNWG/dAANiPatTFCj1vSULNYkCgle/pvIQeTX7pQf6cIgNzW/OoRAS6YTx1Rx5rZFNltFoYOooiKrjfoSKeOeusHU2llcNQgkSkUnJA9mhxdk0vovhjwm1dBGYZB6ZwlC+BZbcHVnDG09F6RE6lIp3jad4qFEf63L9HJrUB/CUxK5K6wmpa78BP/6Qca9SV//9jFS0Mwjo1dMnfBHWkPAUSEftWqunVzttptmuXs6Kv9bAWFUsXf8HGtsvEqyI7SM+w/HvQ8GsQD8KSDm+9ilrg7KFmqjRLZj3SGOexVEPbRmFBv27F5NmK97Eo4FA+5pSTi5UC6TzOJQkMMyhsHAZyPc6Bd4iQO6XpDu/ZqH0B59XTAaZnTpuz8f77K9ARYr4d5s5Xi6cH9S9VrqmrYUHQX1tDpDNRqk6hbkVf09Rxez4lGN693Rj6yCDxrFYsAdd0UobW1z33K5zx3LiyuILcC73p+V9/2DVpyWD47dt3ROX7bHyw2NH97/Gx6Xhkrefhsj38w0rUo8WW8wKH/so+SYe2/Ht1GRujbzPNH0EQJg5/wjV+HBZi9hiIZi5ii9AvPL8IvqFOodsUYVnyJ/5QITEXPzaPLLbbAX9htYjYSGRi9oX17MMAUZJ29ed/5/2ol7UGkOMI4X1MzIQHPK2W6Fo5yBmMkM0ZSeFWwX72s9RUfpvHAC+NaVUcN26qNrjZFxARt6lqNL3BHxL4gXzIqIbdzUXy+wOEKp/OJNNfDzWw/EX3WFRZzAjmEFM/AMOKmpHeW8pU5ywnmI3Cq6rH03/vwLBnZh/XObmu9IFlhf2dIC0T7GUZS0QeN8aw7N16IG8i+BWzO5zd/YDH22CrLj6v6a8M5R+iNwBd+x0cwqd1ev6UPxzGhOX0N7xphwZ4eGKgDBvzVT1lglk7Wjomi8TldaqDnM99iTt8wQOqFtZkienG+R8/am220MCWH8Qsno794CawI/OOJhYZjmlpofRwjMrIIAdUSl7AxdofhKR55AERWtti+Ev0AAqnMeFi06WIAjbVOfeEyd7h5PY+7eQ+JbDAL+pg7EzTolgPe06svx76cqcHHNBKS2QXGxSitdjc+mTBXMNLJJNE2rQduOztOofVCXK9X88xqrv5te6oIzSeVf4tuBqcFSQXEQHyv6ZK2Xl4MumUNewRGYohRNddPhpyo/XWD/L0aT++jKEDi5pyCOXZdC+UyIfSPBqJ4T32U2jA9ieLPON1aJXaP6+fEMHrpuUBJLZ4SwGhxSW0Hj7Eps1hkwJfILywyh60lTf1bB7jiXGWYUnBXahYnnetUx1Mi4mXn4ycDE6Lx48qt+dut1jpbNEv3ryP2o/GSe88xAVe3u9yz5xyJ9iEWHSMFZEXW+RpjLhmG81OtX/2tGuYr3CA=='}}

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
