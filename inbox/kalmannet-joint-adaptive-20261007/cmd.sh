#!/bin/bash
sequence=186
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
Q = {'sequence': 186, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '7f4dce65bb85e75b6d5da71a9431526dbcd518586cb5efa1abc96cb1581a51da', 'ciphertext': 'MIIKPQYJKoZIhvcNAQcDoIIKLjCCCioCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGAT24kZiFo+pew2+V6ifKrFOmPLj2906usY6m/lo2QCuH60JDspN+LbKxDvggkfDMl/s6TLxbeayADLabKEC9mLWYMc5Ygjlbcz8gYAMcmBQP+wpFJrUXdue4JvPdU2Z/wmRZf6PTwdmX1Pyb2WdFqOpQVd+vwJ2bfq902wXEtiJzG1wb/f+P8499e9WlB8vL+DSGD4Phrndvn/IWqTPaFtxS9/EWDO+EAt6sfQHfZ+Z2DC9A6vRXJh7ZAH5JkusHwLwWVWxHipI2HzR+g4jC495GN162g+rtUKOdUu3URGwdBKGWY0fDNWg4PMyO9bkIJCLEI1NjbFlnb/fteKpxfI3P5xGAo8w74hTdmWszwf37z3+/lWKuNlJ8LU5VUxom7vz8QBxlb3wYu3V1qaKgDKtZrVKRzODxjMp9CpbyS5P5ViE2h/HNOBuuJU9ClvlTWGH3mJmc839VeOeEIBShBie6BgRDueuihASa+U9WjkJiuhZUtttog7DOlLB5HYNEOMIIITgYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQ4gWLuGFdQvuLPxIlmSZUwYCCCCDEVY0yL0skD5Y1sEkHpMGF97OTwAMBU//t5NGm2C9LJIRc5hmZmhmFWt1DC4Vq6B3EC60qu8Y70/hH76Ew9JQ3Ur3QEqvO56LQO5VgoOz5JamfZRh5aUS7MXL1I/W/u5p9b5dUSFcgGKv6xnXNAJIO9wA1LbmP5hYs+0hVNjInqmEhr0+ei2ya6Q/t2LWiyGMjHnrQcnZwukEwHYcjNxfGeIjCQ5WKrzrV+MhcEuqOnFMSVyjrSHJ2hevP3SzetJAq6A7pD7K3SZRzuSqxbjSJokIN8Lm44GXtiSa/+UIfYLXPCchIZu7k2tX2nGDk59b1bYI3dgX3E+P+ZC5vBBmktt7fLVOOBry4S66ZzdZ1r8Jq+bfLA5Wtd4sou8BpKT2sNfuCNpiy6KTzV5wP1gyCUO5HT00y2yWlOWdQLmknGJwMAbCmyZAZozgT3NiG5ikRRb32R+/3UpAXTuse7uM4rnr0YpSA+PVItVV8xCTSN3YSJpK/Z6bXfqmR2TOmbOpta4BGE4uXcAkZM1ToCQOqyUp2e/08o75UsKHrLRRexc8PR2hzrTg/7EVfGGIGGtdIJHPJ1D7ctITXrP8tFwadzz2DkP81WFxH7u47akwXSa7O8aYZDlA3D6JGa7Hh4Pf0WZwOtHSS9UUHvfy26GtOUn4fNO8m6wyJLM6VvgOLHowbkU7wDiutHPeOacjfDcbpLVgcyTPnyTgTmzVWofaKmw6mhQydY30brOW2iQR4wHjs1FvtD6PH5LUnLPn70XEP9XEnbcc6VE8jCbQRfkuFhqS2rrGWoSLdB+WThbbqviRCcIvOjPQ8NpP3i8HdPjrwSLhUYQfqwh2NJ87xqL0NDdvAkBDGfeT5mkL/FAShvhGNYf4t64cdfgaQcnULTOFLrnuHULI+WEmmlx7DeNw55wcAjVExBBZvX5RYOjww0UO65Mf6xCKWMBuJy75jhBmYv0y3Lonn+vwLpyfUPSl1NbJqlMC5r7jDYngC9TTS3l1pazmk+nvFN/qJxPHj1Z7QWmgngAAMNl8XdPGrhHgWL/TG1q6Iqrujq7exoXoLVTfpFl4xJb3UG7jXqIOCToHF7UEzr0Of7yBcXX87W94NpUtSMzUnd43Yh0kaBe8EshddJNOMyFU99+fmnwLNt3sezy6ZMudEp6oV42mtmFYHg0E3X6HYx4dhLECIExzRbONOA7pTh/RRYv/hEClwhHkbw+DkhaoFmOA3mCu7qWqlMUwbYGvCDUVD0UDVT2C5x8HDg0WZYzHzuMuNjEhfY75HyUA7uX3XjYUQocABteiWo3D/0vDJw4MCll0SVnlxmNnfx5MOcXcxESumwh97Z0HY4jLSOH04vx2PFTYpbvjR5z15iady+423GuFoQpdhs9zOn9rotkZZ2SBZEwGBSUD4upFhYCa7csnCEgA6EyCU09WVIJ5fHm8nn2eH8081Dkf20JaHR8vk6H/2KZQRYNm6Jw8i2LJNIxdPtqcT/C98dFL2q3XEbO4fC75V4Zgczr6wupMvTyYLhwUjweYcvEzhAS05cnSuFEJTWo7JfMmpKIxCQIfQIhmlADFl0gO6X1vWq5zZ8I2tF43oiE2lO2eAPVzkfb/vESImESOLJuR+b6AYbZKWqI5TUIklNY94J+j/zHTNtADaYOiIcV2FSU+z+dSyRN1lwIi20Na0+4/q3go4gRB6Z8ykvlM9TbaXmy+vrcKRQ/DWs6fkLfWrdSaXna5KRbHwh5ZFf9G4DdN5ap4mZuskq7/Fuq0GrAAM9UaD2PIA2cSWxk2JmJj+CZmenExy458hfxfhSwKn11FR7oWNIFvreNrCv4hDo2mEHTzck8A2ZsBtqqXzHqOxsZ1aLuHhSXItA/Ho0YkAWOvjab9eqZhaT7TiG4NJ3nIndPMfyMtnTLaFci9ZB1ycJMV/+xqgfHzsdSciOn1AuctHMx1hiyGN7gKNJmZE96tfP9lo5wirbN0HYOTUXBMpTsdC1EQ7KHZ11t9SvLfymEMJ9pe4YCtJNF0/DnZBhDuMjMNOc3KScZ31oWfHFM4vnUr17F2OfTgzhU0yoxLiLK7wduDGTr8NY3EmPviN1m8871Ev3aGipXCDOHB8qfGoYfNMXrAWhF+rmsscoajxvgZt2W79MPpVyazi18tQFyNjbSumrIBPn6mS4C5pjQzj9YNP0KY6F4hF1F0zSGcyw5nC+m6oPD4pG4+dok9FCAfIFhRXcf4zxH4DZxKCVGhiiFnW2qc1FAtjR7s4ay5kPShJoCaTxyKldFkmlkvoMHcJk2+VPCU2ONHG/DwAvsf/2DrXEwJmfcD8Z+FMXJSv2YtSvRqTOHCVDIm9hx767yc3Z66MKZUwl8EdCNNejgbqWwvvA5ksu/WPJdbCp1BdRLQw+A5PZRiGAKHHifcMX0rRPF78SK6GurCxYbFHNOS9nB2Cqfjdg/rX65XSeIW1uJ09dw8TJo+ehDyba/RuAEBwuk+jQ+27IUFvin6FXM+9pjBf3KjkwA7AzdORXm6k5GjlFnMK6fIpSQvDb6rz9RFBAQ+Jl5QPnXwENckGAPO4deLtz9ED3y44Zk8N7tXu78s8zAtP0tAMEidlG6LLVvE7Hlkl0EEvEhOqOA6KdRDTLaxQ9DveRmdb7+ZM9z6Hi20rv8+MB9c1llDs2f40xG8h27kml683T5F0FqoYgVkM46gW5PjGlxakM/RUBwU7Q/2fpR+DFc5G6PPHGowAAINSZ41DGXSf+Dqg551qTZSDH2dFVQRW3We63iJzOC1MEcmo'}}

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
