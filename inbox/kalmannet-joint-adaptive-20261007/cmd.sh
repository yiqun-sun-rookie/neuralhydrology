#!/bin/bash
sequence=174
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
Q = {'sequence': 174, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '3f3531248774899900977f3694ce7ffe1215cb9dba435b9686163d5d126ccfd2', 'ciphertext': 'MIIYzQYJKoZIhvcNAQcDoIIYvjCCGLoCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGABAw3H4ySvafOiwb7ahA952ev1kRy3vp1drHRo0wuzNEzxO9AvxpRH2DNiW8Y+yLT6Z4wf/2sNF/nbKTTsezq+OsnYrepLctj8yyPMJjEpJj5Pg9tsM27tfoK0B+soK1jUDievY91ugweTZGLTxpTbtOv7in0Zoa3wp/dOi9sKYs2f8AvpmNDcQxP2gt2v57vn5/c9mpm2brqqUfpSkab3pMn2NfpMAK0W+2v4i15EIOVr3GZ02UlXvoD5e3LczmayCgXsG9KRMPD1WI+t1CmjYP7wruJiRnfbTT0jxlCSrBjhWVrj7BDG2ynMYB2wT23dcVR2kLNbG3QRT+xlLYsmNeJFsAe/D9e9YzIicmjVidGS8cg879YjniSh0le4rSCGJNyoqalqEr+US2KywCsif+a/e8cgZlDBAkXo3aI0icrOmBKP5jMRTb9/yiPYMvdS6Qpgb5XjHHCnaU/x7aEX/f2jcgrIy+uTaOerEA7anK/dY61Xc6thTTpdoIfhe9nMIIW3gYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQR6nmezYMIKjIPRlDEp4GCYCCFrBYV1OxPFXZkmjG3fTvXM7ICjl7b7xubU7O7bUAhOfzUIbBygHTv2jtL1QU933UDSkX4u76b2qVrlgKDjjMMRcWzXz5MkGe2Whhw4emGoc3SNQf39o5XYCnEith7nRdWuU7D5RYHtK2IHjEXI1XGKSy6bpR+qZti89ffwgA+FTzbOMyVcBjJpB1XkiRYHyVhHXd+OVWmB1bXDPrIlGa4S6NJY4+/FYMoUdiNr6na1PFlUpabMCOgyyILlLLWoGa+evjTyUrj31+KnzSrbhkNipWLvbFLZEpL00po4qF/2xxuPdDnDYbN1NQUjfL2T1uUUTR/spN31VnzOgxzz1vPaMgdmIC8Rs5DfNMBfy7Xq8M3/IRG9NPM9wkfTnZtY8e4qdSmeqUQ4NR9Qfk9MeWCZZ5ncT7gRgoGzf9r5WU5uzgDF82gQCmWCgbqzZ9iHjjEzdCfHdo3GZsdp7vFKQn6rga7Muwjir969fIMCV0wPtnBQ4vswzE+OeHr9qEvMXFua4zpKpPvlLJWW4dEgMSaw5UpbTWnb5+EHlXjrjKso80yTqQ0yGrt8Utwd9QIxAuRsWyTHo3eopMWPJvq4u09AEJvkPxX8naX60yAbfWR0LlZV80DeiZ5ciDur8OrKZeMp5g1dSgX2CxXdaE6K6HNF0+hUeuu42PaMapfw+bZKiqwrX3xzJdBthOqq0ZLiQVG7ifZ0cswTIw7bkAPVVa3fh+6tVTUqRLWNTGMb/frbnxaEiN/hrgqnriPpYGATu4RSd861SKn0fUtuq2/hzfamRalC36J8UzezO14gx7VPgBsaWdWeU5A4gcvg2bFtzkXpUqwNJaDhGfR+lTdgrNsr6Xe/VKQDIWJKBkhXEtGfN4JUgJxCD7d551DhKFze3Ll5SjpoEq+03JCm734J7rdweiZIisHuo78Z085niHLRScD0Fq1YrOSX15KNsXA2jCo5W1g6PvOWQ9HFXsuu2wvWXGdSzqzdmyFuKEySfmRgfms8jK0Y5mh3CxI8Dw75Z1U7l1WgM3G1eSjBpAH2wxZwa/1BHuZ4XxZb8wxFSgPtvTgD58HnRxwEGJcDsz6U2LrKdPIuPdQM/Mr+ww2scq1G2NYeOZchZxBpQ8nrbU6z1j9ewguBhkals0OLzKFwjdbYFYhxIWO0c/SJYqHGlcsWg1UsvQhm2fXZRmI/rMSiIgLkBan9o9Fz7hs6KfrMKNNn66X1Yl6gPSacbjGFt3YAPw4qVgW6zcI6vlVv99QagbpEa0g6RqFXZ/Bt3B5NjZpBM7mmNQuUFhoQ7ilhswgIFq2pAiyK+TyseyM6xsso1ZQxgSHyI4eHcuyjNXf4pz77W0M5zWf4mhOLYGqyy9ZKx9vDb+olp+ZlteBnhJdCG0HF1WnOEwgjdwhLDi62zBDbpzsX1tIvgp9zO7LRvw/i3qvRQ3OECEU8bJLZoBiW4tKzapoINiyhNy0At+K0IVSCddcPsLvW9gnjn40TZRaiBug9yHF1pHF3eU9pg+OG9CrmXUYWuTRGqePnycjv1dQfIMzh84axIrIk2hKOuKtZtqcQYdCVdCJ7KUbG/b1FMsDp/79/wzEoc8Vs6kmbNKXM77igTVfRPUReItciRtuqT3BuYqQROUurnXzstnuMV2IBcC4136gKWvmJTM0gDxk/MKscdWHkRSS6bN3T7iE1Cn58/soYIFTvqC/aYVEq91m+9SCCjr7wWgx6Y6Yk3mYVZ6FHHTdE0RwP2C7SwGtAFBevIpHU2hY/zKrtParRqY5CHxXfhqmRNWr0m1ofEd4rBtXnro7NxtGPFqhxr9XaGRWVKGxLHvY/yLr/6aSzIiszJSvvZdxpclK7gJcXZIaIisrnWVZ7fhVnpYbsKsQviZMXMZKQZsHZj8ty7BE0XnVr+Ii0HvTTh3aa1ae06k6TM38d9jzpdCoWr8h6TwOlwd8UpvNK3Go5CwIy8PxBV+Y4NN5I8nlwW9Qv+HawFV/zVjOHRasKYh6PUpsOEy1Y/c0B2bvvoFCHADIQ00ArGDlIt2yWVH6KGpzSmD3jql2TKlKf9cyl33WFt4o35smaSrEVhPM1LwH35w4Zk6bqxpYCsfZTLNRW1DSvjKJu77ZKalWZ+hM2hNjbLeo/u/fuQvlHIor0iKTLgbHFP3Ug0FuPQZUVav8Wy7KZXfio5UU/m6STJBXGWTZJVtc6SlYdyLRQQOcEB11XOgtJP8fGDZhvMUFzcovEZqg4PtBr08xW7H02mSBcW7VRcr3Qi4qWOH+R6aAFXTkLXrZbKG1eKcaJDnPiBgSxuoRZj6yWjy8qrZwB0YfeCdb+ZheVw6RNerko0wL8Gi2Wu06EneFWWr3jUYoR5xE1yhco+39CN9aipgqYq6juozlfZEVyctCvEFZQ6uMJavrB3y4zKq1Ub6Uj+Ix/Gg+iuAC/kS1/uZN2NTtf9PmX7qI+p9q5+8LTMQk2fP+11NcLVQwgbCXvRuPcZx3QVg0PJFmh5H9uskpQwqlPtjHriQvjdkGb8eCGkxKeajGplo1992re4g3LNzSgARgXKQtCTHybR+UroiAkw6kzv+a6P/BVDSjQ6j50ukCtkhHzfCWCk4Nc4sDyGTpq5zrpXn280+s83DRKP2xxYGJjosk76biu0LDXewCG4ig1q/vynm9CYOXt/Assamfghc5grl4YvZyIstJuTTpick4GTJ96szD7Q1+2pJe0DvSSl97/fVa0KcEEVmja/T/xhJnalCQyuwwwRw6xCiGxd2ND9q9T+ilmNKLQTyxSFT4B2B8ts65RLvzfsJXst6SkIlr/2xEOD9xaVOT9KEJ4y12zzOFlJoo2STueoqEZTCeqNjiRLfOIK3ADaV+PfnsJX48pU9r4iu8Jq0MLgkibRCnitG9NR3jYcemz6Xv0KBmGyLnaEg7LDTT9pICvcNYe2vmIE2MGto/4LbfHuLVW2WBa23ijIPTqS7Tv39p+rKoijEOPsJ5h8Y1jydRZT80by4QnXT/1JILNSh+ZEUf5gTzlHBOMj/ouBtA53s/EbW7/icw8KJonThxGdJsHsMWEcBeZuy/qbQdM8mpCvBy3fC3QoEgZTEOfCfsrdfC5RYRqvia7WYCHBBrgqMzK/8hk84k6ZmBO6djqk153KhjjTQXPCc5p0/GA/N7r9sTZ/gNshVPHb1T9cN5ttLCMzelbLYOqT7/3Uwxx1eFhdibdkqWEL1f+V/cwd4l+xCbp/FFJUXJ2mpYqvccp3UMJ6YHQn5UTv4axAAf1IDLm53ZXf1C75S7spmkrA8qlKHbQ9PXu7Lx89i9auDlFLF4pcizyj0N47K5LonE9zVgmO5QDwjs1Ts7/Sa1Di8Y4JUTEYpAoovAiOVYtel5dPH/E4z/PJMpPOEtxLxxgQhxH4WKcqba406S5pBNAEwAxa8JSFSNzqATEk8nCpsVYh49ft/xz/l00o8E5jn3x9uKq64AH7zsZoEa8igPZKIPFdtTIaSbqvI2R59v3wh86TrQyVumiE8ncogd1Cge7oKowIsYTWmxGR7GlvhFYQkE1g6bGBWBz6DN2tx2KjYxc0ELiSaLLqZLq52drGXXyqdweyYnYdbSC7cprMUS18aHTiA6MPRRogNhAEDxeR+edUJ8dFCkjpIzlhdLTozBTN38aiTvdYY8tl7g8awSgi7Lq7IgfWN7ZMGBR0644xCoYEjMEOBrFE64Wtw8Y1ZCjd2zOpo4oDgTfMazjtYm69YgogqYJvch4R9ZXHhtXaqoLlpB3hRT4yVyUKG9iI4moo7kCkIlXNOHGQ5KNqamCnONtkwzk7Dl+u26t+Bl2wmbfDL4VYp2cmkKi9WJ4GQxCR0v/nw3pd+0LF2MYWpGktG9TWLXsHvcbx1BW/DbjlB0LbMnJJq+Uoc5lCfu6pI3MRJYCeIEmWlTMCGgf9qW6umW4aWOQOZ9j+sm37lESIgz/30ARQYbUxHHTBl1oXHHU4rhx+icGa6xXEsC2iIN8Pv8jF/LVK8o0ukrY0LbcXlfDyVC4x2aToqfaRVEe6/fFcDgIAAS3DtAhl2b4/+zhiREO5O9YuJYFDxs77OGAB7HFPUtfNTb/hcJ98wa/dKb492OL1nDd05PXl6Zv4TLkUPkt9MHzbB7DfFtrVtQCJBhgOIQiJ0CSLZZjPgMHXA5OlvBPUeO8INscCDyzmVgCdnKOQytsBWhj0YMOFcsDAyimKwyZXwJtPjbLl6ElfPcOpcKSxz5hKHWa1hiOrvyZGcEhy9vQCBxGHfhyKcLXI/br4va6e/FCU5gQ9g1deRb31zSIOa+QOXCGaGvnI0YjX3pTvoDXKjyrhzlLHO92kQDE2MPHF6GzrTjZX1+9FT72RC9nBZEGQaFjYzaXc1kmnDcP4n60767H3yts83EJeZek7H4oHP6oeplqYotE+0nbdebJFU3RiSgvJv3BbgYjTQ7XfRRET/+rRoceemxrYuSk7mR3wIMqHlPj7u7YsX5nhltZIIDBIjT0Diulf/NiHQ3KskbdJcSArYGu0IoOQ0uRCNTcV2EZZRT6wfQwbjj1IXcoyqa7cn3ux968fmrBcuGz99M53DcCJRU3IuGd+HDOLo7bSjl2eG55oHo5/svxjpNdaKstBZEsi6Z+HcG8qkxvFXCnfk5Q7/KuDSzBxu0Pu+tWhwmy8f9F+dPGHBHwypmD4XlG8PkM5d5Nj3z3hxLcZyMk5IQuCmfYB8AW2qruwBtC3tZHHSEN7SllmdbdFefBrs5EIbkbL03WhPumMa/kpN6Z/E8ywULOekradLEHiRWAh/cVFKc82pVvRHPpuCenRJk9EKPQud9sJ+ITXhmWskR98cI1WWt21IqYYy4AL1rq/FgSyxhOLSfx6hvZa4AcFc76VS8K8PUSs3yJDNhlaU9Nkv1k2o3MOvti9q9kE3dBzAbzwCdXJ/BntTgKnkoaecEyNRn1xl9ENc423gB9RBxY/4UYwsQlDx9/Nd3//iZMQmFNcjb7hUu2zNQ1PwS9IC+cEcpHX4STCAPcVQjUYF2zgLV8on4/BnMqcUMvKNECnoBtQgbB1q3ZgPYqTPQK/SfBbVB7/SBzQmFnmSrQcdBxyNRcPAR/uvY8gfOxPx94O4IwFwGU4Xa5J44JcdkH3EKxJJTqUtjQlBVG97F+P8tSC0JCm1mnyxZ7UqPo8IG5FtGjmbbt7dOIR8VCRSffg/iZ7lOouLJtER5CEVO2RpnNExSOT8WpXs47SHBLrywbpuGmSdax4xPB0O8OcTHvMFj6ZJfgmc0I7x0+xfLt8qC92tJHWT/wiwCksMMHZMO8LBmTp3NxN1kHgDjF/58juWo1zZwNnOs8D79Huy2+Y7YEab1fsEhGm4hIpo+S8WtC8by33SiN49oW6as8lvhXR7SDUJAAy6nJBktNleGaF4xBmglUXmJ/dFVpcmgYe+CYN+wUruwq9ESR4MJCRTM0pWL0NEX+LNdFYkKqJ34VCBwpWafc8tI0XnV9LS8pO+LuhGQYBzigRAD+LLb2n0tn/9NtV1Rj7udgclrO+zogNOvyLg4Lxd/SgydpQIJ39kRhJaEA2frE+brgCmx9Lagz1a7sxdueIp0euf8xwrlGGSMTbY4xCTVoQ2DWz39lshob4yb4vl4NlrOOQa5ORMc88aaIGRNOWqkD1+tLVPuaC9IHf0RtNM86ZfoAUNOQh/itd1RhhAfeedRKEFLLVqrLrC7yhhqKE6rC5hQI+9u7tlyXwUqvc82XOzaK8oyR1DbME5m0dH1+lTxX1svf7xHFTlnO8BSZwQE/5mlnvK2YyfrqAGED4xgMU4En27oXNhyAEODYtgcB0mksiD7rA23byJgy6G1WRGMWLVw2JJY5CDl/zOiTgx/qmQvkXvTM/YdyKt6lxTchLqgbA83DjD0WTqWuYBPio7+Q5iKXi27N05A3AQLzz9aRpnsSr6rbmI7R5Jk3AxUK5VHNj8dXNl9vdubMpF6Xq8lzzOZGxgix+mwad36Z7N36FGyt/3nXc5Zpum1FGjK5Qi8BIrLwHNRT+67DyN57EEn2/eqCaoPRJfP4ncJBvOo4WHY8Y1lAQUHm/z/ur/lMWev0oFup3FDaV1DzJocat5GvjsvxxpfSUz91AgkWkmMVDcMmKiRN3XwY2kWl7oukMw1uXBUXJ7S2BMM8t0bbGD67mOTs5Fxzf4dVBXQu3WkO/ONuQdz07Rw36xgto2unmR3VLcYa+RHRUcAo11aZRs1lXby7DJCbZAe3H1C7iSDMGU7kzO804+Yp1JiBde0oAlQXZW+dvyWWxUKD78LQbPKQnprWMEWaYO38LmMtSVMgfC/ZoYKT7meeT69yl8IQ2t6FVIeqPEjy9Kd9I9xCjl7N1sJCAEQgp6b3eMXVhnFMu0TezQXBi5ZJz4/PgK6Cuw1+d7mse9rSVWbtxdFxe+o6UDpajRAKJddGrtwW93CTlZUIdlpXrgMZ1smAVPm+DOz7A26s7zH/Wo1CMzFd0maWmp37So2hSjpxzJQdB8iWIrcxFYf942qHSmVDLAy2ENL7HJ/fHdpnqpfc6YsW0fD/Iy36jWO3GC29ajgUE/wlnK4ElRBPz3JQ78jWUmES3/vr9cmrUiZF9SfaJxTXuskoI66eAQEvbF5doTQpc1aYCL+9t/6y25Ibh+fiX48OizKiLqsw4n8utgGBz/9DFQRY7ptP4kdFsNCzyLNHfyrpdfj8JVegKzjat6uR3xR2cvgGEemwYNWTHMltpwxkiKQuOSEoEsNmKsVDZItcOio2hUxjx6RyuJJLVbil63tlaIgo9lYaSzcFY0b3SIc795RynJfQJ6D96G8fHAT7yqSe+/3dryzH9oNkuY+b1zEKYZ0aXXSOdVmmw68STq4WEWhC6sRTWBswdJKMfqMLv/NcIRANSmwbtorkhYXD8ID0CPy1wit2nJ5H5ki9dMr63k37FyX4tQRpt/d+bZEIrDNhe5eMxzBApDu8w0dcfXhyrm5GsCLC4C/3rjB4gGgW3SHJiw5RzCdoqE3oY/SYr6sK3ojiC1PDxadJw95vJU21Rfm2uFK/EtP9e3H0/QBOT2DwhbRFeEbYOuGKnPMWr5SMS4SgfaNOumZIK1xuGZ7OUOnGgUZmD6kX3EXP1Rr0fb2/62Pz7+NfKdKTDq8VKLoWynZLt+QUH7akQztmuRU8Uua3hbEcOaBwX33T8fDvodpjCJzmdIlqXJL/Tz8A3C3NTXg6COcdvs67jfu52wWM0cBadmLzjXOfj6PLbV2l/azuFy8EqcYNrhXs1oRGC7mkTHNmxezo4a/HxfO8Q4LG5bmSgqCpTLMaSTTyl22ZcfMJCSgUEvHuy0wqPe74r4b1/qtc6VSr/7MYc8zoq4OJsquFZpM7++uLd9MDXWJjT4Mm578jgWWO6KtfQc5Gi9DoE9xNxPDcOetZs2izEvY3o3jhLfvw7m23R9NTQc6W+soR3qXFI3R0c+Z+0H4mkXPOplB3S7FsQ3PVLomEzbLS8ab849KyipMBt/23KqUxh55XNptCTq1q7AdvP2qJny+pok8ye9VhznJ8MTIh7ijeMyO7JLYvR0KMcICSBdJcLyP1EraigvvbrfhgCR5JZcjCVrjTIu7TXJn2Y5Z0mlDfWQmUpzO11sASnoMp1Rd7SZQBI7JT0SidNK/q4TkNQzkcJ9yieGioJdRXH9yK+ajC7BxODsEdvesaXxkr7Vruq91pBkPwCXbuEw4/2NtMcYNqce9M4iAm3SNJYXYtFgZ2+F/KFZQUhcDJseOP4='}}

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
