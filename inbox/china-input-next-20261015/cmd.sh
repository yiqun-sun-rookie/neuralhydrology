#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES='' OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1
exec timeout --signal=TERM --kill-after=3s 3180s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'NATIVE_REPAIR'
"""Deploy one exclusive source catalogue probe; no Slurm submission or science reads."""
import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import resource
import shutil
import subprocess
import time
import zlib

ROOT = Path('/data1/home/sunyiq/china_input_completion_hpc_20261015_001/native_network_repair_20261020_v2')
PAYLOAD_B64 = 'eJzFfFuTolyy9n/p2z2xg4NUFxOxLxRFRaFKEARuJgRUlIO+rRbCjvnvX+ZaHD109/vO7PkuKqpKZR3y8OSTuXL5v99+bE7r/Y9/pOvL/mvzj3RzyY4/on9wDPfGMhzzjy/uv0/5t7//7zcvv2zO3/7O8t973//27RyuOeHt29+/rbdvHLN5Y74LAr/2+ffv7HrLcUFvuxFED/4U2XeG3/B+L9hueVZci28st/U4bx34G/6dEb797Zu3Pm/eejDWdD/dG/JgOF+JV28S7ZxEZL1Ej11pwPiJfPU5N/ZT9ft0Moj9PZv5iXhwba2YTuD1JE7WKyuajvQPM892XvK+8znt5K4EZr1yT04+yBxbKdYrIZ3DPNPd6eTZgy8/XcA8cuEuHUZK4os/FvNAGkSOrcfBOL64i+Zz67FcrMe3k9N6dj3RGV8SDt44jr10MVuv2MzjFWY6jjNnpUd+YhV+1vp8qn15rec9Xp25qfLlGbg+/Qjj7OHZah0LfK21rhz2+xXYyqG9Lp+LUy+Rz63PFR6n/XDt1nomWuH1m2fu9wZjnnHueWLlINe8NRbrJ7fzejW9+mM59zmzNaaVeyiPvQDrkllYGyPtTsaSEc3pkNmZY5lZS+HW5tyTN7a2dh5dUR4ed+NcY3eap4MQ/r8G/dPSGsmGJfXF6UQ/eSvz6qEN8PqXl8SHmRTNdFMYkTFZfWDGi90s7xfq0sykKPyE15b43kwK+ID3r+5E+fLHytcG9cIx6Vzqp+44a16fWIULMvQ4gUH7mCegE8M/SVGgGia7tSxFxfEULmSCyaD42L9/4cjzRM89frD3+N3V4cTLnFe/PmyX9fgAxlGyj5VzW9tWNGdusKFgqzPxUllOM/XQv2mGAGuYXjdJnH1y+vlzOUqlWDcWpibjXCuWmYHsInflgD5lkE94dVZsPKe2GM6Wx9lU6u+mk+AUjHe7max8LtnFbp4PyOdmhgB7s64gg54C9g/7gv2BLBNfVHiLcQ+7dGaAvPNBEUyU2Fkxb9IexpPoD7HLvRAFoNvZWA+D8egMNgN+Z4WeQcYrwEZim5MLh4tPn6YbehMN13dCHwXbF9V9VO8BfO0yg/dBTiB39TyFtblDVl5Gi9PH7kjmrOx2nmroa+CnLPh1CD4awJ6yq2HpytK0DJtV5IWZwRhsuJF2V3XYv8G8l/Wqd0S7gL9jL1mcX9gO2MqgcFewv0QvZkb/8uJzp9niOJMQb/aD0ANb94zdH2CzpZwGubOKC9cYmLhOD2Sq2wrYw/SocMpXsBJg3/oW7AOwCOwexrY5HeSsg+8IsZI3snET+eSB74COAc/AJvfNHGBLRWUPpb6P69UtBkxA7CqCsQy2Zx5dOvd5OlJCn7PkzViLfdwX1ztN4TOAmWcX5AO+zPt5tPuU+kwldzourJlXr449yEC3Eej85PCLYzCJM3fJMht7EM/GFAvAtsCHhdBboQ+DLeDcybvochYDtsmAzsp9ZOAz+IzwhTa4TED3RnRu29nznwEHY57cNN6CvUQwf+qCzQcTPa/WgD4cADYBlgs2p325YxP8evABPgy2n1EclkWUDxPY6ou13T8XndprK2W6+zQGT+dHX/DBnlt7261Bn2tbO3mpxjjgc41OswdMnceWsRxVMgWbBf+YVuPHIuxdZkGXWzsr/SOxYC/KtdQV2g/EGbkAH/7wWCV2x3EOds3MnuDwPApNSx4YYJMnGOcQjMIQ7P/s2tPa/9yxlcDY9Tg2r8S+bcU+2AGs4+zCHmbx++nObuIA59tTGUq744yMMy7nkUWCQzDPscGs+pkmliTWLVhZRSAJ+2AVn93Wc7Xc0no9V3OCuB1PQcYRxJJ8NrmIqHfQQ7NHEFDLh5Ef7EEfR48HeUiD0B3rGD8LxA7Axri1vq8gh9hT+sB6DHY0ZB+e+1zJEcQQWA/gGf7mxDPa5OeKRbtC/Dn7rEhtOYljwLuxs7oBZkTlPGAjtgKxYoE2RvBunrCAPyIDsgSOsivtEfhOGnXw2YH5Ydwur8iFE9h8vb7ZuF7faZ7Ehc0FZ49TQq/f0h/FNYhH5Zqo//Fr4Bmwvi+Hu8SgkwPaegAxG/HbQ9mOY4gPu2Mzd7bThosCdUC4xEpkgyFzgxgAa1V3necOx9m9zwcc4D3wFJ/Lrg7YHfItxEvARtab6GRemL+HOp2nQQ44tQV5H9bg17MxYrkQOzzBO4xT4HPAAWOR6AxiygUwhPxdxTywb7A9K+rYcusHcXKeWpkL+AE2w4Bvbku8AQ65EK2JwrqwVx9tZSxCbM1E8JEDxkRXElDnBWI+xJEz8lOw4/b7iCeAs+ADuDbgPqtiEMz7z9dyh40H1DvhsByszRKBg45ybemINR/dC9Vrx2dzOoDJgRTuIX6EPmCsC3jjLVnTTy3EwOsa5AwYkCJuYBwsbTCmMWWx0+0Q1jAgMQ3sp6gw6yGesOe0iW1BgHHsSayjtjAGTgixH3h+x87/NCcY9jsYjnpc5UEd7xWWeelrU4nZ+bwOMgG7a+tCprxsnsgZwSQphLjgV3IBX9PBlnrVXPe2ktoNBkVeqlI8keoYH/o82ivmE/g68Kf9YLpkNdMscR/x755/OtwNOIaeIC9xDRbHpRyU069+ziKW5pvlezqVzk3cQX4NcgS7hvhgXUlsNcJojTFjjPHcFOkawIdJ3GfSBfBgwNASc4DDDdWs+r/02WgN9gW+R7gO+HgONnMlf+/DZ/huVDGJxCmYC+wNMAtsqGC/K4x8APvMAsl/m0pB6E8G8LwWUrwRcZ8Xyk0DxPsHHHn108KkHLCOYBLBrbEIeaT5HFsJdg6+PCIzxGrQM8SFT6OfA+ds4yXgkY92hbibgT0BxkPshfgwGzqstlT5SmYl5gLOoQ9WnEzmgYe+w7ictjQLre1HY+CM3A3zoghtoLXmay23HH17cVQYkEtKuPdliXbK60fkma11ntAGwRfODsGEwQmwEHS1oPxl+YjLTZy5oT5xnydYB8TG+AoY0hqr8mOSK6As/kBuNE9uXxAjitlECYO8jnthkJiwXsjNWWqj1O76P6aSf6X69c9V/EX52BzyWpPThuwe1hRrh8XVOThMmdfE5fhXkAf9X/odnvmArT/HUqInAbg2+kxAeBHGOyeNGRc4JvpUuY6Wz1TyQ7nInsJWdkTwUAS82iGHad7Xh4hRa7BPHXAP9tx6f3RFHgs53VCXQA+QA0xHNO+6xxKylnpM6m+I1zA21d9wdDdv+zOsp0LYVQjHN1MbbBlwMV/bfbCnHuSNwhnyEsDhXWkL4RfIYnZn2yRPBTzUid8T/w0CjHOIkZhPECxeMju1khXmM5gvUO7V3u8AfJCHGIpc3bMrrnLnR83zkN+Ar6jFtOabzkqD95Wza2BN4UK4wLacF+PfVH4H7o4YDrkS5FMf0l0cQs6axF+QS6BtF+hvyIkcLgyd5BZ3/Lszn8D6ZC/mcSNDPAQ+4UAsBC6LeffJl3bpfO+f0E9w7ZifkvVMdmQ99Z6yX3MDzD1wDoLdRmVfpf1Mwt/TJ/g18BXAMYjHvFXUdlzxPM4i+Sj4dg58LALe3QN9El2jPv/a2gku9R7sArga5PFkT5Qn/VxuVH+NTraPdlJzYxc5KbF/4BxSePIbrnxdA7dseG3YA/nUfI7KdPGbcYeuH8Zrco0kzmyunuu4gVgJ+eLWhXjugL8DDwJONOgRPdRrAp9usPPkoh4liDG2fiJxDXKkmidFsWmYrGzGoqGbsgp5ah2v6/yxPS57flNjpp1LGlhT9CZu7I5IzricjZF39IEv3Ej9tMwll4tOLlDzGVLTsFkR+FzM2Ox7nTtW3KKR7Z2P8cC3MU8k9YUY5KJv7bzO10iN8XO5YNS8k2MUKo5Z5QdD9rdyiK6/arE3dq7NuhB/ah3N2vuq8xgpBE55S2admDnAGuIVc+fSVnZVjjJPNOQDyNc7n5mV4wC3bHLJIe4xKutXFmDOQqQyFJiq1tRdvw5c7zF2l8+Q2i9dC/m/JQeBB7zLbL7K88LO2kDmGLvQ9rdEdyVHLMeh+VSH11g9yt0GEsbodp7wmGd1ZQXyAQzSMG4/7gNyBqwz1/Wysch7lFeg35w8g8gQOSjykMoOsfZDMGqOc/EW8JWX9WTMGyr+UtfoUGbeKr7ORtaHLvUv0+E0m7fGRd6iHvxMrblPOw8VsK5Q11+ITcmXgMSvyh/JODH4Mr5X1W/7qc7clKUhvAE+X5vP+NX6wP+RR6ONhsCJQsqvAfPUg8nV8iO2ZJ3p5yiPwvzABx4HsUgsuQXgjZi4IIP1Sj7bHBlv69huuF7dCIZ26rrALf0EbEAWazz8NAJrGV0+lmzwoeSv+fiG4F6Mdpf6gAsb8APgr+gbUWsOrCUDf9WxXnKweXzdAowSyVkN5t21rB9sHmtJGcbmyXIUazZrGct+NyZXXB71Svhux3YJ7m5p/FMAt4N4NlycnthttRac6/4s5Iq5FsxzXoOS8e+Of0hdjkafAftMNZTFBbkJ5AApqV1O1LSs21bzXVs+SGKdMRKXllzGsQnN7SDPr86brlMpJDU5iAGMNlRPD3y4iYskB2jWQ85DyDlCuYa798keeJgnevp+4ubOKrhgrHick3BFlN2zff0k/6DPkRiP+AO4Ac+eIUcE2xNXuqUoehTLugxxz9I+l7JL/l6ylqkb/pNxMZddoD9HmKdBfnx1jUfs6da7iJ9Wdb7IkHUTQuyximvNunSPvCYzT2R+hxFNTaEbFx7tBmuFmOe9tLsA+Bb49wniG/A6yJ8kH/lyLWefnL9lLT0iNikC1rIhT/zFWnutHH4HGGWZConDco4cHeY5ohwRFz7tc2oQmUAOT/WGeho4HKkfXfTmLCr92IO9r3Ti88EkSn+vBvY7P4GFtj035RTtUCmOO8iPj1jzMlZCFtj6h4P8KbGA7wzCtT39Uo1AfCL3Vk6PWNqVCe69lZMfnz3v8aQ2UNZZiDzqOgvoPvYPbBO/ZJqb2Fhb5PHMwQJ5PqtD/Kr2QWxkW8WFz9WTWEHqL0LsJeQc5Pi69tf6mVQ1eL14Xg9r20+cPK+hYI2rf1QLPLfrF+pwCvFXzZDXwWs8fW33BHvpjzcWD6g7kP99zQVrnKUdTo8KAxyBo2dv3TrIUww8A08q60x3dZEHndKfqi73vL52+sLzSHxv3hn7xTracvoJF3rml1gLfG57FX+q7RPlRc9pntZGCCcDeQns455bcatVg6pslOZF00x98N/BHnOydfa0/tXS3Z3My9zvt+d6Oua9PTT1sTYGIf61MWhWxeHWa91zwTAr488v7O+X9bhapu0xsfaDdenpSAA9m4idn2YUTwxTGCxlcWBG2tSwXNlmbvIyCkyDxDzZMixF1iX/6fjqss98DE1e22OdEbnc4tia8zQdZijT3Wzfv4E/MrP9sejWRDFeTnl12D+3OXI3D6G9CA1nbXoQnD3Wq+Si7iF4kq8EXHjyxuaOnK08eb+0/SPEuR/3tVAc05V2tH76yscQj8bCF9jIYT2xruvixRyv7Lb1s6a5IAtypLWK4U/HqvXgcCHrJRfv46DT+sx4mpqji78Z9gt7sss0yS85jb5dssBpmPhjYd62qyhe2IzyqctdW+z4Ls1xfoB+aT2MzHV+xOWHNZX7wJrZvv/HdDjK1MPij9lBfSHHKgdpalu/mKvqMbkGvHL66efrHhMhAe5frKXd3XlOo/OnuEd5fDcPJ7WULu/6a/noE5kdmJZvUcxq2wX4CMR8qwd+cCD1sufnAM/Po4YZnsmHLnA6wIH2OhLkMT/JG9PnZ8XE9stnhXgzjkEvald+JI+AfHGVoU/RXqLybO6+xknzy7YNNPlldT5a1cZLmeDZ7NFZTlntwFY19H/XeSNdj/yvnzlSrBtl/0G7whjCepMF8HjaazhDf+Es5KeRzSkC2E7xudKwr4ghdYWVFq9tF/hic/5byXCehCC7ykd3pzIHYEiOz5O5yPm4O2Tr1+eJ1VuTOgV8/hccHHJzsAvglqTnAewX1vhphLTPT3oHno19cwzpbVPwTMYOT8gX6Vl4wx8Jr6245C/mxHNskGPkF+yvz26lhzOvF/7VE9ux7InuHvWC+rYBX+HvVt2iySEtMXGwf6XuEeispXBAZxAPyxoFnisLSz2yjHlyKoDLpfNmzg7uYbwhNU9DuMD6sefgul6B7xr9/8Lcop7/WR0QMDNY3ZhWPwPIks28scW4y6onpY011pb4DODVp6XnwcrsYjDpR9xRvLHEcclLJgtLl1v7KPOdlrzsxkdbWJGSXOfP6ff07+kR+Iu28Qvsa2przfM2R2pq6HO0z+K+Jl+N2a97BRLEC4foSsB+50OrZ6DKKZv3CO5BfpGMUvv+7LHuxUC7rM6AKMctn7moRk+YH5yLw2Mf7aj+7a3k62YFNpFaPdK3Kou9j6G7xfNX4GtnJXs+V4n71Tw3wCdOLSJOe/H5Kietzn6UYtFzDk6uLne5etDjj6UbuUsrVgt3r62sPXxWcA8qry6dTB1G8Bkng/fhM+Cn3KKnJhqM18+cwwjWG4TOMoLfizIu/n4Nr+zpwNpi+uTcsamtcBrwfjYmnE4KjsFEz/zcv6/NNf1IjfzBN9SrPwG7RZ8mtTCsoYm5m/t/tk+swo5WveEpXoWBrX+BbmEsbYs26Cdx7BdMHfPqeN2uNxPu/7Oac80dcP46Hsye2x8562/Vt3/S60b7TvCch/R9AxaAbjsY8Bu9KNhL6yk81jwCrMPXZymfy0VW9oU1udzPeiF+3hdSniuS/oh2bljXx8CehnWvuXmDdQaw9iCgeeeArrOM+UrV9ys97LUVu8UM+b7Ch3uIt7S3hdfxvOnyqobyW7lWyV9IroTnF519I59fHLWDyaqF84L3N7GL5LNl7vZqTa05f5p7UR+kXGgqncWyN6Vc54vc7xV/J3kk8fH9BnwE+zJ+tpdKrtiDuKZ8gOzpVe2FrvX38qWGp5d7Qyx5wFOaY7zieu1nWpj6NId5wScuHbwhtbhOr1Njd2ADFMsa7lfKMsFYV53Z/5W8oalb1rK767upsLg+c2z3vBMfKPu33+7zR+RCuEbkadgbWfYE1v/Xfe51fwjhu+e786bQT5gj5H4P+ekd12pzdWpjBVvm6hl+/uCuYg7vCvx6z1lTW5HFDOci57PANVs1lyav+1V/XHMfQ/wNW3jgoy1ZdvsrMScu+tl/kE8DBxU/FpZompH8YTKubO6FP6re/Gqd3XwOa9PP74fMjdYZL/JAjD1P6jv/Z7w6ij+XkbyF36T2ozOyqRvNfsD3D/Ssvp6rlKvu4Z2GSp6gi/Of1fFdX8Rf7jX5Sb7SxZdntvKf4dcXB8/2W/0CVb5Q7W/W7H9pmAHkOIqG3IneBWqds0Ms8RPCBeJgosB62FMZ++ndPEMwMN+DPGS7sNTzVNphvt6utebz9l0+WkfOwf4vlINaBeBF7gA3NSPIuczYtBl5ObPON7u+s9J5vvj18+7SsE4y6Ox4V/M7d/aUBL/ckx5ryioyT6tCDmaPHJnU9D1evQLf4YCf4b0y2q/KaqplKZrNnD4XsajoDQds5Tx45kZyyqs3FkMXca1V81ow4oclK4MFu6j6Rk+Um+jbMmYen6wJ8HF6NCPx0wJ/x3yD9MRMlBC4I3BEWCO/qPOoznnzpNw/7QP8vgX/3vBMVU/CGhHh+KQ2NKJ3Ebu2/bxXp6w5sc/PD4Oi20sEOqH9SYAp7tesOmMdlr1R9M5WdefzajLi0GCxVwDzX+bujhOtrU1HZRyl51/IhWmt7MldDSJvxny4K3Z3Tyav+sj8A5P6fIx5zYXgV1WPW7KPMdd4euaI951Q3nXvTCnvp/W7fxW7Kl0GNrn7VWA/Bej+uOEVT5OxN7bqc5yWPYd4p47UEnLsb6UcrL47M9DBtpeRZW6N2Ps4KMFd7aJ3108JY+ikT7a0p7zsSSEyIHE3Pmc0r67v9V4Xprs1TEG2hq4IuPCmWh3Ol+A9tqa/jdwxSBATsIcJ1/AkVp9+fmeq39JpVPVSVj1sRC4gI9Yva+Ll3QaCBXc9HI+6K2P70zPxEpd8tnqt06uHZyfFxsZxmU4NHHxbeLLHTj8o5syt+xkPdk/u9v35fTyTfXveF8+1eBbo3knM42P/ZFbfCbHJvQ//5Zn5v0GutKbBkjsYL86g2jmPgnnSj/8fWEP7p7StOxaKv4Y3/0KPbcnh0N8tRjQAdw3dGgwMa/p4r4Ho1SqAC9L7RW3dDFs9Id3eom19Z57cKSv11ukHIX7b21hljgC55CfW8QyIE7kQe6l7gvevJI5I4Y+ZQW10XfZlKAzp792aEGeBhqdzKZhasr4wWXEBMdNZGf5ZYWR1KTf///m7Fq9+qJ3hOYXHhwLor9anT+58kvUAB7vV/8/u7hST18cx9g3i/dlOfyHFBpb0wEJel4It0L6MGPsRsfcf9LHs39/drPpNqhyk4Vz0rJ/kj0/qtVX9ruRMpBfzK+CEs8fJEd7HXK+YYwtDqnHvcss6z/nQLd1essrcZjVzYQYy1rRN1lIt6SE/oOsh/catPIHWoB7zhDGuhcil5tmVbUF+14yBPfids5rmLv2n/TKfKr/PAb+Hw+JtXkMfvNjc6ctJVVEl9t36bg6QO+RO2De7rXrVUCcdGxvjHVvrbHMa2gLV2VhmIc+4oK5gDNpfygMOrATSy9rcv83wXBZ7wLDPHziyVtD7+XJG7nMmHZtBHyK11JefuZdH2TMN4x8gl8d7s2XNtv035ER52HyviEF7uzek90WAfdA7ux4HHCBhQ9Kz/shjX54bY530/n4iPYvGM+A+ubuCd8fudVv2c5b5gnVvJ+V9asidZXFL6juWuC1r3lubYyEHE7Z27r+9quWWvdw7s+QOuh1iXlHlYg9nv53PdXLw8vsXqhpNHVsevv/gdS3oX71b+oj1aOcT3RLHCzPG3ObJeRiNO58rkq+CXurvbjjN/5wv/fbdx+fx+bHuMuvWVqrvt1iWmAkyjRnIUU7S7n/+59s///ZN+tCWel9a/vfhfEzb3wnE9t5aXwnUY98439tsApFl+R4TeG/euxD0fG4dvPU2a4/nNpzHvgk8uxVEhmE3jB9wvrheb7ZvG9//3v5KoA0pCYO4OJGZHuDvvUiuHqmGeAQzjue8xnppfPINdP8Y4e/kpQM2kBsYpG4cZg77nkP6zQHM3jTrPVOHIxCzzGCpzuYESHsDcL0LhtsMRJHbBX51i4MpO4QnJ5/uiQr25RHa/mM/+F6axx5gC1I1OXWN6Rusd0xDw7SCsD1eDwbzAzqA709v80N01fbN+62jEhi3nuMvH9OVa0XZ4VEWGbNsM3+b5yIp1wI1yDb4lUMcPabCYy1IfdI5PwghlQkxNM4LOZpzI37OmbnKubFz8AXn4BTu0C/UlZOrhXNzilHhJtOeOzYZlK87jAT1EEbaymHcocN/jE1WOzg9Jxll2sHsfSxVwTHEMnwypSzYgz9Ub6pR/waIEAQsCQb2DvQ2Ymx+19Pid06TBH49zvY1DCf06ATtQ12anHZQBe1QU5R9VWYl9nP4PzlmbNZCv7ICv46CrGfVHGnsydeRpCqWwG4fRi+fH/r7VijZk2v64zhZN3aD+sOvljoAVfuvz+XuqkrP3gM7n1gpfj0Mli/BZrJG/ygfDUJ98Ad5T+qxnfdS7bTpjll+JRSW2aZgZxbjrOgV3498UNnLtrHn/vtUzvZq3rup8Ls7r4stMuGKhGz1DBZzRj0FkE7DWPFmoudOeSyK5XYl76yjAHoGKcBNmA7PCPdAsUb0qJiOl3bnwq9leK/2X8wPo4c5YP706fp4tYD05zseLWBJqAxvDB633K0pI+V8npQx+Yd18eS97hzpgNhmIOERgPOwJvqe37EDPBre7F+uh44tY7o/EOlzSuTxAS2XjS1KMyfxhVDoxCKUGG0xoEctBMN83sJr90ArXNbDliI73AJuxCDvAr8GpnXlivoVDT/7J3QOsSUr10G+VgXGO6A+/RywbljSuOQXVE2Cz47Lq80pM/v2z3/+PyEmUcU='
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
    assert shutil.disk_usage(ROOT.parent).free >= 3 * 1024**3
    ROOT.mkdir(mode=0o700)
    OWNED = True
    payload = json.loads(zlib.decompress(base64.b64decode(PAYLOAD_B64, validate=True)))
    assert set(payload) == {'CONTRACT.json', 'repair_native_network_20261020_v2.py'}
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
             str(ROOT / 'repair_native_network_20261020_v2.py')],
             stdin=subprocess.DEVNULL, capture_output=True, env=env, timeout=3160)
        assert len(outcome.stdout) <= 65536 and len(outcome.stderr) <= 65536
        save('PROCESS_RESULT.json', dict(exit_code=outcome.returncode, stdout_bytes=len(outcome.stdout),
             stderr_bytes=len(outcome.stderr), raw_process_output_saved=False, seconds=time.monotonic() - START))
    except subprocess.TimeoutExpired:
        save('PROCESS_RESULT.json', dict(status='PROCESS_TIMEOUT', exit_code=None, seconds=time.monotonic() - START))
    assert sum(p.stat().st_size for p in ROOT.iterdir() if p.is_file()) <= 4 * 1024**3 + 4 * 1024**2


def frame():
    records = {}
    names = ['DEPLOYMENT.json', 'PROCESS_RESULT.json', 'NETWORK_REPAIR.json', 'DNS_www.dropbox.com.json', 'DNS_dl.dropboxusercontent.com.json', 'FIONA_TRANSFER.json', 'FIONA_FINAL_GATE.json', 'GLIM_TRANSFER.json', 'GLIM_FINAL_GATE.json', 'NETWORK_STAGE_RESULT.json', 'NETWORK_STAGE_FAILURE.json']
    for name in names:
        path = ROOT / name
        if not OWNED or not path.is_file():
            records[name] = dict(present=False)
            continue
        raw = path.read_bytes()
        assert len(raw) <= 524288
        records[name] = dict(present=True, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(),
                             base64=base64.b64encode(raw).decode())
    body = json.dumps(dict(root=str(ROOT), stage='C3_NATIVE_NETWORK_REPAIR_V1', records=records,
        server_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), root_created=OWNED,
        error_type=ERROR, slurm_submissions=0, model_calls=0, pixel_values_read=0,
        automatic_checks_enabled=False), separators=(',', ':')).encode()
    assert len(body) <= 4 * 1024**2
    print('NATIVE_REPAIR_BYTES=' + str(len(body)))
    print('NATIVE_REPAIR_SHA256=' + hashlib.sha256(body).hexdigest())
    print('NATIVE_REPAIR_ZLIB_BASE64=' + base64.b64encode(zlib.compress(body)).decode())
    print('NATIVE_REPAIR_DONE', flush=True)


if __name__ == '__main__':
    try:
        main()
    except BaseException as error:
        ERROR = type(error).__name__
    frame()

NATIVE_REPAIR
