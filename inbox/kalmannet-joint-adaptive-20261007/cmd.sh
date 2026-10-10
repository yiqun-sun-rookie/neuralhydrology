#!/bin/bash
sequence=130
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
Q = {'sequence': 130, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'b5358ebffd498d536dc31f2322970545662b2429bfc73c327c9f4c36858ae3d5', 'ciphertext': 'MIIS3QYJKoZIhvcNAQcDoIISzjCCEsoCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGAcmGVGC/pPXFYTFEEmtRKH56dyPJPTz11cQ7ZUuBee8jDUv0QpZdbEHCwXkcn0m5MVme6QHBDLRkzHSSMQxid/ydX6fU+n8V3iBXly1M9vQY4IcHZPUkGhI0eEVaNaGVcO3UuzpsThmsg6UJnD4Js5vB/6/UJ9KBbvOZhVGdctsbBSEMP80Ht6afhjB7iJypdYMvPzup0CdqLgSxCkrS0kO0Aq0whhMcNxT2zptgO0GUGabdzDxWkp0wdsgWpB/L/Q1+ODIvLsCbX9gKXGr6lbM4PKny4n+az09W4u+g3BsKPa8N4WlxxhutPHAzYsFmce4OdfNcT00w8G2m42cVeORErZXgZEANQjLQ2OcSSIZ3KbG7++ncHmmR5xXwWRsbiPXuLR6+XlzQz/9iEHlAYat1zr2LUyXKN04zI2N4Uu/qly/rP9Ko4ATNDj6PK3k0SyNYoeMqCSQkrVc5tDctcsFuMgcMi84fUhOAkt/Zim/AhIeN3MNIUhHF6fcVm4MkHMIIQ7gYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQWqn0zu7N31j+Z2ok4WUJGoCCEMBCMG7CZOhOV3nCyu487g/PUtYqhtHxLNbWQ0zpbgxI7H1w/JZfZLipyu/GjTg84T1hRKt62UnKeVHA5LEioRjNL1oyxC3qZjIDvLRLqgc0t/YRicSyTlSekRvpDdhVURqCvYcdRiLHqPpq7IxAWUXxfV0TxrHYwgeVWI0V+Lgtb/LhVaXR13l+udxcWGlemLUFxYYigCYEcvdLSgZ6wgKKWN+NtfN7AXM5jXGquvFQwDwj058ILnbM8E+nHhwWJFfEGNWRe2MIcDlBlQUkHSGXzoWkUqy88kjABTzOGvgTqvk8mU5MQS0gtLajMu48XyeQEm2F34S2NE6CU/6xl8DyHVymdpd+N7Is9Xwm5//ALOAPbRAUJXGsOjtU25ALto6rcEBgD0NElH/ZhcYCywjw+EXGexHG15xjnddhcfB/iOHI0ffio9Qc0dCvl7uiMRgFx9IeSnZwVdaMT8ZR9POmgJWdtdHxF3vzorB4sp1YYAYPxaZ1Erv5hI2qrknmgz3irYPQ9FF36f6txDN/8UUKYdevERZ7ag0Y3/bSjMbeifaAW3PVq+tV0WWuJ7T+fMzxMrm+D2rp0jtY5RwiwsVB95rLz9VDu4+wNiZGIIf1cOmAurTQEB3TdJockcUI4iVqpYYE/aVa2N21FGlVJEPD/yUS1zQ4sALW2Xt8Z0bc4o2i2irYwzQetPFLOQpBUxNIjnBkljBSLyy7phuQD7RyrW7QODw8aNO3ONOzAvOgJTd7F1R+YO6+h78r9mX9K4bfPxwlBZ60GqrBo4vsoYpiX2Q0xiTrraor75BkVdwSPO2D3NJHJXhKz62BCJ4L3SgfG9HFsYbZPc4p27CVfYfZObdqN+CWjq4JgjGqCf8ZYOpMbCGgiUARq+kl42ndBuWw5cUITmw4RbOIeAcFZfzUS/hcHLFzjAb8XM+Z/K2FEqScZ3dJ+eoF9wr1MtV3bDEwy3mI4bf0ZHhl2Xv11PQAyQve+F676gCTXuHCWej5Tdmlxp2NFIrznenGNM/89YhiY9xq/80aBsvoU3U/O+RQDloiUraJLV036eGcdVpkYUSy8XB0+XI2FcHoPOsHm8ZQYQhSv11bgz4O59IdBKodCJzzpROies2fHc6eMxjhQhtEFw7gCAEdYP/PWp2clGcGeUMq4mNcfcOm1rDgrpCXWL9FKEmCkxdP+u1FOomjzkJL/BMTA3rNMPqRL8f7E5lEF/fbtorMGiKx/T7WicqrDUphdhUV+ZpSNqFB6uAzxJLufZWVBoY2tL6chHW7Qc7M81CEeoHc0SkU+YYzxPwRWOd0rDKL1GC7prrqPLVA9RhdE6f9SSPvMrkKTv0Z+/h1HtSrW869fx+2nrSbE4GtESChTQKDTDgtJEPL50TBh/K4dWyb7CWVtRy9gd94bIAR7pTASYGwk91/RZ1EjUqb6F6yhelZm0JrEIXNALAzuvI+DGLfBFzPUUOHhD7AyTDbD1sDeUCJ6dVuWR2XLSx3k+GXs1Hb5HVyNMWQppfb+vxn1ZNgf9yZr1X3Mcd2poYHFDz91ijGsQOJ9OtK5MZfJWZtNDNvh62xyj4GfZ6B0MpU0NoUQhda32ooD5bRyb88LUJ/DmTAUOFW3d3HxErdAGdXjxyVlubHBoz4T8qOHmj4zdHpEalGNjMjhpJKN9Rvmw1YKda2U6jjztfVYm8q3vS1CndbVzysx6fkLvRTG9hoivGNfeRcTb9+xOgImUNiUCMEx32IZ7vvgecW6f2uihEvx8oMt8dWlLSS0wJh/ca3EtfGZ56/kuAPA6HI38mXHTn1+495Rw5Q1ze/mRtTGw7GjPZmhaxTkaCx2qjeu1FPf0kbBkNFen1KfICHCHBSsALcnXZq3mqC187vPltiOIgEbw25a7/UgJ28lbuFgDknMmaNbC3eO0hQIUGBhMTIDttTCBT5wl2C+UYjJimTflFpCKz2h9bwZkBbjcpVa/rkFXvZBoC9taNm/8d5EzHwlQupOw3NrGoX6Bhkntm+99KysdcIoredMWTlZpFkC4gWb31q044sknyB3BCtyxGet6CDqKgemcd+aEs4MJl/rqrepY0L9bXUKfn6TSpC72Opqltqwm+lPlNk6RN7lDkoMJRfQDQTEetVfQIZ3jAVG/BWPe9WtxJSWmjcvFiShRTBn/++6ZZwN8hRZX+vFciuiYFR+SaiS4Yb1ae0TZ9TB6KvGPCXZuq6Ps5kRgSBngXWW2hi5h35VNW/b15qBcLjqCvGQWRu7LPVAf02cx/xXt2ZCkdmnYU55qeQo07RxlNAyWbrydUgTgels8Qzgt/D37ZbcG/rOOamTjdquUzPUw4Us+Y9ZTIr93MCeQ9r3pS2fbLQdedEZGBWnWIo+9YJwOPvAulpKF0+KW5q44VkPDEPwpCRqfsc1BODvCZHPb8AkWzHVYGLDW0arHUDQ7VTy9HMo0hWWwIFDTZjGpI6iRA3Sgx0QLw1A4zQTv19mZjnr5zD/mcz09adrACI3ZxgTYcTWQubM3/RoC73nteaF8kslrfHj3xUTkMSdMp2+ucd6o7gGggEErW/Sawuh5FghvMvfkl0pidTptX4CULIJuQfVK+DKqxorJBPEtM3P5K7iVnvTfbSvC5g6fIhOaYXgSSQuwLQWt+1GfHEhh1h+3ysesMBC9ItEDNQLRgz7Ljlk+ek664jwu0nl+cFLC+bO/Ie+WJq4LTTYjpZUFi0zfNVYTlHGy6I2rHsBBwOF5S+o5py+NJ5HwRAucqnBrbo2y7FGEOWYXsGsJaGdwFwp85hFX1hwNp5X0FldNoODmRtzSU+Ai+jzwF/08jiaFczEEBoyTPo7CSIuvOamsPwnj9JSSKFl1gncX6HmDNI2+jKXZKhMYvYYRkIrilZKGhuvLLkWvxCL6tip/oILO4KVqKmZnEvLPLgk3ycbQYkR/jsEUI5N7dmsou1BWt8lbGUEvoG/yXgWGvUnKMlSs+8wck4mPwGQ6HQ0MR33hwxsKmB7aN5OMcKzK4sCh6Gz2wlv4Hx2CcMAXuR/uNTv/BptOzJfk3yTXVwoJrIPNsF8fORQpbUCVj7Jiz/CioAe93MhuywJ23Eoy1vGME07GzKKXyJ2m8YUqsms2a7QTMxsV/HNY2yi15mZ6mv0tzJXs2qB9roKBAC0/A/3DbifhWX5+WDV+8wX4/u5T5BMbNZPpfxwaa3NBFK6LmiIasJTzAtvBw1okYoaCGWvDSmCZqo6GEAi7uUztyMkjQELo7NZ2jOV8TvJpNn4SBKn+FS6xxfM4/KOfCPE9JO8cMJv9NLUpqVS2q4iER8Ye4udtEBFpC5ED/17R+jQ+6v3hlSrtK2ZD4jbK42o/ACa+flBg/lgFSJMrxPAbu1+GAe7DyCwCc8qjuSr4PaF1omBZ686PPQ70Uvhga50xcrsPExTQevjj1Iqfz4lgERpgxC1Zq3+3L4Sr1rD6TDOQoKOPKwbYKJiVRymmRlH4IUEVgkdY2dNp2ZgUOYUDfRHC/hcG6HZdSWmEqVud18rL1g9wtoenqfAfJO2q6hwbI2/+1yx0qjhywM8GRayejJarVdTO5Cbbh0Fz56wjtk+Zl+FPSG7Ad2VdrAXF/0Yeu6/jCd2bcl0pS1maMZvcmNEdDSIzBvMNjn0vTSdO9pV7dU0RM9dGLrNaVo/JrwrpO/YGw/U5PQF6OZiWl+amTb6Pousfrh44Julr1MuJvqmFcWdvPbuACAhNX/QtH5QYHwCO+kz5uNktd7HWG6ASpHnVhMS0CGAhJEtNKfYUK/3nFKw2twXLLGzowDVG00WKcy0gkwcJ1Lt/z/KBNDQ5R3i7lKk+cm/p/apLGQTmoRtIXGuY5OLoDMdXAETeEKNHu79EMibwKG/uO4MEMBJO0xfJbSZDZH8twVPyGf5DCWOJ3HL9njfD/TJEJhUmLTlxIOKUDsr256zz8mOu/dsvqrvGYZ0lbhgpqM5U+sOeQ8qZVYfLgg8Alej2xtqmUIe8JfTETUfnmODn88xvKGuJYJz4obXqi/8/TGn7HiYpTP+zQyeDNBTfvN8CVxNXPjt0ECl3Z/WrPlinmf2+f34ZBa652i8lBDsD8ONBIxiB5WrmBLvyK/Wp+s0zqPIg0iP9PzR6yfJsOR/6HjBxh0XNGQ3ra0fRufmRbjS0psCw5ZjBAMGl1BGR6Rw1Ar8M0vbUCXUQvAxIdTqw5ZWMeHPs9FHl92xyD8tJtUf2KZ4myUlq4JuaaMkhoyZURRx4wiv7s2AArBFMuKihxViQrPgOv8fO8hCBjGTv+5pb1jWadNinlHJ4BgB/wjS8ps22K7dFmTGiKt4AP/UxY5869G1PXfQON72sigPuPKrDWneleAJQBe7NaUp7gFpu8gEtKZ4s27ZWs7x7O+oSHEZpjhTJtonnNSk2rb/IdOCQZ5ywKQA9pzmZUp9lIYxdPQBaLMle3i/f8QNX7qp8YPxAVwWWkZIEVk4ZyTaI/JnWy2UQBPi+XuapwLHbuHL0z5BgTdIA6fPzMQb8XFsr7GTDzwPNkIvDRnOjD6tT8fCFEnrSdeFHslWcQuFLa4KbEhzAE2UpQA8iqYyYzaYjUUYmpSgVPgPFNJ5shkKt9n9GzRBPaoW0TX/LS1ZbXTA8XjxTIQ8tXRF5vI9Ra1KI4+OsgCisS5GS/g1EOqeaXifp5BHy/iVK98oltcdQXALOcdrR0geotc9UqBqd5HXeGeQuj0z4OuXF8ER6FPudSirLwG/M/ruYddbcmihG6NtZpMVNjFMenUS/3xCdlow6qQ9ZAVsije3ZJu2NxHwHuxtBIhRK8bSiIlukvV8TEoRQHtRkDKunM8NxHm1iR5HZ2KQ9H+93u5ermwgpt0fWBmh4/QgErjeg2K6ZQSU3UZpA0HJXXiyGGTlJt+CJi8YTIxIykVxRcDujO9cwUKDSlozD7A2WLY0ySG1A1u/fKulJJKETz62HQyBT3rwP3G4418Pj9ODMTOqf3zadfrLElDqPl7PVnla80kZerlGuwu8Hpz/WMbj1IOwm3Wfgq9WnmgIgP3263O58SaTBl0iHa/NqKAcpdhBS95HWNbbvkeWsclsQhTJiU3dRQDJwD6uOeNdwYM+xkkFUdxOPuSIt3p08iVaAM67L0U0O+ovgVJrTjJXgRBgwM9PfVpDOSUQh/R6Z7hA21V4HPFizzOZXpCgD5gqQDXXanc458TN49zD0EZZL7S3pGpJoFic4kQEouIfXNTF7PjrzGxzNLD71U7BggJ42PvNx8GuZiKc6Dso2VrvEfz1RygkminepqF70ixs5jc8G/lwmSGPbqmQkPBUkC72feN6+gA47VJAjm2YvqLE+sQ+yTEeVJ/OWfBvL09b6lTS5OWcmojLuojNe2+/vJFjJDkEXQStWE3SF8U5VWHRWlbMYwxxtcw8ueugf/5GgCUmKCK+uN8l5sNifNfcXBtUcOQQhdJIoxTZFJtHb8N1dxG1yhaVxe22HPLUfZMN1U2iiupMqv4BayIWX7e0Yn6Z1MvpsIuNWNzZ3SPhGQpVUReak5o6brgC94ayrOGPpuO0Q0b7d6YdJ6QWWwPgCq/5Bt6RsE0JxlQkj5GBOpg/cvLlUbawPUh/z6aklZ/MdOjb9Ppg5BzltgY6JTmVmWQEGBo63rKxvuzIfka0e247MfLKaYOP2G+4Wl5yrtCLgEDcXhimO+0NZxAyCeDzn+aj0RvZxiqJXIsDwSbJ8EWw5Ht4oe1MI7N+cj/'}}

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
