#!/bin/bash
sequence=121
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
Q = {'sequence': 121, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '0765ccedb1456f89f56dabf8a0ded52b55b7a13c2785eb5ae582f2918af2a90b', 'ciphertext': 'MIIInQYJKoZIhvcNAQcDoIIIjjCCCIoCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGAa0jW7eAKAtSFwB9nfF1XEnOCXn6Cu7M9xYOkAIfSwhtnn6BIXLNeUxCNHXnxVYdXhXbzI6VqI1uXdKHuy+qqetwSmxrK8hkqcAxKChBHqrfkLQ9J4UXRqfPebgmdZSDCdx5jNeIU99n5L+coUC7520MzeAZoVDNLEfDbOT+Xrf0fTby9iZMkysQeZUMWpibjp9uD/9zRCJNkxeIo7zPuVkPHLElqsb6DbQgqvgwgY/dpIF1O62Rap0ronWn7VR/Mq44zgQ7EtR99r1vGm7hgaoHsH3TxceFVitUz4aFIpCwgZzXRrsoVNvfnDlkO8fAaDdw4ZT0JDTdu2JZSG8fIvRV8IJ+j9DFecov6DnujcAv6MroaQC7AbnN9zoB2z9kVqxtAonIcR7PdAIhQEVgDvjOCKQfFCK6q2TDfZlLYc+dCxlUU2T89uWqqvSpM49JClqLYgr2g34b4F9dt1xkJmtlRgX+8GIltwkKBFzlEbMphe4AfiTBLDtFMXu7H3wjmMIIGrgYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQH68FyjP0bz0P7X1NC2b/wICCBoCX7XDY9WbfsFAAHV6xY979RgP20opZPpcpZc/yMvpI/BhOb7DH5YEO8n/UBQz0ky8ZFoZrk4QfaSgiPe7OytqAZfIpXSaNnefPvBdB6U9BCt+gw+Cu5Z7GLEbJA2dpRp879nw8BBPNGdpXVJPtwYkmkKgXeKYOcAxQGa11AbsbeYUCV4mctbiXj875GDf8SFv5vi8AW1Gg0vueqK1Da/6+4zlIHeozIIyMZ/7gXhLsd3GOonjnyrdQqZul2z2q7id5c+ddsuHvNTub6BKgUlqL5LE32MdQ7Q/LU22gmpfrJkOcnNQt9qhnUompNJ6zdPIyMOj2NmG2o814sWDna9X4MVq1LuRZwWC3tUj7ZvPujdeAjHAPPZIZ/P9LhZBKoYwUkqjVG7bI9/0JeOdk13vHL5H0JxdsWo0ICYm+Kw7nAhy6FFoclZVHFgx16EI42XJFvYjP70v4GL9dE49Kb1IlK7BqBxVx/6tFnE5uTUKi8PL5JqDAd5/9xDE0K5Id+iWs0mnsjfIfGolCZnxZiWLWhvTEGzw0eOicwEhLfIbAPGvwYaGjec++eT3PtjhiDbBwHK0wdiaGLEfTHooPcD/P3U3rIOwrSWiVd+bsIibyTjB1UMO9ziaC2lMkjb+7px3W6KgpLpl3YlnVmQUsYE0WJx02/hT9g/NPsp05n8G8dcI3YgL5l7MIHCZBUBSm044Urh71QDsN26AJcKCoWHiZ9a7Cm/CdjxU5AB+1Lz8mGZRWzvtgD3StdiXMLNaZkGPL9Kpjb4Hvp3sAqLEpV3ckA/0KPFF3ezUB7YAZ0n9eEB6VNMS8jtMlEDuEc6VVxJMTgBGE2mxdnST1bWfFJ1pq0Q18BerU583heLWuIJY5l2Hyk0eAzyJyK0wyfhywqaJNRhlK/2uSAQ4gOhVybX/o/bEfnED4T6CH2XnBGiSd84putMii+vapFzaMaFEklAUrzQE7oLSIOuOk3zwlOZQDWqmbm/DSchIxE2IzW7FKyEpF2sl74hyN7Ni0+yLlra7ZbVi3XISyhI3A5isMOLzCdDwOWO4DlBGEmdaSz+XdE0BX6nnAWJpDnHtN3CSNvE3w9cEFoVGnpNVvkrTVTmxnbWConGXGa2KZ3Ob37xpcKSIrqud5ShV47U1BvpHuysqLj1Lbn2Js1e6ZBtvn43ChheAPYpXYyxLewXR+gc0a0fddpRbiOjI5aguNAB/B35A/nTOj25FjrORzJeiZGRUiD3wL1yeAV/tmK+wV9tSlcL61yfDBHlP7hwAJU3J52VePXwxu+utiHsSD9qL39yyKaO6D19yCWllt8yMxcuK2JvhVG8fzWwO+NLElSr9/lyP5F+Z769lXiJARfA5B1onRaloDbaE7OQqE10sTDhcx6UtX114HR45vECooMZ7jkwPa+UR08sNGswQvJ5WyLcPY+3rVK0iD6CqsmxLPrAXpO7mHKy1ajrjb5Uobs8KUL1zNABra2z7LbFaqx1hkTCtfPLsFibGD/SDq65t6QfC6nx4flYTwL3Op7FDTbtYhxEUneII0JknURVXVFOPZlhGyjB3GZNYpssMIC4KcWG5whjvVp2vv0Cuqf9IoFL3x3BMcfiMhrCAwZNR0Om0NFVaSGanhxE5ciHIi6ZeV10L71kknl1Ofu86sIjxElLoifkKn5BtAZMDZA30rz6bSAjHr+iMfGsqISwnauVoI0f6xQ/6OJwRqODJ22IPafsvAZlJFrwPpWhcdqUcBNJ73b8+7RHGE6KekZBIKfl8TYEm+LsTm+Hz9vzY7Q5JzYIg9X5tCVHvILf697QeXlfNisONF/qmoG+f9tu9VuuPPGe/iN9rrESQRTOu0ioJZHeTmuzqUruiQCCKULU9nfCmxax3ivlgUR36srfPbNO2tbEK3DUcnQ4E6fErb/9oOeADzLP8I7FPul+gQpecPn37OhExK+hSlfPAKMjSOTHnMUzcrq9+IKOCcAHL7+Xz//HCd/NLkQvyrv4dUa0woQy6u7spntM95swFf81wZGlk07/tHECpOQ3xcWJ+H+dU6I2xInqMBedqf8EdcQ0IJ6TUgukzv4/emEjSQJjMKwBN5LWwCpMLpZh1UXrEW8BCU83DCcennhMYyl1Chhh0f8TBRfXMWFxC6N/9fht1J3F+ziNNU+PoY4iR7F0V0MRpI9qLreZN0fZIJLtyb1Qc3KDXEI8DjVbdLZZWy3vuvaRRr2tW0Eg=='}}

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
