#!/bin/bash
sequence=132
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
Q = {'sequence': 132, 'local_cert': 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUR4akNDQWk2Z0F3SUJBZ0lVTjdybmxCQnoweHNmRko3QzY2UWx0WW9OdlN3d0RRWUpLb1pJaHZjTkFRRUwKQlFBd0hURWJNQmtHQTFVRUF3d1NhWE52YkdGMFpXUXRkSEpoYm5Od2IzSjBNQjRYRFRJMk1UQXdOekExTlRZeApObG9YRFRJM01UQXdOekExTlRjeE5sb3dIVEViTUJrR0ExVUVBd3dTYVhOdmJHRjBaV1F0ZEhKaGJuTndiM0owCk1JSUJvakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBWThBTUlJQmlnS0NBWUVBemVFTmJKS1p0YzhDVGxUeEZYajEKQlJJZnNCQ0w5eFcrZG45S3JsK3FSYlorSzlYcXFOdUFlREdSaWhjUlM5OEZWWU45dDg4eFNsdmtsOUN2dnFQUQpqbzViOGlWMGVHZ0ZmNHFqcVRrOVdYTXhQeTlUUUxZUzJsaGE0SDRCa1F5Zzl5bFJGUzZYMnVTamU1UkdMRnRpCnNsaHlsenhZTU5YUlZ4Mm9LUkdLQnY4cXY1NWtSUm1CbEE2VVBvc1NRZkszejllUVNHYm1ZSGtrQVlLczkwaVUKcmw1NWtDNHhPNkpmN0xOU1IyMnlZRG0wQlE4L0V4SUlVdFVrZ2hXZ0FrcTd0eVUvWVpKRUJraGltRFNxRHRRZAp4MFpiNEZaUHZCK1VtSUNSUkxpOVBUbEIzVlFlWHJiZVE1SVNGa0VPT0hEY0Rlb2plNDQvSFhvUnBhMFZPcUtWCkk5U1RJYXZTNms1YXJhOGdtMnBjc3J6djlwS3psTjN3Yzg0Qm5wQWcwZm9sRGRqV2tWTmJuVjhCTDEwQmE4VzMKN0V0TkxWQy9NNjY1U2FTM0JtbE1KQ2tpVGdZSXpFcHZySFpwbWdSejMwQWZ3c2p1NTdrTk5LMGxvNElSL3FmUApvK3VvRFJyNVFOb05TYmR2V1dwa1BvdWI2aU5rQ2xOMkJTZkZ2UlZ3T24zZkFnTUJBQUV3RFFZSktvWklodmNOCkFRRUxCUUFEZ2dHQkFCWWh3UElUR0ZuMUNjN2RscjkxOEREZEFhVnR5bnVjeFRmQk5QMGFhWFFKVHdaZFNKRS8KUnVLa1Vud0plS3pKMk4wQ2VuNTNBcjNKdUFXMEp4TlBoOEZ3SWdETkhkNUswMHBiaENFOXBnV1VhR0krMGZVNwpzZXNGbSt2WFZLeWY4UkRlc2hVMk5PU0tlU0wvakFjcVFDT2lEK3NzV0MxeXR0Mzg3VERHcWdCSGMvaFJjQkxpClFTQVpaMTdWdDBTazZzT2YzcWFKOENiMlJIT09iNlJnWGVqczFiYytuM1RvWGt5QUtWQTJ3TDZJMEFkbUcxdEoKT0U5aVN3OGdIQkJrTkw1RWdQNUxHR2p4bDdKRC9nN3BRUkpqcnIyRWJSQkF1WWM3N0pua1psMm1LWDFJdko1NApxN1o0cGw5K01qaXRsbjNYL2NaMGg5cm11d01kRnVLOGFNL3pRUnlQTVdlOWZvQS9mY3dWeUxaZDc4MFVMcTMvClpoQ29VWmFRYWVqOUgybEQ5a3IyM211b2d2TzgrS3puMWFPZ3k5MzNHU0tCZUdGUUVKNWZmYzJhSytGMlA5YXUKMWdoUmY1ZzhlSXhSU1dWUWlWNTJVbjlIQTQ1ZHYvNXNEV2E3ZkpKN01semhCYmp5MGRpY0dKa01PQktMUjZIZgpwL3hSakw4elArdmtYQT09Ci0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K', 'kind': 'command', 'script': {'sha256': 'a9ccacbb8f9ceea5d2f2203c360848fc87597d43b7e26bcaf5ad583e7ef2d1af', 'ciphertext': 'MIIS7QYJKoZIhvcNAQcDoIIS3jCCEtoCAQAxggHRMIIBzQIBADA1MB0xGzAZBgNVBAMMEmlzb2xhdGVkLXRyYW5zcG9ydAIUKpk4awgYPxajEWFJvqa47F3onNswDQYJKoZIhvcNAQEBBQAEggGAjoMTqjWHk/ZOddHD/R6xe4T2YfYSO5CGAF9CD3WC+ZMONKP0U+KhRcdwQXJfrAf1f/Ih+dPNB7IrJ+OuChGoTY568R59NRJU7X5DcUn5G+gOPeS5zbtfbvwpPK3ruAzpwY473G1eM5LrKamkXSskq8p7A7hdVn8Pr4pEpFWSczojYRYdtOjkH0qIFh5DRjBQGdvhdz4GeLtaZ5Y0+ysSbdPR+L1wDuzwQdzaIcxj9mXB2rvpJ3h7gfzes0GDl6ML2mNuLYFElEDAHERD8Kc9+X3J5xiTj8fgpT2oLcOFkhJfH2q4Kob2xOOK8jp94F2XhtckVh+/tT1h1yexE+Z4/F1otsO/s6/QYFZF9v0uAw8TUrEeXI10M1jkGesmd4M5NHOMhZkw81V8mBKZsIrqPoXKnNWL07EQXdaKKzIP65T5st+xpXi9GDmuPBHyBzIncmcEn2T76hdqthVviBWnj8Dp/uwJ3DkzvNlrUm4wmFH67i0Q3L6xUe+dTo5CJvN6MIIQ/gYJKoZIhvcNAQcBMB0GCWCGSAFlAwQBKgQQ+Z/BguPg576o8rlMEHo44oCCENC4gxQb+4+VVZSxgWvw+mlgdRdEJW92wP+VRIkzll9RrMBnohdpg4q6QAIhUu00MHXhLjnFQKAiwjcVyvJTHOLSjuOKehXibmDBD/w7nDH2UDSnwCZjzYCB3Pd/KN19bUUQCVbNrIVNyT91HSTxChUM3SH7yemupDqgMhJr6HcQCfDqvTLVs26siE0duRemGts4A46rjkVIy1bkG5LQ/Vjsayex7p2OYnL0r9YCTKuTizS4POAC1g6L/E6xeoi4LKnhzRrFftNmfSLYlHr8ZwH+Vl0nHwpNpDJDNtnBsCTiRbTTXSqBg59Gu9KttpUEWq77wLExdSkD11e4eaPyKCqNRw9aO/FZE9pOaEVRdVruXdxlf35Y2iqpQhpYK/nhgrriN3GkB6fEJK8DmoJKBMwAL1lRIE0AfH7oVQF1B4IiSLW7AaZ8aRpwm94WSwjn5mPKKMaD7Hu7CRa2dyGS9WX4EagJgDMJdkP8vawDSszrQ/xZE8LQYelfi+ZKvH8mCGn4lbei3aiVZaKCNOGbtJ1b3d1uIhUm9kxCy9Is7Ao/is6XGEOAi86ZdnjBvaHD/6/n3Da067jknyY0LUkn3iaTtKtNzF6wHEZjlDobG3j6aG/0d2/a7/ZH2EYpj+cCB5mN9ix2p7+K2jbyFEuCvIWxJ9ob3YuhhluMcz0KtiSb26Y+p5lX7OI/d2MSIEZ2c7hjYRJUT+G25fcMvet770E0mczVXjw4Ot1+58fJXJbjoy12E4YlwjR/s16K7sultujmcFVpVqyxDiqOawMENkK9Kwl5bfP2PCA2DyiB8dU/VlOxRVbxI5Ep00IaSxbuwcGI7Lsfs94xGbrNfLKiBEgxhgVYG/TRfBtJX+vP2PqyAejN7EzGa56aaEHL9IBXSBnXRTFKcqi7x/h2poKmu6ZV5+1quXMflY+VkxnypLsBGp91fLqVY/9v8qg6sk//xV5LuLgsKvNVXRBwl85moP1X3tab/ul/ctN/z7o/2rc37ghCFJsn6bWT+rruKXNL0LiqlF11WIo499cioO19qxoT/LVMJzL+RqNwQkKEv8FFCrwqyBX+6qStab0yOByT/GynGQPYF7Th5CufrrxxheN4uOdIVZDqEdRIWXoCdKLsxuJdW0OCcoNr2IDAGFlv5NVz2zkXpzkaZO09gPcPmwT316UXc0pNkZGFjA+fNeXmnTiPBxKAFV4dehz4i3Ht9FIW8rQKu1KWUlvMiRbNkEh2zQW/m5mhUIt0PwFmbJcrm7e184Ut9QS8GlK6hr1ApLvSYMMb0h5z/wnvV+8U8NRkfZvmLT/+CyGLoV4Q5ao5N1CzTFhnHNZ6IMdvK3NdC9dlS4ZaQhVO5P/6L8zzJ+giA84lFzDCdbyHvlS1+JUCcOTiyMfi7zVxGemWxj2vO94tTamXKb0xyVXNUihnwXpEwr5NlLfCkKi3M/o/PNi2978e09RAdbh3Abd00gFHojDpPTrFQJwE59/TC01QctxWXi+vB3dDV5aI2Cpw38i11mv+EzA+uumAIA3wDTh1ss5N2qJE8gtJRbCYcdJGhFHp9k02TSk/PGuH0hMyWziNyzS62O6Nr/BSSz2mKwP/MsL27BeEfcZbNxDa/BSxUMtLoLyd6XeMP157FM+ChHbMrh4hrVcpKQ/EnUHsf93YGT61tA4e9PNZBH7vNG100mhd+ne7Jve7uPN5o+OsfV4vWElNhx+1BGQMCaZlsyLRZxah30WDd5Zl/WDOrOYFmNj5TuUlDJwHfUPa7V/p7OX1bQiyeFX5PoZvwZPSRD/QS2uG2+cG4ULT1jMUMYJh92H4wkqeqIG5sBq+lukS8p2N79XzyOHQlqFmmEdlgEMST06S8FgqIsiHT66SCNHASHCVGGgZe3yAIfpLZrhA/mdVLzl+3aDZ8JdynicyFnUpHLnpDTm+c7Zy6OJsOvjzmPljSapAcgKLrzc/vTQkTkF/V3xDZMj7HIR2L/3Q5/SFjSuEp4OrYaQZB/indnXRFKlz2q4rWi36Wt1GvfXfWBXfi1j6pE4je7R1EZSByavjevt0VNbFPahUx0hr7wSmrs638dmY6yNWIzG7Km+pDkoePDO519z5ZP2fmC08NBxsbnMcTf56nG7xUPrCOBckLqauSzeNKzU5njS9YIOiUAP/8uiGwzYsbXyArClny2XU01ZjooNVjQ/YWaxmSU3Vleza1c3q92sxYNiJVI/sI1SbIBbqGu2ii6Z/2QeuWGYmo3iwubtacZrVRIMx3xpDCNanZfJDlASssYDP/crqCPosO7IvYYOF0OImNVedF6XGE6+IbOk1cR4Gk7lrJSINV+ZizM0UMxixZtMj1EP0+dn9VYXW4/hiN/kltBn03H+C/zBas8IUG+jZ8njPjyjr29zCBltgl0maj2vg7iNDp679wgofVhAO7rMCKY8Fhxb3UIJI+YGXOkWx+GAcNe0Xn0409On0SRBSonhsB3tbh/dv2TMi0Lk4mIcOYqcbeCEm8kBM/A1RtPoZPfjRunuAYonvJWvYGwLbTZ7J6YLMLPSCqPv999Ef15u7niyyIgv9UdKVt+Udr8jIJKcdoqcNVqF7DE8wPSKMTfKSIR4FlQIYZ9ZYY6rSF0yppwh+HGPdGg2wJiNDRJSSpUpSW4plAtWwIT+PM3bK7usqz23R5YGatml8ooHMS+ALmerkctS+IYkq1EMjkfCIp53rQrspLFFQZLrgDhTly1un3G6ABuvYiLLUv6dxidVRupn+ZePnI+DW5G8WPdrBNDKZCleI+BB/THaicWfnCfElOe4GcP8sGCinCIJsX6MWAHHr5JdyvJu4CHxLzZwdzG1tu4I1DvZ9fxKoW/x2++aI583j+QAwMjLTm2+8XB7lM74tzgkIfcxUf7FiDwJ0eQDdiJYZpEAiaKXoCfqEHnsg0o5pyHuLSA2APLAmKIUQvw7aOUqr0k8869wo8XVfhByk4WRkaEYVP41K0t1O3s1vQUt9aJm6dPPAnEg6kFN3z5/pcvzcT7UcyCIipfpnMkrD7+mn+MWKJDetF5JxRQ7WshC0EbV5yl0UHfAzH8ToAIljIMjW8pNhdNXo5aXrBURy0/4sIkjBMhFspIJDYYduLoZ5adECplgn4rNu2sAwWF9kdOayUNqiLDZpv33gEmHUGJohRy/YKU7PMPDpRiQQq2qdq+bfyckWCKh67REpH1yGpd08wNj8X/i3xWktOigMiM6h79+aAOVIUdi46eNm8l1+nQOLKhv9ILCT2ulvEJ+CoIYx2vSRUWIQv9OvsQGyl/hIuXxfV4PDatF6E7XIb6QOB9Bz5rZB9nl5XTzi861FoJulXsnYTzeNvHuszINc0c9Yt8CWyBjT1UFm9vsZI2iwpr4Wnxh9gHauskwjEQWw9tYmxWH1sMeKNRWgc0DyKvD9mUu4uciCP0dT8esOMJb1MsVduKVx7G8PS3WcdJevTZ9y8pzxkukcZS7ZTDz3RZvRJY+e/In7pT5yYM5IneH+96aR/xVUMKLch3z+Vu+OsqlnPyKFgtRV3zfl2iZSUfDrHhkMtJ6mCNywDJvKvx89T6TAVxgCJZcQC4O2FeJd77S7ytNnS8DL/eUbgP3upwkbKOv/dK7cru2rxashOgcz2XcrEtoFTI3X3QePVGTSYQW8oXNd87x2RY1Y3wHPtCK/hAlWKEruNNwP9geQIr3j+ekI1ZaNakJvuieyQ8/7JRGVvyxg9M1X+JaXddsl5+Q9qxsSbHJzV3V1mbuAxcIUJd/IH43X96LMuisaKPPBZ+CpbTk2VRkkKUlV6uM3hGbPFlX67Gxip0E6Y+VCRCbGhxD3Czchrp5uOCju9xwbDVLKGGWbRfsiBKTcFoeoXAKu6V2Nxvib/fZRFReAN/Lhp7BG8hjtwRCeaMQO+cWjyZePR5EZc1h7r1DRubZ3EymaTfTbRWr4lpEc7VOeCXMsP+x7zjzpCMWNthTxKfIS/7cq0JsDaOieVr67PHBPTMWEfVDxXjfyRHBF0YaxHL/rnT9VzIT4fBfUsEnNqJdXenIN+HzV0SUT1qWFx+OIc18SuRVYgclV+sUyYuV8ezzrON1Y1EjiWu+/8xh50Hjvg+WvpaLgNAMtQiaic6QCdZwlRoLXOFsoN+tfTOiHaDjcK3zUuWRy+ooFlkpWRoMfsGoePjSxMolhKMee52gTrVgHP1+d0VEDSqhwH3oTuV6+jf+I3J+T9YXy4mLx3sQQUaIm5OhZ65j6RW9tSbU9msPwGGilkDfvdDVURs+E+LhqyKmJfcIhgRA+9JNHpAzY5Rv6lK8AfEDNwD3L0tTWCQ51D83wOGDN7DThBP3uXkCf0tTdRDnYe1sHT6TETRNL8nhp6mR8p5ZAQ6IXT19PpDSZEUM+Zlzb5JzQl5oI+2UVkTjIurYk9NKE6SialvjM2oTDoJzNj2l5+RizkdraedMsscze7x2vsY5BRSZNBabv9Sb6fHPn09FgQJNOYpRo5F89N8gGEyMX9Yph4+8AjoLKX1Efo2Vdw1eqJKAqZFabxEd1G+Gb4B+WqtUkYYqHGMlEwR3crj6yKdFSIiMNnMCwIZ4d+bMin3LiUl59aUmFk9kVgUS2uqOIGc7UYY4gc3lJafcq+VuOeKF0tjjl1Bjfj6yiWbfd7fEfboUnXvRNE8ujpAUh7rz39DkXr0jGhb8IlOy9/UrzEq14goftV5TtKkigflbclaT1n3KlW/3QsbcK/X8+L8gTxqYQfkXUT4SN9lqa/RttCSRoHhRYAnVni9fSRPB7fz0/Q3sYRbO9EBIcu3SF4nX4Np4x4kq6SVs8cCQy2o35yEkeFddMpNDV2qWaE84ej4WFMpE+jkjDGM6SMgTbLw0vo5R0KhouUZbSNY4ZLFHP2R4+eRiPvsNbkrVpRafvVqI5LBUDY5Ych0TJwGvEb1w7BrF6tIxJjNfIq9ob8n/j9nIdlZYazQNGw6QH8v4fg1AC8vDdfeV9Fg0tMozoSJ+xJITsobWuCgaT2Zuv0lf+beyNjwXcQWwF1fT9vA6KKfYncr8SlLzWO1ED1Isg/fB9oEpkBzYhiLbNkt4d/ZaUVfFZptRs9MWHgTqFxPsa2BD2XWSDw6lWp6UwnKmaVc78vgKkQwmmRX4/10exaB7p5ikx9Wij/IA46nX7VGJzD031MB6xTrEpKWUO2j4McQf53jenS9L6YBGU9QZmjoZumh6S++S+jUzkTNoagIFEovJlM7gjgsXfu9p1oM4XxADcmI+2kuquQwQWDZIGKoGm0cFBQUP7uABihmZv6aJjq1Wb3ml3VLg6nOPyomndI3KZploGL3X7ewbLbLrBzK1EPqL9AqGZ6ZYPeOqLkC0TTbdUM3rCYLBRy9gShZrLw8Jw9cQbm0y8cpRJbH1cCyc2MPM28/h5DHbcIqZOoGWsfDcvVE2fSvL4J4m1uQAWVjWqeOgpOeaYQtafTNm8DM96TvtX8VtHaQguKRUFHMdSeJSAgWZ+9l3JpcKkBVIGlGgLG7ZJzOLRm3SiZKWB3UxLpyfip8fj3FgqjWUGOEWj45v9bza/m9elCiAQn5MB557P0GmWodWuKxLgfSJRjT6c/2mHS5mwqnGrVESOvsdfQ1CqqxWVIugrr+Cy7+hBTnFQde4Y62V/xKJVuVnX/zzXAM7u0HHI7hTKeAhYpTdhOhrHWvvYFNXnzkPQH0FXRn1AnrHhEhO7VyMlliyl7HDI8D7lAvjWtMgiVor8kzxTI6njYtEEUO5NgW2n9Q=='}}

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
