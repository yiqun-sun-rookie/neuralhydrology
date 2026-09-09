#!/usr/bin/env bash
set -euo pipefail
python3 -I -B - <<'PY'
BUNDLE_JSON_B64 = 'eyJSRVNPVVJDRV9SRVRSWV9BVVRIT1JJWkFUSU9OXzIwMjYwOTA5Lm1kIjogeyJiYXNlNjQiOiAiSXlEbnJLemt1b3pwbUxibXJyWG1tTDdsclpqbHBMSG90S1hvb2FYb3Q1SG1qb2ptbllNS0NqSXdNall0TURrdE1EbnZ2SXpubEtqbWlMZmxuS2pvanJmbm42WG5yS3prdW96cG1MYm1yclV4TXVhc29lYVl2dVd0bU9TNGplaTJzK1drc2VpMHBlT0FnVGJtcktIb3Y1RG9vWXpsa293ejVxeWg1bzZTNlppZjVaQ081cGlPNTZHdTZLYUI1ckdDNzd5YTRvQ2M1TGlONXBpdjZZS2o1TDJnNVltcDVMaUw1NXFFNUwyZzVvQ081TG1JNUxpTjVMaU41WTY3NW82UzZaaWY1WldLNWFTeDZMU2w1NXFFNW9DTzVMbUk1TGlONW82UzZaaWY0b0NkNDRDQ0Nncm1uS3ptbmFIbm03VG1qcVhubEtqbWlMZm1qSWZrdTZUbGhZSG9ycmpscm9ubWpwTG5yS3prdW96cG1MYm1yclhsdDdMbm9hN29ycVRtbUw3bHJaamt1STNvdHJQbm1vUXhNdVM0cXVtRmplZTlydUtBbE9lbmplV3RrT1dObGVXRmcraWhwZWkza2UrOGpPaW1odWVibHVhWHArYVdoK2FobytTNHJlbVl1K2F0b3VpL21lUzZtK2kxaE9hNmtPV2tzZWkwcGVpaHBlaTNrZWVhaE9tWmtPV0l0dU9BZ3VhWG9PbWNnT2V0aWVXOWsrV0pqVG5rdUtybW5Lcmxyb3ptaUpEa3U3dmxpcUhsaGFqcGc2am51NVBtblovbWlZM2xoNGJscElmbWlKYm1qcExwbUovamdJTGxqcC9scExIb3RLWG5tNjdsdlpYamdJSG1sNlhsdjVmamdJSHBoWTNudmE3amdJSGt2WnprdUpybG01N21pYWZsa296bHBMSG90S1hsdlpMbnNidm51NmZudTYza3Y1M25sWm52dkl6bWxyRGxzSjNvcjVYa3ZiL25sS2puaTZ6bnE0dm52SmJsajdma3VJN25tNjdsdlpYdnZJemx1YmJvcnJEbHZaWGxyN25sdXBUbm1vVGxqcC9rdTd2bGlxSGpnSUlLQ3VTOG1PV0ZpT21IaCtlVXFPaTJzK1drbithWXZ1V3RtT2VhaE9XUWpPbWJodWUrcE9hWXZ1V05vZSs4ak9TL25lYU1nZVdHdStlN2srYVZzT1dBdk9hNmtPZWdnZU9BZ2VXT24raXVyZWU3ZythSnVlV2twK1d3anpJd05EampnSUhucDQzbHJaQTBNdWlIc3pRMDQ0Q0I1cHlBNWFTYU1qQXc2TDJ1NVkrS01qVGxzSS9tbDdibGpaWG1yS0hrdUlycG1aRGpnSUhvcnEzbnU0TXY2YXFNNksrQjZMNlQ1WVdsNVpLTTZZQ0o1b3VwNktlRTVZaVo0NENDNWE2ZTZabUY1NkdzNUx1MjZJdWw1WStZNVl5Vzc3eU01TDJjNUxpNjVZV3M1YnlBNTVxRTVvbW42S0dNNTQ2djVhS0Q1WStZNVl5VzZLNnc1YjJWNWJtMjVhU041cUM0NVlXODVhNjU1b0NuNzd5TTVMaU41YTZqNTZldzVMaU81WTZmNTZHczVMdTI2WUNRNUwyTjVMaUE2SWUwNDRDQzVvQzc2SzZ0NTd1RDVibTI1WStSNUx1TjVweUE1YVNhTnVTNHF1KzhtK2locGVpM2tlV1ByK1c0cHVTK25laTFsdWFQa09XSmplYU9rdW1ZbisrOGpPbUJ2K1dGamVpMmhlaS9oK1c1dHVXUGtlUzRpdW1aa09PQWd1aWhwZWkza2VhZGcrbVprT1M0amVhSnFlV2twK1dBbWVtQWllaU1nK1didE8rOGpPUzRqZWEyaWVXUGl1VzNzdWFjaWVhSWtPV0tuK1M3dStXS29lYUlsdWVzck9TNGdPbVl0dWF1dGVhVnNPV0F2T1drc2VpMHBlUzd1K1dLb2VPQWdnb0s1YjJUNVltTjZLR001WXFvNmFHNjVicVA3N3lhNXArbDZLK2k1YTZlNlptRjVZK3Y1NVNvNXBpKzVZMmg2TFdFNXJxUTVMaU81WTZmNUx1NzVZcWg1NHEyNW9DQjc3eWI1YjJpNW9pUTVZVzM1TDJUNTR1czU2dUw2S0dsNkxlUjVyaUY1WTJWNVpLTTZMV0U1cnFRNks2KzU3MnU3N3liNmFxTTZLK0I1WkN2NVlxbzVvNm41WWkyNUxpTzZMNlQ1WWU2NlpxVTU2YTc1WkNPNW8rUTVMcWs1Ym0yNVkrVzViNlg1WlN2NUxpQTVMMmM1TGlhNVp1ZTVvbW40NENDNWFhQzVwNmM2WnVHNTc2azVyS2g1cHlKNkxhejVhU2Y1cGkrNWEyWTU1cUU1WSt2NTVTbzZMV0U1cnFRNzd5TTZaeUE1cGlPNTZHdTVvcWw1WkdLNksrbDVMcUw1YTZlNWJtMjVvK1E1WWU2NUwrZDVveUI2SzZ0NTd1RDVaQ3I1TG1KNTVxRTVZK3Y2YXFNNksrQjVMK3U1YVNONXBhNTVxR0k3N3lNNUxpTjZJTzk1WTZmNXFDMzZZZU41YVNONWJleTZLK0I1cGlPNXBpKzVhMlk1TGlONkxhejU1cUU1bytRNUxxazQ0Q0NDZ3JvdjVubW1LL2t1SURtbmFIb3Y3M2xpcURtam9qbW5ZUG9yckRsdlpYdnZKdEJWVlJJVDFKSldrRlVTVTlPTG1wemIyN2pnSUZCVlZSSVQxSkpXa1ZFWDFCU1QxUlBRMDlNTG0xazVaS001YmV5NllPbzU3Mnk2WmkyNXE2MTVwMlE1cGFaNUwrZDVveUI1WVcyNVk2RzVZK3k1YTJYNklxQzQ0Q0M1YTZNNXBXMDVhNmU2YXFNNDRDQjZaaTI1cTYxNTd1VDVwNmM2THFyNUx1OTVxQzQ2YXFNNDRDQjZhcU02SytCNllDSjVaNkw1TGlPNXBlaTVweUo1cldMNksrVjVweWY1NXFFNlptUTVZaTI1N3VuNTd1dDZZQ0M1NVNvNDRDQ0NnPT0iLCAic2hhMjU2IjogImU3MWI3YjMyMTljMjA3Nzg5Yzc2NWY4NDg5NWRjMjQzMmQ1NmIyNzNhODMyMTVlZDllZDFiZWU5MDY4NTE0MWEifSwgImxhdW5jaF9CX21lbW9yeV9yZXRyeV8yMDI2MDkwOS5weSI6IHsiYmFzZTY0IjogIklpSWlTWE52YkdGMFpXUXNJRzl1WlMxaGRIUmxiWEIwTFhCbGNpMWpaV3hzSUhKbGMyOTFjbU5sSUhKbGRISjVPeUJtY205NlpXNGdkSEpoYVc1cGJtY2dZMjlrWlNCcGN5QjFibU5vWVc1blpXUXVJaUlpQ21aeWIyMGdYMTltZFhSMWNtVmZYeUJwYlhCdmNuUWdZVzV1YjNSaGRHbHZibk1LQ21sdGNHOXlkQ0JoY21kd1lYSnpaUXBwYlhCdmNuUWdhR0Z6YUd4cFlncHBiWEJ2Y25RZ2FXMXdiM0owYkdsaUxuVjBhV3dLYVcxd2IzSjBJR3B6YjI0S2FXMXdiM0owSUc5ekNtWnliMjBnY0dGMGFHeHBZaUJwYlhCdmNuUWdVR0YwYUFwcGJYQnZjblFnY21VS2FXMXdiM0owSUhONWN3cG1jbTl0SUdSaGRHVjBhVzFsSUdsdGNHOXlkQ0JrWVhSbGRHbHRaU3dnZEdsdFpYcHZibVVLQ2taQlRVbE1XU0E5SUZCaGRHZ29KeTlrWVhSaE1TOW9iMjFsTDNOMWJubHBjUzlyWVd4dFlXNXVaWFJmZDNKeVgyMXZaR1ZzWDNObGJHVmpkR2x2Ymw4eU1ESTJNRGt3T0NjcENsSlBUMVFnUFNCR1FVMUpURmtnTHlBbmNtVnpiM1Z5WTJWZmNtVmpiM1psY25sZk1qQXlOakE1TURrdlFsOXlaWFJ5ZVRFbkNrOVNTVWRKVGtGTUlEMGdSa0ZOU1V4WklDOGdKM04wWVdkbGN5OUNKd3BQVWtsSFNVNUJURjlOUVU1SlJrVlRWRjlUU0VFZ1BTQW5ZelZtT0dRMU5qUTRNRFV4TURjeU9XUmtNVFJrTkRSallqQXdaRFZsTnpBek5ESTFaV0prWldJNE16ZGlNRFU1WWpZM05EazVPR0kwTWpVM09EUmlNU2NLUlZoUUlEMGdVR0YwYUNnblpYaHdaWEpwYldWdWRITXZiM0IwYVcxcGVtVmZhSGx3WlhKZmNHRnlZVzFsZEdWeWN5OTNjbkpmYUhCZlpYaDBaVzV6YVc5dVh6SXdNall3T1RBeUp5a0tSMUJWSUQwZ0owNVdTVVJKUVNCQk9EQXdMVk5ZVFRRdE9EQkhRaWNLQ2dwa1pXWWdjMmhoS0hCaGRHZ3BPZ29nSUNBZ2NtVjBkWEp1SUdoaGMyaHNhV0l1YzJoaE1qVTJLSEJoZEdndWNtVmhaRjlpZVhSbGN5Z3BLUzVvWlhoa2FXZGxjM1FvS1FvS0NtUmxaaUJ1YjNjb0tUb0tJQ0FnSUhKbGRIVnliaUJrWVhSbGRHbHRaUzV1YjNjb2RHbHRaWHB2Ym1VdWRYUmpLUzVwYzI5bWIzSnRZWFFvS1FvS0NtUmxaaUJ2Y21ScGJtRnllU2h3WVhSb0tUb0tJQ0FnSUdsbUlHNXZkQ0J3WVhSb0xtbHpYMlpwYkdVb0tTQnZjaUJ3WVhSb0xtbHpYM041Yld4cGJtc29LU0J2Y2lCd1lYUm9MbkpsYzI5c2RtVW9LU0FoUFNCd1lYUm9MbUZpYzI5c2RYUmxLQ2s2Q2lBZ0lDQWdJQ0FnY21GcGMyVWdVblZ1ZEdsdFpVVnljbTl5S0dZblJYaHdaV04wWldRZ2IzSmthVzVoY25rZ1ptbHNaU0IzYVhSb2IzVjBJSE41Yld4cGJtc2dZVzVqWlhOMGIzSnpPaUI3Y0dGMGFIMG5LUW9nSUNBZ2NtVjBkWEp1SUhCaGRHZ0tDZ3BrWldZZ2QzSnBkR1ZmYm1WM0tIQmhkR2dzSUdSaGRHRXBPZ29nSUNBZ2QybDBhQ0J3WVhSb0xtOXdaVzRvSjNnbkxDQmxibU52WkdsdVp6MG5kWFJtTFRnbktTQmhjeUJ6ZEhKbFlXMDZDaUFnSUNBZ0lDQWdhbk52Ymk1a2RXMXdLR1JoZEdFc0lITjBjbVZoYlN3Z2FXNWtaVzUwUFRJc0lITnZjblJmYTJWNWN6MVVjblZsS1FvZ0lDQWdJQ0FnSUhOMGNtVmhiUzUzY21sMFpTZ25YRzRuS1FvS0NtUmxaaUJ5WldGa1gyTnZiblJ5WVdOMEtISnZiM1FzSUcxaGJtbG1aWE4wWDNOb1lTazZDaUFnSUNCcFppQnliMjkwSUNFOUlGSlBUMVFnYjNJZ2NtOXZkQzV5WlhOdmJIWmxLQ2tnSVQwZ1VrOVBWQ0J2Y2lCdWIzUWdjbVV1Wm5Wc2JHMWhkR05vS0hJbld6QXRPV0V0WmwxN05qUjlKeXdnYldGdWFXWmxjM1JmYzJoaEtUb0tJQ0FnSUNBZ0lDQnlZV2x6WlNCU2RXNTBhVzFsUlhKeWIzSW9KMUpsZEhKNUlISnZiM1FnYjNJZ1pYaDBaWEp1WVd3Z2JXRnVhV1psYzNRZ2NHbHVJRzFwYzIxaGRHTm9KeWtLSUNBZ0lIQmhkR2dnUFNCdmNtUnBibUZ5ZVNoeWIyOTBJQzhnSjFKRlZGSlpYMDFCVGtsR1JWTlVMbXB6YjI0bktRb2dJQ0FnYVdZZ2MyaGhLSEJoZEdncElDRTlJRzFoYm1sbVpYTjBYM05vWVRvS0lDQWdJQ0FnSUNCeVlXbHpaU0JTZFc1MGFXMWxSWEp5YjNJb0oxSmxkSEo1SUcxaGJtbG1aWE4wSUdKNWRHVnpJR1JwWm1abGNpQm1jbTl0SUhOMVltMXBkSFJsWkNCelkzSnBjSFFnY0dsdUp5a0tJQ0FnSUcwZ1BTQnFjMjl1TG14dllXUnpLSEJoZEdndWNtVmhaRjlpZVhSbGN5Z3BLUW9nSUNBZ2FXWWdLRzFiSjNKdmIzUW5YU0FoUFNCemRISW9VazlQVkNrZ2IzSWdiVnNuYjNKcFoybHVZV3hmY205dmRDZGRJQ0U5SUhOMGNpaFBVa2xIU1U1QlRDa0tJQ0FnSUNBZ0lDQWdJQ0FnYjNJZ2JWc25iM0pwWjJsdVlXeGZhbTlpWDJsa0oxMGdJVDBnSnpJeU5ESTFOU2NnYjNJZ2JWc25ZV3hzYjNkbFpGOXBibVJwWTJWekoxMGdJVDBnYkdsemRDaHlZVzVuWlNneE1pa3BDaUFnSUNBZ0lDQWdJQ0FnSUc5eUlHMWJKMmR3ZFNkZElDRTlJRWRRVlNCdmNpQnRXeWR0YVc1ZlozQjFYMjFsYlc5eWVWOWllWFJsY3lkZElDRTlJRGMxSUNvZ01UQXlOQ29xTXdvZ0lDQWdJQ0FnSUNBZ0lDQnZjaUJ0V3lkaVlYUmphRjl6YVhwbEoxMGdJVDBnTWpBME9DQnZjaUJ0V3lkdFlYaGZaWEJ2WTJoekoxMGdJVDBnTWpBd0NpQWdJQ0FnSUNBZ0lDQWdJRzl5SUcxYkoyMWhlRjlqYjI1amRYSnlaVzUwWDNSeVlXbHVhVzVuSjEwZ0lUMGdOaUJ2Y2lCdFd5ZDBhVzFsWDJ4cGJXbDBYMmh2ZFhKekoxMGdJVDBnTWpRS0lDQWdJQ0FnSUNBZ0lDQWdiM0lnYlZzblpHVndaVzVrWlc1amVTZGRJQ0U5SUNkaFpuUmxjbUZ1ZVRveU1qUXlOVFVuSUc5eUlHMWJKMkYwZEdWdGNIUmZhV1FuWFNBaFBTQW5RbDl0WlcxdmNubGZNakF5TmpBNU1EbGZjbVYwY25reEp5azZDaUFnSUNBZ0lDQWdjbUZwYzJVZ1VuVnVkR2x0WlVWeWNtOXlLQ2RTWlhSeWVTQmpiMjUwY21GamRDQmtiMlZ6SUc1dmRDQnRZWFJqYUNCaGRYUm9iM0pwZW1Wa0lISmxjMjkxY21ObElISmxZMjkyWlhKNUp5a0tJQ0FnSUdadmNpQnlaV3dzSUdWNGNHVmpkR1ZrSUdsdUlHMWJKMlY0ZEhKaFgzTjBZWFJwWTE5bWFXeGxjeWRkTG1sMFpXMXpLQ2s2Q2lBZ0lDQWdJQ0FnYVdZZ2NtVnNMbk4wWVhKMGMzZHBkR2dvSnk4bktTQnZjaUFuWEZ3bklHbHVJSEpsYkNCdmNpQmhibmtvZUNCcGJpQW9KeWNzSUNjdUp5d2dKeTR1SnlrZ1ptOXlJSGdnYVc0Z2NtVnNMbk53YkdsMEtDY3ZKeWtwT2dvZ0lDQWdJQ0FnSUNBZ0lDQnlZV2x6WlNCU2RXNTBhVzFsUlhKeWIzSW9KMVZ1YzJGbVpTQnlaWFJ5ZVNCemRHRjBhV01nY0dGMGFDY3BDaUFnSUNBZ0lDQWdhV1lnYzJoaEtHOXlaR2x1WVhKNUtISnZiM1FnTHlCeVpXd3BLU0FoUFNCbGVIQmxZM1JsWkRvS0lDQWdJQ0FnSUNBZ0lDQWdjbUZwYzJVZ1VuVnVkR2x0WlVWeWNtOXlLR1luVW1WMGNua2dZMjl1ZEhKdmJDQm9ZWE5vSUcxcGMyMWhkR05vT2lCN2NtVnNmU2NwQ2lBZ0lDQm1iM0lnY0dGeVpXNTBJR2x1SUNoeWIyOTBMQ0JQVWtsSFNVNUJUQ2s2Q2lBZ0lDQWdJQ0FnYVdZZ2MyaGhLRzl5WkdsdVlYSjVLSEJoY21WdWRDQXZJQ2RUVkVGSFJWOUNYMDFCVGtsR1JWTlVMbXB6YjI0bktTa2dJVDBnVDFKSlIwbE9RVXhmVFVGT1NVWkZVMVJmVTBoQk9nb2dJQ0FnSUNBZ0lDQWdJQ0J5WVdselpTQlNkVzUwYVcxbFJYSnliM0lvSjA5eWFXZHBibUZzSUhOMFlXZGxJSE52ZFhKalpTQnRZVzVwWm1WemRDQnBaR1Z1ZEdsMGVTQnRhWE50WVhSamFDY3BDaUFnSUNCdmNtbG5hVzVoYkY5dFlXNXBabVZ6ZENBOUlHcHpiMjR1Ykc5aFpITW9LSEp2YjNRZ0x5QW5VMVJCUjBWZlFsOU5RVTVKUmtWVFZDNXFjMjl1SnlrdWNtVmhaRjlpZVhSbGN5Z3BLUW9nSUNBZ0l5QlVhR1Z6WlNCaGNtVWdkR2hsSUhWdWJXOWthV1pwWldRZ2IzSnBaMmx1WVd3Z05qY2djM1JoZEdsaklHWnBiR1Z6TENCaGJITnZJR05vWldOclpXUWdZWFFnYzI5MWNtTmxMZ29nSUNBZ1ptOXlJSEpsYkN3Z1pYaHdaV04wWldRZ2FXNGdiM0pwWjJsdVlXeGZiV0Z1YVdabGMzUmJKM04wWVhScFkxOW1hV3hsY3lkZExtbDBaVzF6S0NrNkNpQWdJQ0FnSUNBZ2FXWWdjbVZzTG5OMFlYSjBjM2RwZEdnb0p5OG5LU0J2Y2lBblhGd25JR2x1SUhKbGJDQnZjaUJoYm5rb2VDQnBiaUFvSnljc0lDY3VKeXdnSnk0dUp5a2dabTl5SUhnZ2FXNGdjbVZzTG5Od2JHbDBLQ2N2SnlrcE9nb2dJQ0FnSUNBZ0lDQWdJQ0J5WVdselpTQlNkVzUwYVcxbFJYSnliM0lvSjFWdWMyRm1aU0J2Y21sbmFXNWhiQ0J6ZEdGMGFXTWdjR0YwYUNjcENpQWdJQ0FnSUNBZ1ptOXlJSEJoY21WdWRDQnBiaUFvY205dmRDd2dUMUpKUjBsT1FVd3BPZ29nSUNBZ0lDQWdJQ0FnSUNCcFppQnphR0VvYjNKa2FXNWhjbmtvY0dGeVpXNTBJQzhnY21Wc0tTa2dJVDBnWlhod1pXTjBaV1E2Q2lBZ0lDQWdJQ0FnSUNBZ0lDQWdJQ0J5WVdselpTQlNkVzUwYVcxbFJYSnliM0lvWmlkUGNtbG5hVzVoYkNCemRHRjBhV01nWW5sMFpYTWdZMmhoYm1kbFpEb2dlM0JoY21WdWRDQXZJSEpsYkgwbktRb2dJQ0FnYjJ4a1gyVjRjR1ZqZEdWa0lEMGdhbk52Ymk1c2IyRmtjeWdvY205dmRDQXZJQ2RsZUhCbFkzUmxaRjl5ZFc1MGFXMWxMbXB6YjI0bktTNXlaV0ZrWDJKNWRHVnpLQ2twQ2lBZ0lDQmxlSEJsWTNSbFpDQTlJR1JwWTNRb2IyeGtYMlY0Y0dWamRHVmtMQ0JuY0hVOVIxQlZLUW9nSUNBZ2FXWWdiVnNuY25WdWRHbHRaVjlsZUhCbFkzUmxaQ2RkSUNFOUlHVjRjR1ZqZEdWa09nb2dJQ0FnSUNBZ0lISmhhWE5sSUZKMWJuUnBiV1ZGY25KdmNpZ25UMjVzZVNCMGFHVWdSMUJWSUdsa1pXNTBhWFI1SUcxaGVTQmthV1ptWlhJZ1puSnZiU0JtY205NlpXNGdjblZ1ZEdsdFpTY3BDaUFnSUNCeVpYUjFjbTRnYlN3Z2IzSnBaMmx1WVd4ZmJXRnVhV1psYzNRc0lHVjRjR1ZqZEdWa0Nnb0taR1ZtSUdkMVlYSmtYMjl5YVdkcGJtRnNYMlpoYVd4MWNtVW9jbTl2ZEN3Z2FXNWtaWGdzSUcwcE9nb2dJQ0FnYVdZZ2FYTnBibk4wWVc1alpTaHBibVJsZUN3Z1ltOXZiQ2tnYjNJZ2JtOTBJR2x6YVc1emRHRnVZMlVvYVc1a1pYZ3NJR2x1ZENrZ2IzSWdhVzVrWlhnZ2JtOTBJR2x1SUhKaGJtZGxLREV5S1RvS0lDQWdJQ0FnSUNCeVlXbHpaU0JTZFc1MGFXMWxSWEp5YjNJb0owOXViSGtnYjNKcFoybHVZV3dnUWlCdFpXMXZjbmt0Wm1GcGJHVmtJR2x1WkdsalpYTWdNQzR1TVRFZ1kyRnVJSEpsZEhKNUp5a0tJQ0FnSUdaaGFXeDFjbVVnUFNCdFd5ZG1ZV2xzZFhKbGN5ZGRXM04wY2locGJtUmxlQ2xkQ2lBZ0lDQm1iM0lnYkdGaVpXd2dhVzRnS0NkbGNuSnZjaWNzSUNkbVlXbHNaV1JmYldGeWEyVnlKeXdnSjJOc1lXbHRKeXdnSjJGMVpHbDBKeWs2Q2lBZ0lDQWdJQ0FnWlc1MGNua2dQU0JtWVdsc2RYSmxXMnhoWW1Wc1hRb2dJQ0FnSUNBZ0lIQmhkR2dnUFNCUVlYUm9LR1Z1ZEhKNVd5ZHdZWFJvSjEwcENpQWdJQ0FnSUNBZ2FXWWdibTkwSUhCaGRHZ3VhWE5mY21Wc1lYUnBkbVZmZEc4b1QxSkpSMGxPUVV3cElHOXlJSE5vWVNodmNtUnBibUZ5ZVNod1lYUm9LU2tnSVQwZ1pXNTBjbmxiSjNOb1lUSTFOaWRkT2dvZ0lDQWdJQ0FnSUNBZ0lDQnlZV2x6WlNCU2RXNTBhVzFsUlhKeWIzSW9aaWRQY21sbmFXNWhiQ0JtWVdsc2RYSmxJR1YyYVdSbGJtTmxJR05vWVc1blpXUTZJSHRzWVdKbGJIMHNJR2x1WkdWNElIdHBibVJsZUgwbktRb2dJQ0FnYVdZZ0ozUnZjbU5vTGs5MWRFOW1UV1Z0YjNKNVJYSnliM0k2SUVOVlJFRWdiM1YwSUc5bUlHMWxiVzl5ZVM0bklHNXZkQ0JwYmlCUVlYUm9LR1poYVd4MWNtVmJKMlZ5Y205eUoxMWJKM0JoZEdnblhTa3VjbVZoWkY5MFpYaDBLQ2s2Q2lBZ0lDQWdJQ0FnY21GcGMyVWdVblZ1ZEdsdFpVVnljbTl5S0NkUGNtbG5hVzVoYkNCbVlXbHNkWEpsSUdseklHNXZkQ0IwYUdVZ1lYVjBhRzl5YVhwbFpDQkhVRlVnYldWdGIzSjVJR1poYVd4MWNtVW5LUW9nSUNBZ1kyeGhhVzBnUFNCcWMyOXVMbXh2WVdSektGQmhkR2dvWm1GcGJIVnlaVnNuWTJ4aGFXMG5YVnNuY0dGMGFDZGRLUzV5WldGa1gySjVkR1Z6S0NrcENpQWdJQ0JwWmlCamJHRnBiVnNuYVc1a1pYZ25YU0FoUFNCcGJtUmxlQ0J2Y2lCemRISW9ZMnhoYVcxYkoyRnljbUY1WDNSaGMydGZhV1FuWFNrZ0lUMGdjM1J5S0dsdVpHVjRLVG9LSUNBZ0lDQWdJQ0J5WVdselpTQlNkVzUwYVcxbFJYSnliM0lvSjA5eWFXZHBibUZzSUdaaGFXeDFjbVVnWTJ4aGFXMGdhVzVrWlhnZ2JXbHpiV0YwWTJnbktRb2dJQ0FnSXlCVWFHVWdiRzlqWVd3Z1ptbHNaU0JwZEhObGJHWWdjM1Z3Y0d4cFpYTWdhVzF0ZFhSaFlteGxJR1YyYVdSbGJtTmxPeUJqZFhKeVpXNTBJRzl5YVdkcGJtRnNJR3B2WW5NS0lDQWdJQ01nWTJGdUlHdGxaWEFnZDNKcGRHbHVaeUIxYm5KbGJHRjBaV1FnYzNWalkyVnpjMloxYkNCc2IyZHpJSGRwZEdodmRYUWdZV3gwWlhKcGJtY2dkR2hwY3lCamFHRnBiaTRLSUNBZ0lISmxkSFZ5YmlCbVlXbHNkWEpsQ2dvS1pHVm1JR05zWVdsdFgyOXVZMlVvY205dmRDd2dhVzVrWlhnc0lIQmhlV3h2WVdRcE9nb2dJQ0FnY0dGMGFDQTlJSEp2YjNRZ0x5QW5ZMnhoYVcxekp5QXZJR1luYVc1a1pYaDdhVzVrWlhnNk1EUmtmUzVxYzI5dUp3b2dJQ0FnZDNKcGRHVmZibVYzS0hCaGRHZ3NJSEJoZVd4dllXUXBDaUFnSUNCeVpYUjFjbTRnY0dGMGFBb0tDbVJsWmlCc2IyRmtYMmQxWVhKa0tISnZiM1FwT2dvZ0lDQWdjM2x6TG5CaGRHZ3VhVzV6WlhKMEtEQXNJSE4wY2loeWIyOTBLU2tLSUNBZ0lITndaV01nUFNCcGJYQnZjblJzYVdJdWRYUnBiQzV6Y0dWalgyWnliMjFmWm1sc1pWOXNiMk5oZEdsdmJpZ25iV1Z0YjNKNVgzSmxkSEo1WDJaeWIzcGxibDluZFdGeVpDY3NJSEp2YjNRZ0x5QW5iR0YxYm1Ob1gyOXVZMlV1Y0hrbktRb2dJQ0FnYlc5a2RXeGxJRDBnYVcxd2IzSjBiR2xpTG5WMGFXd3ViVzlrZFd4bFgyWnliMjFmYzNCbFl5aHpjR1ZqS1FvZ0lDQWdjM0JsWXk1c2IyRmtaWEl1WlhobFkxOXRiMlIxYkdVb2JXOWtkV3hsS1FvZ0lDQWdjbVYwZFhKdUlHMXZaSFZzWlFvS0NtUmxaaUJ0WVdsdUtDazZDaUFnSUNCd1lYSnpaWElnUFNCaGNtZHdZWEp6WlM1QmNtZDFiV1Z1ZEZCaGNuTmxjaWdwQ2lBZ0lDQndZWEp6WlhJdVlXUmtYMkZ5WjNWdFpXNTBLQ2N0TFdsdVpHVjRKeXdnY21WeGRXbHlaV1E5VkhKMVpTd2dkSGx3WlQxcGJuUXBDaUFnSUNCd1lYSnpaWEl1WVdSa1gyRnlaM1Z0Wlc1MEtDY3RMVzFoYm1sbVpYTjBMWE5vWVRJMU5pY3NJSEpsY1hWcGNtVmtQVlJ5ZFdVcENpQWdJQ0JoY21keklEMGdjR0Z5YzJWeUxuQmhjbk5sWDJGeVozTW9LUW9nSUNBZ2NtOXZkQ0E5SUZCaGRHZ29YMTltYVd4bFgxOHBMbkpsYzI5c2RtVW9LUzV3WVhKbGJuUUtJQ0FnSUcwc0lHOXlhV2RwYm1Gc1gyMWhibWxtWlhOMExDQmxlSEJsWTNSbFpDQTlJSEpsWVdSZlkyOXVkSEpoWTNRb2NtOXZkQ3dnWVhKbmN5NXRZVzVwWm1WemRGOXphR0V5TlRZcENpQWdJQ0JtWVdsc2RYSmxJRDBnWjNWaGNtUmZiM0pwWjJsdVlXeGZabUZwYkhWeVpTaHliMjkwTENCaGNtZHpMbWx1WkdWNExDQnRLUW9nSUNBZ2FXWWdiM011Wlc1MmFYSnZiaTVuWlhRb0oxTk1WVkpOWDBGU1VrRlpYMHBQUWw5SlJDY3BJQ0U5SUNoeWIyOTBJQzhnSjJGeWNtRjVYMnB2WWw5cFpDNTBlSFFuS1M1eVpXRmtYM1JsZUhRb0tTNXpkSEpwY0NncE9nb2dJQ0FnSUNBZ0lISmhhWE5sSUZKMWJuUnBiV1ZGY25KdmNpZ25RM1Z5Y21WdWRDQnpZMmhsWkhWc1pYSWdZWEp5WVhrZ2FYTWdibTkwSUhSb1pTQjFibWx4ZFdWc2VTQnpkV0p0YVhSMFpXUWdjbVYwY25rbktRb2dJQ0FnYVdZZ2IzTXVaVzUyYVhKdmJpNW5aWFFvSjFOTVZWSk5YMEZTVWtGWlgxUkJVMHRmU1VRbktTQWhQU0J6ZEhJb1lYSm5jeTVwYm1SbGVDazZDaUFnSUNBZ0lDQWdjbUZwYzJVZ1VuVnVkR2x0WlVWeWNtOXlLQ2REZFhKeVpXNTBJSE5qYUdWa2RXeGxjaUIwWVhOcklHbHVaR1Y0SUcxcGMyMWhkR05vSnlrS0lDQWdJR2xtSUc5ekxtVnVkbWx5YjI0dVoyVjBLQ2RUVEZWU1RWOUtUMEpmVUVGU1ZFbFVTVTlPSnlrZ0lUMGdKMmhuY0hVNEp6b0tJQ0FnSUNBZ0lDQnlZV2x6WlNCU2RXNTBhVzFsUlhKeWIzSW9KMUpsZEhKNUlHMTFjM1FnY25WdUlHbHVJSFJvWlNCb1lYSmtkMkZ5WlMxMlpYSnBabWxsWkNCd1lYSjBhWFJwYjI0bktRb2dJQ0FnWjNWaGNtUWdQU0JzYjJGa1gyZDFZWEprS0hKdmIzUXBDaUFnSUNCbmRXRnlaQzUyWlhKcFpubGZjMjkxY21ObFgyaGhjMmhsY3loeWIyOTBMQ0J2Y21sbmFXNWhiRjl0WVc1cFptVnpkQ2tLSUNBZ0lHVnVkbWx5YjI1dFpXNTBJRDBnWjNWaGNtUXVhVzV6Y0dWamRGOWxiblpwY205dWJXVnVkQ2dwQ2lBZ0lDQm5kV0Z5WkM1MllXeHBaR0YwWlY5eWRXNTBhVzFsWDNOdVlYQnphRzkwS0dWdWRtbHliMjV0Wlc1MExDQmxlSEJsWTNSbFpDd2daM1ZoY21RdVZrVlNVMGxQVGw5U1ZVNVVTVTFGWDBaSlJVeEVVeWtLSUNBZ0lHbHRjRzl5ZENCMGIzSmphQW9nSUNBZ2NISnZjR1Z5ZEdsbGN5QTlJSFJ2Y21Ob0xtTjFaR0V1WjJWMFgyUmxkbWxqWlY5d2NtOXdaWEowYVdWektEQXBDaUFnSUNCcFppQndjbTl3WlhKMGFXVnpMblJ2ZEdGc1gyMWxiVzl5ZVNBOElHMWJKMjFwYmw5bmNIVmZiV1Z0YjNKNVgySjVkR1Z6SjEwNkNpQWdJQ0FnSUNBZ2NtRnBjMlVnVW5WdWRHbHRaVVZ5Y205eUtDZEJiR3h2WTJGMFpXUWdSMUJWSUdoaGN5QnBibk4xWm1acFkybGxiblFnZG1WeWFXWnBaV1FnZEc5MFlXd2diV1Z0YjNKNUp5a0tJQ0FnSUc5eWFXZHBibUZzSUQwZ1ozVmhjbVF1Ykc5aFpGOXZjbWxuYVc1aGJGOXNZWFZ1WTJobGNpaHliMjkwSUM4Z0ozSmxjRzhuSUM4Z1JWaFFJQzhnSjNKMWJsOXZibVZmWTJWc2JDNXdlU2NwQ2lBZ0lDQmpiMjFpYnlBOUlHOXlhV2RwYm1Gc0xteHZZV1JmWTI5dFltOG9ZWEpuY3k1cGJtUmxlQ2tLSUNBZ0lHZDFZWEprTG5aaGJHbGtZWFJsWDJOdmJXSnZLQ2RDSnl3Z1lYSm5jeTVwYm1SbGVDd2dZMjl0WW04cENpQWdJQ0JwWmlCamIyMWlieUFoUFNCbVlXbHNkWEpsV3lkamIyMWlieWRkT2dvZ0lDQWdJQ0FnSUhKaGFYTmxJRkoxYm5ScGJXVkZjbkp2Y2lnblVtVjBjbmtnWTI5dVptbG5kWEpoZEdsdmJpOXpaV1ZrSUdScFptWmxjbk1nWm5KdmJTQnZjbWxuYVc1aGJDQm1ZV2xzWldRZ1kyVnNiQ2NwQ2lBZ0lDQnZjbWxuYVc1aGJDNW5kV0Z5WkY5emIzVnlZMlZmWTI5dWRISmhZM1FvS1FvZ0lDQWdiM0pwWjJsdVlXd3VaM1ZoY21SZlpHRjBZVjlqYjI1MGNtRmpkQ2dwQ2lBZ0lDQnZkWFJ3ZFhRZ1BTQnZjbWxuYVc1aGJDNWxlSEJsWTNSbFpGOXlkVzVmWkdseUtISnZiM1FnTHlBbmNtVndieWNnTHlCRldGQWdMeUFuY25WdWN5Y2dMeUJtSW1admNtMWhiRjl6WldWa2UyTnZiV0p2V3lkelpXVmtKMTE5WDJkd2RTSXNJR052YldKdktRb2dJQ0FnWjNWaGNtUXVjbVZtZFhObFgyVjRhWE4wYVc1blgyOTFkSEIxZENodmRYUndkWFFwQ2lBZ0lDQndZWGxzYjJGa0lEMGdleWRoZEhSbGJYQjBYMmxrSnpvZ2JWc25ZWFIwWlcxd2RGOXBaQ2RkTENBbmIzSnBaMmx1WVd4ZmNuVnVYMmxrSnpvZ1kyOXRZbTliSjNKMWJsOXBaQ2RkTEFvZ0lDQWdJQ0FnSUNBZ0lDQWdJQ0FuYjNKcFoybHVZV3hmYW05aVgybGtKem9nSnpJeU5ESTFOU2NzSUNkcGJtUmxlQ2M2SUdGeVozTXVhVzVrWlhnc0lDZGpiMjFpYnljNklHTnZiV0p2TEFvZ0lDQWdJQ0FnSUNBZ0lDQWdJQ0FuYW05aVgybGtKem9nYjNNdVpXNTJhWEp2YmxzblUweFZVazFmU2s5Q1gwbEVKMTBzSUNkaGNuSmhlVjlxYjJKZmFXUW5PaUJ2Y3k1bGJuWnBjbTl1V3lkVFRGVlNUVjlCVWxKQldWOUtUMEpmU1VRblhTd0tJQ0FnSUNBZ0lDQWdJQ0FnSUNBZ0oyRnljbUY1WDNSaGMydGZhV1FuT2lCaGNtZHpMbWx1WkdWNExDQW5ZMnhoYVcxbFpGOWhkRjkxZEdNbk9pQnViM2NvS1N3S0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnSjNKbGRISjVYMjFoYm1sbVpYTjBYM05vWVRJMU5pYzZJR0Z5WjNNdWJXRnVhV1psYzNSZmMyaGhNalUyTENBbmNuVnVkR2x0WlNjNklHVnVkbWx5YjI1dFpXNTBMQW9nSUNBZ0lDQWdJQ0FnSUNBZ0lDQW5aM0IxWDNSdmRHRnNYMjFsYlc5eWVWOWllWFJsY3ljNklIQnliM0JsY25ScFpYTXVkRzkwWVd4ZmJXVnRiM0o1ZlFvZ0lDQWdZMnhoYVcxZmIyNWpaU2h5YjI5MExDQmhjbWR6TG1sdVpHVjRMQ0J3WVhsc2IyRmtLUW9nSUNBZ2RXNWphR0Z1WjJWa1gyTnZibVpwWjNWeVpTQTlJRzl5YVdkcGJtRnNMbU52Ym1acFozVnlaVjl5WlhCeWIyUjFZMmxpYVd4cGRIa0tDaUFnSUNCa1pXWWdZMjl1Wm1sbmRYSmxLSE5sWldRcE9nb2dJQ0FnSUNBZ0lHbG1JSE5sWldRZ0lUMGdZMjl0WW05YkoyVm1abVZqZEdsMlpWOXpaV1ZrSjEwNkNpQWdJQ0FnSUNBZ0lDQWdJSEpoYVhObElGSjFiblJwYldWRmNuSnZjaWduUldabVpXTjBhWFpsSUhObFpXUWdiV2x6YldGMFkyZ2dZbVZtYjNKbElHTnZibVpwWjNWeWFXNW5JSEoxYm5ScGJXVW5LUW9nSUNBZ0lDQWdJSEoxYm5ScGJXVWdQU0IxYm1Ob1lXNW5aV1JmWTI5dVptbG5kWEpsS0hObFpXUXBDaUFnSUNBZ0lDQWdhV1lnY25WdWRHbHRaVnNuYzJWbFpDZGRJQ0U5SUdOdmJXSnZXeWRsWm1abFkzUnBkbVZmYzJWbFpDZGRPZ29nSUNBZ0lDQWdJQ0FnSUNCeVlXbHpaU0JTZFc1MGFXMWxSWEp5YjNJb0owVm1abVZqZEdsMlpTQnpaV1ZrSUcxcGMyMWhkR05vSUdGbWRHVnlJR052Ym1acFozVnlhVzVuSUhKMWJuUnBiV1VuS1FvZ0lDQWdJQ0FnSUhOdVlYQnphRzkwSUQwZ1pHbGpkQ2h5ZFc1MGFXMWxMQ0J3ZVhSb2IyNWZkbVZ5YzJsdmJqMWxiblpwY205dWJXVnVkRnNuY0hsMGFHOXVYM1psY25OcGIyNG5YU3dnYm5WdGNIbGZkbVZ5YzJsdmJqMWxiblpwY205dWJXVnVkRnNuYm5WdGNIbGZkbVZ5YzJsdmJpZGRLUW9nSUNBZ0lDQWdJR2QxWVhKa0xuWmhiR2xrWVhSbFgzSjFiblJwYldWZmMyNWhjSE5vYjNRb2MyNWhjSE5vYjNRc0lHVjRjR1ZqZEdWa0tRb2dJQ0FnSUNBZ0lISmxkSFZ5YmlCeWRXNTBhVzFsQ2dvZ0lDQWdiM0pwWjJsdVlXd3VZMjl1Wm1sbmRYSmxYM0psY0hKdlpIVmphV0pwYkdsMGVTQTlJR052Ym1acFozVnlaUW9nSUNBZ2IyeGtYMkZ5WjNZZ1BTQnplWE11WVhKbmRsczZYUW9nSUNBZ2RISjVPZ29nSUNBZ0lDQWdJSEJ5YVc1MEtHcHpiMjR1WkhWdGNITW9leWRsZG1WdWRDYzZJQ2RTUlZOUFZWSkRSVjlTUlZSU1dWOUZUbFJGVWtsT1IxOVZUa05JUVU1SFJVUmZWRkpCU1U1SlRrY25MQ0FxS25CaGVXeHZZV1I5S1N3Z1pteDFjMmc5VkhKMVpTa0tJQ0FnSUNBZ0lDQnplWE11WVhKbmRpQTlJRnR6ZEhJb2NtOXZkQ0F2SUNkeVpYQnZKeUF2SUVWWVVDQXZJQ2R5ZFc1ZmIyNWxYMk5sYkd3dWNIa25LU3dnSnkwdGFXNWtaWGduTENCemRISW9ZWEpuY3k1cGJtUmxlQ2xkQ2lBZ0lDQWdJQ0FnYjNKcFoybHVZV3d1YldGcGJpZ3BDaUFnSUNCbWFXNWhiR3g1T2dvZ0lDQWdJQ0FnSUc5eWFXZHBibUZzTG1OdmJtWnBaM1Z5WlY5eVpYQnliMlIxWTJsaWFXeHBkSGtnUFNCMWJtTm9ZVzVuWldSZlkyOXVabWxuZFhKbENpQWdJQ0FnSUNBZ2MzbHpMbUZ5WjNZZ1BTQnZiR1JmWVhKbmRnb0tDbWxtSUY5ZmJtRnRaVjlmSUQwOUlDZGZYMjFoYVc1Zlh5YzZDaUFnSUNCdFlXbHVLQ2tLIiwgInNoYTI1NiI6ICIzYTIwODdkODJhNzkyMzNlYWQwYzQ2MzQyMzgxY2U5MDU1Mzc2MmZjNTY0MWUwYTYxNDdlOTdmYTE1OGExZWI0In19'
"""Deployment body embedded in a unique mailbox request by the local builder."""
import base64
import datetime
import gzip
import hashlib
import json
import os
import pathlib
import re
import subprocess

FAMILY = pathlib.Path('/data1/home/sunyiq/kalmannet_wrr_model_selection_20260908')
ORIGINAL = FAMILY / 'stages/B'
PARENT = FAMILY / 'resource_recovery_20260909'
ROOT = PARENT / 'B_retry1'
EXP = pathlib.Path('repo/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902')
EXPECTED_MANIFEST = 'c5f8d56480510729dd14d44cb00d5e703425ebdeb837b059b674998b425784b1'
EXPECTED_BASELINE = '6314f746fce9f31d55687b35858736c4013bd5369e5b6a538beA155bd1b7c5ce'.lower()


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def file_bytes(path):
    require(path.is_file() and not path.is_symlink() and path.resolve() == path, f'Unsafe ordinary file: {path}')
    return path.read_bytes()


def write_new(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('xb') as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())


def write_json(path, value):
    write_new(path, (json.dumps(value, indent=2, sort_keys=True) + '\n').encode())


def query(argv):
    r = subprocess.run(argv, capture_output=True, text=True, check=False, timeout=45)
    require(r.returncode == 0 and not r.stderr, f'Query failed: {argv}: {r.stderr}')
    return {'command': argv, 'returncode': r.returncode, 'stdout': r.stdout, 'stderr': r.stderr}


def main():
    # BUNDLE is embedded by the local builder, containing exact control bytes.
    bundle = json.loads(base64.b64decode(BUNDLE_JSON_B64, validate=True))
    files = {key: base64.b64decode(value['base64'], validate=True) for key, value in bundle.items()}
    require(set(files) == {'launch_B_memory_retry_20260909.py', 'RESOURCE_RETRY_AUTHORIZATION_20260909.md'}, 'Unexpected control bundle')
    for key, raw in files.items():
        require(digest(raw) == bundle[key]['sha256'], 'Control bytes mismatch')
    require(PARENT.is_dir() and PARENT.resolve() == PARENT and not os.path.lexists(ROOT), 'Retry1 already exists or unsafe parent; inspect, never overwrite')
    hardware = json.loads(file_bytes(PARENT / 'HARDWARE_PROBE_RESULT.json'))
    match = [r for r in hardware['queries'] if '--partition=hgpu8' in r['command']]
    require(len(match) == 1 and match[0]['returncode'] == 0 and not match[0]['stderr'], 'No successful A800 hardware probe')
    gpu = json.loads(match[0]['stdout'])
    require(gpu['gpu'] == 'NVIDIA A800-SXM4-80GB' and gpu['node'] == 'ngu201' and gpu['total_memory_bytes'] >= 75 * 1024**3, 'A800 hardware identity failed')
    require(gpu['torch_version'] == '2.4.0' and gpu['cuda_version'] == '12.1' and gpu['cudnn_version'] == 90100, 'A800 software compatibility failed')
    require(file_bytes(ORIGINAL / 'array_job_id.txt').decode().strip() == '224255', 'Original job identity failed')
    original_raw = file_bytes(ORIGINAL / 'STAGE_B_MANIFEST.json')
    require(digest(original_raw) == EXPECTED_MANIFEST, 'Original B manifest changed')
    original = json.loads(original_raw)
    static = {}
    for rel, expected in original['static_files'].items():
        require(rel and not rel.startswith('/') and '\\' not in rel and all(p not in ('', '.', '..') for p in rel.split('/')), 'Unsafe static path')
        raw = file_bytes(ORIGINAL / rel)
        require(digest(raw) == expected, f'Static hash changed: {rel}')
        static[rel] = raw
    require(len(static) == 67, 'Unexpected original static count')
    combos = [json.loads(line) for line in static[(EXP / 'combos.jsonl').as_posix()].splitlines() if line.strip()]
    require(len(combos) == 21 and [c['index'] for c in combos] == list(range(21)), 'Invalid original combos')
    accounting = query(['sacct', '-j', '224255', '-X', '-n', '-P', '--format=JobID,JobIDRaw,State,ExitCode,Elapsed,NodeList'])
    rows = {r[0]: r for r in (line.split('|') for line in accounting['stdout'].splitlines())}
    queue = query(['squeue', '-r', '-u', 'sunyiq', '-h', '-o', '%i|%j|%P|%T'])
    require('ngf-B-memory-r1' not in queue['stdout'], 'A retry job with this unique name already exists')
    failures = {}
    for index in range(12):
        row = rows.get(f'224255_{index}')
        require(row is not None and row[2:4] == ['FAILED', '1:0'], f'Original cell is not terminal failed: {index}')
        combo = combos[index]
        dirs = list((ORIGINAL / EXP).glob(f"runs/formal_seed{combo['seed']}_gpu/idx{index:04d}_*"))
        require(len(dirs) == 1, 'Ambiguous original failed run directory')
        run = dirs[0]
        require(not (run / 'cell_metrics.json').exists(), 'Successful cell is not retry-authorized')
        paths = {'error': run / 'error.txt', 'failed_marker': run / 'FAILED',
                 'claim': ORIGINAL / 'claims' / f'index{index:04d}.json'}
        audits = list((ORIGINAL / EXP / 'audits').glob(combo['run_id'] + '_formal_*.json'))
        require(len(audits) == 1, 'Ambiguous original failed audit')
        paths['audit'] = audits[0]
        require(b'torch.OutOfMemoryError: CUDA out of memory.' in file_bytes(paths['error']), 'Failure is not GPU memory exhaustion')
        claim = json.loads(file_bytes(paths['claim']))
        audit = json.loads(file_bytes(paths['audit']))
        require(str(claim['job_id']) == row[1] == str(audit['slurm_job_id']), 'Original scheduler/audit identity failed')
        require(claim['run_id'] == combo['run_id'] == audit['run_id'] and audit['combo'] == combo, 'Original scientific cell identity failed')
        require(audit['held_out_test_loaded'] is False, 'Original test-data guard failed')
        failures[str(index)] = {'combo': combo, 'scheduler_row': row,
            **{key: {'path': str(path), 'sha256': digest(file_bytes(path))} for key, path in paths.items()}}
    baseline_raw = file_bytes(ORIGINAL / 'REMOTE_BASELINE.json')
    require(digest(baseline_raw) == EXPECTED_BASELINE, 'Frozen protection/data baseline changed')
    baseline = json.loads(baseline_raw)
    protected = baseline['protected_files']
    for path, expected in protected.items():
        require(digest(pathlib.Path(path).read_bytes()) == expected, f'Protected evidence changed: {path}')
    data_entries = baseline['data']
    require(set(data_entries) == {'train', 'val'}, 'Only train/val may be deployed')
    expected_runtime = json.loads(static['expected_runtime.json'])
    runtime = dict(expected_runtime, gpu=gpu['gpu'])
    manifest = {'schema_version': 1, 'attempt_id': 'B_memory_20260909_retry1',
        'root': str(ROOT), 'original_root': str(ORIGINAL), 'original_job_id': '224255',
        'original_manifest_sha256': EXPECTED_MANIFEST, 'allowed_indices': list(range(12)),
        'gpu': gpu['gpu'], 'min_gpu_memory_bytes': 75 * 1024**3, 'node': 'ngu201',
        'partition': 'hgpu8', 'batch_size': 2048, 'max_epochs': 200,
        'max_concurrent_training': 6, 'time_limit_hours': 24, 'dependency': 'afterany:224255',
        'runtime_expected': runtime, 'scientific_source_changed': False, 'failures': failures,
        'extra_static_files': {key: digest(raw) for key, raw in files.items()},
        'hardware_probe_sha256': digest(file_bytes(PARENT / 'HARDWARE_PROBE_RESULT.json')),
        'created_at_utc': now()}
    manifest_raw = (json.dumps(manifest, indent=2, sort_keys=True) + '\n').encode()
    manifest_sha = digest(manifest_raw)
    script = f'''#!/usr/bin/env bash
#SBATCH -J ngf-B-memory-r1
#SBATCH -p hgpu8
#SBATCH --nodelist=ngu201
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 1-00:00:00
#SBATCH --array=0-11%6
#SBATCH --dependency=afterany:224255
#SBATCH --no-requeue
#SBATCH -o {ROOT}/logs/slurm-%A_%a.out
#SBATCH -e {ROOT}/logs/slurm-%A_%a.err
set -eo pipefail
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export PYTHONNOUSERSITE=1
export OMP_NUM_THREADS="${{SLURM_CPUS_PER_TASK:-4}}"
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate knet_clean || {{ echo CONDA_FAILED; exit 1; }}
cd {ROOT}/repo
python -B -u {ROOT}/launch_B_memory_retry_20260909.py --index "${{SLURM_ARRAY_TASK_ID:?}}" --manifest-sha256 {manifest_sha}
'''.encode()
    # Exclusive retry-root creation consumes this attempt even on an uncertain response.
    ROOT.mkdir()
    for rel, raw in static.items():
        write_new(ROOT / rel, raw)
    for rel, raw in files.items():
        write_new(ROOT / rel, raw)
    write_new(ROOT / 'STAGE_B_MANIFEST.json', original_raw)
    write_new(ROOT / 'RETRY_MANIFEST.json', manifest_raw)
    write_new(ROOT / 'retry.slurm', script)
    write_json(ROOT / 'ORIGINAL_ACCOUNTING_AT_DEPLOYMENT.json', accounting)
    write_json(ROOT / 'ORIGINAL_QUEUE_AT_DEPLOYMENT.json', queue)
    write_json(ROOT / 'PROTECTED_FILES_BEFORE.json', protected)
    for name in ('logs', 'claims'):
        (ROOT / name).mkdir()
    data_dir = ROOT / 'repo/data/processed/high_flow_aug'
    data_dir.mkdir(parents=True)
    for entry in data_entries.values():
        target = pathlib.Path(entry['path'])
        require(digest(target.read_bytes()) == entry['sha256'] and str(target.resolve()) == entry['resolved_path'], 'Training/validation source changed')
        (data_dir / target.name).symlink_to(target)
    for rel, expected in original['static_files'].items():
        require(digest(file_bytes(ROOT / rel)) == expected, 'Copied static bytes differ')
    for path, expected in protected.items():
        require(digest(pathlib.Path(path).read_bytes()) == expected, f'Protected evidence changed during deployment: {path}')
    write_json(ROOT / 'PROTECTED_FILES_AFTER.json', protected)
    env = {key: value for key, value in os.environ.items() if not key.startswith('SBATCH_')}
    for key in ('MPLCONFIGDIR', 'TORCH_HOME', 'XDG_CACHE_HOME'):
        path = ROOT / 'runtime_cache' / key.lower()
        path.mkdir(parents=True)
        env[key] = str(path)
    syntax = subprocess.run(['bash', '-n', str(ROOT / 'retry.slurm')], capture_output=True, text=True)
    require(syntax.returncode == 0, 'Generated Slurm script syntax failure')
    command = ['sbatch', '--export=ALL', str(ROOT / 'retry.slurm')]
    write_json(ROOT / 'SUBMISSION_INTENT.json', {'command': command, 'manifest_sha256': manifest_sha,
        'script_sha256': digest(script), 'dependency': 'afterany:224255', 'time_utc': now(),
        'retry_indices': list(range(12)), 'protected_files_verified': len(protected)})
    try:
        r = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, check=False, timeout=60)
        response = {'returncode': r.returncode, 'stdout': r.stdout, 'stderr': r.stderr, 'exception': None}
    except Exception as exc:
        response = {'returncode': None, 'stdout': str(getattr(exc, 'stdout', '') or ''),
                    'stderr': str(getattr(exc, 'stderr', '') or ''), 'exception': str(exc)}
    write_json(ROOT / 'SUBMISSION_RESPONSE.json', response)
    match = re.fullmatch(r'Submitted batch job ([0-9]+)\s*', response['stdout'])
    require(response['returncode'] == 0 and response['exception'] is None and match, 'Submission failed/uncertain; inspect retained response, do not replay')
    job_id = match[1]
    write_new(ROOT / 'array_job_id.txt', job_id.encode())
    receipt = {'status': 'SUBMITTED', 'attempt_id': manifest['attempt_id'], 'job_id': job_id,
        'root': str(ROOT), 'retry_indices': list(range(12)), 'original_job_id': '224255',
        'array': '0-11%6', 'gpu': gpu['gpu'], 'node': 'ngu201', 'partition': 'hgpu8',
        'dependency': 'afterany:224255', 'manifest_sha256': manifest_sha,
        'script_sha256': digest(script), 'protected_files_verified': len(protected),
        'training_started': False, 'time_utc': now()}
    write_json(ROOT / 'SUBMISSION_RECEIPT.json', receipt)
    print('MEMORY_RETRY_SUBMISSION=' + json.dumps(receipt, sort_keys=True), flush=True)
    # Read-only confirmation follows the unique submission receipt.
    q = query(['squeue', '-r', '-j', job_id, '-h', '-o', '%i|%j|%P|%T|%E|%R'])
    j = query(['scontrol', 'show', 'job', job_id, '-o'])
    report = {'receipt': receipt, 'manifest': manifest, 'queue': q, 'scheduler_job': j}
    write_json(ROOT / 'INITIAL_QUEUE_OBSERVATION.json', report)
    blob = json.dumps(report, sort_keys=True, separators=(',', ':')).encode()
    print('MEMORY_RETRY_GZIP_BASE64=' + base64.b64encode(gzip.compress(blob, mtime=0)).decode())


if __name__ == '__main__':
    main()

PY
