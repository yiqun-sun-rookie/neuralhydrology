#!/bin/bash
sequence=205
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
Q = {'sequence': 205, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'f0125a57da585196c6091f0b7f293436561378046166b9cbe5676308200e6b80', 'ciphertext': 'MIIQvQYJKoZIhvcNAQcDoIIQrjCCEKoCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGAtmSLOFCCxPjD07XbYSePnLvuPw5QU9Dqc1k59bW08f8LXdwBxHW2Z3VNktRgG4zt+VjdSH4nSPVhIzWDTVlBk4MWVT02FjTsQfbNi3TbipKj9k3wJR7nenxhqAMQz8Wk+HVdiYB0MAdGW4A24al7t8P6T52BeYhZmyMvk0QoctAPBVrpgc6igD6e6hQTpeq+odkxrjjWsCM+36K2Yj4PQuek8Y/Zatqo4cIDgu+NyVjvuOXIXMjk3XvAd2QZlXZOclRIfgqPJ5/uRCR2JCSrCCg56oQebJrqOelQyW2SAEmBPZVCeMjZ2ut0FmHVvMA6+BnHyO32y0CWR58VBq141276iHx3Xql4kdj0vQLFwRMn5Oeb1P250q3MqoEH48tnCYe+BwXs7Zoir/hVgQRhSGej1hhrTfODd0tqnQDFdxyIuPPLJApy18G6SHfXFLMtbMlmFAvzfRwQpoZxs5vqeKdRNSU7D7ayRsj1aexlEb2Odr8e1RPJwoUyzMc/L+SqMIIOzgYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQ1kLpX+nrJTr5bLZDRh1J2YCCDqA96JLsQTmwfr3Xy8JbRUToDTKHFEh8eZm2NiYIROzkNWmUt0IZlwEQWWv2xOF1cFICYzE2NwANTIFkoNt9OGUYGLUig5WkqAIGgCkDcmHpT9ZiRpsiWCLnF5HrsSGBVZdg0o19yjSQK2PWoCrHsnK2wbthPeG52my9g99TrPKwHmrR99TFaQoACrw0WzHfxGcLURN5w2nH3S4xownNglDp7dtROqB8W4W6iiCLWsjRyrY+GGU8fRaaAvATr3Z40lNSqvLuUEqG6XQ/AcWeWspV5FJsv57bJ9RdTHlfmc0wQ4BmbKSo0LVHu2OUQVX4ZAqeQJA3Lw3momGArau5vOXRXRieI2mR8m7QI/UYmxxq76yNUX6M2suSHaXwo52lsZ8/bAReN5cvNpWTano75nLjmHe1+vj923zHUI71y1cPbtHljPN0K4QC6TaSBwEOEAP1uqixGsi3dUQz07FNVR40h8GV6heBd9ja84IugMOdjsaYHypf0YvKm6Y1RXI4fpeCOBdkxPXVV+3aH9yuwK31ZnGiKzBM2ZfpOJohV8kP4ZKZuj9AGsUJ37vPaDGPyL0Im/M2JEt7h9Ezdxs65KrnOkog2+HCAXjgb53BD9ZCDpmWVpukRWDjAwUeZK6qN3gsZZz3fpmA9fgti7jHNSrKxwcmjmzu21lm2WPEh2xifdl8DB+ID00ZJGXvNafhGseVV9NU0b5IiU/7CIEsK8WMFMX638q397QhLGf6ZVMz+z58M1NcwgF4VDR3nHOab0Nl/nKiVEPCqUm6tiwGKLLcofzO5XHUlVJ+/9l+1WKhfxeNO03B4X5xrf/zZtum0rokJNSnbqa8Z/HN5YDP5Mh7OnwLe1Nf9W3gIn/MTTngp36zoHNOyB0Wmjo213L3F/6pdGpFW0JjZIYTeIm2q2uF0Odf/coHfB+gayLuD1UUmKrbzpimAeUjj3qViMHLfn4/79fBptolpnL4ZCFERrwOdppQGL06K7EcKwb1/B9JRsDeTgkz6F0afY5a1l56F3HbtT+DA4bSFr3b9dbOD76FpLvtBUUnbpIMHl8pBzGDQiQfaIlsCqtmZkuVuqB6nVAAG1WSA9FyC+MjIKV/uNYX4THs1PXlgxa3UF3xL2MjzUXa2/szDsa+3b1RzRliZ1EbU1Ufq51A/A7mYxrPuL8WL05yI6xqpY2ly8RvDfqhUFbynO8SBs/1TDsHkiivC+xS16JT1iPET1uQolL5Z/YU0DA/zdOqeiwf64OWwCB+WEs3HutX6xTyjKvIyzfieWc5ngTKP9bTGktltgLREHog67v+NS+KoMLspYpNycwoxPh5o+CKMy6eS0ed5Gdx2Drb147h/P3alZk/KLNlk3aQqmFLfSpjcE2xdxpVWYriwRT9kHUvGCSwQKdp1gZ2crLKf8hdmT/Pd8Lt+ZPDfe7GaQBwjTV1EbLljBop8u1xyeDUzunCIjn/dEhPjMLzY6vL+qgUeXvCQNZVPzGCed2KeYug6zyRnHz3MpLBSy6WRA9b+USEaFx7skC5BGSQ0G1UNlE8DDEk5LCUbODaKXgtvIV+eYqe1T6Wy7C2MpJxws28g1RLksGhKr1+2PvQckyAD/erjbbDNZrmEZuzQ9h3cBOQvgq9yWObEsL+LTsb1It7EUTNqJ6WK4HFZHDZRIQ0eXAttP99Hvb64FVm0z3pkdjZjQ1tTwA/e/UVSzIahG3TXwZn6sfQjcwP7Ao/xIjSPWHZ4fmqKehYG4gd+jQuqcJ07ALZSzuAUWcS2HBBAe29UzYohJpZg8E+hbXvchulU370hAhWN6uq3oCNIbmkNYXVzYhDEIGGcwYbF0PGFiUO3Mh0q5pDasVQfNzNPNqbqvnMinlNEi3LCHQC8oTz9rPfDr73B1WXvMiC5Cx0He34yqTMtXACfqRSnsH3ohVrF1QBtX243cRHkhEOHS2fZppgXjLt06jJU442o717fUVx1J32+NnHpWT8InSKUpPw9lOkKJKan3SQeI7X/V4HYnguIE3tx4faGgbSy05ZmWfsjdcfKDF2LW+T+Hik1kac+uEEhmKTpN33Y+wu+B1+UCRK1ybjla7ciPqc0iKYunZ8mz+T1Q4aMob1978P3V84Ij1dwsXXIerVXIyYTm028CScUZiis7xHEQkUrxpXYqckt3xZOyYDiL0qAnJjPN3xBxhCaH1uJ6XYHhYqkoC+cn1STC8sa/cB//3mHbYTQfku/HhfN7kk6fla9IFgcRCAl8bGfzQMqW17vKF1RMiU98D/kzmutN4Sl9UHhkRoEt2ZN/tgbhOgRa7V4eMV18MggrzFdb2GhoeH+8/G4Z/b+y8BFUfbl6EvtkZvoLdUPad7WIbq+Uu3F3SP2gFx6DiXZE5THgjrDTzuaU4b8Rsp+Wbpb0CS6msiR1q6nkT9DpYOTkobSGnunZEldQ+w38lxFvVYvT1mIb4JiizX9F7SqxDgcGRAgahv8ixUQJWQbDxESdTL9PGeFVYbQlE+pGZC+J3j6rNzu5I0oPdVVUZlE29i8v5cr7ab+O+vsN9am50ukPbvmjaEHapi0pR4MEwUiXazRlEqGb5yUBtJaZCYD4P8g3voe+I0AFrnGZe/u6EHFjmx1ei+BUPx/Idaoh7Fn3lRw4zaQ0N8VMPzePHVwj7sinGr2TKDa7bn7V8wxRKT77j+/GlBtEuE1LNCgSw9+3sYFFaz+zPQ/qTzcJCnxmnjE3EW5zoH2bOIzLYGUZxPHKV8NmUXhd1ZqaSRFOn6TDgXQKPFMlkgV6E6Lm5q6rUCZkMnukvkf42XUxt6PcAKVibput4szss6wVwydaFg0g+cfLejaKIIrFVBXyG1nyFXXe7zXBGfQ8hVMPzZsjgFzaJSGf43TVcVDu1w/j08b4yd3825COGGYeK3iaahjlW0CxekoXgiAIj+lbwakvtJOllPkxh1uiXXzMrDebLyMK+1ZLsg9hjENxs5KykMQH1lUzaDvobAhCNFy9VBBFqwVgEQ/hhPrJXICSy+Bf28OYnJkTs7zE56qXCx96yJW7XfIK0XBEVXmTIADYP4sRaImsv4MthOd7JG4FQzDLptUQfJocDJWAoCn7tAgIjNiuGgpGCU+cJu8FytXTo3/pMooTrZ2C3TYgGAqGTScGMMtKlAjFz8JlpmpqKdpPb7R76uSaso8NPW3rA+gnBtm7AR0GbPJYcCe+7ixlgp5YIt1WdohK4vOE11dEepg1UDgUF6RXKiVsjJ/TuZMC/lhSBRBrXy2wuf5+tKWGaztDTbkQtMspREXG+jj48wynBtaMThTU7ulkEIrSwK6sfg1AkixL3K5P8AQ2XMZLDU+toRg+iD7pz/frQiJO1Emjy+PDh2YWRpaf/pcwPD48f+fo5Bw+4ILuDOdWz9ABwqcoDRYwVvOJorJexjBLq3NhVVV1aqqv/uG2NLPk4W/r1ka4SM9KooHtfbRT0RnhSWczy6FuCd+44V5haezwlfRju+2bsNKZB6kNmBCbdYT0jaQzzHoaNsXmvwhycPv2UxFJ53h+h5H+cJoe5M2I4c1vEvdk7y6dLkGmRuIuy9Zzk5csUG8buvNPF/pm80hcXlQy8QABNUN93kEH0CZl98RvCFNqzXgMUv7iL4JCMvmY+Wo224PrYaJmsNv4ZwpXXqEKL6GCqhtlQrNWTSXDnp8jXDcotxPy9w8T1NoF+TkwtJbhPQA/EDY1yBMyDuarnr1dhvdOwu+CyUh/BZpySzRXOkxrNr8UVU3d6PtHeJzEq+ldgy5v+pzyn44Fi/Mj6Huy+uGzL0Gd3pn7lmoDWMFfUqR1lLQawyugDe4mPbrRW1ZCenw6yYtnv7fFKHQBmZDTkn34H4MXVHKXwgkTrlKuJjvB8eqct0n1zROXwHsItKQTW90n1mHvCnb6rbHhsUCcwhV9/m9JW7WPpyPHLEoESmdET1YCXWQK+ipPTn1G5EeKHcOH38eYzpc58et3TcdFVX2g1LYc8x78qC6cbWCc4eBuLxqjCm//DLG3WpDF8jfF4zH+rLLk+rFxxXYlT4zXPPFeBWVlIkRQ1pKtfrPU8jBlM13FhO8Ri1aKCOkpmlPdP9wNs8MF9bXIGJ/TuBYRJLhwXgW7cMTErcoOZK9lUTZzJqKSeiJrUkgacPjtuX3vxLCvwg06tr7oCi3jpVk94ViG7qVkX9nKfosSyeYg5jU0+PoUA8zoOp6sBmSUX/1AHCJhRASQGoQozkaRrbJyVsOMm7IucWJ1Dfm2vMDzQMK/Wq8tquiUinUPzM3kqOhYIloVM9tU94fzglOBbplgv5B9PDTa/O648jHH/ZHvftKrLHy0irE/f/gS/h9wv17LiPdgfXpu7zehpUk2TA2QMaY+1iTwa7DGPLiCdnJUNCU1NbNENabfTvXonTphppjNR98zsH+fwnrTIbW9s3Jbkho3F5tX3x+MeKPCFduAKUDCcz35C+Amnjov78fVii+Wl0Lq3bI0/b947qkRkSMGxlslH+Z8IhhgXuBPRH19Om3bwFTuXwAv80cN4/eERi/XtWGkznqWqIx5DVA/iLjSA+0dhnaiCgu5He1im0dOIhO95OCfSZf8NZnOvKj3peSVpI7xyem78OWyZ+smhjPPeT6QddbyfkQwL1iMuInPp10vkswrBXiA8KnfBEiCb/kbQOinmJpX5D30y0VLOL0uCJX87mOMei0Etzqani2b4JTwhqhMXHZL4EQA3/rrQNVBPWnLQcM3jkCDIYBCAkQfEZEGuMu0GFFKYEC8KJDg4Kd9ivnFRQ+7yFKj2SSogVvEZ0yp2Ooq/EuG6YEtEn8wCuS/PVFzt2LVxMNsgwsByGGm978dd0RUNazaLeT7RAcHqY7Jo5SXXzbgkXV8vPaSxNg9L7XVDmUH7iQddKx9SAey/qDjFXOaUlELZoMoEEKYLdA+IhmznCjx5r/6J1aUs9Wr5PBEgx7u+QTvfxjbyIT7crpXuff3Nk1aEcvsvbHTbwRea4Y6ZczqdLzqVOhgs='}}

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
