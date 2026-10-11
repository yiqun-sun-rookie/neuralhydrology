#!/bin/bash
sequence=210
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
Q = {'sequence': 210, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': '7eeaf31dd7fbc106ce03d07ecca2e4153ddfdb7fcd98896e141a8acb54947f5b', 'ciphertext': 'MIIYjQYJKoZIhvcNAQcDoIIYfjCCGHoCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGAPYeYgQOYNdaf/ir/SDjVHeAz/8o2bfJOorRoSu5OWzaKetHXYp07RbG+4lUgsD4iRD42DkrhIL1tv1yzjot7HdqlNkxmgD23J3HW7kVFCZzrHIMy2QlW3x390qskw29P7gLtBKbNVfI7dILZpcbgNC/6UoYMnsl0S06HvHFMYHXjbo7Y81HlySp03GKT3wWAqrTMy9A03zzyfGHKs8ochf25OOVvO4O8e+vK9f0p/Sm7/m+hndG0/rOhIrPSko7c6Scx+TgQ4KvXaI6x24laF7bR5L6W9wyUb+RZioMdgwygjEWxXowfNMIpbTxZYm6ck6CnjnkFpPZOCEaUwW+gnjWqY9BDSVBI/1o6/Ves5bVFEgg7eCz/JHANqFcoMCgJkyLQOJ7lkxrVqg9F9nYR8vLhfhzp/rzWFyAnuu5x6vZ0DPgimP9C8aSwANroxfx9X5R30X1CHffr1OF8+DSQa0yfagdMnJnsqi4RMl6SeMcG12RvBdWlc7rTaFX5tKLEMIIWngYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQ2Cmp9uiYeXKdOE48EmJxKYCCFnDRGV/S+GJiqJTSnWkoTZFtBozf+XR5FMjs5JbBag2Ju0COn2tfUwn97cFnJ6dCYBgfM4KYS3ejUdcUjnWBgd9TQ5j+eQNQQD46nijMWhYKWvjBTwgfNQGVdBL39SVc3ek/A3+UYFdWSKwci965lGaXuKFGK9jTPvhJ2dj7jmkQbYwpE8NPMff2Fm5E2G5UFRTHimaDL6aFyPL5Z0TsnVUz0f46+HjoOGS/mx0x00TmKLzNTBsjX92QNx2v/NTIsw4aWCmr9sloKbSb1G2fGIfCT71YYLK1kRJto82SEbuYFiHZesYj33Ggrhgw7JinldCLbSkilD0fcDbQIbfV3ES9L49A0juLIhiNw1phJ1454e9TwI9uPCIF18C6D5HX1u5/5JEjN2vqWJJeKEB2IdedpKiTrVkaiXS1nrBZzbljqynix/nWeEkbAGPGea7dQMXbQYyRhJUhS5bsv7bdRTwxBndltB+oLSwGRFX6tb4v88FlbBfNtq3ROIPvaErI0ACBBT45wRC7x0TgrSHOTHdv7+4qzhScyp40r1FpKRdxhxp8se4nuGK4KNDLyMJWy54tOfR3+0SpUFR9MGjyWY6fyPVSlDSyhyzOYgSrrw9yhNVgSxW9XVGy2H0LXp1rFZRhF0ykesmomG3pC2joHPRWUo5WbzwsB0tWYnXVX9W+7hN7CDrbPSRhhMVH0Ca2hfBlCHH5glkmOdbw0o5lV6ur6awWowR+X/Jfxry9KvXUKBDmpeJmnzDzjRYGwFnn17/Ft3y0gt4vrQ/lxIgaCv1AZuyRaV1+JHVt5PjHvsCwgQCZnMK2uuDVTH9S3iEQiec2frE7GvaCTcLATw3+mb7S6TTrEeXD4G6KVdWp/xpIp+Bv4E/CqyQYwQcA4hi34JARrr0ivpOgbS6yVN6oikOUdvECHMmEsxEL9h0KEMTi4ELGRUsNox70hEwY4Wa4ugTT0yxamhBGcN+sJt7uyTw4tzb0j02ucSRJIHZOp0S/PfB6BsdahLHkMHAu/1BqQdxVeNUjgdgdYT2xTQNelA+7gKXgPhP0XB2hwOR4lxWL3ah9ea5NftQ2UOyFLBxhgRzpcoPyUpI8wZApeR/1D6V0HfLXU2qkuQ+VuOuECad/Spg11EKGKFOKb42vhhfqDvaUNHH/Wu8UwKeLfnVKNCbbBSJRZVbRk/dZb7ilUQxIli2XTfqQAnSsdC3U9Us+e6UC59sQbOFOUo0Z3z4P1dDfo3DwyyXyljk8RJ2hEQ0btAuDR2Xs+LoqFJQIk78bm4P4SFsb4D4dphZ/oXYSMg4mr8r9pwS8KrOZmPt2fSGOxUrxOLSoLaKKqL7vjibJzg584zPinmXSp2VlXZGkKQChuqbIc4+HD1LPU4Fj/NJm5Eagjk7YRyDnBSLmjWk8NPLPAg3HaFdTb/JOOFAFIVi/QMtb1AoUvucQnfr8EIZWQ8Pn0ve8putblr4lS8uKNvaXcH316FlxXW91rxHSOseGD3qDiNce+CrlXWXrIALuethHw4L7vmdBexwfBlkrJAl+Mc6uG3DknOLxTB0hHT3pUJtgYSEMMfnsnM45oe+j9SmZjWMFaOLcgdg6k3nsoOF1DY9jRmthOYH3WhiR1Tlj1iqyv39CzrtcvsGa9zF5+ZIQM+sY39gSm1G1iP6u9znQkSMyxY7nRsnQikM3IGb0r+CcBtC4htofJ7d/tjJgKgUVboYKk0/f1YShljd9DV3kS2X8VAu1PUA/T8R2Fpzspxr6ihCCLGcRuX9cAZJyhxgOT9kqNutNoLLZTJWM3rYqTFNuAGnG9JsHauC7VhWe/b5JAbKpEJjCSbzgxDSLixNQhvifC6Eel6eVPoTehKl808FuRVvO/J77DVIsjtbX9uXIzPAcE6V85c1Rp5GVFnWhJoaCDf0beR6ctLXodQdQoj8R8nkctFOcwQRsaoDempS9HIat4/2DThWitZGMgiGODiBHMmv4ibzivB82Swj+P7o6oeQuUlc2Epptyrr8nKJdfV+3m2ZkC7O+tEuY6uO5n0cM3JgHkMzj4tUQ/kHS7KO9HBHKF6SzUvLyEoHZLxeZLsJIbzJe+ZEVkhfGkKBnlRg0bcWe3fUa6qZyy1jb8XMPEfCtR94H6xl3t2tKJ3OFhWmeqB0RlujGcS2tnelsRsPLFiJJDGsBclTu5FTHa/AVs06Vv6TKDWB3rD7yedP4wQ4A5nILaJSjBDvBv06sGuVmxlY0fFqWRE42yxWcTGRj1bUwrKWeUt8JGfkYW3R/ueHuKPyFfQe28TIoxTvc3Hr2nHqvwcglO0qloYtOAL01H4+cEiuJu1wnLRofz2VlfYNc346/50IFy7I/Y3uW/hUqIbQE/mKc+exMA2Ez/9pwpsEG5K8oh1q/z5ydhxSl1hfX/Y6xuMfapZu3oXpW8hXuL92NiK96gTN+yvSrubK8kPGTWJglFYbQ7EtaTiEYwsJ3By0XrkvrluxyFaCQcrkI9368GpREivd8H+XMcTQsQli2KI2vzKy8uNSkH0u1UynV/I3pOgvCTr+SDOLGwdgpQkgxNVERGyakDBYPSOx0tJvTYIWYit43TWlTTapAxZ/s5NGkAgiGvQujkT8FkPPGT+Gprd3Wcp4KlnkWnCLbQnF4Pv4t0t2o3q8G9TmjgMVPN9ZlSUPaXo10SS9jCZ+h6HQI0PZD6wbZtnCzbq5o8oBmjqAPfcOgl55Jsy5JjphkcQCDZADzm3kdoyXMbP4JZSI5ET/qd40DhYH7cQDcqFnG342EhzBR55JQTmv+bpPAABrA7w0kX2yI/By7u6rg1o2M4MqIwO6WOfqedgDFkJTokHAhJr8IpLRKjKcfmpfC+YsdX7N+flobvsD0V28nQ+KH5zXGb6FIgti9Q6DiEjwYkBip4ipGnbcKX27Rp5+Xvn5ak2HL+9p05vnWfU8z3EdEtu+7Lm1ReDTGL3HipvHx8Z+GFZx8qeBs4LruBpqBFNKrp0J+8qVCdLr4agSyoFVW2Bbxw7DS38iiFvrWiU2sfr807adjXCrDcM362ejexz4uYpqzNj7Kk1et2eEMYf6M4Yi6EpULeomB63sgMuK1vNReBtF6KQgnNfMckFawZkCvFE1qOx2RlW9KSj7XrToCecqHRENdNgKhGtp1ModusJzRL6xvdDFx5XYTEdS7VFRnU1Xsml9rgkojsBegA5io+qouOXkrcDAEAOv0Xjv1hQyJag55P4Tg7g2gCqM749t8V/vgWy8BRMM8WvCipfIp/lHMkndiCQGX3U3Dsir4H8xVUBtGU+G2zSZve3T5B7r77xCCFdnX3IvZ22OTsMWbMfPPMK4zAAiBQUQ5bgx98kugruguXjgFZj9JXTLtGFmc4h/ERCPM2GD6PZ0UEB+VnIdAIl6V5pIwF3E6ug2RBOVwh35r1fej4jDS7FnnPqhGEz1deTnqVX3D0ijFOm+FfZCs++yQ3+Fbcl1dNFu95Gxv3bifzH4vPR8Q75oFb+UU1DZffj1lPnKSlg51L8as/Yd2NQTGKOBYlaubDQit/5XZQYQjpc9Sx87gWLuCUUhZCpQHjC/gVl7FkjOnceOq0pKJUwiHDGLjLoZj5XsuXXXhkdCI520/yTTTM84J0etsYOauIQYQoTqQn9lY+VE0gJIAbWGDCfC9BhOY08wnlqEgIkLesYQClzUT7MxWa+71HFpU2YaM37DN/s4DTu4FFga27zVyDYovMIal8AU0zSxdLnjXaXrNwYY7OWB3kGafewLgEacLlxOIGHZdr7caRiw1A/ur/qUx5ZqfxM6kInhxb3Jsy9nw/H9CU2N4uNs6x5xLam6tksILrLjBDvXKh+Jw2Ay8c710FyP+XUiPsObzje92Y/qwn3SDYsSQ6xLLERs5OHTE0rWRTBFV5AyoDoYuhMCNkULtSE7DFbXduyMCwSjJyqrXgAKazbO0f60gfw1xhvLNbjve/CXA/4uEBowsv3IQf3ZKzxPpD8i1Qt8iiO0zvpFgNt4JHY7Q7siGA77quvkHN2K8t4IoHbPpPSrGLpUQzJuen9MqHS5N8Tq0njPyn38t4176AqJXaTwEcwdBiY2Q4PdayXMd8HKpBJnvAeeZFTB1RIiu8wdzswYKX72ABtw50eBiClPZ+tPB+SOXLdWHxVRUuJYSZ7eH/HlZHMUx0xkPOWAe8wex3HEvIlIqyq2jt+nIW5qLanok6b8n6t1L8WXpQVpTny6gmyFxqN42bSZlhA2o8qpsMZIPyBurZeGV5ikzGHVm9gNatlIMJKom3+YpDqzDrOE2SIS9qODguMXqCjDdTctBCUUNk770f8GDqUa8CEdpxFa6Vui0szcCNF2wJua6E8C951OZwuR0Pw2YODQDh+DyE3Y2JgfOgGDERY8fxM+wyyr6jpmceKcx6XdJGE+iK+FqunFOQEvMfxNtlIVVeci2t0uile3Mu9EqRrxuxchN90D7H8UDbUyIo8ophhWZJp6E8jr5P31UjK1/d9bdjkjplQM7/5azkfVYvl15fbxC6ZR1yXKNu70vJxu6pUW8SfkhHTQXCkQHv3UZh/u6KdTKYcbaY7MmB8KZerW6504yW0+k2AzjEhQD+9ZNg/CQq+2z9F8Rrn6x4V2kZuXA3uxEiaCZ3Czh8YLefqZofZ/ywOReYGHOPT8VEIJ62jdsARJ8ihRMPtRlwcBfRHHYqy+t5+LSVa1kwJxbaSlbcisO4XEZTvSJJ9cSPgGml0CKNxgEMOsTa11JVmdMkx/OnCiFsoq4BL38Tj1wYs7Sd50UArrZYHgwBMpXpQNc8zTK0/TT0yqkUjYI2lJQGaGJNVOP0dYCsp0cyMrKJVbJITzaYgZ77oE+FZ7Z8TpIuiCla2+fxZj9Wjo8SpqUQt91L9O6BOcMLWGoLs5t1cRLtbCFZT+Vjv7q7Ts6sYvMSPZV2eEn4hO4y45MIJk25+/P3j/BA+iqzbCX2I2wz3H0kWhHcdL0qfeqrSZq5I+e1vaatt/LcIHniWj1i+TOD47t092b//KRh66WmdEvulcfr3ZJxke7Z+A8RJuG1E7geZmNU35TEaYC0two4qGQiYxtFEUygJ26LfwuMvYGuwSk6EIeDT+bD/lZyZcEY40LD9GMRa1pTa4vvjgAq1M0IRYUCTw8JK7i5HR3xN2ZlBlUr60YCwRrL1V+/D01gS6y4BtfQTrjNq3qt+go5crFtltG6FJ5rPSu9LSA9RfgFBkD1ceZvDCXIvY4YqTAZp1x9BeXUltW5jspYUqYjSPt8WR1q2dx3zJxpXN6f2A2AWVPbKgfn7h0E+wSab4GF6LNBALtnG6EEJjYlasxTRYxbHWnxGHiNJJpYPeK/Lez29fqhvB0s07WzdcZXPGfztYvvY0RBiWlW5/FGo2ZMVGwZ++f6DD8D63kK9Y462+4dOi3JaWft7jNdcc1k6Smccmru4pg6mj7bVEN/lsuzOsU4TP0cQxRoZT9VJlvdsoRrS0VMauaVTYxAe+Mj/8JPtyB7no4zFPRoHJdfQTSm+L2o95rW+skVp3eQG0Tf5xAjURyMeJHa0ORELjDbgxugs+Eaqt6YIcMkz/pWlZzZyQ/zejgsw7R6oFZhs5GTZnywr67dPx2JklVwfC24mLjfRM206AZ8xI1Nb3P3t+ciPL/CjuTLA+84kjZUx6NyhWacNeZaktyNWzapMLIDCVBaIe6LubniebFJy5bSpP0pWaD9zOO1Q44/BioPqdHcld4EzFg59/DsQU50nzOM10lDstXf0bhxeVzYGjHyAwpCmKiEb1Ofqu5PGV6rWz5hAJu+erSg1uZ3VQLf6FocRQLIrhSQ7nU8xzgQr//j4CbMFAhr4BbSh99RmJpRD6KoVqgAs6Ok4+AmYGerWNrV2OF+dLr4IzA/CVD/0+09QNzg0Hzly1yQLYQEYlcnhOML1v6sz2vrXr8nqQgkpG2j7UdrTSWHSIwBX1ZRPKHFPbOezIWBqlMDkBsuA54c1wuoOOxJdSk2q1Dq4k7+rKXN7+XgKLK6NBIXpQSAbKYwVQNiBzcsdsMqRGkrUWbbz+j8xRYSF6n4U8hJOn4gJm3MvfScR4h8v2CHA3oeYEgDno/GfJynLgBMtKJPUvY/gINRkazlem/ydvXmzXVoKqXrXfNMl3ZMfKmXQkYgP2NrdIZqeVIddIS7DfOqGXYaQYnm92KC3mbVkRF8MD0Xl752hxV2OFbTDtfW04mqVCVpkYkrdrLJ/V7nxISwIE3v81RkPl+v1c6ewtyNHlXnufcQC1mrsxnorFoDamQUuhpVSMUFDQhF+Cghu2xsXE7czqXzhCTtsIHizqDpMLYwIi2LRPQkciNIC0/yTaoIuswb1nb/Wz57CXgynUsiFSK+Yn6PAP2Yisah94pSHakPMKaVJLrKe5VFmkPOAxQXelGzBYKEA1rTW+EGBNkdxT44e2YQRdRpBybKcFlq+BQjLjx8do+1knmQ/ZsPmn0fwntg8QvAdAx4iQ8MD0cOMynlnVTGpdrJsA2OQuUnIwYqBv0djuZQYMXH+T8kMtJ1v2qjkuwtrCkn1OAFpCTsJlBbteOuMRIDmj6wbd8YktFhjX3ah9nJNAUVwAv1y36aloe4hJXBLt0YsoMXCsGY5SZJbjauhJaOYJYhx1Xb63/X9QNPv/RuZ1DdUjZuxYJC3IAO2SKUAGxUMx422IH+HqFmgMjmwMiLYix7kcjLfzLYTbdHvtWSWuUbmDTrtIsSunBaG5fI/dT3Sq6y1IIsJaV7+qbyX9h8xUiGiM+N5OzLkzdlyJBmFPLy7L9nL2apVC0Yd88rmsAtBjkaGcu7TxOJwZxdryryNa09Mmtmd/n2nogonmShCiT719ptRCEaABjHvSDc9Zm00q2hNj/Kk+KJjuvRaJBwixQO4MuISvnnQoUNdz7Ej67ufnOvyzjAkojXyGjB/JumSxXi7E32zuBObBrEy8LjrmJFsfXVJ5giRAOb/LAdzOv9nrKjsiGnCsHtQa3TScU6311Oeuer4s6rD4Afx2WQLOT0zl780LI56/7X8r+M5O3S/s+CQY1R9bH5I2fjdv/FZgsEesefnBaFBJsHmJ4pXFx3xqwOcEKGTwooGfG0/xpJ6mo7v2gSIrDoOA5hTXUYnOYu7aGgjhp+j8MU1yxCWhKk7mjzNIEQtZFpSLhDZbGqT4d5plW3E84HOMAzxlO6anUNEfDZDRPC83Pi89cXtkcOQDdhnOEESdcdMeWGKE1klcgBa1HUYQtkGBESQfKEcRk5c2qUYU5LolX/A4+9G4Hj6GwRkx+4Fed/e+wZ1ymhghqgUPZtUskJPiuE5Y7YWA0qUUghdQbwKZses2pX9MQCusucEozLtiAfBh9W42zVngEWxjW8stZlCVFTz7amzPpHBtjgL2V2a4xCOnfb+CMTculX0MKMEaSx69R6gpo0OjyiySknEpJGtJ0ua2Xe5oJCqwByArrnG1wud4ghzaDHW8/+u+XHZ3BzuCFhLkegBveQ4n/2h63ZSnJxcI/d5mOscQOQnD863Orc/rlwfIktFs/J1tqrsbaXL3MspIauXJ2UtyDc9NDRMjDg5hH8Y9CGjoSzw//RHE9TSwVnpr6vknyZ5jROZS72+ZeqLYW7tRU1jqZ/yygTa7yUUxHEO9WbWXcJbBH7IWn+DoYnNb64j5mXMOxzOEiOeA4pA=='}}

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
