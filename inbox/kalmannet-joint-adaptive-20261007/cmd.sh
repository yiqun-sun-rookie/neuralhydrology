#!/bin/bash
sequence=116
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
Q = {'sequence': 116, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '8f8c26eb93431201c97bd4e206721235812a9fcb184155c62d9a3ce91e5d81b6', 'ciphertext': 'MIIM/QYJKoZIhvcNAQcDoIIM7jCCDOoCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGAtVWHTJIt9Xi2CfBKnmuiJuzLf3SFE+E7Hcl66gjGnF+Jb2vjjQTdMgOQd9Lids0LADQL1V+Ooom+ENOxjioJ8x0VrfTJ1gn+I8nYgEsuLfDtVjSDcjEdsnE+vxELFG6ePLc8C1NCQIupWiMz3fwnqOZ0T31/AhpSw0KnllFwb2O+5TlaPCMafNdcrO/wLCJ/I9AsRccKRT7rpqx6/Zu1MRHSA7L4mVpKL0CZhAUtEVN7yUgEPI8Yi8ebabTqFKejEMYxwZ2Il1YGRtvkJpBnCYmVNt3GX6tnU8nfW327m8Cxp63ACbEldCY7rTqs05IzDJlmwOuh78ho18/rZ6WlpPUfzc6bFTQknY1QsyZIKUZamxAsinQGhH+PcLoayMYmnCD5NTCG0wTlfDsbRDQcIGCOu4cCOPlDCRl8kL3MkpTus+2vWN9WvVGEBfF21vK8Iqfis+ev0CVD6+U4E2pAm01HGMgVtSsB191Xgb7Nn1xO4c1Cd/AU05hsT6fD2svdMIILDgYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQvlVWZ+NA1P3+ZY7loqWam4CCCuBBcZeO1hRx6DUtrRL22/yeG4EK73BEn2jic+cid0XmoZvR4zT3WlLRJAzupq61/WFOrLLXDkCxFx52EG1ysqN5zHIfek7Hfzi3Tha4Y8ISmf3KbUVpl9OraIfa9Ug8wOw295df0axK+F7NNJE5v51xuTVPM824/7/zUfpp9gh4h2rlyIh+8mJT73DcImAsR1Asqd0Qc+HcGApmF2J7hfJp/kx/KMPcoZ7cdWb5RIinvAlJzV2Jav1VlucNf5jTaqGq2wOKrQjzzn8k5iSXOWBJ4q4ftZjGXPEDlUMZBsRZTT6/l968Dz9aSe4vvWUJYQ+txlYv3BrVANMyqNd5D9+1skfeYwyq+EOsB3nLrpbf2WK4h7f3BMtY8YZqRCkXtAvC9M/JvfrndFhi7mOfJm+M6JwtWDMy7Oq4BYOwgxjnSFxgQ3aCMVCosa3VSIcGQaKyby9N94HqHu6BVVgf0GK1iXnhvkExFk3Xmsjzx6o2kMZrffnYb0xLApeV+CCfdcsSUdUH5EV1ZaWXsbR4mq7nMrdC7D8YgbvNmG69sI9eOC7KyrFk5w/o2Q7eLzBwB36Ak/tvnac3tFqBul1UlFhGrNDJJ1Q9+9wm1Wpk7igvvQuzKlDn83uUlfwe28Jo8orC1/ly4rJ0YyHrpogl+vQh/Ymgro7TS4qXVuujlPxCyW8jSdxAg2moPWUoQeHNPFv8dcj75NoUEfFtV2gbECNvEWqG4L9JR7j0fjHEG2VyUmnZDZcRgOgEKlwY93YyGmIh37fRdgnNXrv4+0zmDJmvPWS1hlfCOKAy2OEEveIiiyxxnXUScxAIVHytnQfUwHWICvlRxEXFEXqUQ3WxTndN/LQjI0KvcjmL5yQzq65XODsuZGbrnNhihNsAqkMEgGiwk8me4iV9xkdw4C3tcbwTzLVxfyPsvpYwoTsD4dZhbQZlem3RfLtXClppF1oPo9/zdhhDTLodrA6fWQler9JE80wPLncyFptN4oJj8BVk+Md+jhTZzxxkV+3j7eRK35ImI8XYCpIWDDI6PdC2EtZwjLOFGBMll6FnV+BlsW+i80Bkh5fMfsngdrxsNCa63qLfgfVZCOnN6zGz/vknJvx8gsxYOk61HeSyHt8e5ilsyJYP5ozUZqFO8zJfoX799USwtVe4rEb0lXw6OOCX/1jQwxQRrMLFeE3E9Wppm7Sxt83XOJtp36KWUfYMy0Snh2GfAa3byn0OIETQ2rluDHMkT4wnyY+xNM9BuWj6stbXnzHW99jOSn0HjTb/JUVD4GJU67caV0cjYGV5qT4nDG2GU3C0qOBQJ4RXnCMH6zfKPqcLRFIYMfM9xPlaCUI8jToY/lDa+GAC6B3OqL3+D1svYYs7qTfHlJbGrTXb9QxiKj61bliC+sv4STXQ+glEvX2NTYnrIgOlOSFefHO0w61Kj2ZLrYjN2ct7e0kW4SFi0648LipkE6p2mAYZb1UE3pi/5J0pJ3I9qzqtSPIjMuNgVODRRGHnUGAlCKDT6zVhzlEw8sRqGjPJIJYUHlsTIaCkvFxeo5sAoFxVGjANDnJCMWIjWYuTxy8pGkej5ZJo6a/NJOv/4C99kD2WDnl5u4Zw/IwxEO9ILOz64KOSJ9xKLRFM1EwHLvu10y6/2dyD1xYZXv1zkyJUlEUOnlQ7fbakWOGN+fUi9wQqo8N87xEzYWOUYhd/+mHTZwye7VWGp3b2sU5IcNxomc4v2kMUsnhuDHkSZCzBo3QJ/6mpT9MUrmN3RHoHUK/trV6ZZ8As9jLfv6nIA/8CjR2V5zUHrJ1PJyVtOW6syznTWTwPS3dfCk3Uf5kyC8IhrQQv4z+0OP+6nSQSOpLXuYqGssdV9dkc16bLWEAqtZ6WDJP+WDQvnDCJ+W5oH8lTK70qBH1A2U5FTfecU1rx1q12BM1e3rrLfbxQn0GZZZiCTDbJzUJ2xFCsnob0j6w5RpHCiCqZyBAHau748H2khSTmDi+iYzLb+xkjt9m99lbKSJEmEb2E53xht5XTTqHPpwYyjNSqC1Ykl240v6Qu8LzxJByTX+dl3ytnJUba1B61kygJUHQxaZu7JuK4nOmgcBHQ66I35vc5MwX0Y/ozL7QBnCzIu7JlqBv+vjrzXPPM+OkoUIAQTz1yNLkaXPK7MANUBDG9pfHxgZ/siX27eX5HkSQBxiUkTq3w/j75eYX3zzaoAqwVUppFIKeOWAnQPhuWJfkIY+SBLP0pMF1l1wSKZxNjF0sgAnYxwJOU4kFSgQWZ4UtcHlaZpD8mMSLhTJyGbdYsdngsUPv64CmUYc2dY8RFByVkSLHYrT/G34+qTQbFVvPpNay6yfl6m8+01giduFWH4DNQ3qnjMLdDVoLZ7qR3kwucmJaakoUgLkwiKHEeg2VQC8Xr2gFwqeXeIVxmvMKpsAYcueWIggxHWev27xseMPexoF4kribR5XwcNSYZ6R55d9GMVAF0u13dtuqoPj6YiICPSp3e1hcCgFdtOoVv9zJrY4G/6oCsvr+I7XJfnoebxcT4D2GMwqiV5uP5mR/TZFLZCFvFS6XGMg8+MpoDTW/i4p0Th8ZNjiH8CYGPTBhUpFNf2F+PogXeMMCZW2hbkIa4UyB4JXgWTYT0o7u76+GexKhSPyPveSNw1VD6c4eUqmRwPg6RoRSMlqiKWnvZVjb+5Qmdze9VRaySnfXRjy8RatGNe37OxrgjFpNIV80QRU3zLgB4uIy/X+Z7Y1Q3/ynIMQHRb1e4UzJ4hgaokroqFDgPLJxCQRZneUYRfQ98VmGxgQrAIiDZvNFDLquc1nberDFYPbz0dI81ErTp3Fh/scPMOFOveJ2BI0Iz+2a/F9hG4upKhdtUaXRqRsONSq/VqTybmW+2Hfhjdqrl34eR831Uf2TncUcQX7ymJgnY1v3We33jWA6zrBZ1NDw6qeK8LvGuV2/qFUDinnuU+T58X0bvjxqSHyawS9fz1uuyMP5itWhUCYVQqQpI1t4LITTkJWfZX0d3YzaeSpG1e2IAHuA4Zfqbh3AYsCRyMsae2mumJORBxEUIN6IPMnkbPp1hLfmHYMongUcQDPDb/4mbU4WN5dTOhgGyipYXq1n4kHquyIhx1zIKzl+rX0+WN9fx1yeSARju4IjSPeswR0nKdFrky4aHD/6QUWO2uKGpkjkVw1smrkpDs6n5P15PunXhLX9tx7mQSSCd7iiJ9eQjuMl/fsPUiVLfv642Ku5UsCZFMAJ0r6DX8XQGhMCNvxMqUsDF6zIPsfcFsbGDt8XnuLfMuWxrPLL5lsnRciAthmtEYIZqF8rvaJXdS77gUggS3NVSMPl85mwQxtxbAwlW/9OPx+yQ8ohS/3oGwaz0xdy/nAISi0y/wANOlUlCg7Tx2V2nLlsflYiIjdu4dsAFJc3FAn4ydE5gMKkMKV3QlcILZPwLpDva0TIE1Y/eoy69E785y/GuyyXL9U7C5F/8tX7StRPCepVsVTAVQk4h70zvv7HfbuFx+KSU+fBNMz5yb2xet2TFwkbSZnS5WPJbRnHKTqyUppq8/vmY6Ql72ReUsIcvrV26Fba2cgcVVd5hMyQpufLtgDvFv2DZZ5FzuQYqP1UKsIpiw4cRg3N/7RrRNu42crdG8nujUlWrkTfR8c8wwEaGPBGgNtBQwy5ubInmVuoCPsF5p+nRI49ylfyHLuIXShGrkd50j0XhkgsHNge/rMknW7bQcwhajX0='}}

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
