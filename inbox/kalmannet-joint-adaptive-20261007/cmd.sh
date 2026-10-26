#!/bin/bash
sequence=392
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
Q = {'sequence': 392, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': 'MIIUfQYJKoZIhvcNAQcDoIIUbjCCFGoCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGAJPGHTRXgLLdNwRZhexmUhSWciZUbzScj1N9HjHBZe9FmYq7ZgnHcBj+t1qOyG8JR+hZHV0DmwL8ch8tuPexzmFKTTKOQco6MvxXCl2a0iOf35GWxRtw3Qz3gsdU2OCMXre2gFzxfcVypW4EX3UbzK6i8v3he/WL1BdmhQ+Ygjwc90ytGFSc+zcvYZor8OpB80vbQBecqSvGVcBLk+5ZH5b62BkC0nc8Rh7TSoYVHU3srUnbsQce3nhdtgwP5G1IQtEG6K/Fwd+xGMGdX0A6n7IDmT2ZGiRW+vPWI8U1Ocl8YwFayTEXk8Eyvrmx6bLf25KXYhowJ9grzauOfHsJsAgOzjOEdi2MEIGnXKpVOCcoqOtjEAGccWVg/IfPi/os8VSgO27VwQH2Jp1gzjVwURpweVFM7bSyCaS1d2johw1DXXsAopo/BjJBEfIX1Vu26BCf31PGLX5OotdAgYTaexo+mMUVTAVUhyatgOUnnhOMIHQFeOHEFL5bUmmRMzjfkMIISjgYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQaHEYEfMWhdCiC9LuhPB3EoCCEmCy2cmXyPUZxyoGG30JY+YB9yc4MqdP/9H2jiQm+/lT3k9GJtaoJSGBAakJr14TJDr/hbxsWqgI9UHBcI63ZaHTkImio4Lm5TxtMH/kTb4oV72vv5rICToEpzRS1KYauj3EVzx4JfcCuef1P/MayFSDC7r4AxUF+BXHuE1zdhSFxEbhGg4TLTXhvDrtLrOjxBhwycoM0PEXogMTNGaajUBVcFajJhNsPJ4Vp0djozluYo844C2UnypKc9PVhPf6QbMbw9rCqTvJ/oy20vPmrAIch/iay8o5uoGmTRqrk5Kbm1GlSrBzLJrSjv9sEWQIVuje+DuHyGYTDiyNwFJaP6dXyVsIP6PMxSQTSh8au7DrNkz5ldJ+yu2e5Hta4bjQaAtTKgS6s28VYBNm9iGVOmMwpl/yvIsHLCnhp/3EvvtV1P2O4LRPKY4+PHa5am39Q9htPuix641k+21j+HakgdpY2hsRe0fsnqZQ0nbtYZ6HRQyAVTmg81ptroYD3vL1sQ5YTA6g7ozIYbc9AU9Hsq5kyP/AZyA+tq/0NB5Zkyxs1io6DQ2hJWOIt1Rdq2u88qOQEkKKqDLzSxiXuJkEuO+NNYYcTW6l4Izb+ILBFBilXrTfFwBRxP9Z966nmt3LW8rfbMtZ8QBYNdAk9aO3tIfuKaoghDLSzPmCk02aBL1M1C1qHxOzfEKdkaMvHViFV+9S7tsBgdUOFEAAkJf7xb2n0eOboJPAPnNIKymWHYw+/2JbtZv0nqI2dhy+uhL4JNpT3Sw7Pw7DCgSamaJ3Mg1/AKwsDKcd5eyBCQMjZkk8mRi9IRZyCXPJa3cLKvKe+J1/ivlRI/FLtzMkWCh2XeZWk+jsgMiuy8CzE10+BQDfjpfnHlIm5DA3bNZc3NfHxTh1LsDRgd9D0SIjECAKiFH9qnqGcVDB1ZVHgTEE6GawSOVDM55tGdtvfa7pud5bfunbNbs/pzyVJlTkqT6Alc0BDjdkiCboa6H9TgN7+fZREVbDged94NdaXmmZrfL1Ouso9Mn8a3ldP2TLoKRRJYdSu4irNlX99aCYZuSFx6h/NXusDxr+ocAUHxGpBVw9kEhMVoBLyeXaQm46dcTECFyeEvvZ+Py0INN5OO5zx3l+AnqSqeYiYiZ7bGjyYRegdyhoi/cmUMdLvF1irOOD0Q2AJayRcYz20Bv6HWsY+UdPRi6iKX1wUNP4v1CLxVZhQ7Z+9JFGwZfVd4M/2Cbb7NnOBe+/276ORE52u4hOS98wSu2FEFQfgqUjtZx9D8X7M9VNNR5NP/6TwdGNNosHwr2jDxjNYa+zhdG11UIUFTa8ZVdQ3YWbhbYQFOrN7DgY2q4mxVvC3sHyaz5jhCnFPGuejXt23PZsWsRFXlQgLCYm6EkcvhbewyCMN/baIn/4jRjrPELqEJUDa5efWArlaoRYjezKzyBW6zx1H5Z4FjPdaXuls06x5J8nbX5xLtvA+WWR8v3GEuhnIYbfBEeqO6E+z2H5GOUlzIeilrYxsF1yIDXGCt/s2M2h9mk9zm4mzo/I4P8QUr0Dno9v3AUKBeA+NsGkKDxrat6Qcb+jAOPp3Vt79R57OVocDAFe/j/5Bt2w7ntwuA0SIuf21xOH6aAxo2tAN6FlJ9GO4OtsQaP7eC9hfFezxIlr6d1JtHfEygBaFMEdZbAH+5DjNF+RiZucz6Fgrsx/TPNl4ImbuicUX6YOe4KMJQcD1xPVIQaJmykLPq383Ic6ry5CLUI9m1RA4Lp3XkV7dLxrnbYS/Jgrdh4tJtrp1B7wPEAvuAoOMwIcSmMB7WWrVnOGRENjGT6OWLV5qGo/ZBEIlTmeDDmAyvQx4k7A3d1iu7FOosXn4nmXzxcGrtjkgvGxE1pbnY6QHZKUA8v9IOFMpuMCW72rCDzvEDY2xJcIjzl7IFVGSelfWd4jHp4gSkg2wc924X1zWd0JtdJceO8s6HaeFWKglp6MLUFsaQCSym3ZAbhJAy+oScQZkeyZpwGU0mdjip0PHKwGMTtZmp4sFr3JidJE8A/CPp2kSY7QV1kHsA0UZLnupbgXJYL91cRAMBkRKAWgluaZX/PBYgeKeoz9ppnECX3x3KXDYg5IOpCkrs3mSEmOzmfQ+r6SbwzZ3210jl6Ug4e+QVnADLx+Ea3Bv2HjdxgWDN1Zsrv8k0mHSS2UphqLCXrtVSDCDqKaEv4DyTn+0tP3L+rxCzHLZxPfz8G6CdvJVqMarB4VP7DaSuMuaW8F4YIwoyVy0gjTSWjT7hOFmm2WSfEEf1Uk1jPBANCB9s/PBgB0lLiX842vJJtCZaj+wOpK0vjfvU3KtuJd7DyVj5BBRJ+Pgwkm67Q2AHD5Ppff98d8DBU8gkhrmVx+L7BNjwQgye9gk6CzFSVJFOo6e5fnzgglccodmKDRvatFSZWxP62OSNrCQxjxkPSVcuM0pJHtcXJjVsoQkrZIr99KJcKW4JstaBCH0huNsFgohELCbcTVvyzvsAH/9W7t/y4GZ4RKNc9ybSeT/nuv3N/e+oUjn+bZ0u74WM/M+zWY6gsv1faIjF2EYw+rpqi4sFpd6HzjlbTSMCC7puwPzdWgQipCU+aC/eQeYEy9wfkUWz7IzFfS2ARkOgAlJg7Q30RuOM3rr4soHFhAmPUee1hCQxI7SfO7KrewtBFsRuq4+FlGhU+mMv17CRGYkdaNokB+YIIJLCUv6sHbHvRPKGdc2f3xpGEzCGhrWMurgA8tV+QjTdKD28CrYsK6ArgFTB+L/CsETk8xQgBL/v7nCJx9QcWxY3x2MY0v9n2AIfgb/wvi1ed61da1UOhA3nD96+9cErN/mp/O1BWNCAnHDTPa2k20SQFY9kldH0Vcq/8x8S996eK1SC0iCvcyk27NbfLDB2A1AxWQgevMdM5H6iYSkEVVnPGMzPBxTCXpuAJrxonMd6pv84SO2YOjU/Mxpx6pN3AVMspuQp0Gi9bKybyhkYSlrwzFXzHhyPdOzEeg5d9qv+mlZYpCME3WbXzgsJNy9+8ZorpdZsdUp0coc/kOegOFcuMs4C3kcKh7N7LSZUcFhQG6IS7bhnQzmi/G5GbGDOgGxnRZFESSE0jY0cNysTxIwL9GqMzJUDucXux9tCxFUXaTuP7R6UJ62/fjbiFIzODzuIyoALuV9Z71EFYJowNbiLWbAkPRAF45RwdeZJidD4geeZik65g4LLvqid+NPW4onSjeK3m8vH99+tl7SjhC0coroTUkH6h41R74OWxPIWqdDv4NcAA1Kz7V60lpS3jWuu/BwYZWrMauq+AMmSghYJP4TtjbnkFkTgtBj3VKZ05pDivdNhwIpZLN5SRFV77UK9Y6ant1E26ce+KpRAYGsBr12AhDjWru30v+t6HpYoz8AZCQJmp3MwEhpevb6vBtrmuBX2/iI+stVPRkZqe6hDKms7b3DNLX8XumtIxWJMvRPNzNGywP8SeRhrAAnieuCA7H1cXlpNAvHDInds1+NqpDuS10n/+96XL46Xx5H/Zc0CbAMIwprs7EnBM3BXc1QW6VFAEOGuSoQrf1MbMhpsVNlw9kDzT1Y08TTTXC7L/Pjnbzn0YcNiyeUchY31sSH7xGpBTswWACefWlbvDir6Z9EhqNWhzk1nWfHrIirW+fQ9jdyHaGK2BjlLc2osvmGzLpXSkfr7DqeTL1hibnUfuEnViSi1SIvWQR1k5fpXgpyLZ3Jd5/lC5tEgvWnLS2qZCuycJYs6/L7WrAAkvWCLJ1X3bj0yJDPfRTrJbH/Al63B3IIB0BLX+LkwgOvTCvM57sR2FDRH0Z4nIu6yhsL/6yJ75DPUdR2Zs12cNn2EE5LsWAx8eHtiRXY7hvr1+kPpaxk4vDjDsECy90l8RCffJwvFzSh6wSRkHfDgo1W0hca9G/JrFJwGbPx5CNjS00lJGUKoEF9iyTgZeSzh0jQOGynY9RiR9cRNdHmBHlcHU2StZ/btVq0fGwAPzLKjmVJkG0HazS3M5KpfyFJ1Y7OCiUiiWxxGI+tzCCUuqTi5yaqNDQeyVg885L2qFuZyfnoiDOrFw8EM/jg4C1/e8fPRuz6p20oW9rh/V4jvkEar4nWvqSVYZFI3YXs5ZHi9aXXoxBRHBg2mwLrKgwoVTvU6Iaj9h0c6FLa8mongGwFy81d4wLKOmQfDlx53H8SGxNiTrUp6638uq9GF7j92PW8LHDu/PWNK+NFMzyb9mcX82GpGf+iP1EKjdo/ZoRARuihIA+ATMq52Lynbi9qdNsZKOP66aPCy82j/yyupbVmXNKUSYCNd5f8Qy2MuEEV1I3AgoPs/Nl/cYiAZ2MJlQazkCS5mAfEtrc2NgIGuJVvT4DDgVezJk7v8f6XaVwvYhB+a2PBJm8HsU9YPsVP/ICK+8RY9G2V2Zmy3j8GeB/CKi4zrIIamvFzb/9jsXjx93TPXMRAxMWdr/RPG05WC7w2vtq80RqCNXujYvJyhHXClq5Lzm9iJkdeCZjQY9pTfqbR3EhsJ2Wll+Jpl02bgicqck9qKu5ojlCXAbiDrKcFjg9Ny5h1kHyWuOezW1YNsyLfTDuHI3dfZ0lCElN/gi5MT7Q8vAxYBtF6QGTbJyyfZpymLtm1q+QC65pBPFZHvkNRIoLHYeMP+O0EB8mBHMNZMPgymCmPJbpq5pSvqaOIh+G5hQWxRsHAEJFtv+BxgQbNlLy85ML7vTvPuOc+9IjaxM8/dTI6c8533zmBp3xmTtY5I9rPFQMPOgLuEN9XpWn+YZnsZHokRlIYUaJmvKjQsbIB+iegWwyFOn5ZkLCqE5HLoGIsxyJoI6WGKBxYtIqwmzO6/0DYtG9WdDwwcU3uQExCymRlKVuEOB+JeYLiliBd4Qbz1oA8pkiX5T6dCc+O+uqEzZdZzsLHUeW7O7vca7+1QjNzeQ292c1x2ONIFMKa4ejFt0qy+X4sf8kEKMP8+Vb+VliSrvd6YD36ZGoaD9ait//40SrTW2QeDK+8J5JfK3GVYCxCZ7cGhElTFOmXvMMEPdHsZG1zwI7EilOCm+AG7Cd2tm2O/nCmf2NIqru9Vn5rVZoWf+hCBd2wAvEfYdrR+xwiw4ieNPKkpbFRm4BSq4uDrVXVmfQlHQaqqxP2Bgja666TESYhL5atitg+E2u1x0LIVqEWTtegXgBAY0YJ6QBXDdJCY72EAJgUHPCq+4LTpgneyakcVFYsHzwmE1KuhJrPm9UZO2HiWuDMVupsqRNwmkeseoRrFtJsG68xPvPoGq7oOiHPiZPf67XfikXuRZugYl+wcoKebTmVPAjmfRzPfF6WWgOFFkWd7/1eCQ2s9aeynih98+Cio/LM9eSIy05wZSsuWNEVSBv5/YTq3fLrE//qAJMN4+39OMcU3r+0dkgp3F4u8uS3yG2ZQsXhAUYrPX2903g5l5f25aVaBpfwh1BbGcrW9D5JKJ+XyJJrTwX1PPwPKzOFsTxl3EVaqT4Ibmj/zHtgFlIhe8hylgDYqaOrLx2c/GHUwyd3iG6lHhq5J/IPg7wottLHAiUSZBip4Wz7TTVskA9KTkwURFmfMFRdzXaoO26wo1b3xgSbVttRyWBM2ST1WN3vR+tDEB3HTbQHGvdEwZeVa9a9NA4X9TOW7TYNxg+Nh5Y3/77uN3g3OcySunfotssuM9gXMztdRQ6ji/s7A6ZZEawbyb4pgjfuT9ToYGnYro8vIfeUjSl9t1rTP8TQPshH5X//caP5Tg4QRq0Qnl+ZByGGIzeVLsO1JQXhP24SD/Y29iGvoEoe1nqCr0MrFoxkZ9rvk9vYEveb6AHQd1vuiTcVrTrwlWU0rXK19o5ZGnme3iLBpyHf8WLju4fZJV+tqnTQFOjvAkA1+7WrFvK4XVyGizj6srhMi1ouc9vDDvpY7/viSCgb5GeZ9WScsa/nwnpTTLpASLm2SeKAG20yKQd9dUyARoa0B86yLojR/J+E9gXvqbTwEiyZn1LIEvx/QOGsiVZFIRkGebgAQIoYrErMp24/atlmJD8nfsIBU/F/y4JnPBWlsBogsJsGMnweLvfTze2bqVGmVr1wSYNfwUIjmGrgscwoA/gaYlV4Hew+PHi6DeHBrgo2HP2RgquPGwBS8YcZ3pM2mr7x4FzN0Fq3yB6kX3BEN3kB50Os8ZWOb0NLq+ibksDZAXn4RrV2dt2ym1luqCFTNJICBJHFhfigLRyMI0QJOEahcGKvhZBLZL7tl85zCeYzI3kKhKdnU8k0cpfkf+lUyrEnPblqB/KehMb4jPD5x1bA1JQA8DL67/fMsOtJjj9+Gw='}}

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
