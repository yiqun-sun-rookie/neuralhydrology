#!/bin/bash
sequence=403
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
Q = {'sequence': 403, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '4daab91b80b9b0f2f47b3c2f149f9e15635394f8b395029d3ab076c8c0242993', 'ciphertext': 'MIIUfQYJKoZIhvcNAQcDoIIUbjCCFGoCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGARkof5pYGrDtaWdceHQDzFaNvrnBSdFhPulet4AZRWGE733qNAOkW4Cr9Yesp88wRI+hqX33I6lSi0cnJq+X/tN2tTgSMXPW6DvNn+Qb+Js0WLaJhHYgdbSnfseHczYkNMbXmsJsiugsDaEvZptmCQn0De/nKkmtFABhEDW+WsoYdi2Zcz3LBjfG4qAUdxd8FNKxO4cxO1iWpx1Il3mvLA8hLE2OjHYzqpwxRynW1A8DHbBcykdWem2bx0qMbtXpa6sdKEb4QEhc26uloX8onAhI4RoJoCfLQH4u/xwkRJTIwDTPCZahCjrLrUg7jMa71IfpNV3DNj/yEgPzSJWtDN+U6pg9Xo7xhuy0//174UYVsVGFFtxvHiso6glMXCX275QpW8E06SDfS4BS++Xg/PLuSBXKudMxStixQrpS2lAGMTs9MwjCGkRDNy2pxT4R905BxmvdpCBNHc5T6qVoYKCop84IkE1nkmCGrMl5pikk8162ziyeFfndjZXWRvLx/MIISjgYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQiHFJz4yZF6xxsHrGko43EYCCEmCM+o5KWDh+WvtUtqK6xBnyF7zB2gucR+Gc9fCYFWIIU+Jq36fWxEd4s7K2DGUs/zEYZl7SlBsDqckv6SfAU95uwn9xGSd+2U1PC2HZWdX6lpAHJvEF3Itnhu/oraLA+bhbagwx338dnLDqXli+OSK8JEeWbMWbX1HUnKRRwPrh8ESUDL8TguhDkpI8MjytlfPrIl6QjhYV5jexlao/NK3PciOaSZb75qzqLU71Qtt5Byw+jjP/MRitJyzIKbR8t2O6fwqXzUTj5eL+TlcRITuurfvfOZs/iLs/P1zyraDjVFyv4Gn7Yh9viqSdunu73hYkQCgkTAqX62fZPWkLuocWfP5eJU40HCONBbkK9AXzEsAMJaHAJe+Ti2sdPp11myVe4MKAhjnIK2tc4lJkesOpF/CtYEOOS+lxu0cqkO1oTDAF11lgJq+KJ/Es7hsFc4giiCni68arobSagOhCgkaHCczWh22PztzVi8pD7KIFsY47wAAvTIVk9g1jEQeHyOv1/LZQxhdSIt8vcobyJRg0N5MWOGVcEfHl7B33cg/R++hYAKXjTIm57XiQn8GHWr7OxbtzLkgqANVRkCmAjq24lvfVeo2CoG+vceRCKkkKb20uKoWcVqOaqmcTt5LCVK7JR2Gvsv2zl0LYFk2U12b0krYO4df7U0jt8nE9NLGFT81Rp7S3IpsVMb+aATMzEoj8VnY3d9D2l7S2TtsPmNEjBjYfIXwW1UR30IYw44uLNGBMrSlHXVKNdPqBKrT3ZON1RaRs2M8kYaWvsrCobL4jtl6BVsY4NOL5Prt0fsn1fRfo2xxJOcLYPcxF5Wbt/D6hH6w7jazluE0FARz1+GLnEDE7LTM1VfjfG2iG3Q0b0DTCkat8Gb28e/rkYrDoIpKhhcUfCctqGw3W+YkjCtDMO5Dgus7RkFo6btVVZuLGwniBurNN3icMCrDt9sdYjKGphgzS0HlUg5HprN3h0IZaTvpPo3aIm1y23jVu3amr/Ew0qZJULlUEt8cO+g0RJflIy1TAuonsrYYH9fOn7M4vdRM9fwEMM+1GiKmyfrura00kAq5aIaY6BN3PgFPOzLU+A3BjDF7NdJF8aMEzU4I3orfgOgKn20tbuXy3NfmeOfbaGaKzJcmm0yYbj6+zWpt5+siKlQ4BtxvQ8BAx6fCwKBvIV2IE+GpGKqukDNXKxOLUrXYs1uP//vDoSx2fsIoh13vjl+otNjYM7JDPU+CKHzWWhN0zI3kPq2N/VH7QsuVYh37DXSC1icr8/s5Sz/NuldptsXkRgicFcDdUGvlFFv1OLlZE9dzai7fY978OewGCpiQDXFL9MpkaoK2f0F+Fid+MZ5fnB/3oB2f148FW1zbnyhf75lcxCacGQ68LyOvXsQYFnkjOB8X/aJLqgIaCSN7uNswGH/8HsK6F5W2qtQTWZi26eydUNnld/NaLmMkDxY7H7gkNnuip+SkSc1JfXKr+tqmvYrfjX1WUPJafLdiOawDbGdri/x8eaRSPIaN4+ttgHlYvuWZ2EYNClg6Lh10pZzP3CnHMAm6i/TH6VMMV2KxSzQpuh1SzwQNAiuUtm+ZCPmV9tuu8KyxK2qIeGAuFDvegeNEzuCwRVHBwuZX8ZVn0iUdoDmwNY3cyXmBq4SlJrdGBARGFwwRQM61WRBDZ0vSM9hgu68k1Iru0cNpQaFLVrI2xyjLKawThX9qz4/TjZixQZRdg5hYIoo6Bnb7r5D2VNTOklRCi93AbAPIou0YzC2nPqfs95TTSgNZvzjIF7OAf3oC7tYLnvv6tfys22+QHnEjKtEi9Gg/q2tS4LD3FWSBAlUiMFgLQpKLDcNc922Sn2kNfDZfJLPI2ZGokQHHomStR7gYb/iKHPiq51Ad/8u9DBzGrAVH8IGUo0L9sQxaXIQaOC0sJ3aQC/Ifa5avfXQu+EYK7Al7d65E3pXZGV2RfBSCOgNSEzwEkaR1lFAFnppidrGwl6fw+ITo52DzFNgYaxt6JS3QVNP2bQgaf5bN/3g5HaLZKX8XNdy8cSSwAmSxuUJDldSwQ+t8P9/80h1ZStQ6TaaqCFfZgn4Ur0t4qObJT1RkTb0oGhHhEfDRpk//KakQA1dJysK3ABU8fUtEwlTXNaiU8BCmYbz4xCeYpTVNpgINV2eFahiqy+3WB8PapnSWpaQcAfqWiC4TkUzRYLLtQWlktl7HWZtSb4Zk9rrDtyiei9X9jveV8PRKSvE+bmFdNYEcavC7wV21805MSIdoZjFbL45vmWFTSjlosrMwyPzY+6SRI45u4wYlWI5JwqSJOX5ANtVA+n517UbmsaGmp7bjpfX36pG70inDbyrOvesFpOK5uxVHvZ8hPLhOIoZsef5nU9qmMITiqDOdguPONqCUum3XDxvGA7yFZibdcw+IdIQZ8idRytseog6Jr3XbMUyMba37oQ9RF0pZl66wmSGqjTUY2kQbI7vP7/kdcWQFkcnDEkGIMHQn1EI5y1IghFWxsVNdwsur54EeIyEdUC0dcyR5a1pWnG6k8ppckvwENGfbAKc5VVdf77yl1zofMwkqwUQrNSeqKegS5lo34vSb54UpqNb2bAyUvKXv9t+eY5uoXxqe+BJSDmkds0j24IyJEuMihzvaM4GCYdMOVDSfpIAf84WQGrJ0JcIwU8lnEv8oozis9WEPSvCykVJPgH2PaHweQBTVSypTXSnrGXQkNzLTBkTPf9hxEUnpOWUWNadNQ5wqPPLzjStzC4lljeLihQy+NdbbmgpsMgQqjAGcid1CYV3+KxyrBELvhPulcIJtNdFrGY2tuOnLVa9ZqyjH6OxRAFgMVvaOX1BV0nQXpoPu7yzOlzXG7LiWe6YVFS2Aq39RNwvK+fYg1P8ex80hsrfdIU/Te8tWk8Xw9PIB0QbW433ZidDZTmFncrdNIqXwoTt6b+MATZ7MQDPhXl62xZlSovb14UQTHn06kTeXQsVT/VRKjGRHD0inV9Dow0oUuFG2mTy2iEubw5cX+eyvD9Mf9os4JxsYlV+YiZMQ6GVk5xF5aTgAiC8qcJtgNrdD9Bbi49PbXF/Eo9RcJEPyIOx4FnDKELjbHIj0ECIMHpKA09QCAtla/zR5voRLJLyXL0Y+tA0WfAGlUhgVqh9MfXn4Eg8qq8ve4Q4Op/N6fHuzrKVbW7rztEJ9tcQ51czb1phoYC/fhQ/z8Ahbe9qiYHjLubdRF4KwJuN2xgUZneYzTqXe3JZwsIVjhmOqb4YSULB9tykLrusDv2J1UCCOWqcExpsodbpGKiGDz1ANOJOzjs3u6ANYHH9RRSsZv94Hebf/dnI5vqFA+akNu1kLU0m5Ut88B9SkK4XAItFpj1sF3jNUSSwN70J0kplpGWQONOFq89Vj0c9iyB/K/QW6GubrwDtAO4hXmzkEobuRW8rjQ015xvkjE3RM0DwXFz2Jh2CxCV8lrxuj7Z2jqctWVGaOnapY+0bPaB6uzVXGLiIcn35VEffcPiJM9RSRoyRsGunTT+TJWqUzS2not7GWumP9qiaEZwfO/Hc4Hj1MpRqaoXzMsxPhfVPoYMyWTobATpL1FvTKl3ljS/K1q7aCOEbPSiLrx+RYj6GEUNbWCL4IJvokSW1xVwTHNywMHdVKrlWCuHd1Wu5kwb6wbel++I8ifrb55SM316zAgl0pMrBgyqlZKwaUbQjb9Laf3XXUhayiOup38+pQ0/5KfopJvPd/qe9HOQ7AO6jREVkUloCfkGKQOCB8CKev77i0DtdeLA/3DRKTX2YQ1fZSkD3ZMriinAYz9nFpKhAxZdYfWuQfFznHu8DKaKiNPZjblX0SQXZTKXae18O9nvvLQc9Z+Nij/07+DUZJzhlGqZDdJpV+tDpcq6++0HjUoFIepo+YOeYx/QipEUuwyeRAAH5pfS1tkROB83jYNnKfAV+WuNIR3zkcvSlBjhV3gmZX9ndEiDrm9pCM6NjPBLjK8s7bblvPp5PmZ4Q2KIirKJTyOt2xK0AwWqSdaB/echeQ7R8SbrHsAe4m5JBmT++vyEV61rYVb3nkb7snK/zQ7O5d/x8xV/cr9wQvwiHZQm6M9/ry0K1VL/SKSHFiTpOlRkD7I8KJPDYbsCD3JTICslAswPiGWzjFNnoYN51RDXEF5uh7+lvJy/h/SqtFfUkw33H68nMEIQyCo1FnaiYjZXb7TFqKRK3MskaDxka91GzFCfsDe2FY9PdmXl91Up0XlEwGk85ej611Otn6itP7RnHP9z8whUM/KlxNcXHja8A0uv0SvR12siFQ34Wa9LYHBYtuLVh/5qmsIHgMXItIUlOIbPUTu+DtAr2P/YgpDJaj/eHxPfZ8zP8csUEM5jnvLYTc29sglPAcH/NnY2Z+dDRz8EU511WgikmKt9CV0XkpmXfkI+dCSwl+Utze2HSvs4gIYUqLiFfopEJeeaJeAVxCXGXWxQtjV5L4e5bcdpWZo9gvresdvwIvnYvt7N+JDjnlPFB6eT5NlhMqlTcrWCFciD8LHLc79uH+dYfihyn3N6vR1wZDw7WPTrRtKu5sc4mroMhWmxiYN2LApFB1LBbQh41SKIwo2SrEY61Rf1fUbK8BBX31PYh3Hy21Khjt/JafjZXGfHgQTCHxVJj99nUkDUO9Xb1cvrz+b2vofKzIahFp7F6EIxr/nFuIJxffROa0tv2+BLUG14Ni9pzNMMl0jkjThpk9F11Hn1BUXeb4Eu9ay/6Mag/OWFb5hoF5Od9VGT3C2msoO9i2V/vBOTEABNlcSJOsSzmKlatKINAk1zA3EcQxIkJNvGViSG5kvKop7yeq+/EFD1gPyKNU8+4mXFjggIEobUwKITJ0gut1LZJBMHeJGJPwzmQ1URcBNUQdygQsbyNkdsNFTUrMqVMDFBVQiU7JQm6Y3jHDeOYe+KqJcqTbsJodImRNLDW6eLe+OyXnFF1hN83dnnd4ALk4C5qJInRwnqlSu0bQHsvpxAzJUtU7Gux1ulN+4LMXvEDcxmlgMk1vbT778H63tnZ5JhCYMMI1Z84Nyf6NbW7r6zNHFgCb31Jj+/B8ZPYkEqkTgvxtXmiFdHlJiBQHdGSqBDhQFt0TnJqdgNlE84mEU49fKu/T+qZBXLkLNcoq8fZpc3QEA8D31U7sO7TXAco1Zzdkha3G99w3mmr+sSqFa87jryy2setbAGJTxfABVKdbQeAPwVWJBeA7kQYb+4ZHcp0lNk4XtrBF16tsG4Yld7IdpwX+5c2k1buAY1AD2RH2lbZRpK18no8NvdoZGU9hHLCvDdsVz42yn1GdY7I9p8pTXWskwQFW79cQPItKlYzu749HC1+rJKz4pJrcyIFye3U9I6+nbbPVYCvzAj/yJbQddeJooL41U83iolwZx5bL4UVVgsYNRm6Pgk48C4EYrufrBjQZsTkFEpsqryqiQPq7E2v7xmRzFpMFsobO2t59Ie0r/SNTvMelMMoIU/GGM8Yu73C7GwKOE7hAkmM2D6pG59i92ss/wP/0/1E9AyIzio2QpIRK/qY74gPHaMiHb8EIt6lFFSBXdXqls9TRcpZiK8ZvUPZDy5w4Zr8nm+4U45C+rcrD1L/yfw1c2NoKI0o15OG40ryFZ3+fY+AoNro+zvRSHU5OcjejHSzE/trP3k+QRX9kV6PFd83g2D/GgeMVYupQU/QwlqV3G/4Ymyqg/tlxboozS7LzXFVNVslDl11aRuXfj4xEPyQzRUWI6LBxWcmfJXd0XY98iqAJukqs6XrsGUvW3FFnMFfk80ByrE+xtrcSq0U6GKsT12hiKu+vPn7cm3NKKGOFwidunjCzq+ZCy0HmN/pHC8DyBi94jo8TfP2mQ9CWx4Z0i57fnjhVt4ZuWxJ1SaMUeZy2jcHmsAW2Q28qYp5lVHY4KhyVTFfOD61a9XmjOHDjkaX1gW4xTWUaBVbcUw3hpiXscp49Ccc4vCaY1VRN1w7ngU+m+p+dJJyt2dsQ65R1kGKaPwhOJJYw+qhiXY6jKNmBKOITFI5n+EV1VM5vba+4szt3VW+EypmnZi1njhf9NUDbdXIw4vMR1HlkiOCItqWAV9NumPvo6jtvcls26MCnaAG6uIdbFbwNd7S7SUzXccrABCP5s4luAKm2vHJzTlv62JUZdSAh0GqQuVJHaRRp9vvmBJ/ZSQ99QwP30R/h6mFuZW3pCJQ1orpPZ8G1G9ymqSMPv0Y5dh9HmyLJYzIT7eeeuUEhrdFP7D4g8X8g21dwOwPcTM63BJbNcuNw61MjtUaci8CRkVexP1tAW+Ymwqew='}}

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
