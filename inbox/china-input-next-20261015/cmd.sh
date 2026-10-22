#!/bin/bash
set -eo pipefail
umask 077
export PYTHONDONTWRITEBYTECODE=1 CUDA_VISIBLE_DEVICES=''
exec timeout --signal=TERM --kill-after=5s 160s /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'CHUNKED_CATALOGUE_QUERY'
"""One finite HPC public-directory session; no GIS, source archives or Slurm."""
import base64
import datetime
import hashlib
import io
import sys
from http.client import HTTPResponse, IncompleteRead
import json
import re
import resource
import signal
import time
from html.parser import HTMLParser
from urllib.error import HTTPError
from urllib.parse import urljoin, urlparse
from urllib.request import build_opener, HTTPRedirectHandler, ProxyHandler, Request
import zlib

START = time.monotonic()
REUSED_CGS_METADATA_B64 = 'eyJkYXRhIjp7ImlkIjoiMTAuMzUwODAvZGF0YS5jLjIwMjEucDIzIiwidHlwZSI6ImRvaXMiLCJhdHRyaWJ1dGVzIjp7ImRvaSI6IjEwLjM1MDgwL2RhdGEuYy4yMDIxLnAyMyIsInByZWZpeCI6IjEwLjM1MDgwIiwic3VmZml4IjoiZGF0YS5jLjIwMjEucDIzIiwiaWRlbnRpZmllcnMiOltdLCJhbHRlcm5hdGVJZGVudGlmaWVycyI6W10sImNyZWF0b3JzIjpbeyJuYW1lIjoi5q+N5rW35LicO+mZiOi+iTvlvKDlv5fpo5475byg5paMIiwibmFtZVR5cGUiOiJQZXJzb25hbCIsImdpdmVuTmFtZSI6bnVsbCwiZmFtaWx5TmFtZSI6Iuavjea1t+S4nDvpmYjovok75byg5b+X6aOeO+W8oOaWjCIsImFmZmlsaWF0aW9uIjpbXSwibmFtZUlkZW50aWZpZXJzIjpbXX1dLCJ0aXRsZXMiOlt7ImxhbmciOiJ6aCIsInRpdGxlIjoi5Lit5Zu95Zyw6LSo6LCD5p+l5bGAOiDlhajlm70x4oi2MjAwIDAwMOWMuuWfn+awtOaWh+WcsOi0qOWbvuepuumXtOaVsOaNruW6kyIsInRpdGxlVHlwZSI6IkFsdGVybmF0aXZlVGl0bGUifSx7ImxhbmciOiJlbiIsInRpdGxlIjoiTmF0aW9uYWwgMToyMDAsMDAwIFJlZ2lvbmFsIEh5ZHJvbG9naWNhbCBHZW9sb2dpY2FsIE1hcCBTcGF0aWFsIERhdGFiYXNlIiwidGl0bGVUeXBlIjoiQWx0ZXJuYXRpdmVUaXRsZSJ9XSwicHVibGlzaGVyIjoiR2Vvc2NpZW50aWZpYyBEYXRhIFx1MDAyNiBEaXNjb3ZlcnkgUHVibGlzaGluZyBTeXN0ZW0iLCJjb250YWluZXIiOnt9LCJwdWJsaWNhdGlvblllYXIiOjIwMjEsInN1YmplY3RzIjpbXSwiY29udHJpYnV0b3JzIjpbeyJuYW1lIjoi5q+N5rW35LicO+mZiOi+iTvlvKDlv5fpo5475byg5paMIiwibmFtZVR5cGUiOiJQZXJzb25hbCIsImdpdmVuTmFtZSI6bnVsbCwiZmFtaWx5TmFtZSI6bnVsbCwiYWZmaWxpYXRpb24iOltdLCJjb250cmlidXRvclR5cGUiOiJDb250YWN0UGVyc29uIiwibmFtZUlkZW50aWZpZXJzIjpbXX1dLCJkYXRlcyI6W3siZGF0ZSI6bnVsbCwiZGF0ZVR5cGUiOiJJc3N1ZWQiLCJkYXRlSW5mb3JtYXRpb24iOm51bGx9XSwibGFuZ3VhZ2UiOiJ6aCIsInR5cGVzIjp7InJpcyI6IkRBVEEiLCJiaWJ0ZXgiOiJtaXNjIiwiY2l0ZXByb2MiOiJkYXRhc2V0Iiwic2NoZW1hT3JnIjoiRGF0YXNldCIsInJlc291cmNlVHlwZUdlbmVyYWwiOiJEYXRhc2V0In0sInJlbGF0ZWRJZGVudGlmaWVycyI6W10sInJlbGF0ZWRJdGVtcyI6W10sInNpemVzIjpbXSwiZm9ybWF0cyI6W10sInZlcnNpb24iOiIxLjAuMCIsInJpZ2h0c0xpc3QiOltdLCJkZXNjcmlwdGlvbnMiOlt7ImxhbmciOiJ6aCIsImRlc2NyaXB0aW9uIjoi5YWo5Zu9MeKItjIwMCAwMDDljLrln5/msLTmloflnLDotKjlm77nqbrpl7TmlbDmja7lupPku6Xlu7rlm73lkI7lnKjlhajlm73ojIPlm7TlhoUo5pys5qyh5pyq5Zyo6aaZ5riv54m55Yir6KGM5pS/5Yy644CB5r6z6Zeo54m55Yir6KGM5pS/5Yy65ZKM5Y+w5rm+55yB5byA5bGV5bel5L2cKSAzMOS4quecgeW8gOWxleeahDHiiLYyMDAgMDAw5Yy65Z+f5rC05paH5Zyw6LSo5pmu5p+l5bel5L2c5omA5Y+W5b6X55qE5Yy65Z+f5rC05paH5Zyw6LSo5pmu5p+l5oql5ZGK44CB57u85ZCI5rC05paH5Zyw6LSo5Zu+562J5Zyw6LSo6LWE5paZ5Li65pWw5o2u5rqQ77yM5Zyo5Yi25a6a55qE4oCcMeKItjIwMCAwMDDljLrln5/msLTmloflnLDotKjlm77nqbrpl7TmlbDmja7lupPlm77lsYLlj4rlsZ7mgKfmlofku7bmoLzlvI/moIflh4bigJ3nmoTln7rnoYDkuIrvvIzlu7rmiJDkuobkuIDkuKrlhajlm73mgKfnmoTjgIHlpKflnovnmoTljLrln5/msLTmloflnLDotKjlrabnqbrpl7TmlbDmja7lupPjgILor6XmlbDmja7lupPmgLvlhbHph4fpm4bjgIHlpITnkIbkuoblhajlm73ojIPlm7TlhoUx4oi2MjAwIDAwMOWbvuW5heeahFx1MDAzY251bWJlclx1MDAzZTEgMDE3XHUwMDNjL251bWJlclx1MDAzZeW5heWFqOimgee0oOe7vOWQiOawtOaWh+WcsOi0qOWbvuS/oeaBr++8jOWFqOmDqOaVsOaNrumHj+e6pjUwIEdC44CC5pWw5o2u5bqT5ra155uW5LqG5LulMeKItjIwMCAwMDDlm73pmYXmoIflh4blm77luYXkuLrnrqHnkIbljZXkvY3nmoTmsLTmloflnLDotKjopoHntKDnqbrpl7TmlbDmja7lm77lsYLvvIzlhoXlrrnljIXmi6zvvJrlnLDnkIbopoHntKAo5Lqk6YCa5bGC44CB5rC057O75bGC44CB6KGM5pS/5Yy65YiS5bGC562JKe+8jOWfuuehgOWcsOi0qOimgee0oCjlnLDlsYLliIbljLrlsYLjgIHmlq3oo4LmnoTpgKDlsYIp77yM5rC05paH5Zyw6LSo6KaB57SgKOWcsOS4i+awtOexu+Wei+WxguOAgeWcsOS4i+awtOWvjOawtOaAp+WxguOAgeWcsOS4i+awtOi/s+a1geaooeaVsOWxgu+8jOWcsOS4i+awtOawtOi0qOWxguOAgeawtOaWh+WcsOi0qOeJueW+geWxguOAgeWcsOS4i+awtOWIqeeUqOinhOWIkuWxginvvIzkuJPpopjopoHntKAo57u85ZCI5rC05paH5Zyw6LSo5p+x54q25Zu+77yM5rC05paH5Zyw6LSo5YmW6Z2i5Zu+KSDlm5vlpKfnsbvov5EzMOS4quimgee0oOWbvuWxguOAguepuumXtOaVsOaNruW6k+S4u+imgemHh+eUqE1hcEdJU+WcsOeQhuS/oeaBr+ezu+e7n+agvOW8j+WtmOWCqO+8jOW9ouaIkOS6huebruWJjeWbveWGheimhuebluiMg+WbtOacgOW5v+OAgeWMheWQq+S/oeaBr+acgOWujOaVtOeahOWMuuWfn+awtOaWh+WcsOi0qOWbvuepuumXtOaVsOaNruW6k+aIkOaenO+8jOaYr+WcsOi0qOmihuWfn+WFqOWbveaAp+acgOmHjeimgeeahOWfuuehgOS/oeaBr+i1hOa6kOS5i+S4gOOAgiIsImRlc2NyaXB0aW9uVHlwZSI6IkFic3RyYWN0In1dLCJnZW9Mb2NhdGlvbnMiOltdLCJmdW5kaW5nUmVmZXJlbmNlcyI6W10sInhtbCI6IlBEOTRiV3dnZG1WeWMybHZiajBpTVM0d0lpQmxibU52WkdsdVp6MGlWVlJHTFRnaVB6NEtQSEpsYzI5MWNtTmxJSGh0Ykc1ek9uaHphVDBpYUhSMGNEb3ZMM2QzZHk1M015NXZjbWN2TWpBd01TOVlUVXhUWTJobGJXRXRhVzV6ZEdGdVkyVWlJSGh0Ykc1elBTSm9kSFJ3T2k4dlpHRjBZV05wZEdVdWIzSm5MM05qYUdWdFlTOXJaWEp1Wld3dE5DSWdlSE5wT25OamFHVnRZVXh2WTJGMGFXOXVQU0pvZEhSd09pOHZaR0YwWVdOcGRHVXViM0puTDNOamFHVnRZUzlyWlhKdVpXd3ROQ0JvZEhSd09pOHZjMk5vWlcxaExtUmhkR0ZqYVhSbExtOXlaeTl0WlhSaEwydGxjbTVsYkMwMEwyMWxkR0ZrWVhSaExuaHpaQ0krQ2lBZ1BHbGtaVzUwYVdacFpYSWdhV1JsYm5ScFptbGxjbFI1Y0dVOUlrUlBTU0krTVRBdU16VXdPREF2UkVGVVFTNURMakl3TWpFdVVESXpQQzlwWkdWdWRHbG1hV1Z5UGdvZ0lEeGpjbVZoZEc5eWN6NEtJQ0FnSUR4amNtVmhkRzl5UGdvZ0lDQWdJQ0E4WTNKbFlYUnZjazVoYldVZ2JtRnRaVlI1Y0dVOUlsQmxjbk52Ym1Gc0lqN21yNDNtdGJma3VKdzc2Wm1JNkw2Sk8rVzhvT1cvbCttam5qdmx2S0RtbG93OEwyTnlaV0YwYjNKT1lXMWxQZ29nSUNBZ0lDQThabUZ0YVd4NVRtRnRaVDdtcjQzbXRiZmt1Snc3NlptSTZMNkpPK1c4b09XL2wrbWpuanZsdktEbWxvdzhMMlpoYldsc2VVNWhiV1UrQ2lBZ0lDQThMMk55WldGMGIzSStDaUFnUEM5amNtVmhkRzl5Y3o0S0lDQThkR2wwYkdWelBnb2dJQ0FnUEhScGRHeGxJSFJwZEd4bFZIbHdaVDBpUVd4MFpYSnVZWFJwZG1WVWFYUnNaU0lnZUcxc09teGhibWM5SW5wb0lqN2t1SzNsbTczbG5MRG90S2pvc0lQbW42WGxzWUE2SU9XRnFPV2J2VEhpaUxZeU1EQWdNREF3NVl5NjVaK2Y1ckMwNXBhSDVaeXc2TFNvNVp1KzU2bTY2WmUwNXBXdzVvMnU1YnFUUEM5MGFYUnNaVDRLSUNBZ0lEeDBhWFJzWlNCMGFYUnNaVlI1Y0dVOUlrRnNkR1Z5Ym1GMGFYWmxWR2wwYkdVaUlIaHRiRHBzWVc1blBTSmxiaUkrVG1GMGFXOXVZV3dnTVRveU1EQXNNREF3SUZKbFoybHZibUZzSUVoNVpISnZiRzluYVdOaGJDQkhaVzlzYjJkcFkyRnNJRTFoY0NCVGNHRjBhV0ZzSUVSaGRHRmlZWE5sUEM5MGFYUnNaVDRLSUNBOEwzUnBkR3hsY3o0S0lDQThjSFZpYkdsemFHVnlQa2RsYjNOamFXVnVkR2xtYVdNZ1JHRjBZU0FtWVcxd095QkVhWE5qYjNabGNua2dVSFZpYkdsemFHbHVaeUJUZVhOMFpXMDhMM0IxWW14cGMyaGxjajRLSUNBOGNIVmliR2xqWVhScGIyNVpaV0Z5UGpJd01qRThMM0IxWW14cFkyRjBhVzl1V1dWaGNqNEtJQ0E4Y21WemIzVnlZMlZVZVhCbElISmxjMjkxY21ObFZIbHdaVWRsYm1WeVlXdzlJa1JoZEdGelpYUWlMejRLSUNBOFkyOXVkSEpwWW5WMGIzSnpQZ29nSUNBZ1BHTnZiblJ5YVdKMWRHOXlJR052Ym5SeWFXSjFkRzl5Vkhsd1pUMGlRMjl1ZEdGamRGQmxjbk52YmlJK0NpQWdJQ0FnSUR4amIyNTBjbWxpZFhSdmNrNWhiV1VnYm1GdFpWUjVjR1U5SWxCbGNuTnZibUZzSWo3bXI0M210YmZrdUp3NzZabUk2TDZKTytXOG9PVy9sK21qbmp2bHZLRG1sb3c4TDJOdmJuUnlhV0oxZEc5eVRtRnRaVDRLSUNBZ0lEd3ZZMjl1ZEhKcFluVjBiM0krQ2lBZ1BDOWpiMjUwY21saWRYUnZjbk0rQ2lBZ1BHUmhkR1Z6UGdvZ0lDQWdQR1JoZEdVZ1pHRjBaVlI1Y0dVOUlrbHpjM1ZsWkNJdlBnb2dJRHd2WkdGMFpYTStDaUFnUEd4aGJtZDFZV2RsUG5wb1BDOXNZVzVuZFdGblpUNEtJQ0E4YzJsNlpYTXZQZ29nSUR4bWIzSnRZWFJ6THo0S0lDQThkbVZ5YzJsdmJqNHhMakF1TUR3dmRtVnljMmx2Ymo0S0lDQThaR1Z6WTNKcGNIUnBiMjV6UGdvZ0lDQWdQR1JsYzJOeWFYQjBhVzl1SUhodGJEcHNZVzVuUFNKNmFDSWdaR1Z6WTNKcGNIUnBiMjVVZVhCbFBTSkJZbk4wY21GamRDSSs1WVdvNVp1OU1lS0l0akl3TUNBd01ERGxqTHJsbjUvbXNMVG1sb2ZsbkxEb3RLamxtNzducWJycGw3VG1sYkRtamE3bHVwUGt1NlhsdTdybG03M2xrSTdsbktqbGhhamxtNzNvaklQbG03VGxob1VvNXB5czVxeWg1cHlxNVp5bzZhYVo1cml2NTRtNTVZaXI2S0dNNXBTLzVZeTY0NENCNXI2ejZaZW81NG01NVlpcjZLR001cFMvNVl5NjVaS001WSt3NXJtKzU1eUI1YnlBNWJHVjViZWw1TDJjS1NBek1PUzRxdWVjZ2VXOGdPV3hsZWVhaERIaWlMWXlNREFnTURBdzVZeTY1WitmNXJDMDVwYUg1Wnl3NkxTbzVwbXU1cCtsNWJlbDVMMmM1b21BNVkrVzViNlg1NXFFNVl5NjVaK2Y1ckMwNXBhSDVaeXc2TFNvNXBtdTVwK2w1b3FsNVpHSzQ0Q0I1N3U4NVpDSTVyQzA1cGFINVp5dzZMU281WnUrNTYySjVaeXc2TFNvNkxXRTVwYVo1TGk2NXBXdzVvMnU1cnFRNzd5TTVaeW81WWkyNWE2YTU1cUU0b0NjTWVLSXRqSXdNQ0F3TUREbGpMcmxuNS9tc0xUbWxvZmxuTERvdEtqbG03N25xYnJwbDdUbWxiRG1qYTdsdXBQbG03N2xzWUxsajRybHNaN21nS2ZtbG9ma3U3Ym1vTHpsdkkvbW9JZmxoNGJpZ0ozbm1vVGxuN3Jub1lEa3VJcnZ2SXpsdTdybWlKRGt1b2JrdUlEa3VLcmxoYWpsbTczbWdLZm5tb1RqZ0lIbHBLZmxub3ZubW9UbGpMcmxuNS9tc0xUbWxvZmxuTERvdEtqbHJhYm5xYnJwbDdUbWxiRG1qYTdsdXBQamdJTG9yNlhtbGJEbWphN2x1cFBtZ0x2bGhiSHBoNGZwbTRiamdJSGxwSVRua0lia3VvYmxoYWpsbTczb2pJUGxtN1RsaG9VeDRvaTJNakF3SURBd01PV2J2dVc1aGVlYWhDWnNkRHR1ZFcxaVpYSW1aM1E3TVNBd01UY21iSFE3TDI1MWJXSmxjaVpuZER2bHVZWGxoYWpvcG9IbnRLRG51N3psa0lqbXNMVG1sb2ZsbkxEb3RLamxtNzdrdjZIbWdhL3Z2SXpsaGFqcGc2am1sYkRtamE3cGg0L251cVkxTUNCSFF1T0FndWFWc09hTnJ1VzZrK2EydGVlYmx1UzZodVM3cFRIaWlMWXlNREFnTURBdzVadTk2Wm1GNXFDSDVZZUc1WnUrNWJtRjVMaTY1NjZoNTVDRzVZMlY1TDJONTVxRTVyQzA1cGFINVp5dzZMU282S2FCNTdTZzU2bTY2WmUwNXBXdzVvMnU1WnUrNWJHQzc3eU01WWFGNWE2NTVZeUY1b3VzNzd5YTVaeXc1NUNHNkthQjU3U2dLT1M2cE9tQW11V3hndU9BZ2Vhd3RPZXp1K1d4Z3VPQWdlaWhqT2FVditXTXV1V0lrdVd4Z3VldGlTbnZ2SXpsbjdybm9ZRGxuTERvdEtqb3BvSG50S0FvNVp5dzViR0M1WWlHNVl5NjViR0M0NENCNXBhdDZLT0M1cDZFNllDZzViR0NLZSs4ak9hd3RPYVdoK1djc09pMHFPaW1nZWUwb0NqbG5MRGt1SXZtc0xUbnNidmxub3Zsc1lMamdJSGxuTERrdUl2bXNMVGxyNHptc0xUbWdLZmxzWUxqZ0lIbG5MRGt1SXZtc0xUb3Y3UG10WUhtcUtIbWxiRGxzWUx2dkl6bG5MRGt1SXZtc0xUbXNMVG90S2psc1lMamdJSG1zTFRtbG9mbG5MRG90S2puaWJubHZvSGxzWUxqZ0lIbG5MRGt1SXZtc0xUbGlLbm5sS2pvcDRUbGlKTGxzWUlwNzd5TTVMaVQ2YUtZNkthQjU3U2dLT2U3dk9XUWlPYXd0T2FXaCtXY3NPaTBxT2Fmc2VlS3R1V2J2dSs4ak9hd3RPYVdoK1djc09pMHFPV0psdW1kb3VXYnZpa2c1WnViNWFTbjU3Rzc2TCtSTXpEa3VLcm9wb0hudEtEbG03N2xzWUxqZ0lMbnFicnBsN1RtbGJEbWphN2x1cFBrdUx2b3BvSHBoNGZubEtoTllYQkhTVlBsbkxEbmtJYmt2NkhtZ2EvbnM3dm51NS9tb0x6bHZJL2xyWmpsZ3FqdnZJemx2YUxtaUpEa3VvYm5tNjdsaVkzbG03M2xob1hvcG9ibm01Ym9qSVBsbTdUbW5JRGx1Yi9qZ0lIbGpJWGxrS3ZrdjZIbWdhL21uSURscm96bWxiVG5tb1RsakxybG41L21zTFRtbG9mbG5MRG90S2psbTc3bnFicnBsN1RtbGJEbWphN2x1cFBtaUpEbW5wenZ2SXptbUsvbG5MRG90S2pwb29ibG41L2xoYWpsbTczbWdLZm1uSURwaDQzb3BvSG5tb1Rsbjdybm9ZRGt2NkhtZ2Evb3RZVG11cERrdVl2a3VJRGpnSUk4TDJSbGMyTnlhWEIwYVc5dVBnb2dJRHd2WkdWelkzSnBjSFJwYjI1elBnbzhMM0psYzI5MWNtTmxQZ289IiwidXJsIjoiaHR0cDovL2RjYy5jZ3MuZ292LmNuL2NuL2dlb2xvZ2ljYWxEYXRhL2RldGFpbHMvZG9pLzEwLjM1MDgwL2RhdGEuQy4yMDIxLlAyMyIsImNvbnRlbnRVcmwiOm51bGwsIm1ldGFkYXRhVmVyc2lvbiI6MSwic2NoZW1hVmVyc2lvbiI6Imh0dHA6Ly9kYXRhY2l0ZS5vcmcvc2NoZW1hL2tlcm5lbC00Iiwic291cmNlIjoiZmFicmljYUZvcm0iLCJpc0FjdGl2ZSI6dHJ1ZSwic3RhdGUiOiJmaW5kYWJsZSIsInJlYXNvbiI6bnVsbCwidmlld0NvdW50IjowLCJ2aWV3c092ZXJUaW1lIjpbXSwiZG93bmxvYWRDb3VudCI6MCwiZG93bmxvYWRzT3ZlclRpbWUiOltdLCJyZWZlcmVuY2VDb3VudCI6MCwiY2l0YXRpb25Db3VudCI6MCwiY2l0YXRpb25zT3ZlclRpbWUiOltdLCJwYXJ0Q291bnQiOjAsInBhcnRPZkNvdW50IjowLCJ2ZXJzaW9uQ291bnQiOjAsInZlcnNpb25PZkNvdW50IjowLCJjcmVhdGVkIjoiMjAyMi0xMC0xOFQwNTo1OTowNS4wMDBaIiwicmVnaXN0ZXJlZCI6IjIwMjItMTAtMThUMDU6NTk6MDUuMDAwWiIsInB1Ymxpc2hlZCI6IjIwMjEiLCJ1cGRhdGVkIjoiMjAyNS0wMy0wN1QwMjo0NTo0Mi4wMDBaIn0sInJlbGF0aW9uc2hpcHMiOnsiY2xpZW50Ijp7ImRhdGEiOnsiaWQiOiJjZ3MuZ2RkIiwidHlwZSI6ImNsaWVudHMifX0sInByb3ZpZGVyIjp7ImRhdGEiOnsiaWQiOiJjZ3MiLCJ0eXBlIjoicHJvdmlkZXJzIn19LCJtZWRpYSI6eyJkYXRhIjp7ImlkIjoiMTAuMzUwODAvZGF0YS5jLjIwMjEucDIzIiwidHlwZSI6Im1lZGlhIn19LCJyZWZlcmVuY2VzIjp7ImRhdGEiOltdfSwiY2l0YXRpb25zIjp7ImRhdGEiOltdfSwicGFydHMiOnsiZGF0YSI6W119LCJwYXJ0T2YiOnsiZGF0YSI6W119LCJ2ZXJzaW9ucyI6eyJkYXRhIjpbXX0sInZlcnNpb25PZiI6eyJkYXRhIjpbXX19fX0='
CGS_SHA = '8e11830ddf7eaefc75394de08476bd29d59590a1da32c851a36f9201460782df'
ENDPOINTS = [
    ('NGAC_ARCHIVE_66528', 'https://www.ngac.cn/dzzlfw_sjgl/d2d_blank/dse/category/qwjs.do?keyVal=66528'),
    ('NGAC_ARCHIVE_67554', 'https://www.ngac.cn/dzzlfw_sjgl/d2d_blank/dse/category/qwjs.do?keyVal=67554'),
]


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *_args, **_kwargs):
        return None


class Links(HTMLParser):
    def __init__(self):
        super().__init__(); self.links = []; self.titles = []; self.in_title = False; self.forms = []; self.scripts = []

    def handle_starttag(self, tag, attrs):
        self.in_title = self.in_title or tag.lower() == 'title'
        if tag.lower() == 'a' and len(self.links) < 100:
            href = dict(attrs).get('href')
            if href is not None and len(href) <= 2048:
                self.links.append(href)

        attrs = dict(attrs)
        if tag.lower() == 'form' and len(self.forms) < 40:
            self.forms.append(dict(action=attrs.get('action'), method=attrs.get('method')))
        if tag.lower() == 'script' and attrs.get('src') and len(self.scripts) < 40:
            self.scripts.append(attrs['src'][:2048])

    def handle_endtag(self, tag):
        if tag.lower() == 'title': self.in_title = False

    def handle_data(self, value):
        if self.in_title and len(self.titles) < 20: self.titles.append(value[:1000])


def expired(*_):
    raise TimeoutError('Frozen public metadata deadline')


def allowed(url, name):
    p = urlparse(url)
    assert name in ('NGAC_ARCHIVE_66528', 'NGAC_ARCHIVE_67554')
    assert p.scheme == 'https' and p.port in (None, 443)
    assert p.username is None and p.password is None and not p.fragment
    assert (p.hostname or '').lower() in ('www.ngac.cn', 'order.ngac.cn')
    assert not re.search(r'\.(zip|7z|gz|tif|tiff|nc|shp|dbf|csv|xls|xlsx|pdf)(?:$|[?#])', url, re.I)
    assert '/api/access/datafile/' not in p.path


def framing_probes():
    class Socket:
        def __init__(self, raw): self.raw = raw
        def makefile(self, *_args): return io.BytesIO(self.raw)
    prefix = b'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n'
    valid = HTTPResponse(Socket(prefix+b'3\r\nabc\r\n0\r\n\r\n'))
    valid.begin()
    assert valid.chunked is True and valid.read(512)==b'abc'
    assert valid.isclosed() and valid.chunk_left is None
    invalid = HTTPResponse(Socket(prefix+b'3\r\nabc\r\n'))
    invalid.begin()
    rejected = False
    try:
        invalid.read(512)
    except IncompleteRead:
        rejected = True
    assert rejected, 'Incomplete chunked message must fail'
    return dict(complete_chunked_accepted=True, missing_terminal_chunk_rejected=True,
        python_version=sys.version.split()[0], external_requests=0, scientific_reads=0)


def main():
    resource.setrlimit(resource.RLIMIT_AS, (256 * 1024**2, resource.getrlimit(resource.RLIMIT_AS)[1]))
    signal.signal(signal.SIGALRM, expired)
    original = base64.b64decode(REUSED_CGS_METADATA_B64, validate=True)
    assert len(original) == 7559 and hashlib.sha256(original).hexdigest() == CGS_SHA
    a = json.loads(original)['data']['attributes']
    assert a['doi'].lower() == '10.35080/data.c.2021.p23' and a['version'] == '1.0.0'
    result = dict(kind='GAP27888_CHUNKED_CATALOGUE_QUERY', member='27888',
        complete=False, metadata_session_finished=False, responses=[], documents=[],
        reused_registry=dict(bytes=len(original), sha256=CGS_SHA, base64=REUSED_CGS_METADATA_B64,
            version=a['version'], publication_year=a['publicationYear'], url=a['url'],
            survey_epoch='UNKNOWN', original_data_license='UNKNOWN'),
        new_jobs=0, source_content_reads=0, source_decoding=0, source_writes=0,
        scientific_archives_downloaded=0, model_calls=0, automatic_checks_enabled=False,
        scientific_input_accepted=False, prediction_approved=False,
        permeability_units_verified=False, porosity_units_verified=False,
        member_coverage='UNKNOWN_NOT_SPATIALLY_COMPUTED')
    result['transport_probes'] = framing_probes()
    opener = build_opener(ProxyHandler({}), NoRedirect())
    total = 0; requests = 0
    for name, initial in ENDPOINTS:
        url = initial; doc = dict(name=name, initial_url=initial, acquired=False)
        result['documents'].append(doc)
        for hop in range(2):
            assert requests < 4 and total <= 1024**2
            remaining = 150 - (time.monotonic() - START)
            if remaining <= 1 or total == 1024**2:
                doc['error'] = 'FROZEN_SESSION_LIMIT'; break
            allowed(url, name); requests += 1
            limit = min(30, remaining - 1); began = time.monotonic()
            row = dict(name=name, hop=hop, url=url, status=None, complete=False)
            result['responses'].append(row); response = None; raw = b''
            signal.setitimer(signal.ITIMER_REAL, limit)
            try:
                req = Request(url, headers={'User-Agent':'china-gap27888-public-directory/1',
                                            'Accept-Encoding':'identity'})
                try: response = opener.open(req, timeout=limit)
                except HTTPError as error: response = error
                row.update(status=response.code, content_type=response.headers.get('Content-Type'),
                    declared_length=response.headers.get('Content-Length'),
                    content_encoding=response.headers.get('Content-Encoding', 'identity'),
                    location=response.headers.get('Location'),
                    transfer_encoding=response.headers.get('Transfer-Encoding'),
                    http_version=getattr(response, 'version', None),
                    library_chunked=getattr(response, 'chunked', False))
                assert row['content_encoding'] == 'identity', 'Compressed metadata not accepted'
                typ = (row['content_type'] or '').split(';')[0].strip().lower()
                assert typ.startswith('text/') or typ in ('application/json','application/vnd.api+json',
                    'application/xml','application/xhtml+xml'), 'Metadata text only'
                cap = min(512 * 1024, 1024**2 - total)
                declared = row['declared_length']
                transfer = (row['transfer_encoding'] or '').strip().lower()
                if declared is not None:
                    assert not transfer, 'Ambiguous CL plus Transfer-Encoding rejected'
                    assert 0 <= int(declared) <= cap, 'Exact declared metadata body budget'
                    row['framing'] = 'CONTENT_LENGTH'
                else:
                    assert transfer=='chunked' and row['library_chunked'] is True, 'Unverified no-length framing'
                    row['framing'] = 'CHUNKED'
                try:
                    raw = response.read(cap)
                except IncompleteRead as error:
                    raw = error.partial
                    total += len(raw)
                    row.update(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(),
                        base64=base64.b64encode(raw).decode(), partial_body=True)
                    raise
                total += len(raw)
                row.update(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(),
                           base64=base64.b64encode(raw).decode())
                if declared is not None:
                    assert len(raw)==int(declared), 'Metadata length mismatch'
                else:
                    row.update(response_closed_after_read=response.isclosed(),
                        chunk_left_after_read=response.chunk_left)
                    assert len(raw)<cap and row['response_closed_after_read'] is True and response.chunk_left is None, 'No validated terminal chunk or body cap reached'
                row['framing_complete'] = True
                response.close(); response = None
                assert time.monotonic() - began < limit, 'Request time limit after close'
                row['complete'] = True
            except MemoryError:
                raise
            except Exception as error:
                row['error'] = dict(type=type(error).__name__, message=str(error)[:700])
            finally:
                try:
                    if response is not None: response.close()
                except Exception as error:
                    row['complete'] = False
                    row['close_error'] = repr(error)[:700]
                finally:
                    signal.setitimer(signal.ITIMER_REAL, 0)
                row['seconds'] = time.monotonic() - began
                if row['seconds'] >= limit:
                    row['complete'] = False; row['time_gate_failed'] = True
            if not row['complete']: break
            if row['status'] in (301,302,303,307,308) and row['location']:
                try:
                    target = urljoin(url, row['location']); allowed(target, name)
                    if urlparse(url).scheme == 'https': assert urlparse(target).scheme == 'https', 'No TLS downgrade'
                    row['redirect_target'] = target
                except MemoryError:
                    raise
                except Exception as error:
                    row['redirect_validation_error'] = repr(error)[:700]
                    doc['error'] = 'REDIRECT_NOT_FOLLOWED'
                    break
                if hop == 1: doc['error'] = 'MAXIMUM_ONE_REDIRECT'; break
                url = target; continue
            if row['status'] != 200:
                doc['error'] = 'HTTP_STATUS_' + str(row['status']); break
            try:
                text = raw.decode('utf8', errors='replace')
                parser = Links(); parser.feed(text)
            except MemoryError:
                raise
            except Exception as error:
                doc['error'] = 'SOURCE_DOCUMENT_PARSE_ERROR'
                doc['parse_error'] = repr(error)[:700]
                break
            doc.update(acquired=True, final_url=url, response_index=len(result['responses'])-1,
                title=' '.join(parser.titles), links=parser.links, forms=parser.forms, script_urls=parser.scripts,
                excerpt=text[:5000], semantic_admission='UNKNOWN_MANUAL_ORIGINAL_REVIEW_REQUIRED')
            if name == 'JGCRI_METADATA':
                try:
                    j = json.loads(raw); assert j['id'] == 10631421
                    m = j['metadata']; doc.update(title=m['title'], version=m.get('version'),
                        publication_date=m.get('publication_date'), description=m.get('description'),
                        files=[dict(key=f['key'], size=f['size'], checksum=f.get('checksum'),
                                    links=f.get('links')) for f in j.get('files',[])])
                except MemoryError:
                    raise
                except Exception as error:
                    doc['catalogue_parse_error'] = repr(error)[:700]
            break
    result.update(metadata_session_finished=True, requests=requests, received_body_bytes=total,
        server_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), seconds=time.monotonic()-START)
    assert result['seconds'] < 150 and requests <= 4 and total <= 1024**2
    result['complete'] = all(d['acquired'] for d in result['documents'])
    return result


if __name__ == '__main__':
    value = main()
    raw = (json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(',',':'))+'\n').encode()
    assert len(raw) <= 4*1024**2 and time.monotonic()-START < 150
    encoded = base64.b64encode(zlib.compress(raw)).decode()
    assert time.monotonic()-START < 150
    print('GEOLOGY_RECOVERY_BYTES='+str(len(raw)))
    print('GEOLOGY_RECOVERY_SHA256='+hashlib.sha256(raw).hexdigest())
    print('GEOLOGY_RECOVERY_ZLIB_BASE64='+encoded)
    print('GEOLOGY_RECOVERY_DONE', flush=True)
    assert time.monotonic()-START < 150, 'Final output/flush deadline exceeded; nonzero exit'

CHUNKED_CATALOGUE_QUERY
