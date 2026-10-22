#!/bin/bash
sequence=349
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
Q = {'sequence': 349, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e86f1c2865db500df8ff989381b12ad50fcf51c341bbebd796a9b018b8e5e7a9', 'ciphertext': 'MIISfQYJKoZIhvcNAQcDoIISbjCCEmoCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGAr7hmWNvvbZyljaE6k+cQrJzqxkZSyDdQWAUGW4zs9u0Sp9i8FH5KORhs/Z1XGAJ5svqy6zpD7/otHcBKmxliGa+xSCT7JQ9lvYcw6RyEpkLQiE8OUJx2ZRj/K0n8MMaRlclpXiadY9UULuAhemjxe4auvIPdRj6rOSldg+LxA9O6rdJNGS25aMm33P3Sxoa6v5QPzTmg3zaoVxb+jRxKViL3ntGDQwWpvRBOr5sa7cxVr7aEzgYINv0Cn3SOxxsgyaYARZZc5f7oPkFyEDeLIiBNWwY1M5GjDYLEfQogYSOc+tdqAV0nSHb48VDEG44qz2RfqJuETazeIyMAHSAtDOhXlmkkRTlt7oe+Ecg2QS/0sJ95m3s2T7wzEsAyOnw/j6SYOV8+4NKzkx3Mv1PLPwGbJ6ZBm6DFKplomIRoNfMW9lXvxF3vHkkli6bDu+L+7nYq9udvwWeeNC1VxQwEb/RXZB4Yp9S7oIfTG5i+taD0SuxOFstLN59QiW88ZyLaMIIQjgYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQRyLnGREsaxxx0mjbfsSAi4CCEGDa2Z852lgGXh8da56Gfzc6dWAqwOxMDeCl479KsTErG03FXPOWEaFf31ackJbQc7zOSG5fdSkGRea/Iq4sc8UZB1GmsSOV7p1RhTsMQvteSHodCyvAe70ImyHt+f7I1e4JdM9EwxcNsChCYrDaZRNMHQkfNAqM7aonZwrE5i1IMzjdlbKg3//TOPgrAyFQRt7euUVmtd/reV+ClM657xavn6TZ3TloGXE5OYyQ8cgpVUdu9ZkBgo7L61Bz14Ik3aNbwd2s9+m4PDCtPBWkEPTWRjXwWxEid34V4paeT9fk0Vz2KIjSGmROD5D6EkY+FxTC/LzqVMdcLBU9C5/pow9d3aO1ETea6yhY0j+1oIuPElASzZkkpdugvgqookrKrsuODDTGYdlSK4GZ/QUa9Pqbyqm8jM3kv2Fn6o7nq5f9AIq3HmczYJIMfokuEtiwPrUzefMs0Xx41hhBp00Zl2lco+4+iqAuvTJefsNM/0PrEh1jkQnofJtLiHaML9U23mYgGUtcwWoS/qEOU9xdDDwLwWu8v7xLBqpxhhYlUufNtoqd7Uo7wTUBfy3ybK6l/35FpWT+jIWWwj74OvfLIO+8JJ8FVFsPjDA/FwXOaI5VufXCCMgY6VZxIeuzAZKt2dr3txkg0YDnoav8ZFQxB8g0nvCf/lk06EHPWFoJ3sP/F5xHaiuylKmsFqRf9xhvjkrcbXIZZcLlKcKbEFKAzbFNuP4CbyabpXLNBN8duEKsUcOD5RAWSkp8Q+qxZbCTUAWz3dgnf16XS+RcsirH8c0/pxAwj3ItOXU8gx8vKckfLLsxxSI3U5G1AsvoRc0Mir2E1QHKEJh+hLI6UBNn9ggXYM24dlDJL6GLZwLE1qkPK+VRLGHRISWJKTI6qt/tje3C98bX0s56TxSM61Bwi3iAafdaujaw2uRI2k9a1RnllI4Ol1elgl6EnZWuPvHYTcRcs3Ex7miAc2/crbX4MYS6YK450fcuY/UT6RQNsMLkWqqj+6QP7IJASsPjLu2Ijw2sUduWuh6U5CAC824rbDpu4jgAGNCQYUDLFcycPM1oautRFXrIYLuECXQryFVmFvTcJCbPeHXjLJKKgvFsLYHb/XlFrY8a2VkoXvmjntMBMBA6EnJoXyL9sAy/BF7CGRMa8D4ZNtu0jvlALq1bfSwb2wwcre+5+ry9rTBVutS+THLMqEDjjnCBJ6nwWMWn7sthRzBO43DaVumbKhwu8elXrv3cn9DL8YNToVEAJuEkAKOpdBOxmiZUiKF3uaqg4bL48gg29XZ8f6IIoWaZZ+Lre1Qfp/EwygVcJi6QuoyOPJET1HhKhizxdE2qtQu3H3I8QKkUNQQrPl1YstYTdSiBV694EZqjzQYE3oYlVhsmn0rHiY1BYWATCDIh/YHj786Jan1+KZXNNCbDdU1muQwRL4+o7HE9oAwYf8tDmI2jKcxnVD4a386nD33BIbIq5q/JPnOhMnS2zvWcuVDM70o36+/BJBa/XZu6Ijc3oI9CxjEhTUs0C4C71jxWtz1MvZuKqlPePDOYdYDk5EL/FNqzweWpidCzTNSRQ0x9sUhtUK7ejS80tBqVi0A+p3GZeggm2Dwj16YjD9at6DJ4f5W4Jh4Q7nj8+yXwxI6IDZV/66WDRUcmU2sz6bBNwvvTDCmxgt//l78Dm5zJ2m4PHRGfxPZ5jUQWJqqrk3MEqk9WHzGpFCaH45Ssk/M+3z00tLz6Qm8QfWL15uYMVDATO90SFGdKGomkOWBQRguQveSXDHgun0Dfti5ilP+6K0O3Tc33/uIpN3VAyDpls6c60Wx3sJZzJg8vCBeGOvKpKr2rCn6rncupK46/eKOs2HR4FSlv1+yEX1NC76CEY+lX2h9M7Y60cBkjsRLAvXJBlKM3W76M7ayOh0dM/CiR6PDQ0JU10CIpXsQK4/4TiW2AzDM5Zj+5VfF17FQ40OvQJn3mCU1065azV1JGOrfCOe+Ow0lkyhvPtH+vMW9etf71bAQ25zKEtMYKZDgKacrNhIKHQKHIaGyG5sA4/4/Kry61Dm6ZQx+Dt19lZxnFNt57eFTCIR7ngcsKDRPDuoHA2gswgDmpwyuY+2TL9m5tDHknPtxr1THQsfLsk6o9OpMxcFSVHpG8VHJozRx5pXFAoFMqs59nMSrJVNhJCTIosRf8CAPuo5pBN6ng/os4mZDpa6qAIhCuTwTFL9rUFtQ9jW9U93LVo42phFlkYSe5epyW2EKhrIiRdVsx26gBBqL9qGrRXzFWFBk72BnFp5FUj2wg+foIsPoAUaBrLvGE4Tg6Schz31tT3glO4MgtENKpYqFbvll3rG+UHh6LkS3nIpDlA3k+wWjphRDkeWR1crYlpFltqGnilNgytrvBk7cCfuea6cyUXLskvoAYKvhPA7k3mcBc3u9xD2w4qVZE9xURGJuJyn1D8GcWDEn0pX+t9yc6BJvGN8YS91jrsZop3MEy9YbrIZmy5Z0uej36QEq/PFc/tBLMauuTsPQLp7e1MjS5WNu/SjO8mh9yB7AkiRPowxR0pZ1jG55EjvgGOIAXv8okbqzjsONZIQih/X2a412VF1n8tvVlwP1x3xz2u0OqMBUlyA7IWYDPdI7i4IZpWwQ1Jy90gBqJVzHl0KlSSeyBk0vIh2O9edLm5ZH/fXXChe0Minr400RFWCWSeYXaWqUROdZz44K9v+4a2ckHyo58PcNKvO4e9xMi6Y+sUoHn9Hty0CZaIJz7IW0XEb1pTy5AI0ZIXycOrZzz7aT8KMKwwH1tmzUIsAmFnYTu3rFIc5CtKxK2P3qbsrKu+4XDbLbIq+8zKcR3/LT+ML2Cao7mPTYBlcQQgT9MxNYHtkXbCcm+TTCsMerOVz2bfIaDAqz5GylogLmI7g2wgJGs2xtxJipKQq8ucW8KzpcKlLTeej5VO0vayMh7Q2xA+HVx172nUviw0ZMoRUcBmPY/gZ1AzYRfTJ9r1iDOyp7oay8GZ0R/hhpfa9pdu7/MdJY/PqT1WHQzYi4G/bW5vIIu0cmOpGlxAa+KRcfku5nGvOUZrmWa3n+Ce7A5yccs2d/LvVFAOlTZN30RZ+4dIfK9AOytP2aIo5duFHUBLlRjApaH2THJkxCKUs4TKS9hgrgj6Jo/cdGxTHjJHEHJJhbviX9T1bAurAcLFk/mxuGcC2coqpEA7mRbqANlRKtu+ULGmCUAF6dlTnam/fmPk67PbQePLiirUzxJh1Dq2lGx5aXGnxuCGqyPmRATzTsneTjRxDW7/uPVhSzS5XIYWMcyXHGrT6ViN6naQ3L3dBAxSQG2ifYQ3m808jjCCf38PfGWidGopQi3W8ojhn941IS+DcphoVUZTAj2ZPivdLwjQNQjhB0Lf93dcBwApjH0HkBfKmkYVTdIhyEIwde17jNnmjxDDwGO8YWqpbSonfo9yrKMRtg/K/LKLPRIi7+L+C7nsOhG2mP4hnE2hfqN07SSaQY79YocxGHe9Y29e+4ceX2nZXi+w5C2I/uM0sT2jgUul6JgYQGu9fkIiI7glvW+HFgOc9pla5jotl4V0HOHW5KYxAlZajL6XxWki8LxQtiHKSGCi5wSPWy+KbroBviw00sNCC+81XWI2gJ2SvJPQi7pr6Se3zmI2r0LGEhcZbP8x+Af8/J6EB0JnOnFucaPU/RtMDmV+3WXiaLTZVfkpB+DDhEQ5/hkZuzVjv9Q8O2m7Cpp8EN3seWkkT70NLkrcu8bKEvo0nGFiWpMp8i+8dJ1xTiOAiF1lRs3tzOpk+A4rRd0NHq0NeTaeeYdGzh89nk6WovcSaCXxzlLDov3rVoXsrN6gQv+DIhx1A7cSgUAOoDikjSmTGetzWcRmTmFfoFU3TChdbb+wVy+Xro+DuskWctNZdIwETtYwePRnE1RPgkagCeWzidQHbRBhPjQFLcBpaPLnbjPIHTdovmZUEWagtkugfpx8NqgH0XIu6fU+s9IdwYqwuqLDzndxVy5rCjU68e/xkYpxd13YQOafDmU4dhgGkA77+iUhchoiSu8Jnlv7Nq4CO78k4AcHISjvlLK7nopIrDUufA9kyH5JvxOlIgivcbq7AknIfcWj+73B+DK6QA7QXN8OgO5kibe5e61Y1j/fvkKaKZ8BB6lpQ+TC2YBCi7MgN5lFHKTWsM5netk3hU/9aYY/Lj4GCK+t3PljkvMCiKMImeOHR4iTH7KUEbMajzNQcNBiPV+pbBnlexDN94q3+L8T2tWa9TSMBAqwR4zoRcW4dxcTZafgp7IMNyBoY99uT0wWqgJuX+0xBCo3p8w4GXlKyC/t78HFB7b2SIGKMS9aaIPI+6XA2aUG/O5xYDLd18415zZtd/Nydxs1/Sl5SSGX8pYm7+ffhaVXCIpQavqtl3ycsnfbEYM4zko5X67r6WCtnvIXOWNhq2ku4RUs9+B7Ym1lPsnSFGKopM+90QDHq3W68wUxfs71AnDQnGp6nvrum0z86J5EDnsX3+Zp4hT4YgJUu6C3po5LM+RaT/slzGkAOZl01vNmSweWeUESLBHNIAKMOcRRgg8UlRZSnSKIgd1Qb8/3BahlHGfGqWVxV/8EpXe0pb5zdJCyyBempC6w7YN5Uoltawml8DSTfHzNwKfn014HzGY0gaSlyw9Lr9pUqtx6p6O46UeyJ9aHgSOh7kfzprJsnebNb0mXYY/dT4uwNxVBUVEYMRAPfFrGc9KxH9Yd/vIg5N+CumiOMrxmZyvlBGv2w87y7GZSZBsjws7BY38PUVRQRlsUpV+Hs+jDvce4wgH5UxEEjEp+eqCENZ6YWWGB/phgJIjTxB6oiEUZo8saR8FPPlvE/drTw6E9kcePFLqtnniXVtXKZeaxcdBhMY1Xvq23KZ+XWPRtl7Q3KN1MVVL7yPYE+LIVKq8yQJRbO1Q8JpsAUy0pCTsljc+uh9A1ZbhESRnmtTscc1V8Gt4YnyVCbXMSOFbpMSWlHdfbuOIbmnOEG6t8o99jD7i6eks1KmGSxAfGDxOEogd/Evuwizqpr7NNaQs9aBfKDA1J++KxQFdQ0G0FBn+ap2UBoSiCBnA91MNNCyQVWW8saS8fruUKhPkqsOr4pKNcIpboRzKwMQHD4rj9eoLMUh/VZmEV9Y3NuqrKQvwT476D8kR7OUWoS0tO18PRapUZdCB5yJ4vmRr6MSWUQ2I3uGaJV0OleH1zQ/mz2PNgxf1jYr/Uvqq+fex82qiPeGR+BvniXkwzj45/DVgAR/IuGTKfU4kQMIYfYQsKhuPGUbvv/fpcxI27e763xrfqt683yG5QEeUjwCyxovTITxCyKwU7vAeycHsSy5Pjx5l7OHDPxkdG5iy5wGGWyhOp00+ImkOlx1S8x+REbh8Ij1FFxfj5lo7ltA3wpjyjZvqErJBg4pHR0RKwMhcDdDiufW55M2R9j+SEOzaA+FZ02Pe1z9Ib2lLmWZCdXIlA2EDSIcTslGd9h9kh9g0vfU4Wgc6bJfzz9Xtmhanb1oOIVDLy1MyeGbbuZsdSobBQAfdX7JrDVM+FXF8+BbC9y1LvV8YWlY7vbVY6jIY28q5tY/jIba7MjF2ouawVO0HLc+CfObK3dTvBn4r'}}

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
