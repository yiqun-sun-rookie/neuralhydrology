#!/bin/bash
sequence=15
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
Q = {'sequence': 15, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '216adeb570ef48dbb5e24bca092cf04e9df6baad4463fa1301797fcd4a28e974', 'ciphertext': 'MIIQHQYJKoZIhvcNAQcDoIIQDjCCEAoCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGAx6Vvk7TA9FtSI+ArJ6CTPDQ0Zlk8FEHcJbS05qEX2bApVV2lq336mD7pXNxx4LPK4TsaXvyC+o3omWR1YIkrG9HM9Rlvf6Nw/W89k81i4JmEhRIu/pfKan14dsznpxhAF5MiaKw9TT8ROcJin47Oo5bZWTgm28Am4Dj+GU8bD/tnS73i+f2npelEGJaH5gU82ZBbPiiyh1Ckm9kVIK2Wot4r3OECHMns7aP9bWduTmmOwm548TvhXu7ouuadv6rGhGEEbkpB7afAsN/NG0x7+mvQSb0H6VzBPs+o8OX7EQD1cK6/5Bio1W0T3nzPhYgQXjt+aEqxKSkwW6uwE977So116rL2ppeUGE15mwdmL0QIt4zcJyHnnaPPWSs6gWBE4hpZxsFrKWg4tHdl6JiyhGBwEqDVD0k7jIBT6JVDr5OgvdfpBppi/12GTFiHTy64ZhRmYKqLm4hwV3qHJZJmV60cOvkBlsotjinKNeZnXga06DV9dyvEudY8RqRUOYj8MIIOLgYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQYI82m5I88Df/4TCOsN8znYCCDgBx+aWwSB5ZBn8nh39kahImBvmu2dsAr/HudHSsreF9ZKhcpfEUZ1+R5oicCaO32Clv6w0d54+75NqCsfcbWCPE4BakREVYhhCgcLuKcL2zcG/fougSKIJx92FMP+KXK84Phr4+WrsxitWUcZMZ9c5Mprt/nzyy2Dzy+WmXFHjtlMkiQwXY9jZ+l2yFlu5hLgiL6+3NGegy8qgOeBWg7yU/Q+Hqpb2RzLhdRUGAwBNlgvCKOKQnPPlqxQs7wX+fu+dKTtjTXSNfRwsysICANcYMILP1eonh3v6IvesohyXNydFfAxBhIqXBEE8TOgTWxnGWnV+cC8xIKYPFNNA4YDalLmVMEb1WuynG9NthZfQ4XJoCcvsdOBv63LTk/tV4RM/DK7zhny4FjsPSVLBcV4zntvME+JCacH9ueDT8ClKkjoIIqyEB7lD2FLrt/ze6PgkTFHFilJRnmt0VxvKAfV3WSpFu9NoL8+KzvLICP3DUPfdu+RNPZGg+T6il21U6nChokX9Q3PTcUZI+et/a3+b8HYbRLOc3EakDfK7DAPuaNlpU7f7eU+qv96FWmpk731mbEubD5CmDEqIPxdYcnWkYMe06E9tTVXxzClYeA4j6sIR4iWrNyfUQgHfTU47tJvhUC9tqJSDmKc9I+P0BWJocee+1XNPLZd8C9X7i1uc/3TtBbqKcf2giL1QrIy1okJZrW80fJloqWtnYZSxFsnDRRaLRt8e0oxhfJfpNxsjKp+DB6212MfiTsJwYg9A7W5pJTK/1eKFYfjL1KWP4m4dVuNkxIhS+fFdf731QuuX6K8mMPB14q68cADxD/g6IC17KfIe/tQIq+xcVmI+mIc5S+toloYQh8rClLVN9UVSAovIgaRGnImuz7MlcAGhnkl2XXuy/zVsM6pWfBKwyznEVHmj0yMPHC/5WkNiAAFKJukU+qJWjxx857rDithTM4GqhMfCj5p1yDlAzak+kRpocLClT/18UQkbebDWoe+FHoPJjdSGumNs/epUicVke1vyBrVFnu7CV0GSERK51nR6olKG2rQeYaujyH+DZZ+KySYKfjlbU+2KvYXwOkshXvuy1BSanfSpatRjC7GpEl2WT69k3MlwD9+HrvwdYonQY6uJBV+1l2Ob28p5cE0MyQgWH32kcxO3D6e8SfrrDUz1skcw1h8AQojpZK95pwf3CD/MILXfNlQdEOxGf3dO9UX/6mduV1QkV5uGXzdqdQ9LMbfhNcNptfkAq/s4gVj7STRh20py+oZOCS0U6ithjFpXIPasNoP8Td0Z5XXs6ZTQwOQcQoaEqiLIJTI6r2BaYntWfymELxKEOoSEFKnoj/uMij2j9FBrULXZke+TopUOlxZscDYMp5pmjBSFt3Rl3Og5oEgU7hmGwdWAshqSuzSFs50omat294EJelQYVAWyY0dFrG/oeQ0s5RhwdCChytwU+UPtw/Fa2dlmv20GP1QISymPmoyvdsVSuXy51ccupoV1nzuFbYXwAIFxQh6lr0/5TbOyUQIyhJCKKC8y8OWuTvG1pFfTtzSB48d7Pr49aS4pYmRZ/pAt1HE4Z4h2VaGM/k+IaRhlpSIJ8BUllHNiHRktn6vrD3C2CmvcT7Ay96H+Sj4MeuRby281WWqDa3h3nx/siMKxdQHIARNX4FNgyC6T61X14DYfhj5AK+7MsilZRlvtxsfhiBwG+9f/VXj1STHHAxUeDKksoLHr144JbCrwriukHdmpaaUPLIONRoSR6qQBwTTWEz2pK21LhDXjgxb+rU1INYIDzVFEv/Oz4RHCwJR+ledbnYCXHB8fPpP+krC02vLzs3R3kUPyoAhp8mkTBpkIFy4JbPtS28v2FebG6Wl+35w/GD+idSzhZgoQgtyfXOwI7nRDwen52qGPbq8Bqk13NI71BH5f2t+v80mAq3sxVv3mcpIo6uklR7ie/2DzBoh4HE8RseyWiUY4fDUUwH6UlBlgk61ki3fojoyeMpD3nw0iqhoMiSzwRBYBjUOU5amYRaMF8bnHtVCiT0lo9PTXM5+4fp/aZ0iAkoJ8NlLwtjb3M3au2VpwGXKV1UAhvj6JCsESxC91svrorMUxFI0kYMKl7q+yEDaOJ3M8YQ9KnkYa3w8aS0+tYTupYsAzw4cKHy69LVm3gF5ay7TDJgb48QgMLPbEk3r2hDIl37jobBvx88WQ1Xd82iGT+2PB1B4kO3LLuc3NUDiawaW/KAj46NTnhe49PFuPYo0czf9ZBXW2M5vVD4+fEbTU0s36wxotUiZqkgkl31MJWRo+W4HFjfIKYjRGUIp9CTzc9s7VGUEy0z4whcvzorPLFlF2LTLSzYyVeHPlE5C6CfL085hwTVcZQwfcvzKfvzOsdc70YMnLFI7Y8LN+lomrGr6cnDUy+MBR5SRF1dr9u4GHJU2s5Dl27TrqdIhxy9Jp/nbVhyOz7X5GCX140Z5s9zvwdLsBDQfc6QNYS0p9sKAScLIPmzTajj00e8+goJLjlgs0IIjtjTK/4RWnYGFtjYNaFGMtuDGgf3Xqdylq4suPiBhvTcpwmvl0HDpSD6AzZFMrjkiC1CqqtuU99XIQGe2mQNO1ZiPpS5pduREXzer/OeAwCy9Y2/CHXDyaactmUskQp1MaRg/Z1LycayNZMjK7+GSdepsb8p9hXHGW0fcNjJqXiG5/+EbsLpNmf/bXLCrdeOVlmhC/y6z8pSF1yBC55tpFFdP5v4iglUHDkVlvmJ414YaSdhoWALdWBnwtaEz8d3QEYfeixbsXDiUdSWMiIMx3qHQa8wIro4It4VsP1vvxeVLuKWCNjCpSLp+ducWb1tT5YhjUGmXMDKQwOXpYwvxxPRhfVGmF0lyQfOfLdnW01D48dlhrvVjt1BKp3SK/dvep4z/6Io5D3zeOAXNnWugH5Bf+eG50qwIfItEFpaH38Ky7JNJWVIPpWbBs0dVu92h6WLPAXPH1GomgESP1L8065K/S4QnGF1IUZ0wmL/DFPtwnPZ9rNCq/WEG8Z3Hq6xtK9dFHX/wxMQhUZ1D/qZmkGDuQbZAPiaznqv9ixs4h9YppCJadXF2cxSY1lAxWHWzmCoT9+AlYW5e5wOrIv/iTxiPU5g/TLAoNc/Xatj/OaKwgEacgV6bxGbFUe8HG6bK32Bol0Puq5VK0/IpV+hfR7LFxCUb+5YDGKGgt3EhKAFS6smpko7uFcMhxlEN451TaQqiOEWeBlZ98J6B3qrUmHf+eYvagvSrmhid+KMCuCqQk9WGtzVqNBw+Gs5PAXo5eKWfbhP0xSPRjf6kqGWPEmk0Mp7aGdEE6o/2r0dyfzcpytsq7iXHpqPmhSfx/o7tYmQCjbkiTVMWT6TOxFfFRpbpZIbwNQMH0Vzzh31co4GiebnPB7eNIvXekEKPt5ANoekt4oS8I1/q4bid/zU20/ayPUGQrUQchmjD+D80aY9UYd1j00kLs4uPZWdlW7zUGyqm41YdywT38kV4AfW6bgXaM7KSpM90HjXurH7bm9sJEDfyh/EE7mfIZmCxm0jafN9p1Fq3kB5pp8J3iKDXzexcVrcLnXecvmGMQkkiY08LDzEsoHRzWoecwAv7UB6hF0pOANcuiZ/dw+v15EOBUOIqHE0AhMYbPg9moztUmngo0aHufiLYG4OnjDAn6sv4GPuWJdldC1SEJ/aUInBq21BmpV8FHKmNaaSHL5jB3VrNGbrXLl5E+i+z0hbN/os2FLdcAW2bulEQQqw2bPTFy3NcMmN0u8h5FvwPw7blSbgNWATqQRZymvBBY2xPQ82EzBRv7crjtMLS4w5RAX8VCyMpKXrSFd4p0o0exF6eDpKbrVZKtXlbDF1e78Qu5vdoI6dkeE8geh426T62IBxxHT/Z366+w4EKaOc1arkE0L967Pa5yNRiZ3c3Ogp49MF2fIABtrHjKGLZtPWH9xa0Ys+seHG5oKmUZd/jLN8mglygr+6cUem3ARizkEIVZPSYoZP6D8UZSMYPheOSLqbF7xws4Cnh73hpOkyQKFtxIucHLJ3qroVLN0CcCvw0aOf5hr1yy87ia5MNWPW7UZhLqQom76WHJRyU+D1CujEWp4F5XYDjujcrQpDY+cci8FCYWZBh5Zf6UK6h0S9K73Ddv1Bv/z3s2f3Usu257Z+8REkOEYBYsdYODeZrCsKkhPZ/N7n6HFgcqvFDroVcujr7zdpM3c+9WYxyBpfDs0JoxIqbXlgxa8BmIsNcNHs+x6DF6Akb3dlA5uUj6fRH4b/UrsdcrrOkSm1V84glKgP6Ubjc7Gmn/oZQQwcHv7BqO/3g1Coq+lidyuFhtmeVRnFh7vZUhuyuHqI/FJiWmzif9xvciqfB8BTqzde4vYSZ6PFOICBRElFjrHkBGt+xt8mLZLmVkFNqbiP09fTE3e0ga3nbqvMGcKNpw5zKfMdVExLcjbMXDPYwCWRjcmuG/HnbKc3RkN+32AajyIrC8v1KnQwOZeXNwnYSofFsDJgo/6OwuFqpBB5VMhruzCoTfUSIJRcvvxv+pJJlQmlm1TZZ3gJPMHnTJSRo23TaCeknv5T4kDmaH9spyHGw5sW38vEpEvAydVxxwTt+pyACRTU6vdE2kH+yNm8cz6Ps74+8VoSvPMjIM6s7GYpdhJaoBVLu0XdFKr8T77ho2bnj/M/njRwOGoEoFqOVfbZlhDSUwUOx97szpgrM/ekmFMIawIPqEeUMdWPWQsioAeTufZGeIiyV+8ZpSdU7kOcl1fxiIIs0AjoBrTwBaBX0lwzDl4+rNJDJGbXirK6g=='}}

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
