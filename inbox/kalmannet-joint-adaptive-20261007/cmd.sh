#!/bin/bash
sequence=128
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
Q = {'sequence': 128, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'f238c30a7b5e5daf0413340d922f0b0b70286bed223a4555ba343bd27a961a04', 'ciphertext': 'MIISTQYJKoZIhvcNAQcDoIISPjCCEjoCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGApqcowaehhRx3Gij8r4K7X4FQtzIQK4nTsCp67YtjCaPU6rBHFbC4BsVZhS0pJKXESVeP1CHrvEE29gvF6a5b9AbaeDQKwAaIrNC/O4HFHDMqrcG767ylkOAZRgjSWy/YHE5pBcyKQZBkK1GNWnvVsnwy6uPLPSnvYE0ybUVsx5JAZx+tnOrpervQusUzZWJ7ZVz3fzuSQMIDqvY62S3A0as1R/XMNXZc3DefHNdg0BtvqaKr4XMwfLlvAv7qeuBOM+g9fwNoHxmY4+M2OokGh52z4gUBEhehzDP/0c9a25j69oWPQZa1POJhEvC7fo1kuKFa1yaj17TnV9Ic3D0jhui2rtyNWo8nAQSbx0E12Xnp+68mQ8OxvaZ7DNZKz6lNY6Reie1QZ1scpIWXCCBH/1LnYasmBKRO1WXQ7MPPJh/SHSt+IB3m7ugmJceP4XzxjGGXWklqngGMPvsKG/lBjh424PFVhxN+J9PoF3gsgazMEGDJR5xUAj7iJbfcp04BMIIQXgYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQyNsP+v6mzUbT9CFuvF9je4CCEDARBKn9r8oKheyuLICwl7F6W7Ck/bCOxiEeaaSk9Kl98WeqbI8Ti7pRbaCRiN+Lp+VdVbmx5226qoWGYI+1JqS+xQD9XlnfSMo4qMFTEwpuLxU7fCMsXk1sJuJjRmY1smc12WayTXZH3TI7VP6e0Axug4i/KlHuUsveFqd0cA+mZCV+aohYZefuD2dph5u+qrV/LnzdfDCY34KJDpZCBNkErU+qHxPFAIKnsxuOu3TACd6QTXUVMUxqmRoR8x6JiU0BJfuFZp/sWq/t8DdSlS5QERgveZKG0DT8sumOZvGbfgYO78gbdhFDYEScme9OMV04kVQkOvE7p00p86IEDv9hu3kdXErbPbNtfHzg8DQi6xZsoH+0oXEkrfM2eUrLWibgqoLzFnu36qKYdsf/KooiryzbaHwO9WUTOVf3CP2H+qmmqtkODooAsF2nv6JnIOyHVP4zfB5VS2NLuSdm/fcsG1Y8CuAfGWhdpdQDpWQaCqW7Ej2yf4g/CBTQPpnwEsdL8Hi4yL801OWyBtxGlxfZdHBjZvfwoP0APrLBIEA4X2NVrlk8pmSyNThLDVt+dXlduIkh5ChOWyH/GOcmmsrejE24ahFq/qw0JCvlASP37ZKAxO5FcWQ8mM0sEF7PIe0H20OcTRSFWwN51RbP8vQ9qeTaCCdNyl3uPgCpohpqQFzSMxP+dSIvObRv4oFwQcMsLTqpSnnPVT3ZjzlwOAnbgH19NfPwO23CnaehkF5Pvf1SEONAtD1Nr32QPe+gA/VZfmwv9YfDNkMMocSwgJ8vjHJ/L9SX+GKtlrZHEsutbfaX15FPaf+eLzB8yfFQKpMkwxMpN0GIDJOJyrggF4YlFlXqIcBrT8V+QSv95MIZvxBRV+PSRxACGmRL/8rdqDNx777INrTvPsvKjF1ElXboPoYhbZ9Pza2v+E7//pH4sECvXy+Q283rUadSx2N/5j8LpfVslSYlOYr1SKwfbTI5C9p+W3N5oBJCKnGYyxeSJTDubSCbkPy2T5n4gikuky+3BBtOUmDWE6+bvezS2syOjB4A/9wtIGX3kc9E+ifBzPR24G7oqhpcetMQLZrPi375g5P1ird/8YptGklLsyRhyCGKJ0GJUHKoxIIDIqTXpUMQppUc05EMkm2GwVHQ1/X/V5bmeX33cCtnWnhWA/MWB1QwxWIfUH+3wQAqFE3N6t+FZiBD1jSD6oTdWz5TAshhVc9OaPR7hKpv64OaQDNHy2uJjZkYhA1MvX44rQu2fEqVphi5s6d0rxjvQNV03k0inbqJNjCzdGrWuyS8YqRhRVw6CxfPfbim66EurEZPQk8FgF3wBhWAjiNt58YdcAaKX69DU7iMjuvmJpVqfF2kRgAPwjSD+qvFNnTFE07nwpMGvi1EIT0jt7zWk7flcVAgmGbVncxRexqRdwVALjhnwjMhajXG8MsKsRurMV/bosxvGsMlLDjevunB4M9BhIz6i/hMb18tvcLnNzVKm71rEf5Vnq1+2KXf8SHe3rtWAhvTYF7mm1AYMe6oedXr+3Oa7Et2TP32l0WjSNOzFUOP7fQ1hgeTLIXVKHbmpBAwpByhYV9o/hhAjKYoZFJ20hwdPnc7wTTeXmY5jofHLQnojylgTYx1gy56Gf/Fw97b4yaoeqMTNYehIKPfLtjFlf2BhkG+GBciKMNWtJr/SbniAefrslLaAjpGDqdl7XdRRy8oBAXQoQztbQKSWW9cYjfp/4Xmu0QJch2f5KNqidjDDwxDIMRyMrmQcyM+FLhb37WzN+KLAETp4vGAhTsbH2QkYs5umFoDPyesKjfsL7LrwwDDxXWCJ0CzqoD9nR3Dl0gLzD5iSXXubjsDHORVoEK6yYfpMebXMHCPS1Rtrt8TqWpyi0UwL7EN8zYwjrgrr6E/oo8M3sRGs/8pRvZe7Ni54n4JUiRT5vLV3+RZmCd10DOXogt3IU2cGdk3AmNzMHcihfm52QTBAtjd86Y+dpM2JmwiK1KDMzGOrLGL8c/eqfkkHz3exDpfImipMmzhl4MkZGc1RfHfa0xoUm7ll60zB0AXx41IVlHsM6pXmpDZ1iREHPaS+QNu7O03bCyOn3x5AOanP9bYUnIeBDQFqywoL1xNJKpZo7yiJt+RbKeAOPAuafI1/BDyfYvXNJowDkOInCNEdn504LwRDW5STWmb1wBedjFSM7wHDoNLTHKwsxRb7QeMD48eG4aO/hyuBYETjLsTjBjfvQi2ug2KXCQn0ni5mTuNMQKr3mLmNu64BsjlrGuV4ACHL9FhQggsV2iNzIHXR/GHEQFBlAlI+MYs1EkvA/nwf0RKGrZ6O6pxskryXThJhOBcp0KopZfNwE0ctYwjc0BCM8DF43FsH7cmDbddw60LHsoGmJAq257+ENYeIfE2QQToF7XG6botPT1fIdjXxWCdIaq/6qHfiNkCsTgg1SW/KNxzqi3UbQLm9OQYFotBntdqL5SR+Sk5aWotxE9PMey+OqrEkkJPtj+p4/Qwe6DNaxTa45/lSMwjgQEsxPYQCM2QhBlYIxCVzxA6JxNm/HINkMzIIeQAgpZtiYeB72MEm41jdzsrNkLahz88f/T2HJdsXdYILp+HE2oh3mFwLpEEzI9oJIEcJxiO9+q3Lr8nB6kbsYVXDZvMBGPXEinBtsE3TrjLZd9aHDLxIWpn3UmKAEq4gHACo334oSq3QGjBzKhS/zdKsPMiWReyAUr5Q+9/FWYUlvsinn1sfv8YNHkTiaHShoGgbXBbwqhr4XZXFU2iOr8Nz7b7AzeJw5Bkk3duxRq/5xr6BqH1id+MZ3T8ZBFVv2jbdiCWVxhQ6xP8cWK+B1V+IUNrOSj+H7m0ToelLkChO+beYPtZho3SufzzYDW8qoMB3ZuR/gdkj1P0GkQyEU8/icy0ug0WtFPHdh173P2Q+04WV/emwZ5v+RmK65HMg8DcHUL7qrVTvtxyUZ5GhPY4GbuQhWVJoxGID7nfPW9GgJKpE7Nit0RjSd7JHX9j2LbLG6YkCsd6UthQG0tElMqE5aIuoQu2tMjxnr3Dbx5p5pNi8XjT4ZxbZyQ3NIVHRuxxjYlzrEsKIORNPmjxccw0Zg1KCa3UWKIK6ZjjpjPjZtxYDGiq9J8uWjBwUzHLgQIXu9wvT/HyFkZZIkghnA7bh9zbuwOtx5x6ruYeCNeCV//Huo0bIMK3DuBjmiFnN7IN6QaTY8V4d52ogAkm8pXgxC9qHd0yCQZMWGy7d038lxZwkNNhbHqTJ3XbIW1bxBgYk6fu1YTQPgUN9xnn3CPj6d+8X9Y8zMSretsvUb47AIXQd6G1mzEedK+0WMhIGfaT9wxXi3PZlABqhxb2QgbwRHtbVKiFtGZIXFxfAwXRTG8XJgPdHGAM2a0KZm54bcqgD2nfIoYDU6tMHKZoT8FsbTOC0cC57nf9s//USC0kBhoH/BqkZas6j/n5+T8qo8g5YMi430h04WpmCXKusp8ghdNQTywD/c4dih1OtxCQ3564eyXG/2Li679kNF4l7E3u8PCnXCZub+fxuP4A8dJ1xOe5PiduxHUg18ZVw+4wBbJ+N3PXzek/fuxppvVeGXb5hRS6Sni+rexep+UXJsWiYB4BV6efPey62QO5zbqbx4UEg+vIRlXjxDgSeCO9mx0gk7omMHuvubByj7y7wxtBobaLDxkb41mm3Lb1l4Um/N0JsA3waU1XXmp/2wdKKU+kC+91TVKolKLqSM0R6k/lo7M4euFvDWberOPnTu5Wx5qECwODqx17mmY1LDiruR90v1FSJZkOWsO2L7PMpM9zFE/aJxzX2p//u6af38x77jKixzlUQCKNaLjrfSzvP/s8WBwV51p4i1ThYJJI3O8A1ClXlKNCkXT9MYtbyn0oMxTyFuyAEbMurcjBUK/c8F/xUV9OFHX0sYCYNsJj3VUtO0oDRXpoDNyxYiBaDICxh0RvyUKTCDwMkfU0/bw8I2iRaFdj/eZjO4U/LdcHP2vv6su/PZhKBECxTeCfGx3LICeZV1XRyYqHUyXxMy49Xe+PRuMa+qs+1BdBu0uXzaCWcyR/tbG5YHo80wcygif1u1u5icRU3SDTeUEg+Qm/T/Fyfh1xGNdwsvPyqtseKcLSDzLuj43ocI5k4ChoM9SmtGnfE+O644LMbjZTidkSpWLma69nkCxyxi0dQ6+9VBuNloZwX1/Z35ER82uEUG/bB3ZxbbBRN5Z/uMxOoSPKjhJA39ymCrsBa1zgeFHlcOUUCmeyLKrKNyfbzjkMdRF3l7HFkdifWG5uRxM9P2gWKNbOgpkJ14FTAZpyuduUkqQRfNAwMM7J1h5hrWb28TsW5N/IOwHccSqFhnpuGdnwFqRXSF1sZILQRj+24i80TEZsS6zu2xqG5nYPSomUn40oufK3osq4iehVbCmekjMCv0JssQlLtoISCUlI9h2RoMmh8X/+7n1XtqHv3huRkhme+zbFFZcEe1SF2rzxHhdkNRKysBH5b1unAjZlwClgAefAEhcsTUye1K9kejMvCYZ5jIssDfWBnd/WrAhZqh1kEHynjtgtG3W6GYj4jgv+/Ixnfo2Gk9JDlgqflfnUFeLplXlVzhtHIjKcl69QW5b4JhrGO87x2uUelCiXKQ8SwmVzT/81CYColMKpugejbPBoNYVHU7sZOkzTSwLO61Fz983qw2buQw+16PKzaOpxFJ18zZHBRIPiJOoUAVtubN9NLRduUX43FWtEjAV5Kv6gJqeiEtsKA6dhK4idHbfoDG6+d6kjemiUHweTgEubhINzBZUKR/8DvbaDsOgDU9pNUAoXwP98UQqrlftexkcnxo7J5PVJrGStt+/Az52eKJfBfmgdrutUTMLCxDkp0Ac2zS4RaDpvLadEPpGlfau9w3yhIifTc2FwRB4zhc8Y4Rui9JSt8G+bBd3HWeNr9wWgTwRd9QFSMhrGGEEZvc8SFU8rL7DdiJVLEaLtDg4Ut9yVlfW/0tO9B5jKQBAOfdyyx7SeJGlQT1x68hV7jfAbig0IPxz2wYzaw1rq+zC4Xo2Ms7ew5J6TPtJY3ABIhYs84i+xwvzvl5dH66q3gPzTSKihMKmjDJfi0hEd7ZuBMMtruShckSb65NxS5OBSOtoy/68RIZsKtMDuFiF45NW+CAhopWl009TTjClJOqpxYJBZ04tMP7ALvU4QzuUh0N5zOp4tfeALZZ4D1hPcc1puWoDtfRALm7mNjbaEDalNlCrcM2PYzB0oJEtsCrY8u/PHvhG4p/TLsedc9sbgUwZ0DnEw1chEsPJNrZZ+dko4dYEywBRai7QPxHz7HBOhchu+n4y5vx1VKCSYGQ4ViLlWtCxH6fBsiknMeXxHRwKq0G3tXjmeUXNzDp4Ne+dMYqfcr71v2skgTfaMb3j6dH9TmNmkFQdstg2Tbr7QLrYDhs4pVKqF7YCZ4axPAeRPfunu08nvuhns4IH44Tnl26JT/Ep10I6/wssVJA0bRK+zjIFuZeuvikfCtvA0urYevW/4sgkSwzg9+1NJoEQcMfuAjILTpkgb'}}

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
