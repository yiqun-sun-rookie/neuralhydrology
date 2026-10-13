#!/bin/bash
sequence=274
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
Q = {'sequence': 274, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '9299e94791c572c7111556b2cf5ffee6bac69463c63c37b3b3fba5a393a409c8', 'ciphertext': 'MIIUXQYJKoZIhvcNAQcDoIIUTjCCFEoCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGAUObCgyUyzjUU646wd3AM55CcZXlNbsUeRTWt9Ip7zC1Hrj9agz/7wc1+cehjXUS7gkOw1H19Llyb84sZHX/sxmygJ3RNn3lhErslIaG+kLXgCUwjdXX0kr3v5hm27y244PnC7588ueK1R49VvpfVG1T3c0wAk+iUya44f8xyTX3anjIR3s24SKCwHtR6wUZvtqmcqsXYqsq3BLpup8b+w9TIyibDiFGNzd/mUB0C/4TICqgSbSnfF05y6PerDZMkEXL5Npfuk0jOrQZJFpeVj3maCa3pm6gx1h+xSjiLIxXzw71HgiTqO819DHzl9XfzOEYZsvAfIR0QYnRAYf46UVebn1u7vvlD2p/LsXlk/Asdk2Qb34ccmPYAT+gg8hk9rbkp2VuZwbaTfsfPILkaEoV+2b2E/bAEB5NTRVz4BIZXVvo8gGx2/3ow7yM7S8iCzMvajK9ZVGQp+ksNM5Wi80mBiiVTyDNb+M8of5bhtPdxSFsiu8t6fr1dJsRX3o8AMIISbgYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQzL1iaiqnyKcoYaSwO9dwfoCCEkA9dLEqNhZYdI68cyKuqafUfKYLY7N5YdQ7xGPu4i+blStv6tGKXCeh9rdEeAUTKIo1/f4KcxvpgUUSoYxYQ5MSLhbSnwhAcY1Clwfhl2Bt7wlfQmcf6Rwko0H0tkAha2MRazAZs1g0ZKxIeNLVmA4vBvn80jcppkHuNLjhDcdAiHr9FC0AWumalUr2vC5ihGGIKhnByRfsMwa5Gh8miJKrb43vtejGKkCOaegg2J0RvSv5EdRV/4kxFJIS+XhXNjz710Ldcpnjau/t7BWkpQV2n/dBqp24cKX1pnxHbwx3SMe7gTWwN6VEzmIsd4pDHiHUV1mYMGGATrDsDo88YO1iHuOoEJ9Zt4He2KrfcSdx/pV4oDzfEpH+CsH0x8/TsPT9jzLHGTEOH9WQfCZ61mSQ2gpdmucoFDA8vWvYh/SAAh9sl5uy/ECHjnfQHSWyoDLOowP3IOdcKfyuqky5AfvHjBrcYr7dJK3rseMjYFgNQNr6KNvVOobR+e++Az6QOal5VPi1ZK4RX+WweIBxF21fF3UGWNHBNa+Ros2Hd4q6VDfRw8wAV4QgvmbWWbzr26x5A6/SNlyvJ2A4gp/TdZzJZ+aeqFKnCvExHkWK8l1UgN/h590wolYgsKMGGd/cIhcTlrVUYIKlUANOeBPzxEQK7gdnj38R2L/Bqwrgt+hRqI8ARbWlDaJaBzhaRlFjthWzGoVk3v9AmSJE3zksh7UqiS6M4zcsesLnmSEf9IYjklD/drh6YNCA1FCSpJh3CfHUwt9wg0r07hWhOVmWtsos2jIGxCl2FXajrzwfqp764kPB+SiYMMn7xOrWRnC/J6AgxJShL9J/K9F9pSOCZMjl/R7HzejoyBfSwruRLiEeylvUj3054W87mRwGhtJG7rdXuH+neTAoi/gpfCUjfC7IjfjAmyRqusVvaAvvpfSxdIlY875Y38DYUMrJ0CDKvJ/y0qykh+si9Zfkw09tX46bxu9IICs3d39Pl5AgTcviWNjr/7UC+hg6R8863NWIY59/tapdp93CQDx72Zk5uqjommUHsU3HmFpwydCEzpVMQ6EEAW0YKGK893heyekv+V/47N18OPo2LCenmepdGWaLiHyiJWqaASWd4OFvvUkN9lIXdeFE488etWwiBzjshSJkS1wZt1irNUqWD2jrfYa/TxQ/ATUreVTZDjBCBg391aQGGpQyTqMu8X1c1NXhDvcigB1SRrrWPb9L/ZqNHqdVpxAQ39vYZmPiW9cXrJzSZ1eqbRd2OpT3fOnHTUC6JvN2/bi8FfLFY6JE8////TnEB3KXOLQr84dXT2a+rmUsvN7zELHv7CiCVP+6unqEELsudoTB7T/vA+NoxMPpiQoF8Uu19JuS49exXjXVNOJMZPuicOdIOzAYamOh3tircJCxW1Z13TivHhnq+LgalGEF0CBFKToghu52Fh0mckh6JUGLgQXPYvrN249lB53cJerM1qjdEs4ikJbycBKa6ZoPUBAxE9e68QS9WMebSAUoHJE97iUPCDsBvKkFZJdw2gY8gtQb2SS6dROHKYPnO7dccrM6PUxftM8hI6YMw1ik9iLVWwwUR2NjQPAAhABTvOTYbT4wcMqOeujSyYdLP2zhn9L8lj9hkPsfdLd4uVLd8+zUGo6QhzH1MHxmZFYioinwLpcFggUfgLOLABNJQdl94+W3xxX8KiD/Ruy9ru1gieproqV+0pxBeHywWzXaiGUpQaaUaXGr5XjLGS51ebCUY58hKGgkwwyrDtquO+ccKC9G6V9g1wLH8uPG12zX1+RIy4WoF48aemVV96sm1in9PsmWyFFQdyZq7FLA1npdmgy109Lza/uZdYbdMZ39S2h1CjqAAyl5hda70Ynkwk/9SVq2xG3j0JNYynrJuRQXVlT2rqpfWbiidNAG/h8wSOvMJGVKlarkXez+yStIIob2zy8yQ37K2o99HyRMWgIZ5GsvEs34B27iRdYWEjbQLhEAnSpCr92eRuetsbp3oO5JZWeDGOjCGKSJb6hTKl3E9gGcuhI/asWnmqPpos0QKH/fDQBHHIDNdkLAuU6f2TC778EyeAYX2QXfMCWSk/hem5xfF2EkRTo+s9TpnPxzFHYmKtD+Qqhtz+WEDgXdyLeQeGmbCGm1I2dXn2eJtfQOHxPMomlY89EBEtTzW2UcurWHPuBxVfBHE9XhkSOiYmVFfPIjo6fk6Qq8V0/w9A/WNNqfXlQZWhVEdhPsYY2lBsi2k5EybwHPZnmTH/j1fIG+PMT4TVtBKpv5T6ulndByyRoI2tByzMX+xGSpYxy0DxzqumAaoI/N+U96LTmuZzOqxyM4mKhz9wvwF2+p4N1cLhD7cShVy3XPvFj5b8mZfV8a7qBIM3/nmDCkSSBQZvbHZp1b9JN7zlgZM/xN5P3g83k5CUPsoVbQE8UFpOUwvxHOg/zBgN7/GyVZIeRPR95TgwntwVbzYKeuYDtT3roXM2VLAFI4F5tnqmFiWZrCp8TQgCohd/98BMia/RUH10uL+1jhg7gRDqMrR1RoFU4HkkCpKL/33g7d6s7Beq/ocNqrsLIWyDfrBwiiaiyeo730gpYHMoCZRBJe57yVN2j8wGuFM9rTN0gR/UFyxA7RD3FK9hkTCc+NN5xVbFK+PJDSNInq8vbNmlmS6c3ojebNtOGKM1izoq3ywZCVMl+jOW/UG/ubMYxl3rxkaOi6PCFJ6TlxR08FxwIBcbZWOFDoWYgn7JjSsDmQYhGQCSvOYgGaBpm9TYSSipEvbL35GdYCiEWHlKaDhDcsCirNR4Qk5BwyQ5YfPdGJstKtO+4lecvaZ/Wko09prer5vry5NHUrGTo5oj1BWK/A4AVGNrRb6W+5TKZdz5Oi7ejOLGfaHpM3hyCjTEOZPDXsPg6YnJQCXdxj4o7igE2JbBMyswftETDTZTBF+9w2NKv35jxpM2amr59ar33ctwpweU7WCMu1EEzjxeqpizBSkz1uPY5eBxK1lboZsxMoZBJyQVtkIPFSl8QWk3Cs3suZF1zEKBQGZHLJPHWpRz90XZ3rJAocAhmYVCMg4OsdkOOJioeKVxbfw5VxsXbCduXH5koh+zGoZGqt5ZhbHhS9Ak+CpWqw5KbpKnJGI1zeUo5qlJsojnosVV9zFa2zO6MvDJCbt5bUbFJW7PSqpV1P8vAaJ7U81MT8uVxtZBhm7j6E3VZKZZ5UIumhHQPtYzOMDiJrw4OKuHVKaBq+lGSIIVYwAQurcTSgFikBWjkblPOu2/UD5nB42ugRU25DteXGbA1mJ1QwnV0WYW3SXs0w9kpXhXpJ+3ySmIjNZE2SW2KhielbJy052rlkE2FRW39XiPuw8rrUjI/wmexL9rrRo/gTJt1c4PNpr1BPhFnu3ASZHzljblQMpiWLH7d7wZEMt8bR9eC7WWzObHJzwy7ZPCmQuzlkum3nHwwTKG3iFXCSIm3/Pqsgu0VEf7wtcY4aeZjUwRmJy13drBinQaZvISh1OPLeeuSk+3WBicH4vz/FJWxVB2YdTuTMslV8ERRiRLGQn9mpu7qaGz0drLZQgyhJoCwK4dHaAxDm4QPThccjEmmd48PjK9Uxr80qMb9aG7pC/Tcgq9oGZYsaxo3pHFjpdjccSeyFx+jBDiXppjnO91tjhGCOTY4cHQMApWUO2nTGLPHiqP+Pto0sIBmehwhMKobgkx1Himqc1IJOeSF83u39VtQq3Q3UJMwgvURud65WwLkP26BxNsMyDpijFiOJsW3+jfbpkSkEBdgAQM3Lo2XeuYaCXhiSYS34ezNdAukWcNb8AVQt1oDJrCv9Bev7S2bNrU/aLGSsBk4T/yva40ddH91g+g0hKl6pAQC8O2ZWtb6EJdIrm/DtO7SprIcueeUhn8O2KndUxkqa7p8zuQaS306s+Ix3Osi97/q11uufd4pa4I95/0DoWX4m9PzGfr5iM/FnzCfNOxhgSVJfa5XLF3NPpFJqrZJ3Yae8+VkzAJsKerNv9z+KY+DKgX7bSpUCIVn0NjBkS2VQSctYRfcGIy0OEFDE9cD87489oIIKiPkW2IZtU2b8IE8Kh0xf5Ew+8Ekb4WA+VJDjy1sZ2eykYnoWphWFsfxG6faZ1ieHjYli32zKrluAq4L5U89MXpzctdSMVz90WKMMAlQOcb/WgoK2xXcqzVYLNqsdCs+A74TEGMC+S14Z2TfeYF1Ks8YSDyGK3/bqczXewKGoPu2hNxFSjmZO7pHerQj3GUB7UAORluuUnTozXpc8EQnIgBIQFSPRNS5Y1fAzCP6JEUQNA0TyTrK9bZECEN1adktNz1H7SZWj0IJI4OpKfiZIf1Yt4hatkl2Aso3qeDtI9aXbY5pRrMrLlH8XbkQEvKvvCU0amlIkK0Ob51F7s2qvOIeovgi7UMwgGKDlW5xCcxY4lhXF9bkbwSXRyo+SDN3yfwXAJ5WiOPTcUYkola2/A/4tKusq3vJ26QHNs9bw3glmDx1aJre5FN9tmW7Jxk/V2t8V6Q3iupZYAyFuW5ZJXsAyuvL5mAmJdNiNntLBg0Y+e8cFPiVrcPvJUeX7LC80iw5LxxufYCHokSBSdMgYDrStwGfKes1o/Q87vPxUL20NplFwZ7x+5g5WX9x7PdRSjyRfg01SVGbFQ11JrC8SBnsEwCF5a2ja9x4RHvGrvfRNcIgZ+EIqjlX7rILQRlIs1GTrLbYtzeGfiGFALXsUMAzY4wxy9QiAyCWylRBakcEVdXW4s17dzmfppj23CcOxhxujseZLkINZGeNPVRTipODY8CuKC+xO7Znwlr6/DFsk4vs8QHFh7e6O7WBn8wvEi8EXI3JBZyaWhyUoegyh3f3SzDobq4zTdy0z3AeysT++4x7KNqKN3tGq1x8Gs2AGyHfv6yapcgDaQyVrdulj9aRRCxE3IfFyd2dACVFSbdU1JvdxQScp7Q5eCcLgA+7i7pRZi5G3zMUAnByeAr9KnQ6YfTY1XPS0zN9cE+0TxUouqbckAXNMnCRTMNozgrNq2stNQyTyRbzHqQFcE+4TWRdyTrOhmNZqp5YSfzk/JjbQ2KNPB9NhfGdhEvbAKFBPON+LE4uQ1OFneKs1JYqlPaaPSWW2Y/BaUVMksZMion2OR8V7J6qUUGtnr5p7/QKz+WOWLCi6iC1/SRIPsz2o720hmNafnWti3knRs7ZPokcP/hMKFRJTraTsOvAwvzG5Cy/ag0XMjtpuJgd+n8krH7PyUTg3tCyNjxAUfaW6cIXsV8fY5Usg84zqLpeRLxvU204vngRHMgG60Bk1nX6VW8if2ZHd5tNFhKLXKHwRHL2DV7/GkU88Ht0Ln7MkAvYrKchwoNwlnbapYGn0SUhDyXHt0IlrZC8Chaa3Q9YcB/v1t5MIy+2EKYXyK3OVH8Bda3y5uM1lq5lp5lynIdTxoX20ROxG084KYKh8lGjZNLhYWe9fdtLtQ0MY/6layl0TBfKNn1O6aPws8JuDoDWb4B7xV/HsS1BrlAT0cdYzJ/h+Um0N9eqz9GG4z7i6wnx3yAGvX9cpjwxvKwhlgMl7FDNknB1pGzlHP324AGRkZD3Ms1hwNq0ID23AuT6TDLa24DKMLEJYBqU0n/CXa2j/AOwNcxheQlg0JOgg37KqIFWMDsusuUA2XBlMvoZZWYXxfkD6rv9LPdTVBmKZODchvny/2X4BW/oQLnEU8w2QJkICJ8eLbJWYII+jV88nJXpL/BPz3yNYxONJm6lBMZ+mPS76u96tz3y2gygSvHCGjnbJ7dGmYSLcp1Yv+gaFsgKPxOtEot5mNuHnsLpcHZdhvoFrGFlq0XYeXJu5b1Oh4+RX4FhhEyfO6pyEfaA/QpP1UDrpWVv9rZyNVjt0w9zbKCqhjRcEcTy66yiQ65ABnFYQTZKbMS2xwCiWRqVxt8mQ60whvLlJgaKLDFUBceZfdHqDBd5TZa+kmj1nwKGDCES5LQsaTz+4HGCyOlLurkds0bO43wJNL5GdW+AxxvQjhqPrbF0IhiWup+4DOHXfbBtFyZPNqrB5blseTxaHtLMHCksu6MYCmum8hnypu7QWEaJTdbSUnTIdJs+qoaC6v8nC8BjYPSFtndgcJWSKl5y/XurNSApRsfN0M90+dOawxBn6HJD6NBI3YC1ar+kD1gPGC6I2Bdo/U4XmZM/LGes5EHJJ8H7HfolAYkQZTeCmEMu7a399KaIcwcrd3grIm7kwCJGLRcQyNydvn0B+6tsJWqoa'}}

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
