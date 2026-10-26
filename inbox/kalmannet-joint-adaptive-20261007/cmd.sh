#!/bin/bash
sequence=388
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
Q = {'sequence': 388, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': 'MIIUfQYJKoZIhvcNAQcDoIIUbjCCFGoCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGAWfUdBauAJqAc81+GdqqbWup281JnmdtsJV/3u6ZhwXKSGx62i6q6Vmsx61YkGJ55EhMO2+bRPXjMhm3BJ1d4SpIXw80eikK42uk9hpf+HKJYZ48wlAE0JuPjwTJE7r3kpEGFUAGYCUbHZ/PWNbjGF74hfT2ZeZLiCw63upCGkoQQP1wWxtsapQVMLwqksUuLKvEWQROxTtzgiyssGUS6wvGjNv0j1HxXiw7Nlme2ZXucVVAl+CmvodgRlJpCMSDj7No3p9t0jjCVeOa+2AC1IxYsJwjZCs1AZt563Mjco2s0nZYhWkiws7BIQ0Yj7aZ9sgomWEiziI4dmvSBoMXuiMBs0MW62En5ABNSkmoLfwiofzU4HC6Pc9J2e8OEzOhZpP9bRn0Pu8Qb8t3TbX/zY7+znzqGKAFcIywEd+1E8ZVLDGrHf8JTMnDViwR1lqgeRAAhRSCBeOrX1Pxtl+9myLpK++oW9CnFhuFUGmWkhHxswZTzWYLavP/L8APIEtrZMIISjgYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQ8KsCFGzIkmvcN3IXaKh4iICCEmCW6AQGahGQbJyMM798G1thzna5fCmEUx4cjHwPp8z/bKbDA8q786p8xHNFJqpzq/teP5R+ezWUIE4HE3hR64hWrTzRxSFR1ORn/zOFgyL7DadBUjJqpTnpwKhzGiSXV/lwQmvDEZaSRe+1wd1Yditmw3xD80CHbf/rsOKPDmE95wf1sQz2p3XopCdUpFwGtHjIBPUTkkF1EQv7zf1INL+VDAupUFplaDZkFYfpK7WRQWEIQXgiKdfMllhL39nkX6ZqjCjjUQGcZb3f6uNOnraSDZi5NlKbtbAuawBL+fZmFn3ukr0VXGN1QCrID9MunKQq9IsWorA5thJCHbZo8JtcMBFW7j9GGEDtquKYOCvQ2Ky32L60BycdwiZS94CE7yCb2BeaHQ0AVJXOfhAAg6u7a0WNBCYOwD+4MF0+4wR3JSwVz7YgciptLwtGh1Iz0P3T2yEYoHt36zL8Ib0Pfu1YNT7F/J6+CSipWGY8H43Ztwa5eYel50+mKWSgpDoNmeG7xMIJYO/ha42uNi98BA2+6iaaRQKtUfHH/1D2vqlVI2ZFPj5WhpAkv3i15A1uWYs4Lby0ISK7ugfUxBX4tHXVJa4Dz+KhlJ2EQxboLIvoS6gZ6xBhEW1hzfnlrMGFI0K3xT9KNybrZ42G6uRD356wrM7Y4Sn0XhLVKXwwvCQx4QgVd8vvmZjOKjts++IfvDUMR16Zad5X8hHu8n3eek9i8HnMUcc9VZdC3e5lBAIDgCnIr6jwxI+UohKhxH6CENPZ/eR1qrQYs1iS8CetqDqB0jL7oaxYmAa6mJAI2+IT3Y7arPjKcFv7UOnR+0pQUdIELhAeGCh5kzRiswZ+skHIu1FHPzLkAsrJGx40/cR9Y5W9gjEF7X3HGWalkOn7YF1Cyu30N9nXb2IcD09Ld4pefHOHRcQWRyPQ1xn2Vcfb250jW8RwuDjpO/lJS8nkZkdTGkmYp7DEIEQnrezWjqtOmDHC93vm4H7nCl/LYA+pnTaNE5BOxlKy5s4T4bbcPyhVhmsO6eyX16xgdlXsRiBmS+8TwVxz7y6w3cXjT5JpgtCQ1cqcNrGIj9spGAnv1aYrekkMVD2nxfDupxc82YNMbPAntsRW2W6eH1hHKGITJ/uWOVyt78XPaoteTce07DSdnSVxuj2ZZfvgyAv5CyupRvtwjrbuI72tfmQCNvnHJEtMWxVQSU4IZ12qDvxt+yvYLfd9cIR8JgRjCDn7kTMjK+F8McjXXJxVEEda8ENvScmjte50aXhpiGqBmRpy8VwrU3kN12j/ZDRYnYdbY+xKqolSTV7AAqFi9OrZgHzNTJrhsi6j4slTleMEOjWIidNDWKolp6zL5XetJp5/iW20YjCulQWGqge2jGUuljuHGSpiLBMJr/thXsWGBUp7BcbrzMV50xMBe7EdPHJreOmL7+xoPFd+kY7dcayJKvQamRMp72yhzaJYCKccw9VudnNvZIX2iqsQ5QNM+jGkeoWHFua41bua67zc0neFgFOjwN5yL36+Kt60OCnUl77eQ+60HXW3xtMM8aDrTmcjzZCDmsQ8wcBD26tI0MWWdvjSuBdojITaA8RQ8NlgvQ6eY9Hh4y0KeM25gxLBtMgDloNgiY5VXb+iPHMv0Rs4lvLW4rb4fX3NybWwtLhBgCuVzWRULAhr/H642Vqv3raRjyotuti5MaeRfHJcBDslE6t0utdL0RUuVFbgRh0Ls3td8HRpwfuAMQs5bx5eXvlGOk+5wbqVuWdXObuvD/YsFjtMeX0U3bLEwpNG99tydThY3OsMnI9fhQk1osiXGAJkGtIP2WgF1bIRqJRXj82/jFBxn+QW71gIclnG0ApAgP7XTzNvqiri+9BxYM1s+x1buLMbpxNaGQ0L7oRVTZP4wxEorFgLRl9uvQsTsVV9G9vEw8i1pfVB9MFbcZ7eskODyArrpx22ZX0a4E35Gnx80EcjWOmjHpFdPLWGXstoJ5YVau/c1NdrPouzvy10wGUvP9UfLj//WMvHP9inmzPS2hWG+1BJiPa7MtdSGHr419uxqrfSpfVRqiLoqfArmDg3qBVhkVGkhE/4p1WNJkg1AbM1EZNRxTansKvBILsOvReZlzyJpaINYw9+QIje1P1mkBHf5NonF3Wzrw5s5S/uMO/f6SO2Zt6zWGLdSBqIoNvGG82S8bRnrY6GmPjZwSJ0LmNlSTqvvPqC4K/fRZtc+H/1xkldl/kAqJFY+TTcte4DIALdxF0fYauqTjCKeVZKizlWfdEueO0Rm7tdeWN9NLAJI7OJpvMZ5BOoEVEl7r1iIpJAg2/RHT9PJu0ur9NUTHNNW2OIxCrNdtm8zRjs2K6MNUxLwx5UIfoiHVyebdkGZcGtV+2Lz/RADcXZAow7Xmj2MIfCkNlVhGy2DqWFgqE2KAOBjRET7DmCPMEdkogWpzHYTqlaoNesgDNlqp9d3//FvbCc9uiLygiO9g+eyBqz6AzCs/YSbH7tfLEAOPSrj9aDzgFFynlZUSSA37tB7I2cLXISVMwdx0Dm3BjQfOPbX5NRXdQw+FECm56K1WTWoXAM4MVIgmyC4WjGnW2G2HPqSfDUjoxQ3CK7xl+8NwSj8opi6hiSmr//UJFkXYbjsF0G1dgyMXAljE3sR3KYr13YUxSdFaYRJX2WuD4T0CXEY5YgdDVHQjkAJlUbpobBUFJHWRJRG5oNO98H9xRVbYVrp9lsln5gNIbovwMCUFnDQWgQ/fk/PiWfRCGEgSgbgIqW2YjToVVMI2uLn/laKd7fEsuATQRhrCInj+uOg5jPXpcGjssrOzJUUsyavaTaoU8TvhJY5V6ISGtHV89dUIEIr/jnlC/f//FXmU8pvkr8YbOYjHXEG6bOMQtwJVp25uZKshoHOwh0Qalm4LPi/WL0/Dvr71ylkaxg2GLSi+K0F4GCEr74jeN+ZoUlTICdcyy3YX0NNieELM1t8+EFagL0vuezQ93qU6XoLb02bWM50qsODounWoNZCUhhYM6QxxbbYIiMIjP0FsptkShMj4KsHRQSVv/8N+IlRcSpHFE/NbyZz2IdaiEfxGXAbxrotxp4GIc6r39yjyIwhQiPXr8ucMsMGoWLjk7TAyetWqfiQGZNaDdOlGlQZFAYiL2rhqy4CoPvC5Bvd5BASBlQRMselFL6SL9tTjd4ZRoA4U/t8IpLxdpPv2emJTrKygKwj3lZ5ftGGFNKH5VDOlN3xCBbAROjyOngTBxpwIp0gTmyZan97jYKCsO5/PELF35/EXL8S5mpgifqdZT28/D5xBdDXQfAFi6lh5DbLaBedPMdDQguK84aksKmtdpGT4X9bgR+ZrwRDt6qgCKT6B6HQKAuvww/reqk5M0f5/QZDTTn8g/ECm0NGEpKPFfd9vywIu1ZowJmUMaqXHCxsgwi8nD7rrPAdq/iZJAiMP+DMTnPjtI+zj6my2wLi7IO3/jgAA2tR2SGRjxj3uxe8JP/fYG4OeXVKjqRMUELbfi8FKRbJihLJRxn8TR/QfyVM/s+3k6/KGGsYvrP2m1va/PrhgVnOVP3RdCzPu9LJ+n2EGSOg5oQqkq5pNAYzwWtqHpSxhxJSkGUYHqETCgHB2nJRASUOaggDghDw2NC33gWK5AyN01kZEBxzdd3eh1OfQgWzuJiDMDsi2MqvzlV2PIhGyBsitfsVJKsP95xqPeCrkcUs9OiWayIRCsl3he6I92RPoLAjSowzm0W3z4SEGZcpVM17ZUsoo3323A/e4YBG2TVUlkoOt2KWPk7fiwp/P3BmBj4GDajPgz/nitNrE7YMuc78aDh5b82+HxeIJRjpWoP0uKn7JNvGPZZVXdh1n17GgEtvOX5ifMQqVYogcay1zJgfEMmZsDUE8KMn39NPteoJwhVhJMF6B9wSesll3gS8bLeZSJvQMALNGnRXjG6y6nTUJUd9NR9PzO1qnVGMPQqkD0LkYcBMQHqLMgPE+Z5DUgH7cRNvRPhJ0tktVIzLtOG/JfGxGX55M+V1I4UkPjN4oTGhOvtylwerxUqfna5s9dMVDHjJVjfV3MmbBCipEWtrme6JTNHHKilZOtNoN4apKafgUIN11Y/q4sTLkr6szeK7cCapA3fOzRyw+BPq5iSOwwrcvWk4wtAk51UaGA6yHIhnPqCtiI0K3iRIk00f3YiYmWnTLxqMG5FcKVYMfOY7yf4X0ZdGBZrQFSAHtToGjt4SCcnyFY8S0J9/GC0OAEFUpqLWzoDTNz3Hkr0MLHyWErfk52JjhBLxe/pUP7pIrcsb1TVjB8MHuIMbMehVC0DFTrSxYCC2mBwFBGMDcwFLCw0sQGWqWKqjDkqUuzX92J3KhG2tOEbVfVESQUrIedDqlfCtFiR/a0kTOsIcLcQi4r6kIzvDlVOcAk92le23hJTRiC84YUTjIWDiPBCoqZKuuKTFTAKQVemHd6/wEIn8npCrZVjDEur6ovaNB0O0Al24mNWIZNej1XyoiSR7EukyXzmeXKy6QWQ85660kshldR1WtP5eVRIjg9lXGrJ1xZIDO8ZY5x+0UyfjfUig1IjX0lT9gfA5PZHLXnKZ6KShVH1+OVHkRuFUuyn9ZDMPJGI+EFuIJ/1IPZ1P0Xka8TN6rS/byrqRsSsByhTJvdRwAH2NZiGV8x7IemCtmVWI5dbkpU/iCVXpwW6XUJlYmAS8bVA/HFgNXyfJPIW6bMfgP3I4p0L/XSXf+iFPK/yGwJTH61fJbSxzU9EWLKzo0sRLbXNwYeELSgTnOgRCqiv06aaWRpvr3bmmpbjIPikIttcYKEmnurQguOCqfbY8CTDxFgKPvAllV1wtjXYazLK07M6f840DYb0MdIkx7+21LJdMe2mbLZbvgUFEcb++jrrMkzXT0gyJH82KbT5AM0ce2R+HCyb9gK+whsNhLAqvcjzQfnPyF+43InNZWJMECJcSYJ1ui8dFD3ekGzQp7okfjedicrdMqHM0ffF5ckD7icbtQPFrjXus9K33G7/uBNQFB8kXE6QyW1r+IGgvhCA+VzdsTJI1BLuJWCH0miLhlRO2ueJAklP/eUr7VT4jCT1Q6zIlso3GFiHf3L2tyshyxIfHQV+8s4AtKiZ9HMQaH452buES/noQh3JrTNtkx0XmJ2Obf0Zl44W2gBAuUMi3C5FAlLXD/pf28hPMn2a4qdEks5TvkSBdptPeFR4wXhE03nlwRe26Hgc9askN68AU4nCxX+XTjiIvVr/yEVzZy+RZBvEn5U/JGt2/ZjH3Wyccu5G1KgZUqYsEqEguRWfrNN/iMY2RD2mXpnMZdsE5C41mDfm7O/mpigiBHqmDpAqmvolzRgajbdYjarogSQxe6yIsjT0H/9nthjb/8i6cm7l7+/mHLBbEwTeppCHTUjjWFzhNFHMWr56+A60vWHKTnJIvKy55ZjPkZunweGt7mYD4qligSmyo3bH+zk9UUj75WSlZTVmLp/V8m86AdP8Eqm0uOGjkxxdAi1cDaCAH959X7DKvyCWvAOjji3iIP37H28XzdaqR6QQ+hTVQPbOo6GcmwrRLkGi9WB0R6y/tFb9KkzXpXC4fESmqDMaxKZI7cA/g+36WHHJqBZHwW/JSKME0BOqdmvh4iHIiHqm2YoR8Jp7MhRruGJp7sAU4/igYh1U+yphzZpwsi4QrJR90KhAVR6BwY+Fnf+8bwYXvGeB7so0gHsGpTaCFQwLoziESzXPRvEvYivRgfpvoYJZcmupv665M9tF7PvPoqPXSxee4mtg5DLzMgPpmUajHtv6jHkgttyfPqQpfRKWQ7PefT74GLVLB5HiJmwVqqOt9Ms/eYHDz4cMTqiYYJvehJjkcfQMetaAQPYxxKteLegAgwZi06RHj6YBYr3uuAZkKxQ8x2RKf+RJ6wEI9Jn/9hN4sJc6Z38dX/S9lWXPPgMrXET0guNjAY/B25Rf7RyvJhMvFnElHvp9oCRuBMnHBRYBdqJyGux4mYeqhrkI+L3HyBRfSpHrBrNNwF/oymX6ua+gVtDhZkSgLSi0LIszkgwdGIYsHH0SMSSMt9M30eCdErJNCe9HzAeG5nPXKtaHQ8MsEl63QcL2yxkbEjFjYa1eW3rOrMv1TayP3DvdEAfWjq+2/dj6DnTFaiLT4jxsG5YiQtJLpmPhl7ZgxXcNbGw6yoGin6u7jGwTUJ5x1PwYvDyory3hwwxzaslrWHZ2zDilFfisE1H4jzremD29KeujUh6Ouy+iLGD1CcbHxKHC5xnJD1fn9QHhzQRmLA+yGJwl+hL+OknHa8D52SPAMtk='}}

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
