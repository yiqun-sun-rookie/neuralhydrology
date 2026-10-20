#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES='' OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
exec timeout --signal=TERM --kill-after=3s 5460s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'NATIVE_BYTES'
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

ROOT = Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/geology_native_original_bytes_20261020_v2')
PAYLOAD_B64 = 'eJzVe1mTstqy7X/5Xu+OEzRa62O/2aGiUCU9vKwQUFFBXcuygRP7v5+RExDsvrV23LMj7n2oKMuC2eQcOXJkzjn/+0fvUzP1Ts/8r81xv/vxz//+EWTfi+OPfwrSb+I/fhzjudD++PHPH9wiWrQ+lpw0X4rSb1JrzkvzRfhT4Pj2Ty6cC+KHMG/Pg6UYtH7+1hI4YdH+aC2CaBG0g1aba/34x49gflx8tNDW4rJfjXtKFggSN97g81raeq4eq4a0DwQ+mYoaH+ySQ2hIm/kwOXm2dAh2XT6SpQ3+fwmGNjd3pJMrxBeP/5mp/bGgmp2rZv+8qP3B2RfsczCUdgtbOqHdQ5Tay0BUDr6Atpzr0tslnO9qS3XTybTN4KJuustoM15PO2xcsSdoSTjSE1+Wvn2Myx/KnGeMP8bycTLudVbjUfmbfnbdOBqu1p/rznoq6Pg8uE6F+Bw41jkU7dPCSfC3tp877dhF/+HI5lxBOwdu94i2D4HQXs5H3Y2bjzEO74rx827eucAWu2AYt/Fc7ore1RX0Q5jam2goZZhX5jvyNnDshzkMzrOtZOiWrBq2ttQHsjWzNdnutf8IBek0Xl/qcadKOxraOdn/05y11Ob/dtreM8e8tsace+Orupnxah5t1VSOvXzGa2YoeqmWeLnF++Y483KPU/thW91Ygm/Gsb/ZYk3k+HM4vvhmlHrO+Oo5fqpttm1/MxA8U0nvx3KNvdQ+Mixsta49kFWTi2zdGB976/KZnnIMBC0OZOmCNd0Xz4YfrnzdzfF35CihO+q2PSGOw5Snz8DXIfFEPcczR8+Rclfwz2RDz9U4fLdFe/Q/4Ek+hfw1nHGxYm7lpWG1Z7atL2ecpFmDq2wPki8zkcbWoIEZE7bvd654P/Pd7jncsX76Ki+NzEHsm3bXdHmsG6d/wWIP6yRjfEoSYi2jkRa6Mua8tQcuF6mGnGiWTGsn9S1eyn130FJtwv316Dsaw71qY6y/WufVntlsaVz+n8crnoF/wed3eivq3a33euHqSZgBg/1xrm2s5v/y+XCQaabH5qE5SgL8cVo6aAG3LfQBvKqCmndE/L5qeTf2+921tgEGzXHbN1eCJqgXLdfXn+ZA1HI79oBxP4Xv5yvx0xkL3voeex76CHrkDwrZfWBaVskX7Jk1+GZD3BKCK+bFc6PP5BqCc7j5yF4TzhYO/MpVvulzmEp/0HoS7oC/c8hLKTgq8QQ5j2S8h/bof+HwGgc7YGSgjYHLrssln5ZsWy6nfQFjqm7rism1l4bc7T+tCXAC+17QLutnlgMr3HXsWPwM2HKAq4HJaWb93vjC1u4e0+bM9mVdbuC6xHQo2NfPvrz0BOkITsZaJ+egxLbn6N++0eYWo9m6sGNXquxV8H9ht9pe4zPjWXNwng/Bu4aUR067PXcHZ/j0IUjlJTB5iVyd+vuGXRLWXyLtw+GzX06F6DgfJd/hSCN/W/rDJCN7wxZtVyzHZ99iR6bKkgAMmyZvGzPOBgfospnoii1vT/Md8L9+h83tRTPecmf+ObQET7ATNbeu+AE2rZZmzjLfVDbaRhW8jbb1Uw/jBh6HKhhpy6n4v7aZXX1nzOHvlgrMesSbNL/hgHvPnclAt9qWYev+wzOwoXx0xdr39fwQusPoEA1j3gNOw1GCWCtnAWFmpJzn5LvETYQ/UVv6KfmwFoeiju/0sydqxLHwizbjPWOQfM5sSTGTrm3LUt/k+Jk5sC3Dkj5dLp7NnuL0AwcO1LzJfzbWrODAhzV6wLTFyY5u6U1cF5gWEcPN1ZVxF7CCOADuahG2f7XGJV9y5Vp3f2useR13/nN6BTbmY+AceA8zNZHyQLQz4IewL/hOu8Dvvb9mU04bmXa0tAbySDfa+2jIH9/FejXfIn57lyZ3hYiZFLvZ3DYeuBbY7MexNvRTv79q+eb2ih9OG44Fv29l3maM7+yN39dS1fFyf+NBD/jJ59DLPLMjaoK+VXN9o/btVDW9trZZPXClvPadC8PhjIs0O/v/Ms4jDvBdtIG22Fo1cNV2yA9NXvEf1+oNtxrqRllanGRbW00usXt5wK5A/eoc77p8t6tz1mk+0r8RkyrM4nc3qjRsiDaikQobd4MXWC5xZRVcUPnO/TrwYVqsEfrhwpH6Mc2kNYtRzvUQFtrh5AngZ7d7mAryBjjNw6zwDT9Njr7xU2R2vOfOZDHq0pxIXzd4dHDVzI7wCT797KvN589A4cETEsLEN/DHxgR7ttRU3wJ96Wc/zD1zi9jvAZ9jaoPznVnLc2ai71i/jj+ChHlqSYEz8I/F3WE1cpWCW9OYi0bd/HP98xyJkThN9SwQu7DH6kTxaCqq50/X5wMxQt/K5dPxrnPX3k6564F8U+cSUzEJC/B7o73zh+PTIk0uX4J+/DIHd336bnyhWOU7epmrsHU8Rc71eOdHgp/OHe1AuiNwZjyNM9jZx6B8ZjnDb7nksjSCXylkwxxtn4NUZ3yAWJSrPcYViMV25kJ/IK5zhEHM6+QzDGENoSdKbH17LuKxa3/fnhUa/LIZIGYhn0BO8Fm2GzjJae7wfGBLKfwyaT6v9cdtrb+Fh+L3plOOlY8Xw+Q7cvgluBE8L118V1nCn6GHZzQersI59AC0KzSEAz2S4tk0KfFUtdVOIujoYGQjtkl/wAbFOKs5C9qBeHXuAGO8JMCWPOWG0CUZ5rZtPhs40tan/BGxNCjsUtkE/crg7OTk80wHHu/HIPPQwd+Ui6IPxAh7M6eYCo3tpdfEJ/0z9ONgpCVle1X8IG18gC8z3Q0/I92IOEA26CKvuua+Uc4DsRQaZ1NqojgkXhT9u7Z7O27y41//+LFcfIfx77v59/q8+H3/53q13s2T31ne/zsy9w+eE7jfz8J/HbJGPQBf/uQbBQERSf+SF5cLKUKMi37O53xL+m0ZifOw/cHNA2EehdxHm5eWyw/xN/631lxsLeFrH8EybEUR1ywIjNfjtSm0k/EIghgJAQHGz7pk1FMo+Em47gIA4xUcI/bE2QpJCYJIshkPCwCOh0h6BhAZ+XEVpD9XzjaZIShv5o59gkHgJOqqWFBqt4XexhMAkomI8ZCIjAI0n/RSCEYSJL0uhLq2Rx/rxncsuWr8fQ4vBwBa+h6PSFjFx7kzXt3alZnYqvshsVOSTaONHMkB+r40ngMghXYcdA5wMgoUmK+Y5I13yrH6CHzcigiKxjlN7QxjycbD23NjW9ZnuqsACOOJv1POgdFF/1ca56mwh1WPlxxkeDjPndaRfcacwp323M8O83DtJMQ61DZU+Llz3boCHNVpY70uK0PWLUtmoGTC20Dw9RHM6H8WBOZilIwhHrcQR9m01zV8VybH43qrg2FykjXucyuLJQfxEgH9gOeWbrY9AR85kmHBN1aHKZJZ/H2KOuDYgWzYvY40HiFYOtYJznoKRJBDmmwmve0E7W4CwkvWNaOhvPMtnZIA2KKdTAZ2C8Hrwpxnvf0oA8aFCKe32k884YqAqq5mjID0AUtmIfR8I5YXQ1YsogB9+CwT75D6uewnvVQ7UhvAJvWVhNt/v08zlQwEgiKZ7sVsTa3U3s5dhYLozYYTc18IgSEC67qb3d6RISpL205AAsHQOzIsGpeVv+scx0MNiZeF33zuZ5cVyAmkAyzhc5DaIq37rW32g7ZdHThq0dhO/ozmyfoEyan727PoIyIcrbskCChZo4Sw+RnrE+4p6WOFBawZ+949YM3w2dU3E6MNocESY5AnOqr7igNKVow4nzsRAiOH8fuZB7+o7dA+R9l7PBTPJGn53P/5MroVhv4c9y1OzTsftQjBmoLgyV8sEeJGsBsYWB3KtTtgXDSn1deGW81szURyvoQQHFS4KO0Sz10IjkHBXTqz9xXBw6L53fVllGvx8MzNBmHKwX63/9X4E5IdEubjFP4LmzK+CNeFrTzncjKoaGDZhssr8sy60NrHi97qMt1QIQe4qNtcTY2Cb6YpD9tJHALRwctWh4nBfAoB0UN/MvwxPpH94ctFEDVumM48FzYxOvsiyWpvEdgvYRaXz6E/JJHAWUKCAkLv8GWVwRA2hVBJgt1MUtfb1STr7NxhawdcJEHKcHuzWSEOiIuuSbCOqc/DuH+Rxn0PCY8qlGMRKYkY9+KCY3o/gXEZWNxi3bp4b7VbDMdoH7bNuufInd1hAKKZm+6iDG0kE6xjlNU2mDs0Tv0QjbZ78LBY+wGLA5h/d0YJDd47R/xxVxQ+ouhp/MXzDZ6L82ikHBD3JHukkF1XXya3Kt6HH6Sz8jN8hZcQ664J8L0iXmDYZpyi76dpkkPUtQOH1vVY2y21WeGJ+LZsJwc/crWPMJxSPEHSRomVdQpFfQmMffhGR8K8EF+iQClFncJzqy+0pZljTt2sWvcYKMeyYwWYStzWY3F8juJ8/ZzGlX5/b6Ne/GIsl9tc6D1X4BluXaGdT9g4O/uy/ft3Gt8FjIfsZbBTK59miRTF4DnsMIdPeOt2VXzEOssisLiHLtnCtygm7idNm4hVMSiKKjtU3EnvEs/D18BBEJRDCcnKbE98C9xXCVozphSCtF/E4jJ+s+cr+8yHUh6xGFjEbr/X3geixhUYh5ZYd3bK5Rlv5bPwvTgBVzJ8KUKR8CjZDWOsf8RcpkmgE1aTQZu4+jjuzzg1e8ILfKr5nk39MY4YkxZ4+j+ztYj125a2yiMHCY4bQ9BjTjAWMMYKxuDdvNiUaW88IzyOexGN/UwxIRRZch0HPSqi+GcFcUwRZMQPiiuyGGbtDfTMrrLZ48+c8VmZFPY59BvdCp+wRUK8hLHsfPhxOISO6RXtTXud+rsRmyu+b3OUXEzBVYERHp65Sj4tjJitEetrtALHjMt1JI7T84gKyOhvug7Bf90WuCmlZxbEjeumjbaPcRc+pCDZm904CjxCxeQUeL/nqGGZHPa6XYvXZFuWZHM7q+JozDBRYxq8qGx844Zp4osMvl9gs4jt35j7GUkPEr/av5sxkZ4lnT+RNWtmK+DiY5WMQu/qwCRiHIvFY1Htd2p/RMxrtnOzKdYMcYLizKXGj7bxSX+hLx3xEP5ys1GhYXX2P4fn6u+BH9iI8WGpb27+h7nBRsCirHyZ/Gw1zTr7wrcwzl7IEnqGY8QBxNkbxprxkeap8FKhNQb2YJoewPMt4KcLDik0WrhDzpNIpKckpoN6W2i20u4mX8XZOhGvk3VJ3YSXMmGt9FojYS84+sscrybrDhWluMl6n6Ot14l0zl2IixCTWWzzoZ1ckWIzbMdLFb4ktbet1ocLd9u7mMkKKBRbgDcni6iotHObvjescgbY9SmPiGd4r7WwYnCQfiTcLkTugDF9BnydW0xu/Rc/fpEHId+wW/SbNFeQRsmkPzvcabFepbnZPAjj4JbrOQIfTciHepdKH0weeQI2ukaOnUNf/238N/rc1vqR5s3Dl+Om7x0bGF3e+4N3edHekxZs2qPCNjCS+YTfoU56Ys94ps9X8z+xvwt/P5Y6RGryM/4+PrX74ofW3K1i34a/5dLT2+ZITDg4YY3BkTrplcM0jZMFxgVtDe5b0RrT5vs+EGaSwkWy3Qtfzqny42kqX8KhjbgSEyYQJ2YvntezxV0u89BWw/eZHkROPU0Ji629Va13j40dmrnM6Xaq1CgovviJusWBgtm3XsyXivu7T8TihmZk8cNGXhCu+S5scIp64QfeLTYUDL48yGB91wcZLt+lfjqrRiRNoGUY9hzwRp8Djz5j9g4HMjQocIVYUWg2g7SJdgFuc+CXacDIVZ/agNYBp3Y55LSWLXflcIeYt2Z6OWGfN+/t+6bf4r11gYXX+OqWa6pT/Cm5TlvCv5Z1vhpFb/3P6Hy/9KfOew3gF3UTKu5uoZ2YVmGap6+yHAn5YYY1y9W+Cn5TL1rGvqP4TPZgecuix3Rn/sw5jZ9hUbeBRjhCBySTd+tW2sFzoH2MrhGxoiWflPWdvcKx9VhavN61Zdt0Ob9rWFdZh99Qbkw1nGY8e/xhG9hsg7/VXJM98RRsAf+KEvjlzqyfe6uhattdz6RR3z3XyNlog5JtkoGv8zJv+cQavsPDCTjkXJE4mvTurXZV6We2iVTWVl7bs6G54ect8Hjp14z/nrmj4tkyH3iDs59Uf6lqPG/aoH7IxvUc3uCQcI5+TpFjvYo/G9LKiKm3gr4r6mdXuPHSzjXe1j8or7/VhcDVyLMU2jR56qfOE16389WMZc9xaU16fd7kx6Ju04x1d7au+2vw8QMmyvzhFV+x3EXdVBrwfZsMzyzGrw6F9n5YhzqPafbz5A8ztkbE17xc1CSoxsxykoM/ZPVnbmGEhzKXaH7X1GhHxMJdWSf4u/2p5Tv3fshqWlfErojqAwfwMuMu5vsvYt/NNv3BReuveC33WP4O/HKTWztb9p267vxBz6mb2R+TzXNsYLlTofNebPKBnx/W8R0v1rwA7PfiyjblOhX1kxebZPe6cgStwbRVHIdCXNS8y43ue47t0qYi2b3WKSm/1QzEeege0pL4vQGvUJyWyjziQW8mGdXD0cZaye7Wtag3NXFX6E1wnXystIUixnhvi3mrrMb0QqOK0AFH8L4V7uz3dhNiPkiPjxhih68mxbrVuv8X+S/V+cZDbY8Y8+evY5dCbf/5hufAT4TTzp8Yz5HmWY7vL7n1lss9Y66oa73nouf89WnMZc2310XerED/vtErxZiKZ5hmLuzh5HvOfWO7B964vctwwXen7mh1UflrS+3PmN7T7XimW5pFB1jMrWwZti+7/EGxZKlncrqvvNGVd3XIclzv1pMwP93ZF1ZnN+LNfGSf5tm7mEi4b/Mh2xOz3q/XEBqz106RB+bz3upwXye38xDxkOrXmPdTDP8b8aS5hmUdE7kv+Gjcb0kNnmr6GdXebxw6Jz8iDBf1qY/n8d/WqMIordEBmIP/I4cQ9f0Tp/6Kd4x/g2dvc/kLLjOKuhtt7D/mRs13Hw8BKFUto8Kv0/7LmoVyh4faDwse8A9sLwEaaQ6tEGb36x2IKtWqWU1iMrrVPo7Ve3d2ZDxoH6NGDlrlAl9GdDs0ptvSl7VNRnTg0YQvOLYuW7xUHJbpha9qIUWMyflyPS/Peqnk/i+X4sJjzfbC7PzlMPw//+/Bxq7oJ2FK+8r29st9uw6POHzOnUdd3kvpME1M9R6B4jw7KNZs3ynrb1STvR2QU6letKf1oHywPNwHjY91o8MCabSkWo4nrCSFtz8Nrv1lc63d9Elndm/a8ct9qxNv9Q2qBWGMNM4l1aW+XJujvaC/VyN6XhPCHh0yRts7zJdb2OXhCMTdxh7QJmD2kHe+zWxEfSR+nx+WByBW8CfEZuSDyNfpIAf19ypOv6jDGbqt2aY8Kw8Ahscao6994q3uH8imxdHBXPtT79zpEJ7l/6JKfMjid1krS4q9Y8RkGfobeGvs8x3HAz7BWmQLq8gPH/dgWR5Y+ladkyvQOnZzT5ppijIf+/gLWwxnVqLatiK/qEk++luRHyYSt3C7CbDTDhEvyn4O00RaMo6xpeULzFXv0lkEupix9ESq5TFdTGu+ZGOr1/BY1A5susixvdUwnYJHm3qKfMB3i/qpX9S1Sp1Vc9eL8RQcKRd7Z/dtcHtrK33Zvc553GvYKmt/zN3ObmJsKYc7UP2JarTP/l3XZd/XJW65F/Ha69rv8O4AEe0hAedUx+0c7vn1DmuFf1QYSdnll+ND/WszHhR1h/Eo2tP8EZf3vlHgPerRoX5pDT5HHL5SjZHi+zewd0K8owOYsFFx5iYc0aElqlF22T4z1VOBJTXMWk3cPtWHG/H1bb73ToM2tMbrWsOwPGPR6+yf9+0vK9OxqZ7WLmsor2rDd35232a3h5ie6KXvFbULOa/qOS/aer8f0fi56e/GHvWk3INh+99FXce2tlbFWQfaD1/AZtGocf7i8WekxVFqNWJ/tNS3smLKtqEbxcUR2itjh8h6cbX/KBXPX0oOAe+Pkgt4gPn9pJwr+l+6dGbJoTM6zzzftCfiTTJ3/TovrGN2vcdCHMDOS0Gjwee/bD2LqCb9d/2g1B7B6BXWWP3h8azHi1rxs72sra3blm3aslrHi0rHVPVh+Hrjc3G2onmYMee4X+23TG57DerKHsZU69hAH9HeXLUm8EWNYQ7aeANf3dGZGsz5zPYu4Pse8DO/q1sghg4l+s00ZcEFl1V1kB6+z3KJ2lfV1Qxx36N1KrVVHRcLreu77Fxesf/oFIcoiUOQ5yFGxvRMqT1v44vBL/m09AvC+RtOpLM4zRzgPm6JdnnQGBpyUB5sXP9n/ed/NVYaUZdx66CuE87YGQRlWMShYi2Ud370N2MhaS/iR6bXnOrsCHgcmi0QeKqNbugiDJ0tQb7R3MOrzyhUtr7czhwx7kdM+qifrfaD23Q2LgO3fs9d5g8VXk/W9qqYVgJtJJvIe/fsskFvv6JLHVpv/4e6Zli8Pc/8BLo4cBLYsz43OU0U1bB4BbjoWlkSqDZ3qM9M1e+Hf/3+0OKSuQ57TPpPe6HNOe3+ek6+adgHeWIfr65xs+HtrFV1FmtSnevstU3DipDXKBrxQHGO7XZ24hfc9JiXSfmUzj6mCXR/i9ls0otM4nPTliYmpywNa8bOMrE8EnkafFSYI18J1jSv2V7hNFsfyEt7m2BMioq8a6DbvjLjbJPqUSznqOpZyFsR3xEP2VmFVXmW6xgI8ha6qqGTKI9rW9ZW7lcXEpXi3GZc1wJXL85C1O07WcQuB7P9ITrrJOrZpMhfK1uwSx00joVY5l/FpZKda+6fz2KVZyboM9sPvu/rzYXfKFo+jbGuJVKONykuQgUKO0enazremVJ9/xd1w5e5fC+8esLg8un4sbaZtf3+mPc29lpN9TVdoFEFeaOaalszlUTrVetRn8tS8kSIHEkEF6zDfpKqTsL7PUmdW7zrcpFiZRZdOrqoJvmWvp7uDoewF7L9rOKi4XFXXMSpz3RUsQZczNZwSpfIHOjcas5cfdkM6/SE0crn7uzbK2vAMovnZS2v9DX7uKM9IOjMsy/aicLzgUJ5305je01uca4qYHtvclnjgBYL2cXDYu/dEVfF3v9oxebWGAPtWcV0yQr97lz0xS6olLUb8FoLzxT6X0i2Fe40dnnHj578D7nKpNF3eb7sWu5LNGrfxwv1Vdd0iuewDhdts2qr/VX+2HajFhSoMmwgaIip2p/g4u/SJiy3rsao5J3ss69s/aEq+JuVqAqD9udwIGgpXSJctTWM73MobzUB75T1RH+HfIvtDWn7iPL+XnuL/OhPV7RzykMrX5umPvRadWam0EMK3zV0S/syt7pSXJh61kKsffum79ilD9rPZxfb2DkUateual2S1u/cc/Bd/gwjQLvf1UTq2sDtghy0J7BDdUv5rg5Qxb1SS2aYI+flfHFWuebr2v6FbaBBOpzae7HfQbVP4g/ouyb/VFjDunzQOQO6GOmjP3beE1xa4JI+s3Nb7GxYmELbycBHca48x/pKlf+R9gKf08XuKZ3TtXhbrfm01unlvpekcMqXPYiXJq8oOpd8zqzrcpYkVEsjLv60OF+2Eq1x2c3aFbVw6ORefKZcky4zhlm7vATD7NPM3cqzb9FTbc7ldWNmtU19axt0QbnZB9aobjvnG/3cnVH6O3WoMi6+W8vivLoraseILlkLh7O3Ux/qTn+rTrV6uOjDvqOzc8XFzKj5/V2NqKnp6SylJ3znrkC1UeV4V88YVhfr6VJ8Ah5/uLTTqG29vdhze+YZw29rDdVZu/6lOGvXuWknYEg5lfttrI5NtYJJA+vTXWmr+uz3XZ3+xfn5CWlxl5eYDnb5nwVf8RLVJg+Yy1LJqzPSj+dyuvnCVVltBeOpNOfhsW5midDsQ/tbp+f6/4n62GpH5yl0zv5Vrvx/Uwv793D/v5UfV3cQZK0NbZUEFtXHZnsV6/rjX//6H4YUdAc='
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
    assert set(payload) == {'CONTRACT.json', 'fetch_native_original_bytes_20261020_v2.py'}
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
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1',
               CUDA_VISIBLE_DEVICES='', OMP_NUM_THREADS='1', OPENBLAS_NUM_THREADS='1')
    try:
        outcome = subprocess.run(['/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python', '-B',
             str(ROOT / 'fetch_native_original_bytes_20261020_v2.py')],
             stdin=subprocess.DEVNULL, capture_output=True, env=env, timeout=5450)
        assert len(outcome.stdout) <= 65536 and len(outcome.stderr) <= 65536
        save('PROCESS_RESULT.json', dict(exit_code=outcome.returncode, stdout_bytes=len(outcome.stdout),
             stderr_bytes=len(outcome.stderr), raw_process_output_saved=False, seconds=time.monotonic() - START))
    except subprocess.TimeoutExpired:
        save('PROCESS_RESULT.json', dict(status='PROCESS_TIMEOUT', exit_code=None, seconds=time.monotonic() - START))
    assert sum(p.stat().st_size for p in ROOT.iterdir() if p.is_file()) <= 4 * 1024**3 + 4 * 1024**2


def frame():
    records = {}
    names = ['DEPLOYMENT.json', 'PROCESS_RESULT.json', 'PRECONDITIONS.json', 'GLHYMPS_STARTED.json', 'GLHYMPS_RESULT.json', 'GLHYMPS_FAILURE.json', 'GLHYMPS_REQUESTS.json', 'GLIM_STARTED.json', 'GLIM_RESULT.json', 'GLIM_FAILURE.json', 'GLIM_REQUESTS.json', 'TASK_RESULT.json', 'STAGE_FAILURE.json']
    for name in names:
        path = ROOT / name
        if not OWNED or not path.is_file():
            records[name] = dict(present=False)
            continue
        raw = path.read_bytes()
        assert len(raw) <= 524288
        records[name] = dict(present=True, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(),
                             base64=base64.b64encode(raw).decode())
    body = json.dumps(dict(root=str(ROOT), stage='C3_NATIVE_ORIGINAL_BYTES_V1', records=records,
        server_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), root_created=OWNED,
        error_type=ERROR, slurm_submissions=0, model_calls=0, pixel_values_read=0,
        automatic_checks_enabled=False), separators=(',', ':')).encode()
    assert len(body) <= 4 * 1024**2
    print('NATIVE_BYTES_BYTES=' + str(len(body)))
    print('NATIVE_BYTES_SHA256=' + hashlib.sha256(body).hexdigest())
    print('NATIVE_BYTES_ZLIB_BASE64=' + base64.b64encode(zlib.compress(body)).decode())
    print('NATIVE_BYTES_DONE', flush=True)


if __name__ == '__main__':
    try:
        main()
    except BaseException as error:
        ERROR = type(error).__name__
    frame()

NATIVE_BYTES
