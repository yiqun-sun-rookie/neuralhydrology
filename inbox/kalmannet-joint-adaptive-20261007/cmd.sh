#!/bin/bash
sequence=199
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
Q = {'sequence': 199, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'df373a35b9ad5e893edc0b0392e92834056558ee971b1b9b1183f4ab0d71e940', 'ciphertext': 'MIIXXQYJKoZIhvcNAQcDoIIXTjCCF0oCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGAqqIuKBt5VaQRW156aT/ellwbjusKWcMYkpTKLddJL5fYWNAXh/nCT0DRFd+IblYMse5oOjSvbTUJbQFsNkSWoUrdxhDM4GyqnqPNbr1kqv4v1Ljkak4FUkqU7PeJpmncNZJFxq1dRlTDTpKoLxTSeD/eFehuz0IXnKTtQjRTwWGKxERT2z2Tesmrg2OJ0CZVJXY1U9jYyCXrFhXbu05G+jrmYEmQlQtl9d6JWbz4BiWmybVAacvgvAAi+fForx1yMpGiQJyWDzRt4GJQXJhXZIttipMCGUpUlh48KikvEloWqiPhe8C84AqFMqTB3ktYDIFDef+1u2H2ULMN1dne6oaBY/6jvK0ybYYBtSk2fDZIXzXXkrYVtKYVPQnUI9pnjZ/k8Z5QTcHFu1hE07gg8l9OqHm166jAqYtrZudGkliybW/FgVhS8MJHbN4UuIv+HjW1+p3D/stV1s8foOApG+dj7Xl9RSnzB901uyAmA3toSwZ3/eJpsP9+prmNCFwUMIIVbgYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQDr5Epob0GrJVOFzAI6r4ioCCFUC14ueZaZMkSjwT+fKwxsQ8V1Bz5Kx83UsMoM/1ahaf/+Xco/dGQ+zt2kdR5WPWWovhV3SjZkvt38i8BF5Trnjp/AD+qsnofv6C/NVkWkG+2W12+aPujKQtdi9pNhdIRawfT5C3h/MfaCWlP0cdGidX0flX0VrCOqU6CKYVrGZk5F+ZzCyyIV5ea1BIWPyA5uNYfBAS2lNqY0NAzqMS7mhumeiMm5WT/hRdbnLdwNtVnZksbElaOuF1kAM4va7jRAgHrlZ949XknPe6+KxiNMhyDg5iSabUOSJaOidgkXsgbCukWFsubDNOkzUG2hZeN2vo/L9fvyLpEQkqGXSpdXsbn6vsQBqG2QCl6f0l06Z6zhjQB/SdNFKeqyvBw3OzD0CHCkUvz4PVZteJgtK6ox8q0l4nWFVUujpJKq9x5qN86iHsjuzL9HyhAIeeYwnQtTttwNj867QL993dmvuTtBXOivWXf5Zt60z9QR1BwzmIIU57de1bMPaMkkYSzSZioPQlDftdJaO0xsvIOEyXExpmgUCEcbLEpC4S5kUvqAwkJM5sUVXSmaEB03M595w/uyfNwN48x7unCT7rssd2DcVb8rlqSR8SMgFhqbeXoLYso0ZmmvVeAh4D04XSCa/p7iSxieLdPd8i5T8os/CbjArvQ3bYhP3rsW+vvpPKVdA4Np3mGpm6PwBT1Y/BVxXYDKK/YyNSTI3h4UlVVt+WKMb/IKcRrkIxVkq9eztjDIC76p8MqQkvRa7+YUPcs6oLRNjE68JoyAmx6x0QKvMiNhnlEHCWA7+4SfIExchuEnCfpjVUWBoBZkEzajcDRgnntytCcgkHimE2/ydy+ygIvjN10b/IQnzTMYgWLts+K8wginapq9L6yDudt/Lzd+/DBQEc9lYyg8a+zJlYIkHqm4BMNPaknQ5ixwnrfbiyUqCs8txuYAiKkAV2yoNDx0EBv8SXMN271ejaqcboQBogWMz3QtVqIMin2cF7Wtje622z6fosh0Qiqsq6JsCBe3HT8XCtqefGpA3KSrQTE6CBgwKj1XV2f7JIxHMEYJJLv6Qfhe6YhqSsyOL/nBJTo4tLEo0ORchyzpfxBEkXt0hd5/8oT/hpvqU2ZolFSzMw0Qh3zjj1gJodwU87JUh0OHKyUcZCvrXm8JEH0ai+SUq4N4+8wDcsHFoP5YKGV91KS3p56IRo8mWUSdHtLGix0W2M7aWy0x2Cf4U7mm0pEWT0AxAsQvJKHrtDmr4yuDtsY8AotoRelmoJqQvEhINA46x010QccoSqEK4sj8/PVdq5U+S89uOPTtySV2X654af3vAmg4cJ7DIJcieWJN4Z1IqsILPodAXK3mxGKtIzHrV2W2hMxwG4M7zANr6T+VeCDQxsGzLuBMirvKwWnBtm1pTViQ4WPurn/cTwQEWdAs/pikh0naQ085CgheZo+Pdz2GWmhVJkm2qxbxkgWsyJd+4QJ3FvxrMp7HUrXDkt/vxkjuRyLN4esUWYMYDoikVKG8TlGaZWcLmxNKJhez5I9C2Z/AuklbOMcTg5g5CoWrxRxLY2c6TNHEfWVJRE1AXtt0jqMw3D4WvD25szMIR6hdoDUzTOZ3NaXEx0zJgxXFF8XpG2vuv/Y3s3XrThVVTqjIGuSoYvt3oGNjyFdgHWS4EdRsBdRu5/chDDNw1p3R3SH9nD8f7zWaz4jzPDgAs4tAZn1PgJB52GZEL5MyZbzCHajhdCNhlo+AK/8sSk7c70CaAtHNeFoDb04yBYny2s9PB4eGUJ5YH03Ks/z5MRqVpDFfWkelyXX8M5xWS31YBf5aHG6+WP2aBnich/REoKe4VgqLlhtcw76FvlIkpQqrfAVmT0rItkO3CmZ2H44GNX50l1lpIL5cdmhpKvfF3WmUKoUz1+dOqhP4Sb4AN4MrBGLgCKiwiBvi4ZRTv/NN3EnzHUtczsGTynUpOK980PtTESIkN7wq7WiPnIWIL4S5sbEk9ATV2WocxJPK9uI9H5FyUejw3zuuuLbYAP/vITPo9a3r9RMJsb3MeQ5jz4HvjYGSsBvO9OnPRNBp6rDUy27926ZOf1AxrKMXOiLG7wJpW3gHh3bgQNggf/zhJI/wZ9mMa1gGMeBtRHai2ugCD99SrJ6Of7E/N5XnrNfEoMWm9BeDoBaLKFLEzg9juDpkALwikbS/xmU8CdVmSiCPNit+FGXbXkDThX/Om9t2s1jSlEhIQJ5rRhgbtoGiSahSR7YLDHn43aWIpJfbng8IcyloNlBCSTnb97RZ/Ej9g0+7nPTmte+ST2EfSxssyupSZaDsdEkr35Qibj9l8vr+h7KOztzCd5ZA86CYWVV1wJLZVLA1G9D0HLuZQAgE//qR1OeTt1C7/VK9wxOP9KdNpu+HpONs7pU7zUIqb9tvoy7d95Vhw/As7ZP407AhgdvhLgBIOqzbJQTzZga0jEfMZvDM0OYD4aaemgRadA+5ER6t864zOV9gCygm9gwkfEh+C9llwnQyvTVLiQ/aum4q6wGTharoIgI3nxqnFEH52HBWFn9vwKpzRHfjdOr7OJrVIWUU0BrVYP//+ZUOu1p4dMePigatiQh4ejmAPrR03Pw7A62KrLHbZTPOENVz9WhP9uSfvilkUzuV4hlWgOA0A3wiQ4YC8CDCoWOGgbhoC9d5iaEreYVJXKJ8vn9q20b8VLjzWILe2e9bXqcvDv82NbFsMKy51wl4DctKQWIvqB2SZxdxO+dnJuEI6/H0vSrxQ69wpIeBmgVmUNQIF6BmSJ9ulicda7hKVyNhtJVPyYWpbGuO9mvuP1ZK05NYlRS79Wil1IeKFAzRc1puHKn88qGppsrEHNDIgagNDBWJieZIlsEmU7Vd1IQw6uD/ROamJRDlYwlqgEH81iqvhT7MDmyh++bD7uQgrHV13woi4lYN43Me67b9jSLhFphct6slIhImS/yD5IR+7K06vITZnLeajiDScD4M44dIuRDuceDuU7PChwnSIrnRU9qYtB6Gn6af671GmKv+6K1GEQCBi9/teQ/12o/dX532fbTNG8xJds9p3+u0Yf2N2qxH/ET/y7n11E7JUhUiRfiULwEG/JBihTSt3rcmaMQNstptNaO09MqQ7kjQFBHfKNE7Js1XaQtYpXWS8JzNoTWETB6+bwm6P+8LuuKmXnUjIjdXM+WWzzxojRw45ke9MBvuFkNuu/KpTrQL1rF5S2ydIoNh/hxu0aVd22jsunlIJHTCbmcL+hW8e2np4NHvKbb286u+Pt7THBPmPbxCm/2gq474GabffsiQgVetCMPOpCcFSGE8C2gIw7Xtj6uoB5T8oKmm1UsbFNEVuRJnUQ4BLs89wpUKBRIbP+IPyt1XQ/pafAZDqlNdowk4iF6DEzsBagIvsmDGT8NkGCXizmfuINiZyoZWydRiOtclhz3v8/Nc9ciXkCw0SgsY4zbsHiOztjYyJVHcEgMXVlHArVZrbmEYfFXA1yZ1sE9AYFPxZ7mEFRmhHCKSPJFbEKn1fYEZgnm8Ss8+7PPcjwb+zKwp5WeGzEJttKHAM47ay+Uun2SFQ5hbHOGXAJ61ripzCHhL+iZhP161FKJyHUftL4vxoyhLTaHaJz6CYY75QutjEp8VL+E5XR2BuaOp67WxBJUTZ1kgUYE9n74OZsSSFBmMsbm/eVS7p7lMIUpFRhMD1f/bU66XpgBKyHeERRQb1Gxfr1iB13cEEm4hd4mMXHnAsWFe0+fldgzESG8JxGAEOkJ6P44p9nn+AUtRCb+XiJ4Y8cJKsZWB9UhWEYl7QTeW9t56YXZ1fw0jnUv+YJkgTj1YxUd8HGvROoRGl81DqlvjScnZz9d3h1R69JhciB9PGUZQ38XHm9zYIkXb/fmBVl9pSz2oO8Qpms/vNSXKFud44e3KWCG1rrL/0G55o/pnFczcRJ7diMFaQMYEuao6s8+i7nbMXWeECpe4++G9FpU39WDCESZSDPfVgUs3IgfkNbevbiU2rG/Oe747Lytm2bE75rfkvGwS4gSsInsgHt9CLLTixpSX5f01URJosP2G+fPFF4zRFxNu1rK6B8qqJFZ88BRdx4asylK/7bqhlWJzSORipK7hDpfnMMvqghjrJHFMps2fHWfOtxXuBwoWpohX/tV8NXNwNN2z8z4sFpQrL9/97p19BKANATYiY3SC46neSugIMdZ3sykXBgHA4vzjVkAyUFn885WBM2P1cBlJnfwNnIcPbt/rP/fRXc6pbX3p7QvX1eABRZoX3EEkdCctDXNFOeQvaRCDdAId0Jrt4i63yYBVtwNHpwaDh6qQ1D3d6bJK42joqHc0zsFQ5LdGCTBrfInQZ4Xy7L/S5yrcTbUSWdyHaveC0p+dWGm7D/M7p4Rly/SkvuBUoTMJLxPiD/ZP1zqgLJtm++XZFJXQu0i6cpeTbkOeDvosjXKZIQ/PZePOol4JxuSwCaD9e7G5g31XW+wcU+t6peS7Mc277+9sBoSd3UTQ6LYhDOWd26K8Hscs8VW5eQnuyPSN1trZS9nv1OG1HJbnO3xYQcpShL/KX+GwGJe/5sVuoKi1yP2I8vDcBKVPy0YPbmOA68VCfxrJ3v2T1m26XGiMBD+YC1AIB1QdlqytJcEfMWilitMXBZFwnoRCGgA5oaWP4HtK1+PiNnK/Dm+UfeFqSdQTN1iwXZBZzZn4QO2tuKzUuKgzScD/6f/aTVVa28Lvlp0ea1mqh2te9EIb9IGCnidn5ISfN78Ye72+VsrcbojSXeaFNnlRHFeWsPKtYgbJ9uDzgiP4djhSjpoOLOtGpeRdIpKNxhjcj8F9tyOQSkd+JtoWILyMB1d+8XgZC8YW6x8ASjsSjVtlcGrnli2LuiUOWigCYqN0FofQqUg+gOxAJp6QWFzskBlbENI7/XIDGHQEwVxK7NFwbMh1mbpcf6d63sdNU9MwfwcwH54cdOylPfQLKo5ne4+DNTuxx/8lBfhbwe9gOuoouH1AcVaTT3OJxdT7OokxevKBlietM0JQXGTjd8r0xp0IL+8wGcaWgxF2RDk5iTf8cMuAoJMzJbjnqU8VAmz0GyOmsc5Iko7zh+OZGp61YESnIy7R8+5apdgBhxYZ4IQ9b0RXwV2aTs6XATsZCnb1ViECQZNP91LRTwslviulTyybYJHW8W3nA8C81V7oQzM//eNSfdXctbbYX0cEPUVJtpXaDH0lDz3dRpYPwPWxgrQT4bXQ/6MN55CtEOCGcyTZxOnxu/FlVzeEl50KC631zfXbTpTtP6SNPpmaeDk3CHGpCGfQYkbzjFlP2/a1a6bGYivTQMLXVd4ebnC3kRatHTLjs/Sc5CAR3EawxOw2e6xJzubyWt0Xanz1JQK8Qs/QIab2niQeBTMM+F6jlNAZkB7B7KXr1j2DiwQBZURvYQvoWmLHIttRBop3wjo5fTcyCnC+F92HsbcaGZ0jsD4FhbahpN51Ef/JD4JasqpRuV9vsl+CInjzonATiXgaWTSyOVoeqXpDq04wLaW7nWz1GESSGUT6SHnTtu7WHPD/Tcbxj7GkG8d+rYNURgmOjlpb64xY8F3lC2ZHno6ah0enUcHuaXIJgol1MSZIobBBYY7n3uRtKd3H2HZ9kxqYfwtiW5O+HlWexV55Henc9g2BXWHKbdJmZ7r3rntOYAltS9AGHrdl36Fv4CBntpJwwZA46x0xH8BG+XdruvkeORsAqT/V9SzB5bq5xuDs6bchTIz/oZ1G5CDYNpA/w/xVe/pOHmrQ7N6pRlKYJBC8ezE7tP4kZyN2kUrVm8vwkgBwuvem5GtuOKRWT3cp4Yn+qsNk9ktzkTj73MNmeSFDrFti/Mv4q3UKpF0dUXdz3NFWPy8D+mb/vg+WLHi3J5FxJdD6ZI1wvPQbxRBpQzW3yI+jqSiW5u2iwtCygntAqd07GUsG5RHY72Rb+YxEWCOSPVRzRewUebHn6qfZGLY6PltgIe4tLUqLs7uvN5f9tBGIYBtxKzji0dEihrQHMhwm4RRPnr+K78MaBQSDZi5NNDPryUOxfm5jVNBvWNZFeIZui6XNCu+XOl/839POSTJSRfOdIFiAVU5Bon3Ru1yutn+rL/HDN4ZPvSB0Y3dxdNQuM8u8rn7BwcSi1yMtjJhsjbH+eFppPJFSfAdJ0UdrxaZ72xcCmB+faHlvfbI9BQOMbXq8ifda3P75UixcBuKeTG8BQCe+rMKY7t3/GUMBrXRPlKStIBdLao0cj4hWl393+b6gb8tKf8Pn4IIrKCLK5n1A0Rm0hHiM5mLcs/QZ0Jg1ZfyRW+VgpZp+RBNfRT25lH2AEenXpPCi0TpUJzNGGa4kgBu0YWNqqoLsdyCYVNBSnsNrXTup9PGKEXmm5twY0SDU5Zu/oN7ThsPRDKMbkOOSv3SSltz/UBsQ9QHyOdiCo91Ku1LzVfFKO8iNV/4QVWryS6/qxGBOLYXsxVt9ULmaLBpPJJykyEAaDoCrxZkrBRhWcNh06MZeF6ehvJ5URMeTJfINBR7a+d7V4vQsx+yndNia2ISQsXt89I5NJ47gqupF6+XaqkUsTYeQJUkRHX0HqZYM/LGALa8zaDJlJ4UCcJLJNzYNHc8qgHgn8zXEl7AgFWUGCOawDWZdaPSrtiill+vJGMGeVyLyyDjCk7cbnmj8lVWD0TEUhI2rpFjvsRn7IRC6YN4f9Gqfgc5kh5ba5OCnC9AUaFR5gEFn3M+FsNdPiJRLCR0U6yef+FjUz2qyNiIPHeOyN3WsNhy9MgnDM8FixdInSRyVcxsHQpV/cxWT+y4gpMr80pZmqOISjWXpvQMN7VFPODMl98v3uR+mriIv2h1x7kfxq0HKTJ704d1AY7GW0Iat0uNUBS4lJREQLwJ2YW6bUm838YxBZduTCZAstJL4MY8KD4YEPdMMu772vH9cZEF4ZACd2vUOSGmxDbDN46VcxuMs9BDhTyzAEwPpEvsMv7dSdHlAatfCZJjKaurCIh4qpxEreLsGqtYYpdnhFgK9eyOtCy6rmKgNSD9iyYy+X6xqYI9yjqfAKBKayxY+8rUEqQmNMv6Nx1S+eV0VZl5O3jI+TgjquroygmJFhen6Oes2Vwi6SDZPSFBOyC3wn4ieXzRoFgBoNeNvEV3gqcUYyNaLtvIVlQGC1YPHLKCWAcWb6WFMM3vl0CwXi6bwGnMgp0owDLnlbN/QMp7UGe4IzFEzwAipqqT+Otdvk0CaDu/77u4F9xFQaovL1VIXtBSi3fSo9852qONx/+sGvQYjpHmHArFy9G'}}

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
