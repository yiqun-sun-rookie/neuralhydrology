#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES='' OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
exec timeout --signal=TERM --kill-after=3s 270s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'GLHYMPS_DOCS'
"""Deploy one exclusive source catalogue probe; no Slurm submission or science reads."""
import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import resource
import subprocess
import time
import zlib

ROOT = Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/glhymps_v1_directory_readme_20261020_v1')
PAYLOAD_B64 = 'eJy1W9uSqtiW/Zf92ie6AdPcyYnoh/QCioIpd3ipEFBRQKnyBpw4/95jLlDRzNxV1dH9sCMzFdZlXsYYc661//WjP9NM/b1v/uf2sN/9+Oe/fgTlcXn48U+B48R//DjEC6H7+uOfP7iou4i6nVBcLIOXaMmH+Hgl/Hx54wVu9fYWBeJyJQriS9R5C4PuSuzy4WqB75cdkQ8XS+7HP34Ei8Py9QVjLS/79bivlIEgcuMtft+IiefqsWqI+0Dg02lH44NdmoeGuF3I6cmzxTzY9fhIErf4/hLINrdwxJMrxBePfyvVwVhQzfdCs98u6mB49oViv3T4S8iLgmqLycJVUq+jn8NdugozO/ZlPnWr8UXdegXevbgdrxhvLpNx/30TOPbRy+zSFdIkLMevY+lAn2O941KrrI5ajg/9Df39vlG3YVfbJpvpO+0Hn23HnZkZXpqxmneSjmo8vVONn9/hnt/RPr2zfn6n+/TOi9p/fGc2GD69sy4/vVM+vzN/fod/eMdcd2aP83CP86i8OgiF1juVZiZdddN6pwph+/Z+1I5qWtXj2tYvmAd/96L6OSUJhGQz27xvfFnMZ9vhZbq1hNlAPVv8eznldFXnY9+87ifzc8RJRfHlXOp5ls1PWsPCmdNYHXX7Xmq3eem9bhw4FptH54qxY/Fzq+y+Ltz3+3rxvrdLOd9V6bkCa79o23VXHayr9jOBM+dZfGOO2UBJfFkV/O26owrD7kweClo2L+k9TbaTmSwlmmCn43X9/spo1jQ6tNaWJjSexmLXutqTbHPyHD5lc+0Q645+9I0utxzNv1tzqVYe//Vapa1nvnf9DOsbpIm6tTeaMy59eVwg1ivPUQu1Sng1s7jbWuf4KXGN3aXLwkDe9JV9NNIvYbU/TwXlTHkXyGnlyxLnGd2tZ4hxKCdn9rerpdFIPc92vTTcaXnY0dNgpyt+/+2/QtkuQyGtItk+RcM0+XD088Kwqrl583+qJr5pDcb0c2gOI8+x3pp9K+ly1EPeM19vFiOdC0fq67QUN0GH7FTkoaDHkTw8ecLw7Lm9fMr+lirf1aupYL+EslhGA7EZR0/DLc+wKspoXfZqsdPOwca/+K5SLVyN850uZzhzkWJUMbUecOmkmR7yzCr1VJurG/xMnmL16jMbWJld/sZa4SvBrsKyxk8/Sw++8VbH9BU/Mm0XuNEqFCTBd/QVxj0GffjnFlfKBe/u/39w2D4Hsrhb2mLpO3y8cLp5kIWlmopV0LFLj+zndAWyGfbYfcJk5LQ2Mu1oZQ2lkW5095HMH+4YoWyWLvxBGD1Qu5ppCWr/9l21kIfAKo/ZUtuqgpqpHHKO8zM/mQ3idGZK+DfnvK2faKYCHItTzdESVfAKf6tl2jba+Jn14m+VGHjW8eV5pcnqRXM8ygOhwSaxibMdfL8KEcsLsm1/XMe1OTwvZBG5KFaR0+0uXPhNiGEDCf6ALcmOiDXEd7ZwNPg2PQfpWwH77ENZWzE/AudUU1+pg/cCsZmGI20Vba/8oWzCTOwgDsFX4oZ+RpnEfEL+vOHdroex1zWmVXnoylEeyTHvpUUYjlL4VioDm35XzovM3kYjDc8UcdDRVn5GvtNi5CQ+089eB9+NegfP6VauVAyMYTqb26Jipj3blsSByfFITdsyLHHmcvF8/ikuJIyTnsKRzYV8Ed4wlhcdcHXfSkTX4mzD5bSePZRUk4ts3RZlw7JVXWrZZNuDHYanOv/u3PKAcWZyx7idtvfMMa9tmH+wnjX5OdEyKYWfS01WNp6pvngZYmnrg6N6ieooW69Kt74z5GcDbaPK9kZ1pO3MHHY9x88QX5U2sDfeVkvVgVUwPBw1OLjTDpGrHF3kkJfxwDQtD4Qu46MmTuEvLafYXzh+7kGrIMd5n+KINArF0eD9OtZ24QD/ZBYnK89VKB8FetZztCJyUviIYdyliYuj5yLOXPvoChFhK33X2EIhrFohNzmsLfUE8eTX31/zZwP9dPYy6fD0fald15Px8VJOj5HDr4LM7riC0o0artUGw642QJ40Y3muzQErKLa3rqDtEUt/QJelyIEN8IPxmY+5QqHhs6yODVeQksBJKTeQE+CKUa8MOn7K7CL7cTDS0ut+YK8EdmmwSLpQHAOf22NPwFH//ePf//ixWh7D+Ld1GpdZfvjtzP8Wbf5Yhsf9H+VvfywXUbb8TeCEV54TOHz5n3nZUsQi//NnSxHzbytuFSyC16W4/Ml3X7hXDhKZe+uKHRF6uPPKCavO8mckdn4KQfe1sxJEyIgXHrN03oKO2FbE4814Y0i9wRjKFOzDUHgsSye/30uXsrSN+j2oH6Axi4Imw2XxFIySA57LYP1yPNL3vtFDJEiH8agXg61yz7msgQrFbPBOlsiDkV36xgtmG08WUMhAXW4sE6sQkvNpP0uPjPH6vT1YeQ/G3vQzH0qdW9fM0QVbKGDH8fr2/jC2TKuYN5+3xs2rQHiZ+DvlHBg9xjI03li+zTGnz1pzlojoM7Jm689zRC9jbqw/3SFaDq3nmrXW68LzBxp3SowMtGqNP7Ylfa67qDQ64+s6wLDFYeGMT0BrMLh138fIPoWufY5kC/azy0DOzwvnpf6d2VP7PCeYG++kYWd+H0dW+IVTJEDkC7I7DTeXtSHpliUpqS9TpmqcQb6VC/adhWhdjtIxEDVBRpTTfs/wXYmQgOuvc8PkROvDZgi+d3kRCFCkLv+Ws7kF8RBl1n5iML9ANc0nFq/3rHQuIuNIBR6BOtiTeFo46n4yx3h8ZH7Yx6ifKpIFzMbzq+s7ZoZsn+fa3I4V07a1D3PMqe/7ST/TDoiHajyMDoGgxMFQJ8UCO3bTiaTniEv4TZdC2DjcJK8s/jrqxBMK+rm2MhsoZVfR33wP6zGgWvKQWKkfM39alO11RXez2cTc18wv66m/oRxo3pHAXo0tJ0CMQPYO+LyYyv5lKmtgaesQuNpuKse0LqhP9UCIRv7FmGs8y+H303jYPQeZNYE/Et/x1kDqOMy4PYvNnX3EeCUp8Ps60gz5iP1ZpwC5GqD6DLJ0O+knx8bW//Fh8T1nmGq2xWHfSgwFkX5p3340goraUC7DXhw+JxW49mWqZAuoCWs3mdcsFyLHKaa/tHc/+sCza6ArkDfdYs5b7PpuDJazsbc5WCDM++v9BONjD1AliC/kH2KpqBnKSF5rtu2VnhuKUByHyKE88tbYAxSihjV2t74RN88XjVJL1r5TVL7xvq9Zu5tEVKWXt+cQvxry0wbDEeMlot4wA9afEFMiHqE8ikPQicA80unDqplgYhx2rvyyQx6AWZhf91ebUNyC8bixVOdQvZfkxH4iueq/e3GQzdeIpdMEvojK5O3DhCoYjF9m70/jjIDDRnyZ0j7dOeVehTiD+s9TMBPiuHeB/09jSfkw+flpQXvPEI+bdV7HxfuJ1GKt1tf5xDgefOdlD991JuZFvDFoM28kpFCV73soow+7L7JKD3OeQ1prP3rxNiHGlSrwAR8N9msoa266i0qat9lLU0kqUALAsk2PseVEZpVus//GRxV/X4tRXFW0CIWI34vc23SvnzXPdPeIHYwXURzBFkk7R8hPYOyYqpoDKqIt/E0YdfVrPmsqyMjkCZdrbjHY8/ms7O2hQLkP1zpBRaMCZOvF/sZrpQybPCP1bBPW81NSSbLNfKoIMReNepVS1n6NgI81NsMv/XgGTEyngzmnIiYJQ8YyMJLGyCiPoyPFWhPjwCEtJR7CGDzN1cRLHpY9Nk7D05ifPdvBPBgvra6Y8bTOek8mt/OYspYOiAXG99NMi7FexM/7vmWren39mL0HjoMa0zrwLUA5PEFBolIriJvY/oARwPluFpTI4Vt34J3ZjNmwT/mhV3VMrXdT7MVzc6xT6oRlF1UdhxxKWP6bfE8yE9v4cJ75LJ6DZ1+WVgzb6gdw/n7Z4fIp9nvH5sdY8IGjnrDeE65Oaz8eAkd6AWcil4q7thnwsscw4oYxcSAX50iwkwnFbr/1bD95ti2LXVZBIH+1Jqe/5EGDN1FdGPaguHFdM9/Gd6I42PJMY0wzHrYRoWC7uVeuKSbblaxoWpJnWLxtGtzey+yd57xc8b2xf69CbpzIL1gjB78R55XgotwXYId+V7HBAbqtrKzE7pn94gjNsde278RTR89JyZ/kkyaHLZFs2GgXZs879oudD/Ae2Z75esAjnuMzKjeGGdMRwz8xYlpB30/JnoRbv8hx5i/EHKqApMaq53wvjj7pOmEuKlwk2f3w0I47vActVkDTWjcsx3pi4FD1YbH8OCAPkqUtNvjDES8Tf1MHKKdYcK9dDsTADe+bPde+7lJ1gLie78kGE/NAvF1BA8LmVq1p2GdSp5nz5xgx5Qm1jm4+a+yrl8srh/drjrvqhw/7xpdNHN80g7gsI5ticGpJO8IOpdrv6kp/eERewtcpxcDx1pkueUE1eMSyelaN8KBwbI+XqM9LNX+lJ78MXxUhZbyHuOkqyLG2baOR0p1tmGa+UGXpm/yHNbRnuj2G3oA9NvFt7dPRVWvNRVRVp8nAu0zBB8hBrJHmSh7GZnrA7TFtb0u9Rp8B30rq0OH37f7Bxn6jsdt2A/YHSoc4UufDMoo+gAthp3cGxyOvGEd/fl6ALtgx36+iUXrxjef3bjY/UQUL/htg76zrNrX1bijftVDDeeeIP+ygZajTQnG1Io73O/pe4TmxtQdwDOkp1BBld+eD1xXuupb50by+c+XS/iM3/NVxdIcwVifs2E37Ue7LrKrnlkaYEycsmriPRsnuAb/BBx5hh/DyJ2u+x/XTWnO/HSsGW0da8+G6UgfDg1q9l1PoDrW84O+Q/n6ZPORC/Y90Xms9r+11tuaDjm06WlvG7b8HyIEGw+/fbZJP47f9Ft61/qrmL4qHez02aeUxYRNxJOPndgy0/hE+OGXUrg9obatQiGN1awkUE1/hYGu/J7/2IfR0klM8LmUd+Q2tDbL7ZItmHy0c3Lkmb4U7O33IN+K8L2zNMKsd/6xTPN/fufNQTMxjkzvK2R+lq6YDRvPctdwne7B4aOnO7q1jdNVk39iONBrsLR1cgbqBNtNKLJeow2zEtT4tQ1Zfw8fguPBAczhVfu9KGd/6va6DJMJ5O21qd8S1ny+pWyTf54QOz5eoZ1q1y+6LfTa2+X6t07ZGbv274gTs/ysM+fTerU6Av4Msgs5qa0WxhJaD3bs7cDHVAcSlOcVOoyNRP8G/zfgTqk/uNcn/Ir6ofwSMGs3Xky9qy+kQGtMRy6VV907qmpfVkI22sl9qXupJ9TgsB7BHdd1g/kP+NzFSc0Qqcku3l5K9ayyP06bOP7l8Xce4/NvP5p3biQLD/Ibnmz1kWCvpwO5DbLJa6p4bTHPXOp7ZevaMd8AP0jBfrLfyHWA0dDFb69d6sdaFn+evcUpAbAjdhPHclhPUwVe5/P0+Z516HDa3Le6ANakr+DH1enzCPFsvUWM/6pJvdOgv9W7/C064j4Oa9/3/rBdRx+dN59KJWs7Whnrh2tObJqmFdUtWKhq6JalPmuS5bqV+A+Ofr2zZ5M9n3WFypTpoMNaoY2Pa4o0p+fBCPS7WOyKcj+nUCvZm2Eh9InAy6kLUzA/9HcrJe27X8YY5s5d13Udratu6PyI2PQ/YVEKcxLQXqidY7ffh1niHPbG/EYdsn827V61TUe83ArYTLiicOEW9mFL8jEf1+02+COw0krRt7Z/r+weKK+hv5/o9NAKrDZtT2VpD3E9A28/d913nGDAiPZGWh15NJyOfndwCG1Dnp1vUZq/PvbOnWu22xmkWpcC/3e0kWHo+BSZtxFN+cfAHOJuwWMxv2HsfM6hPZUlXNHvpXNfVnaGe3iD2UEsVn+a+vZfwiD2xNHf1LRDs+/CLMU3yhw/tNr3v/2pr5FWR0n5slo9h7sJnTgWd1b/sUOupiHdTt+bQgSHic/gypRNtc8zbg3Ex287x771wNlF0x8CC+jNXvGRxorMeUhTh75xwYgZ8RUxm5FN6jum729q64MH6VoTC8+Jzf4Pq04lcf0/xtaxoXWN+OmA/hVUTz9RfohMa1kNu1kbzRcSNGIPN2coZrK1eO3LxAb8p7yq+/o4/wvcK7KsHVPNgfRFyI7tzL2LDorWB39r4cvd9k/fEB3pJ/S3SA27dp2l6CnU/wE8xHtnNYX2IHfnlunaslfES5V/dF/JvNqP+HvHDB+weUtwgDm9a6+s1ZYRR0OjbBZ2kE96b/E+lU9cps02k6QOL6oCm/xm+ttZx9PGd67b1RY965RfUcCfP7VEvJpnIdb3P9mOLuT/gs2ssTGtfsv18OLd9XPd3aNYu3uzhMj0FmxX3NZv8pz1MRw82vvXy7n2IJu+btT3c4JDYGr/K5XuebflANS4XrOOWQ26H9dLF2zMpqw3gQ+CUzb7Dui9tW4GvNOonp8DW59y8faeUl51tdadmIrrmBnncxP+HI/LRqMdH/WJPtzqohgdfHNwO4kxAvtBpbhatwFXU1xIV3p4ZXPfD5l6I/1rnJcSJx2ryeEZ263uyHrsk0i2IHLZZNWcU+Yz64HSu0WdaifiQg1aCHjxCqxQZ6g7Yxq9aOcj6bIvmXMll/KdwiKfd9dyDfp8Sf4yU6rGuYzoAXB6KH0YUK1X+MMc0s1/Id34/Fpr+9h/TEeZySAfqHGrxuvdfsb4r3vF2DRcLtS0Yr7JeFvZzOzu4nfUZTBuUAXBy4VIPx25uh1gnKykU00otl5PMaX9Ntdjvqvleav397+qmaI+x+ytjTOxD4RrJF725Wo+0+nKmYUU9U1I02Ay+VI5k+7/Zy7v1Fm9nEYJ4gv1j5MWTHlg3/f233ZwTZ7ak9OZ0dsCeCfO67tOvtR31Vn/e64wHrGW3Kmuc0rhwE7Pzw1ZuVpFTcNc+4a0XZ0RDk9Ns07Ixt0hacUS3LuZWqjKOGn19mwF68XDvb1Ed/YsbDQPu0rpxRtrwr9xqENV+caR6m27L0JkC6xGOaL91b9QVNKoN2Fr+7LbBVW8/rEP+kxsHt5508e1Ng+e+ZKuPc+s/Yk+sp9bCzO96jucwS3es5hnw7Ix88ujjrS/wHfiCbqElrhBzgXPZuTYwkd1AiiLqCdDZXKv3eGI+kJo+a/lYBz3UrJtamz5rLk+IjhEvVh7wFOOw21jgaeo7sNsfd86M41CI6zP2pq/S1K/Ur3qBPtyx89g+At75i/u692fadrreRRBN+HDRUQkfr5+d/Mymsyfay4nV7qxnE/GR7B1n0JQPdYpc4zRyht3yw3sVab1o02ibDeryzW2+0wIc6De499CP3yQPZ1WEkZizE3WwBsRKKCvnZb8+ZwHvJ9BoFy8TX6gfGhjh5/q+OVsKdhIfdOg8r9X7Gnn5tL7ZxXqH0456nrk+nosQY8pl5njFwrWTKVfkdItO51JzPBhfVJPqCX0z3eV5+GyH5rxXud68S2zb4uyhy6VD3epahq3704zd6wCXNBgiUA8NPPtXfGnQubkGTvVR3zY2d+qfDzlZ+/fkuxG7qVSfCwDfO71N0IkJT8A7CWHD7SbhXRuIR+TMdjHg2tx+CKmOzFLwhbZifVNJZGc8pGdd6EbwI9aBXK5r7af4YLzHzjGv53+Ih+ApL+lGK+mQ3Typ61nD1lb6ULLmtibZ/e7vsBXVUoen9663VD+/a8dzk1esq80nNve538pyq1hNGz3t096bM9d6rRde3c7L2eCr/iTDnge8oroYeHf2O3ZzflzccaD/uU92Oyvox01voBhClyUBnWEYheY7PN28v93xeOgvfTXOsOk5sf5w+8whb3p59zMRV6j7Vn/SY/qyh93a83rhqms652tq1VeP8e2hjTUM95DLpsnbxpyzV4alS2aqK7aUXHm6qX3j2BNYr4y4o9XjZ7XIKejM6/4AdHar1yC21vMUe1Rz3/f8qc/1qV/L4lS8aw2d1UWtG8aoea711vzxuXt9GKj2596mz+5Xxeewz+If8QvdZayrr84JWrHZ6vcX8GEoPpwH9yOK9yG0B+GNaQ3FGTBnpZTHKhqN6SzzQvc7pjv9JeqHB3WrCppRsB7n537v3b9/p0f0p+cgt/shf3bu0fDp/e5De+/1ms0j809rrJ/MB1jDY4/v/TEG7v2mewx9Z/f+Y23f6iF/Xb82+2udfVD9+fUdj8d6ua5Tv/FDvfZ77x38WvNL5+F/Key+68F/kX+2mZCW1z/mvK0RJ7m8BnzVbau84mvR3G8BjuCnK4gl9dhJ37fPLJpzZeDMDfMf7qi0fj/8ytf1HrvkYwH5Rfb4bB/wHvKLJ41M3AteJC3LakjiLdLLLV2IWjym/lf9PXzvp9BdqD+Z3qX+U0aa+Rs9+7X9sGfqfykrxBr1v2K/4cynufPvcqrRI882+yZeFbrb8sdjr72uPajffu1jutAt4DjUOvpqzoEnreJD520JtdpMl8Q7LnCSQ3VIjYX3NYxlm9a8VvhezwIW4/0V+HKFes+0uHSm82KrrlF336ynhcP2qqXT6Szle/yGxoaO5YPRA77esZ/69s59rc/nMfNMqnzrO657voNA88xPkcv6xeDlBrsq2G8oDmyLJy5i9zh1YKeeSIo5tIfIhYezGOQ+9Z72zdlNPk3FFdMItrh65JyWn//KWcxNN/qSPdTGLq9IqGMNXVKfufF2JyGseHYXdSrfb5OH13uLI1UExseRq5+px0L1IdN8WVrfEfmsFWu9Wd92J11409ak7ep7G3pdIwrieSFgnGstc6/vtlTf1fUrcoFvfAkMvT+T5F/F0HRnX3zWC6a6QaH8WmHt27r/bjd3idq/g7/LmPmyOa9hny+ZLuiiRlHzaZZC80F3Zqhn++scNXhzGx/1cWZn9L+C3E59z+/D/eVd08c1s7PP9Q41vmnw8JGN/JBuvYbDdU+Tr3uaX96LmtqEwYr1MbzdaX3QTn+vb3K5fO4lghv7Mcu9yUP+13x+z8OHc5+/hS3NfTXqha1cWhewwKWeFi+u2JkUckWpcuo7UC/ZXLL/7cVLiF1wDZ2hvbA7bz/+/e//Ad6OC24='
START = time.monotonic()
OWNED = False
ERROR = None


def save(name, value):
    raw = (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode()
    assert len(raw) <= 524288
    with (ROOT / name).open('xb') as stream:
        stream.write(raw)


def main():
    global OWNED
    resource.setrlimit(resource.RLIMIT_AS, (256 * 1024**2, resource.getrlimit(resource.RLIMIT_AS)[1]))
    assert not ROOT.exists() and ROOT.parent.resolve(strict=True) == ROOT.parent
    ROOT.mkdir(mode=0o700)
    OWNED = True
    payload = json.loads(zlib.decompress(base64.b64decode(PAYLOAD_B64, validate=True)))
    assert set(payload) == {'CONTRACT.json', 'fetch_glhymps_v1_directory_readme_20261020_v1.py'}
    identities = {}
    for name, row in payload.items():
        raw = base64.b64decode(row['base64'], validate=True)
        assert len(raw) == row['bytes'] <= 65536 and hashlib.sha256(raw).hexdigest() == row['sha256']
        with (ROOT / name).open('xb') as stream:
            stream.write(raw)
        assert hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == row['sha256']
        identities[name] = dict(bytes=len(raw), sha256=row['sha256'])
    contract = json.loads((ROOT / 'CONTRACT.json').read_bytes())
    assert contract['root'] == str(ROOT)
    save('DEPLOYMENT.json', dict(files=identities, slurm_submissions=0))
    env = dict(os.environ, PYTHONPATH=contract['gis_path'], PYTHONDONTWRITEBYTECODE='1',
               CUDA_VISIBLE_DEVICES='', OMP_NUM_THREADS='1', OPENBLAS_NUM_THREADS='1')
    try:
        outcome = subprocess.run(['/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python', '-B',
             str(ROOT / 'fetch_glhymps_v1_directory_readme_20261020_v1.py')],
             stdin=subprocess.DEVNULL, capture_output=True, env=env, timeout=250)
        assert len(outcome.stdout) <= 65536 and len(outcome.stderr) <= 65536
        save('PROCESS_RESULT.json', dict(exit_code=outcome.returncode, stdout_bytes=len(outcome.stdout),
             stderr_bytes=len(outcome.stderr), raw_process_output_saved=False, seconds=time.monotonic() - START))
    except subprocess.TimeoutExpired:
        save('PROCESS_RESULT.json', dict(status='PROCESS_TIMEOUT', exit_code=None, seconds=time.monotonic() - START))
    assert sum(p.stat().st_size for p in ROOT.iterdir() if p.is_file()) < 4 * 1024**2


def frame():
    records = {}
    names = ['DEPLOYMENT.json', 'PROCESS_RESULT.json', 'CGMW_REUSED_IDENTITY.json', 'SOURCE_IDENTITY.json', 'UNIT_DOCUMENT_STATUS.json', 'FETCH_RECORDS.json', 'TASK_RESULT.json', 'BOREALIS_DATASET.json', 'BOREALIS_EXPORT.json', 'readme.txt', 'README_RESPONSE_0.txt', 'README_RESPONSE_1.txt', 'README_RESPONSE_2.txt', 'BOREALIS_DATASET.json.partial', 'BOREALIS_EXPORT.json.partial', 'README_RESPONSE_0.txt.partial', 'README_RESPONSE_1.txt.partial', 'README_RESPONSE_2.txt.partial']
    for name in names:
        path = ROOT / name
        if not OWNED or not path.is_file():
            records[name] = dict(present=False)
            continue
        raw = path.read_bytes()
        assert len(raw) <= 524288
        records[name] = dict(present=True, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(),
                             base64=base64.b64encode(raw).decode())
    body = json.dumps(dict(root=str(ROOT), stage='C3_GLHYMPS_V1_DIRECTORY_README_V1', records=records,
        server_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), root_created=OWNED,
        error_type=ERROR, slurm_submissions=0, model_calls=0, pixel_values_read=0,
        automatic_checks_enabled=False), separators=(',', ':')).encode()
    assert len(body) <= 4 * 1024**2
    print('GLHYMPS_DOCS_BYTES=' + str(len(body)))
    print('GLHYMPS_DOCS_SHA256=' + hashlib.sha256(body).hexdigest())
    print('GLHYMPS_DOCS_ZLIB_BASE64=' + base64.b64encode(zlib.compress(body)).decode())
    print('GLHYMPS_DOCS_DONE', flush=True)


if __name__ == '__main__':
    try:
        main()
    except BaseException as error:
        ERROR = type(error).__name__
    frame()

GLHYMPS_DOCS
