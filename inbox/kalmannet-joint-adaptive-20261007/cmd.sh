#!/bin/bash
sequence=225
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
Q = {'sequence': 225, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e28620806c99ac64ca7004b05f5d088cf9d8341e5f43a57c8500f93defe5428c', 'ciphertext': 'MIINPQYJKoZIhvcNAQcDoIINLjCCDSoCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGAsFEKo/8eemHGCLp898FZEaqNrdfMrEgY+FThaDd5VTeSwnqTJOIAemnVkG5N+YrwRUmpyRBEbwZu6ZEtqNVsJzgyDjmcsXrtAtsJpNXhVK/0gIsUkE12n13OgPVGaaSE1afBwn9I/zNJQD6tMtMqCbgNKzYpIMrn6lvm6kcC3R26shsix5p/r4/vmVJwcq7XgdPibHIPOD/BTSAy44nuQOusW3qkFGxLqMtVPDLulrnf3p3cyjXPZFaL4R4hAMgcUXSA0crS/r1YLhr0tMi8zivU2zmqMixGBL+whDIcwVVUGDnO+DjcrjxO9mZX19tvfgut/dqOdKcy1Fyfxxy6PzUPaO1rOYV0Ev5c3LFc2invCfLjt2VO93JYGoDfsTmwc1lmcKhpAGj5iYEWT33opRCIbHgvkY//4VxXEdm+UV7xooe9+qlqcV9YuZK3DkgpgsByXn3BdYv/qj+qroxxcEH/S++GOtXKbQk8tF/lj8YSm/vi1f4XGlD1dRzneGHCMIILTgYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQkM5RSJTVniWTEpH4sql9/4CCCyDJYTtcs4dYJEfAzKFmoM6o67UaK5ZwmVJXSO5vBjqdxO69zWjYC8VoDeSDfDc5DwOhhhRLfr8f1fFgJBVxh7XO4zf3FnnqXWaLzNkDL9LCedMfgPt/ApXjpzFrYr/vRnSbvgF91Fa96wG33+NSW9wx0aYLeCVOsgEI0FhI2uUNcEdQa3o0YsSy1ZgS6L6hwa6tdlCUXQcqL2ohXEocdrKS1IaKAxLNZ1adqMYRdJOKINf5oNgjq8P5jG9iuLTajm0hAL/SlNjeUcxmbSYsNZISnOkeQ+nVsiLvzshiCgk/6R51GNVWTd9xVkXrmo9A25bvZ4+BSBLpd/dsirc+DDsrsVw8hd6iZJWuTFnSG1rJhBGx+4dMTxF1P9yy1LthdSwAH85yopSX3SpuZbvwP3XZx7if/RszkI2/KP7uTvs87u87nBkvqPJvzjy/ij+ThuWJsxYdB2u4vtypfMfumHIjwSSm775yfV3ZsvN19nRZCL4TQ5BKEcn/WsHF3S8sC1wEH1/yD0fuDMf2v9kX+YGBweetf4Be982FQyZM0LjwKSF3hMFxIYAaeJsDOs1kT9X3CSlyh7vMnQxyqSkfiuUmhiTTleUFaSl/F12otgPKclh0rgD6U2loGd7nK/Dgn77jejtnW1IJDtzMlncHA+ayXQZPXLa6Sc3Z3xRDunMfoNvdPzcwA0MKxH3J8e5lauh5G5YQP6p2ndsvSY1hmN2j16htgbvvySsTiSs04Hiw5EyA2PdrqBYBw9pXl0Q9JmBnW7/DHAWIK7TPedPVGSqTvBOIRBxUWCmIKCnevM4/x7ZUZ488hijopzHaBWKNwtfnVg9695RKzHpePGcJb6tZQ8oRK0RJZDlBLCfoC8gvRbCtKwp0SRPG4wVBHpxEhznmMtehhElRtqymr4is8S7g5rXSNfgHDuR2tdPOt6HtvR4/r7CtN8fi9B0scaiktui5NDWHNkeGGU1+bwXzNYbo2vvPc5obMURx2ICBLt2Fl3u5HpIdGCXkodcPWq88nQNDkf1neQqhBWuUlqxE+EUMGenepsklXFIm2jwJdxxjPEP4Sr8sjkH1I39wvwU96Ddhf6gZCqBi4pms2ZGjksKqxhw0XMEoIVC6p610Mlb4QUsskQTbTqCdDICojnMP/O2f6hkGzBsFxdJT7n65NbAugEGiNGeDwK7/PahKOuF0KjJJPo/IOIMOcIxDOWXFszgNP3e/vXzpnrnMcw8255yUfb3WZo4o3mKcNCvL7JwmeIOi45POgxna0tNI6YRPtN4dMOdaE3zZUp8UM9T82Urn6/bNhzotrIMetIs4obL59E1DECWIuiJI/pE2P0CNpAeKo59PA104p5vGbXu+ygnKKuIN3nhq8A5Oo3bnSkVF62TnJAR/BrizjCVeZTzb+Q3TQKCvJPTmp1EwfGQ4hgI7aoWzHLMlMDZVzalJh/8UKBnqzPiiZeSwwThYAuzxJMImrFDXxeHyjQ7Cj/IIhY0lS8m0Bn0vuOEmotZn6jfYOAo68760ZHu2UejDgtBsQsPUjQzAjcZLPf4saZuDjqPIdfjSirxAApbOlnQgwHTDxA7QU5phlO04OyJpzUYlczrb9DJJiTVXM0hj/LB7xlpR4wHlJNr5iiV1HJja3OOjD88jCdF+5wY2oaGTPjbNhhR7kqKFzeMNmv/Z4H3Sgzb248ssBg/NrPpa5A08d3yMABUFDpBayNHFSsQVNhjJd4AkYkXEYCJc3m6j+HxsLo41dGv3oMZbtXJHEVq8ycVCFT55R/PyMyCqQLzSj6OOMTQqtnWrVpj4+8+nAhVSHSpEMLe8nUa9iKwqQF8mLFjygZc3ka7KHUGAOe0sTPAW4DFWyTvEB0oJKTrGyN+ryHykjV+7kzwpvvLbX8I5KzbyMqFfUDS0NJXrjkh5TMIiKa9H++YdVVmOy0+xnCrgh0qO8QCTf88HJLKaqntydVE8ei56ubouZRy5m6lDRPsoiYUbpBLP4UPyAGLE4+Trv4xxFCF4eygClUj6+f5hmDdRybV4Aq6XpD7MwvEp/f4UZlWF06w/uHfnUSWjqQZQSvO8gCdy7cpoUB7wkAmymPXf0LxLP8QiY0PDwkTJRz1oPHvZQTTbIlZI/L/piorClHXQ0nyWT+XAU7UYmIikgrv2SxBxHZjUZYhRJZI5pnaG9lu3NWoKakO3uj3bVoNFn8ubgEgA3TeeYkF84c5vQW5yEmgOMJvvwrv0p1wg5g/YAkcS8eshbfccPc5D9goxNIRkRGeFQDAgkh3rtHOH2MKcLcQapbrbmzBKHLOqLgh9PRDGbMgnvwOBhKq1LMguF5PmI9wVe5euCH4fj8LdaK5FRhuG8Z4QUEshr+C43532tItJPO38KF9QYPzd+4KC4oWwMms6lG3RXm3x24PpL+Hj6GEJDzoBlwIZ9KDqeQAJ3g4Uq0Wjx3TZLws4tjMgnixazkjDLRh4lEdFuUeaNO+ch3+LjRr6v0hPLy5sqgRA01Ksu2k1Dq/FL4XiphUz6aHzDSxBH86e6GVE1l96BugI52423k/1P4JCVru4waIp2R8LtNcXMB6z8SCjlm7GBKr9PFhrQVgt8pPnYqni/CqouSaBZY4EtSbVJFUMbCbJEzmA4/aS4mEwz5yyIpPYBgy586z191AY8srFmCxxU3dtAZ1Wm8Jdtzzzp/woOw0WmnkbjyDFSsMkpHyROXz8YEzfYShbGZ6VXuriXCRvI4mTUTf2vlt8KGH6CBkTPeyxyDQg3Z4wK56tH/lLBDm4CuoHVIb//wePEBBR7je6qMtkvIc4XRP8C8f3m2r+Y5sgFCah5shv587osiOPKq7ZundESu7f/M7yU6iRA3e5yePdkHwdP3dOSu0HK6kHD+LF0H2xJBlSMUwtpu5Jne9Zb6LrUF4xcnc/zqbEMy9FhvLbMuykUhrNTZNpUr8Gqm3gaOBD9R79D6lnSy9Ao6lOwy4JJzbK5hAePT/bCGxop9JNcCWsxyDWPbtNmTrQHi7n9cDfpElxQukCKl4+ZikbV+SqbVZKhLijn0uy/V6OGhaFGKEVFBexj3bKNuPOXfvMV9iyM52Q3klTe3oy9rE05QolygaRoHDM6eLwxosw8Wd0714DHL2rn7dd90s+6inv4da+IMlb3qEVK49zH0zlm1bynX+lxg5vc5chHBjEN08pTA05skGBS9vvpHXAdjIdAX1F1HlOOFQ1Wb3iTfx5PZCBOpoTNDubZm84cWgso3U3Q6rrW07cOrKR4Nz4re5ygrZabjcSzaq9dNoLsb74Dnorir0iq5y+S0JcOUUtD2Y4Qksp9n1BpyCzqlFKwmhbRTkHcImmeMgFLG2jihJrt0JC5bJQwZ3GmUqWcvyzuItrx3oKIu/A1F7SA1SYhe2GQ9MeLSeL8nGfLbQhfJtkbujG4KwHnMDBFCqxnOyfsfGHDcCayRE3mD/0m9RDqgZl/eoTsJp/CSqJmcE9+u6rJFnCVNLvgb30FWkruQLaAxq8O1R4HNLFkmH+nGmtDbooDS3CxSjlHsiGgSxbBYgj04Y9kwT4VjwQc4c43ocfOuGX38Dg2CZ/igss/JHFUrPeAeUdhqVB6KGdTnC0hUPADzX7D1l+3KiENwijFTcekuKyl124LpiXK4mnGtVReCyLyh7rWahT9tj7iuxwUjHsht41kHAmbRXSfA3ZKjslzHw4gPuthctpLcj7Y/lDsbDCFE84Wne40oMeclHK5TdRwiCvgYVBzO2FOk3Va6s7ooHecZP7L6V4cDqz3hjfPjlhZVoVfg4cImRDGcftTuk/OMiw'}}

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
