#!/bin/bash
sequence=359
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
Q = {'sequence': 359, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'e86f1c2865db500df8ff989381b12ad50fcf51c341bbebd796a9b018b8e5e7a9', 'ciphertext': 'MIISfQYJKoZIhvcNAQcDoIISbjCCEmoCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGAwxVHD0Nlm/TVXmLE7U/yZb9HZ6NxL7Aiwk1sCvaZn8pNg0l6pbacV+3AMuzVVVT1LXqdtnsZCQhBELpkKuWMBSAf7z8xE5G6qfxhHBPO8OK54o/t82AWWrgNaq8pwoNyv8+ZpqScumvBl+ZeT/Ce8/mL4sAlwEPZ2ssTj5UAOzfpK1YXwYzuQJAcByo2ZDnIcpGSfxC5Ykp9qnaxNGeRf3XerGy7l66b56PoOnfTLw4uFQYvaPqQCTQdjYfwgsRsO2KSzqD+AGVQY2RvJuJ8/n4kWOwMsiJKPqOPLrcKkCr27euxgGAeTnp1gDgaudhfBlvt0bXlLtok/S51PIM6XsaHtK4LKkUmqGWh2xo+Bem1lY8W8pDUCzqE3CNleE/jSSSaqehnu0K6J5kHk1uyPCISHST6zL9CXXQ0zTZKinT9QEpr+WiW9Nbff6LI4MrKyCTt3V5uw6CHyvXvPRTmI9L0dbiOjGAV8lga5ojcO0rxkru1u9U8CH6HjBn3jgrYMIIQjgYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQKN2LHEQC+beBoogwTWJmYoCCEGCjSqL0n3lP7g5kspzNQIt16EUracVdpuGEpLOJVv5OPJONgBBRwJr/Srl2QZqgXPi63MOsN5RBv1XiNo3LnTD48BjM+4MR2pgad0IJRX2raQGU8mS0LLA3SJ2Tt9RjZdu0bEf+IhPc73D14l6EMlaBhvj1t5El5SVK67axCNBJ1ld9/4kGT1o0ieN7BJ/V7QqLMNv+XbTlmSVN7NdtuRr4yWxeBuVSdRVSHT+uNxMtrM3cm82sWsoahblPs8J1D3A6n9WVhmv0HhQar64rhO8POSxomrlKgHuQiKigFcSpij7MWPM6QnupooeoaaSMetLHHGKCTSnyv+PrFSgqktLHZxad1WF9zrFdTDO75QGPiDBkEhv8qmwWlt+UlS2Oyy1lxnYqbEtq4SQegTJ0E27xFsmfst5sEKZaFW3uIKKXj1Fxios3PW87wyFio2Xo+mrQgVBghBxusGfD2MTbsOknR7D7/+43Ep1l/QDQIE/mr5WHihsnSOZW5eryohs9FRDcPCzHW0WCTRpukmK1Lrl/qJrhxPk/Se4tQn5Uss+EEAEn1uRQZ5sRX1BJyNoIy5H0KIz+vuIO5UCToVMVj9TeWQ/t/X0QZCpyunRefhHczVJ3d3LfI9ncaUFQxG84ZwHuW4gWPKfuEfyF4CmVIkGmaZR13TxziZM5J+pRXPJmH4VsiA20zFEvQybY1TVHGF6cVTXMnMd18qIzhK0fmuE5RO814Sz7Q9Yh5FA39BIO1LDmh2RuQj8qV3Ky32uy8p61iUgs89HnAsDEAA5lgKcZuP1GMuW0JynXSTODqvq3C/le7FOBOd+wh1/BN10jW6gloH5oUSgT+oVYFhM8frdQ1+S8HzbEnAL0dsJ+rVa4nhU9VTglHqOPvFlH2mk4v3kM6/ZRz77kNh3/hRLNsPi+btAsq8oxYx4FU4Kbwy9ok2o6B20+ZyM2aIoEUj7UUEg/KY3DrAyljXyBF/uVS34oFe0NuzMUHpKe2YsWSbgK47uiSMuwH0/ZwVAqDxKdolUZh/7UURD7yiC8oGCyOAu2IgNMbL5RocwwGS+h85uDmjifuPuAtMkwqkMs/5GZ3Ps+Hltom7Bd+z3bZg/Qbkhr8H9Gv1+Q4qdc681KJdqOSwIrI4sZz6AOyFbK7LPXMoMkFND/op1zFqZLkuYM7jphytuwltKrP2jH0zvsMWNTnf1vM/80eR4Jq++8auXoju2Dhz4V3g3dGQBMQ87kVpBE4WYlVthFdlO8yuaSnd4tQxnMHzW8+J9O6Bjy8rxwG9lDl4jHEmzbjXh0WqSlPd+ADsDv5B22MQTVMVOrPTBAXK2S4w2XxfX2pgEE3sHPjOEM/Zkf33iBXdI4AoZILqtSCvlbjd+xgdECGO8muNVTdVsOL/afwRPHB1nr1HkN4ZI/3++SjLSTJRKsKbeybtFIt2aG0Yyh+5rZ9JYdoqIyFRGdEBSpie/wsRmTSkbwVR+3M+ETMIDq1QfCXwXq42xPHCwFk8opCbYMd8xKwn3Vf8HGuuev3RAGSsAG0CHqFxIUEhLSRjDMkg5BfV6oYrmiBX55lhfMxw5DQeMCmx4oMxOUaLjHWacXl8+rjhuvo0N2O0UdDByzZ+p6HFFnk3S22E/+pXzd5YwCvujnS4Emy777oNZyu7hKSc8YlU0dZQG1f7pJamxpZ72JQr+t7g/ygf8qFC2QgdHfiN0JCw218dU4NuRWZ0rUwjiLiA9bGhVm6dO5hlKyJgUwChHDXgLWR7Y2aSFbMGXS3Dn6zWCAwMVw7sYHfHpqlrCS7Wt5iYuBr1SEurwGMg/wwuF4IxI8tXk4Jqojlyy77BsXwL//VmB+CgmAgJ59aDOY/6J/FDLqIP1ihNmXQuL9elcen7PhTSj6nRvqzcEdBLHf86bY27fI2dFE0LgZnlQlK8sIRlb1kbg6rip/qXxWtFN7HmDzforOsACNiuMkmIxeGWoZ8Y5Gt9TkN+5Gs0/m4QKJYT9V9eQ1r9QjLtfiBQBdOqytuczTwbZ0sPtswN07egUCcHTLTNnHDORZGMxtenlQ3VvNcxKtm+YrlVTRZ/co2fPafxtzTgffFOK/wqobB0D3psZFcT9Z78d641saXHHT3BIuPQKkghNFal7lWvR9hwXYO7NoK5rz5VZvTmia58RTugp/9tWwmEKeOeT3C6N+dOP1cjI+h0XMTMt2cD/2Pmsm7TMsYpkfxfHRgH8qQwU6BLCRTlqu570cYyhkYRZKrZyBDKJIwEyybBkPE3yO1foEfr4DqJxhcS+xeUZgrGvsklTMdX55nNLgK4d/78hXxxeGhGB5dpPz1VrmtpK6YXwWL+lc9jRtrh5UlQ6FEtIsfLBahP77PVBo+RKo/8mdf8ApkuEMiVut4oCGLhkqRaVv9g4W5aQpsEqIsJOw3Q2m+eqZBy1meyAZ7/T5+h+s5ppBdUwqUfcUFrKvA3HHHJZX14KuShZsiQMQxgRnEII7AQzlXHdA03G3TPfnHwtDOzIvKAhriGfF6Sh3aU20L8EZZTu0OFxJZdIMveD5+7+Bg4DMhYTmAL+Fmn4cak3w4L3EnqW3gBY0Nd0SlVaMGHDkYhk0CVCdGBU44g4tUXuWYHliXKEDxqZ4JI5MC6y0X3xc32ADnU9QDnjG+4LtxFCY7qJtk4YrtvjP8Wp2WD3GBmzkzp2cf6Cm+AmWlQib1QYKIw49V7rbHpdOthcCOGoCiT+FphxfT1lrgmxgtULkQ1K+LUyqQwoKJ3dZe7oHku5g5v3KmQUtzS6mPvhXKTBWnPL91wOW9/uYfc0//6TPjV+mzgSSLFHAn/Rq95jDY1sB9cncMSGl7idX3qyME8PnVS9E8cuyvkeDv4MwDhA8y6+gZB1exRZXLnkBEKLnbjWZgjtrUKXjuqOEaNeUxEu0eBF1VW28uMBRkuqs3IdeNLXDGIa/Rcvd1kdlpc1X0bxnjaT+qpKWggAwlC6NRjfAH5qa0V5tYgolMeS65CZxEoe5hsclTHG3OD33mpwmiHUFIgAKlcxobVSZLXjK4DYrbfuPRuiYo4NOLPFfdEQ6EjsFTQH6ZM/9YC+Ld9WuRfpxaCsmVjF4Cf8VA9OXKCIWTdA3UcRsUCPRAj3NtInrVKcppnigYEaSxhCD/gWndlzKEXm3Hu/KromCFNzt+ftadX85nnJxOBG7WkXWCGjydFetWnaTanTq/ct5BaugVNN8/eWylj9hixMjQUYI4wKRpGSyl0CG3kKmwOdrsZUA88Lr5T54c0la5qyJZ73iQUG/zWcFTSsDU5/bu/GCHp+FJBAc35KJ/jsRdHUnDd4nXm6jfaYEUYOy6SsRBJ74Y18RKjhXogmosc/O8E4gVuSA0HpFv6lEqju4MlFTxMiZ5zJnbwClGLCxtVIgZK+GwgTSNfVISy5jT5xJyH750g3D1Fb08N/2BBSW7QrUEpsL0n9ULlFIgW7SGoZc9viuCNakjVaOI4nHzH51byklWYlLYeYU1Xtpq9gW4zXJVcdgFuBqIUXiMjb8NEIRXNnOsNgM7HEtRRY2abDar/Je34JrqL/MF1aCgmWG3qTLBEK+iIl/7VGzz7/6vj+YZVRJhgcNaNV78C+pJWBo8EXLMi+CWhC39wfHkIcpe9ctkDENSyooxVNjp6jDQ38duMi5NQNUH1OlKZQPTi5KUNZJO+b55YZZ5ejSEsbyz5Jk9bM3TjnxJRm6JT3LBp+ojXN+VG3VqnW0Wt6cVQbiuK2/KEjvKjUzh3+vWLu6Wn6KO0oTLXMP4pYuVzyaqppih+xOFqlIGt3V6jXL9qjFXowrJi8+Q3JiveIApFPynX8jR2bopeTdZzj+x5H3Ye3R0R6PReK5e0A/JjPWk0K98ea7SBhTItVhAHIUao5multgJLp5mdVhqjbTW8o42u6rtUQNCSTGROd1JFdFStVzKMxGc4AcYZsUeyjhPRqPvUMTbfNv1Sb6BcrN2YZf94lodcc5CNvaaz8Hve9yLvmrRO5SdaThucpkQhJyjc6rQehQROTy5QyujbxhxMtdbD1fkJgcnsQ8scrp8/QYtdeYjYuREYzZZztnoH479efvmK8u8oZCR1qNNDTn2SaN6BeL4K7oYcwQoYvhDTFePpnnrux8S9ei0+EjkSiFhMHriyUQ5Cc9Yz5dRLvdjvVauXa5F5RlLU22vy8CxFBfRLH1rlIGvNYtJ7njAlZx51cwTeyIIqbqCTIgXu8mzxnBt300yHkYA8p4+X2kHeofEotqkZK5zsVE8B7DNQF6f5JGslaTafwInrF9Y8YlTJlQNQ5uyGhta3mUHuyb1h1CY1KsTIEhEzEfA9OMTmkBH/gn9T/h7ocGIDEGlkV6y1P01mO07mPWoY+5HeHWzsoWrUAVVIWnHUAPlqCOubD1/WRXIK7VJazIdQABGMdvS/i3ORtL2s/o8eobYOsR3qdTXEJUgOIYuQv/9U5rcngJhLIS0osfNEbHMKnfDU7k9LbxW8bPZYNsFXTA9fWBm0Mut/9dPC/7j3NpVUzyC1QuyjlECtIt7kpKvYu9Jb0M9rwn96NGDhpHpFvHJrKjVzNTB7v01nqJWZijoxSvcUR5WniytUma2zP3ZewMw8SOSlsClIV9mCMGFZymws8P3IflwykK3CrgWMM6apxp2/QF33uVj7z8c2SqnJRx9jZTUrxlxaI8JSUWfOTOkOUk2PvgSOUbREt11u6BlHQ8hldLdP224rwJyK042MkqESe2fqYpyPITjJxrsQfq6RKkSvrqjaGcNZOSOeYu75ud9SWMEaqqx5KVKJmOPnrck3G5hUW7jCLo1bQlUQ+qTF6pS7Ah0LV8/nrJjh5WNETSPo0qKZmVd5h4jw5DfHjaY0GPk3PBIk65o7Z7WaH6ymEC+v1/Mbfim4q35tnM7eOUas2Yefg+nl9+znsSX/1ZzgtZkaV31QrkJftC8fnSPgcMb1fvE10dpYRHwhFhNiwFs490qbnYPsWvz6AfIqYxcSMGS1jCe8OsXaet0F7bALqEdPEmRBYJZXT8ya4a22Y+L/j9mgcEBPIRWSQenXoKtMr4FMxFNMi+zZFQxOPG9qrJbV1xh2ZrnBQcaCWmxCO6H95zoEUp7klLLWq6KBJL3TeICOUWzESir0P6l2BtSZubItnA1+6uluejfVtGVaMfBqoadmxdP63/EnKTuMXqbSXBm4f2Hmi4xcPUgtxUd1FzayIpdMxsexOhf4ZMeTwRcYR6tlVhTCvkfCXp4tUCztyHGVF/QdzmWB5/SQ51oBqNDyjQUtX6a/B25oKSBlWDBeQMOuOfH0A1SsUPNaLh14W+dHB7m4Z5K14E+VQ+aMVPtAfT/jLjWXK3EbNmAcbL0g2J1K2tPGApcwydccxQPJxonS+ySukDRZQAL7DTMxoTPTt1xH+9NrQ7j3Yl5xQtRZBIdWQXkzV609tWoyTWwsgXbu4X5Sq9IaZnwNkqTyt5e4k5E8juiPdU8rhNWJE2g5jlGKZSp60W9o/XkHE/dRddESj9Fb8z/Ah+qrc04rTu9uF0nIjNmG6g6Cs1WhqCffku+4EZ+ufBP94mrpTORTlyMJWOeuPp7HTL8K97tGeHeK/tzCRX3wYMAjLO'}}

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
