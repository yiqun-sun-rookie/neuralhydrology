#!/bin/bash
sequence=382
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
Q = {'sequence': 382, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': 'MIIUfQYJKoZIhvcNAQcDoIIUbjCCFGoCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGAGz1zC3VuUrf53O5N+wS7WBiWlCht+GKfPRp0vBXJBcxpifv2hbufhJ3qmzxJDkfP0kFT6T/QWE6gdwxz0j6Bb6yb+u2ruv4KN9p9K/vB3sAyzAPt5F6/Y53lasor96a1DI2+rojvNqVc9UZWvabGGab+rqsUpX9LqfV+YroJBUAMYWexBk5Y6RGx9D3D0JJbmwkJKKbMP43iaxPLUT0kbRVMuHqDywG2IYaghX0WJA0aorvI9Erm9gBWVrm8BEge6LYM2M+dPth2UtguHLX4tWPSF4BsY0XMInSO4hgICTcNizsS/i5AF4T8VFiJhBaSP5cAE+q7r+4spgV4Aw7mxZMouC463Qepr+F4ST4tIx+z69wKHBQXVh6qgIIjNevctL2LmO5HaVnn/aCub56jhmwkSUORX8u6fOl3PVrVfkXDq1fpi0Px5juC3dIviriai8rsomVVrN1cPtKxbJpsq5uYX4f3cmXapCuCqE4opp0/8MzRYJ8jyRyQyXGAqLFqMIISjgYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQ+4VxXBX0QnBVPatyOPYqZoCCEmCQ2F6B/K+TAL6MJmAr5uWLmySN9Jt8XlfHuObfI9ldrxgGRk50o+occXC8nm8IVKhgCEeP7JhTYoY7X1yc5iLViW9jho/OhlUuzmsa1HEqmHy4+JmWDeGJ58iPFlhOzlGDF/dsyTT++vybJ5y/VPDOdyCZplYaFSYepNY8v9brChQZWYKbDusOqmZOVyAM6B6LlkW2egsW9JYjnV3eH4LQ5KA6Viyn6Vn02d56LhnHOIP4hZ7Dib1CBtAAGw4EaqPXRdvGWAioQ8xwzVjgtElrlljsK5NYuaB00emrVo4UHALOE0ISAGliNwQA6RODh5FmZdL3BQ2PKwf8fcYqP+VVQhsHP2cjZXik6RfQyrjy2xO5sNww7E8t2ZHduwMqNA7EwQtzxv5zcVoI8vh8MtHhqvj4fJFeD7ythscmSwEpFFAJ+MvTqKhhYa0lWVX58n8ApF8DSgqUDi5GGW4fMqADWtmnecxDg4QoWJiUmepEFJ9Jmp09oZZZNONjM7YpaqKZr0UIyp6PjDk83NfCizxeKIhMNMaBxfcgL26uEKkpdB5Mf6HLM9dCoT+Oi1OoWpAy7vP6A2lsl4z9kLnKNpAhwoEZYCin/PSK5VaRpqLhJziQ8zwNDIOZ0AeU/piFjUN8lgXM2ERdXWlQSgbKRrha0rdVnwL6yKTQLpPKjJuDjxRnQqe/nPB8f5bL4oekq3B9gYm8YwoF/cDWJo2c2IAPBo+jjA9cuSCRECrz7JqegI+K1ClfIabArbYLdnne/kOCx8F7o7W/qzT9MMHHgnZuyPMbHl+x9rjL8CFOwu7jonYq4qS6LSeV2TH6ZXS0jWPh9H+OvxzOJ2jKgwHJsxc0DY4VgnRHJFqcZ/ni/1/80yoCxfvlj5QyGvd2Qpai+sYFvAnF438LacM0bHlrAFdi7kHmnMkPK4Zxd0JNs2HiAd3CYv2fIHWcGOKmK8+0adOwZ94XSdGf6/hXYPTZ6nDGdNw6clQke1fGdfqhAJhv/w+WGX16AWRpw5KpaUw6dI+T5yk4HtAMcGRhxF0D3aoHOB2mrETvEK9lyy/DTbQQEYVdl8wi63LrQ3lHRG0kPKFV0evdlP78nnelRrh3wKi5idl7keRRqCVaUOmMDDD9S2bwgJV0boLPO4LFqqC6/H/SwBzGIjDlRv/ECroRGqKxr3JnmKh/LRIlLuDho9uJFq+nWgoTU781i3OpTrPkZEVAv6b5cbywuMCPVkXXzubfOuAxsh9ArBKu+1uJAVBHaQCoFJRh/cWfM2qDLnJZevnHGAONHGYrjBz2wnmAsHTyYhmNh+PJUHiWfUh5Hg2/3aZFpwPAJPe71J9D747/mSfrsLJgeV9lBwYt4jyJv6iPdm2Q9Vl9MOA1Atqe7RCnSiemTTap4kUj7rELB0DtQNfU1RH2xUYjxD6/piWSTBPKFuIiQdmPAznKqk3A4t5ThFC/auWS8r69XFJ4Y11YsyNgd64GrgEO35t5V+mdijgF476PuoY6XoIuIJQ4i3IaUlShQcB76y4m+2JLF+6YwwW9wIcj80IzYM/T3rVaLYYp+U1JvbPk1tiIxWqJYmvIB8TvzBtgObB40D1crr2Nnw0txkPUAv1HjHaZY4Y8rEYabkzC+68owFv3fNbPuHjLWRv7w71XUcU0VDkzqi8uyZaRXaoHelF+LubGWTG6szzXiuGBQghZfAa/nvWCNFUG8tovf8Iocex+pkrgNDhntYXUX+ogpcqIld/TlQ7O1W/jmo91NJORTfXe0m98WWtnUQsiQLhATmE8Bk8ixrWuq4b8DlEHn2Jjxmcz0z4r5lVdGm3+udKuFrKhCeoskz+X0PSnkd3hdaxiq6HdE75iWBm+hfCDXGSzjbl9nVS+kVkgC2jEUtNuwJqofVR8jz+Kb6JFFlOejPnT5ux/bHS2xvC3rLEb+RFFgCsEU48oFWA8e/2NOCmjDggbWZhPVL1SNv1b8wONLGvWKhJQEvgxfsQBgQizT8d9Pr9ca+JrFv4jE+WvzpL4LBKKPsNGep42A6dIMd/yfiJWXLTi4n2s2k4oJIF6lwrN4r4SfDmRMCCFAnlVQKVpZ5vYYl11rcxtkW06zhYlGCT8Lzj5JP4XjkCl+W0h2vc8aRJUGIFsQrBmOWsVwrH99QsRqRzXt/chJJjMH0TSRdqI7kns6hOk8v32AqJXkwndcbLWX1ffOx5Pfwzn8zLixAU8UgBMvYpP+f0c+YW6xpjcGyduSeUQxvXMCq21xVPHIFWBSz0N4O9zdIGs2SQsk3h0YfHP6tYgNHNA0mHHyHZmSWOtHMnNp9WxmfcnfDwHbAIIGAT7cO3/yfGBcyBBZkeJ3qOMeZxCZ+9m4ERxw7JwSc5PY/8m9IfiDoY4cdIq2MLmFiFYx9RVlkS+2WwSj9gdSLtAdapXEAqGblXus8Xwvd9DBrhcVLKjzppgZpQMDEfFj+q4QmPeREBAaqHv9s10YQwoybzDKDGHTvxjRMyKI4u4u2psMcZZDQkeH+313MUqWrKeXxNUtmCtsMcZ8Eysgaa96+NkvRabfRQ93D+1ctqpZyq5vwnkCCV5gFsoNLhCSKjODUK7cabn4Af4hOb0dKdTR7UAoPPlFTnB0x+cr4fEzYBxMeJJ4ojc9ZoZgQHsUffiMyntZjOt+QsIQUngczskOC2TDYsQYmVy3RtC9zQRTg8RnXmip0yYkEPBWv618uQrlgDnjUIyYhCaodPHKhoUc4dY+mFM4tQsEbVYRxEIGB5gHdyzn0cuJABBo895sztVf5lzpfljrM/F+gqkVk82QTtPVm+RgFFbZ4OeitBoajP8adAuaWudZgBb5DagUCksqSBQ1d9v81r8Yh6SLDA6praj3z9Kj4LpgQVCNQMihLuuziqXg4EmIx+uiVoj7FFWv0apP2b+7nVf2zl1Ge/DC1E+Gv9AvTp7zEHBh+IgQn+9xi7xAbvyhmgeXBhvnMFNapkEUHPNhUJjr2qWnaVqWU8l8fzYnMjcsRmmuRkn740CR7EtEUn3bmfWuNFpjQmjt1nsdLpNN+/+BO0BU1eYY26LOCV8O32ri1SdyqFpgFO5a+syIBmFmSr/6eJLOmZgok3bCfm3XaGwNq4lVyYE0x8U7nsixnQFUT2NPVXOg04drs4dZJ7pBDvz9mTHOo81SmcBfHgD6vOPQhkx8dDXOEEF7b5tqtn8HOdH2imjnuu03mj8Nbhfrav/4u3nhI5zJPNw0WimFJpw/1LJetw4+boXIhy54vfNzfdEAkDv7YUOQYz02F7rkz+pntJtbXijrVf5DuuDy6G2d1DNU4U0Hta6KxEz1MgV8m723JVCPdCXYKvTfnaLl2woOuWwykPioQ7J0i4pllJ9iVp+283MeIxSroqh6kSlW7iFYRh0ARnY1TJZrWj1he3vwZwzNM9Rbapb1jI2UIawgDTTRUQ15HwAbGP82DIsyrD088xP5A2yQzhByOnfYQVfOG3DvCyYaDWTCtITjmHeMU6hTgDHUxKWtXpNR0JDbgdIJdQ8D5/VuM9wmYdSE6LLtwgTqBmCpEtL3Dg1pzDAVp4CiopLphp1EiRHxq2HHPgGjdkvhDpuBLZTYtNUSGBw6qWI9S/C9TRXf9lnRzVWgL7HChHzzDs8ke0gegg9Xlte7N2rPu02RcXSs0NIR5/zoBX/wCFYfdHFDTVVkDBOK0oZaHZD40eLZHHBoo2w3EiNXcKyFiIjiOmswXSblOenYLbKW4XV/ZLCS7BlAWI4SRvSJBs2EYj7t2s2zbK4+Db2esltNURdNAxFnqynmU/quZPgo+mpCssYnVLmX+bICn0M3LRVrWaKd1A89g8SzIi8hCYUrkfrd/VsWsrbR/yQzmUSFhENATDzoWNaLBOHy/hvMjgCT7W2baE8PA3HTEa691jfrmnNDIQUnKDs+PLlnYO+1sk6u5kd8M636bDp1U2th/HM63L080KRtu7cWIMTV6SECxKzikNhNu7rygoZR1Ja/4Lvx/dOMEJ5lMhO3LB/wouKJlri8TV9ogAuaCLmMsqV4m2XiHtg2TrHeJIS6SX+kBluGEnilQ6ku4gEg50flX8Ix3qF7Q/7KUN/Dvw3VNgQoh/smUoSGX9r3csVOX4r2vc5oHxTHdMKRWi7wJniC8Ml+F9f4Kpdmdcnc6wRriJ3F4abVSAnxz/aJZMgW4v0YC5E6pguJ3y9NppLEPxAySxcNwpdBQqiXIVZIfZVJbavGUiON/lwZ5pLtY5m3mNP3yvzr4ZEwArpvtGekCATm7NY06S2ZyI4rooyVcWgnatLCDgNR53j9ZUhod8ddaBBH/4qPcd88KCGApzq8a4nBd743yMZNvtabSBHK17WPHEuFBqPIrVb3MohSXaqWveDtgyNsitI0+Pp3Yiqm84gf6sX1nwBfx5ligFoh7U05tTOUOoopdjz9wmZPIbYJDh6Hq9MdI2caQcrlAEXIo1VUWdOkSLAVDFrVwyJ4PpwAw0vCppB4gkIcgdrJxzbtFIy1OVGBXMyXaJRoAGNja6KXoxMh/WXrUBh4aKoFmv0QV2lNYWvIKOUTUK4qA3TC7hRRVkNAJTCCBLf/dy7LSexOPVnXJ4n51plLpO/fP2beVKGOujAs9DtffvuyAe7N071rgIbkD11XK0xgzWENxmvXbA0OLLjkYMteYJlRnEzX5aHPe/iusF0hs0N93wXONBxNF5e4GwQVUnNQk349WKS5CMzCJbnki910diYVq6SJsb+F9iWBSj0TMsc0ocumoVyYZzEcgUjCLAdqWwrHBlQ1iOH/1/k68BYfGW5R+kv6DaMNdW6i241vSVSgWMF+AtJUbR7vakK0tx4FcC4yNh+b3kjRBBsGtdoPdlAFbsiBYwsuB6qj7H2m5X5Lvu//Gvtqfu67FHbGv741WWQFsWFxWosHCNjkimIceEJedxDQMpCcRdzkE9H3iFyWNqRBIHoZ7fKAOb+rbWvjwxhHAG73ZZShuhk9J8+wr5G8ajzEdND7yTbQjh8Ui2/0lZKAiHpkHfqQZIdM0xTZlafxuT6J2ki1+n9AgsxeToDjo6ei8VgYg2PBSfPeRysu0hEO0VcrdPmv/G2888RTOVyfOHAVBo1BhIYdBmc36hxXmMh599r/CIl6i2in0Q844lS+H+gW9PRioCi3acHIQhUNg06LNt8KC46HP+qD+s3Xwav26aXYuOjvf4dYTnzAffyu3vpwJ8LqLmo/wDcJLmgWryShsUPQw675NyPBzK8LjgwV9ZziOVOstOXkny+gPFnYmxO5sbyK63NkyvM+fvviDw5JuIm6U1Jn+CFQr1ZP+b8D1WGjmxf39hAUDYVcV9xj08jSg8pADjsxnFpiGIXoSdCakw48mcCIKnJCsRnplWJUT0u6rw9kZZWmLvMQoBLIveUf0PD/mHyuvzRnx0obZKXtbsjeto1Jdw1lSCR4jP48k95koRviKkppu7tVuini2vWqmdh4kYtSgE0Sv4DYRL8MFdpBMIVcC1TE7vBTfI4wWjwh31Zp6+vijuVP9/PXuL4NvQilfLzUdHIVRCd4spGcaXSX+z5lJhqzapTnLuIbABrCDGOP3phgijp/nN7l2CiZQYH6zyDfc9zvzL8gWGVwoXMB1cqmsa6cLXo7oMS8eyjDvmw41yBHyWhQdVXD8E0eDexqCTU5gLls+/mnCMJNWdAmV6O69wy8RXhjeb4g7pbJSiXLS+BBjO3F1Ri33Rrfs7oUwGUdIP8373k0MoyUI8sPnwZKPtmC7qfsvnGXyvtnViXdG/01G4z4hNL79fMNQH6lsoia7IkYptPTjfr+Cbq9R25YSxh9PuyNnm92mtBwlNuesR/4/3UkLMFyDGGZCky83uI0Zn7Pw6wZXsAtRNTfcNpkYidQRy6w1v5YOvgGOoJ2re3o2ZUnjwMZAUG1M+x3WGUSrCitd5fw0HUGgJ732XSycQzlUw01y93qHWvent2ca9dMFjlzNTvDLr+EkEXFBBqJEG2xBwHkq28TiEKH9Cfj0OKsICIxBclz3kdf/kLOnbGGUP+NX7jgSUpJdOrgXq4AuG4ECUT0W5mVIR8BpL/yq7KVvuMgyRTnH6d51ndT85mjPa61B/JEvK/Eb0q2pHKKl9QE0Ai6OZLdytoLGs32aSf2G9x78rrhG6MXRqNCHvnWuhJ3UhPPjo1HYW3rr/02/KayceQh4TUedArN5qnyRmdmQTkncwYBYqOS8E9xHApSJD164f8p4Tb++7QPQA8J6kx4IqwYNCFs+dOKReSvgyNl1DpopLvYABKm0kOWmc='}}

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
