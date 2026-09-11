#!/usr/bin/env bash
set -euo pipefail
python3 -I -B - <<'PY'
BUNDLE_JSON_B64 = 'eyJSRVNPVVJDRV9SRVRSWV9BVVRIT1JJWkFUSU9OXzIwMjYwOTA5Lm1kIjogeyJiYXNlNjQiOiAiSXlEbnJLemt1b3pwbUxibXJyWG1tTDdsclpqbHBMSG90S1hvb2FYb3Q1SG1qb2ptbllNS0NqSXdNall0TURrdE1EbnZ2SXpubEtqbWlMZmxuS2pvanJmbm42WG5yS3prdW96cG1MYm1yclV4TXVhc29lYVl2dVd0bU9TNGplaTJzK1drc2VpMHBlT0FnVGJtcktIb3Y1RG9vWXpsa293ejVxeWg1bzZTNlppZjVaQ081cGlPNTZHdTZLYUI1ckdDNzd5YTRvQ2M1TGlONXBpdjZZS2o1TDJnNVltcDVMaUw1NXFFNUwyZzVvQ081TG1JNUxpTjVMaU41WTY3NW82UzZaaWY1WldLNWFTeDZMU2w1NXFFNW9DTzVMbUk1TGlONW82UzZaaWY0b0NkNDRDQ0Nncm1uS3ptbmFIbm03VG1qcVhubEtqbWlMZm1qSWZrdTZUbGhZSG9ycmpscm9ubWpwTG5yS3prdW96cG1MYm1yclhsdDdMbm9hN29ycVRtbUw3bHJaamt1STNvdHJQbm1vUXhNdVM0cXVtRmplZTlydUtBbE9lbmplV3RrT1dObGVXRmcraWhwZWkza2UrOGpPaW1odWVibHVhWHArYVdoK2FobytTNHJlbVl1K2F0b3VpL21lUzZtK2kxaE9hNmtPV2tzZWkwcGVpaHBlaTNrZWVhaE9tWmtPV0l0dU9BZ3VhWG9PbWNnT2V0aWVXOWsrV0pqVG5rdUtybW5Lcmxyb3ptaUpEa3U3dmxpcUhsaGFqcGc2am51NVBtblovbWlZM2xoNGJscElmbWlKYm1qcExwbUovamdJTGxqcC9scExIb3RLWG5tNjdsdlpYamdJSG1sNlhsdjVmamdJSHBoWTNudmE3amdJSGt2WnprdUpybG01N21pYWZsa296bHBMSG90S1hsdlpMbnNidm51NmZudTYza3Y1M25sWm52dkl6bWxyRGxzSjNvcjVYa3ZiL25sS2puaTZ6bnE0dm52SmJsajdma3VJN25tNjdsdlpYdnZJemx1YmJvcnJEbHZaWGxyN25sdXBUbm1vVGxqcC9rdTd2bGlxSGpnSUlLQ3VTOG1PV0ZpT21IaCtlVXFPaTJzK1drbithWXZ1V3RtT2VhaE9XUWpPbWJodWUrcE9hWXZ1V05vZSs4ak9TL25lYU1nZVdHdStlN2srYVZzT1dBdk9hNmtPZWdnZU9BZ2VXT24raXVyZWU3ZythSnVlV2twK1d3anpJd05EampnSUhucDQzbHJaQTBNdWlIc3pRMDQ0Q0I1cHlBNWFTYU1qQXc2TDJ1NVkrS01qVGxzSS9tbDdibGpaWG1yS0hrdUlycG1aRGpnSUhvcnEzbnU0TXY2YXFNNksrQjZMNlQ1WVdsNVpLTTZZQ0o1b3VwNktlRTVZaVo0NENDNWE2ZTZabUY1NkdzNUx1MjZJdWw1WStZNVl5Vzc3eU01TDJjNUxpNjVZV3M1YnlBNTVxRTVvbW42S0dNNTQ2djVhS0Q1WStZNVl5VzZLNnc1YjJWNWJtMjVhU041cUM0NVlXODVhNjU1b0NuNzd5TTVMaU41YTZqNTZldzVMaU81WTZmNTZHczVMdTI2WUNRNUwyTjVMaUE2SWUwNDRDQzVvQzc2SzZ0NTd1RDVibTI1WStSNUx1TjVweUE1YVNhTnVTNHF1KzhtK2locGVpM2tlV1ByK1c0cHVTK25laTFsdWFQa09XSmplYU9rdW1ZbisrOGpPbUJ2K1dGamVpMmhlaS9oK1c1dHVXUGtlUzRpdW1aa09PQWd1aWhwZWkza2VhZGcrbVprT1M0amVhSnFlV2twK1dBbWVtQWllaU1nK1didE8rOGpPUzRqZWEyaWVXUGl1VzNzdWFjaWVhSWtPV0tuK1M3dStXS29lYUlsdWVzck9TNGdPbVl0dWF1dGVhVnNPV0F2T1drc2VpMHBlUzd1K1dLb2VPQWdnb0s1YjJUNVltTjZLR001WXFvNmFHNjVicVA3N3lhNXArbDZLK2k1YTZlNlptRjVZK3Y1NVNvNXBpKzVZMmg2TFdFNXJxUTVMaU81WTZmNUx1NzVZcWg1NHEyNW9DQjc3eWI1YjJpNW9pUTVZVzM1TDJUNTR1czU2dUw2S0dsNkxlUjVyaUY1WTJWNVpLTTZMV0U1cnFRNks2KzU3MnU3N3liNmFxTTZLK0I1WkN2NVlxbzVvNm41WWkyNUxpTzZMNlQ1WWU2NlpxVTU2YTc1WkNPNW8rUTVMcWs1Ym0yNVkrVzViNlg1WlN2NUxpQTVMMmM1TGlhNVp1ZTVvbW40NENDNWFhQzVwNmM2WnVHNTc2azVyS2g1cHlKNkxhejVhU2Y1cGkrNWEyWTU1cUU1WSt2NTVTbzZMV0U1cnFRNzd5TTZaeUE1cGlPNTZHdTVvcWw1WkdLNksrbDVMcUw1YTZlNWJtMjVvK1E1WWU2NUwrZDVveUI2SzZ0NTd1RDVaQ3I1TG1KNTVxRTVZK3Y2YXFNNksrQjVMK3U1YVNONXBhNTVxR0k3N3lNNUxpTjZJTzk1WTZmNXFDMzZZZU41YVNONWJleTZLK0I1cGlPNXBpKzVhMlk1TGlONkxhejU1cUU1bytRNUxxazQ0Q0NDZ3JvdjVubW1LL2t1SURtbmFIb3Y3M2xpcURtam9qbW5ZUG9yckRsdlpYdnZKdEJWVlJJVDFKSldrRlVTVTlPTG1wemIyN2pnSUZCVlZSSVQxSkpXa1ZFWDFCU1QxUlBRMDlNTG0xazVaS001YmV5NllPbzU3Mnk2WmkyNXE2MTVwMlE1cGFaNUwrZDVveUI1WVcyNVk2RzVZK3k1YTJYNklxQzQ0Q0M1YTZNNXBXMDVhNmU2YXFNNDRDQjZaaTI1cTYxNTd1VDVwNmM2THFyNUx1OTVxQzQ2YXFNNDRDQjZhcU02SytCNllDSjVaNkw1TGlPNXBlaTVweUo1cldMNksrVjVweWY1NXFFNlptUTVZaTI1N3VuNTd1dDZZQ0M1NVNvNDRDQ0NnPT0iLCAic2hhMjU2IjogImU3MWI3YjMyMTljMjA3Nzg5Yzc2NWY4NDg5NWRjMjQzMmQ1NmIyNzNhODMyMTVlZDllZDFiZWU5MDY4NTE0MWEifSwgIlJFVFJZMl9BNDBfQVVUSE9SSVpBVElPTl8yMDI2MDkxMS5tZCI6IHsiYmFzZTY0IjogIkl5RG5yS3prdW96cG1MYm1yclhtbUw3bHJaamxwTEhvdEtYb29hWG90NUhrdVl2a3VvenZ2SWh5WlhSeWVUTHZ2SXhCTkRBZ0x5Qm9aM0IxTk8rOGllKzhtdWVVcU9hSXQrYU9pT2FkZytpdXNPVzlsUW9LTWpBeU5pMHdPUzB4TVNBeE9Ub3plTys4aUNzd09PKzhpZSs4ak9lVXFPYUl0K1djcU9pT3QrZWZwZVM3cGVTNGkrUzZpK1d1bnVXUWp1V2JudVdralNEaWdKeG5iK0tBbmUrOG1nb0tMU0F4TWlEa3VLcm1tTDdsclpqbHBMSG90S1hsalpYbGhZUG5tb1RwcHBibXJLSG9vYVhvdDVFZ1lESXlORE00T1dEdnZJaG9aM0IxT08rOGpFRTRNREF0T0RCSFF1KzhqR0JTUlZOUFZWSkRSVjlTUlZSU1dWOUJWVlJJVDFKSldrRlVTVTlPWHpJd01qWXdPVEE1TG0xa1lPKzhpZVdQcitpd2crVzZwaUF6T0NEbHNJL21sN2JrdTQwZ01DRGxrSy9saXFqdnZKdm9pb0xuZ3Jubmk2emxqYURsdDdMa3VvNGdNVGM2TWprZzVwUys1YnlBNzd5SVlFNVBSRVZmVUVsT1gxSkZURUZZUVZSSlQwNWZRVlZVU0U5U1NWcEJWRWxQVGw4eU1ESTJNRGt4TVM1dFpHRHZ2SW52dkl6a3ZZWWdhR2R3ZFRnZzVvNmw1TGlMNXAybDU1cUVJREUySU9TNHF1V05vZVM5amVXRmlPVzlrdVM3bHVTNnV1YWJ0T2FYcWVhT2t1bVluK2VhaE9TOW5PUzRtdSs4ak9taWhPaXVvZWFjZ09hWHFTQXdPUzB4TWlEbm1iM2xwS25taVkzb3ZhN2xpTERqZ0lJS0xTRG1uS3ptbkxvZ01USWdSMElnNXBpKzVZMmg1b3lKNVlhNzU3dVQ2SzYrNTcydTVaeW81NnlzNUxpQTVvbTU1WW1ONVpDUjVZMno1cGkrNWEyWTVMaU42TGF6Nzd5SVlHeHZZMkZzWDJabFlYTnBZbWxzYVhSNVh6SXdNall3T1RFd0wyRHZ2SW52dkl6a3VJM29nNzNsaUlibWk0WGpnSUlLTFNEb29hWG90NUhsa0svbGlxamxtYWptaW9vZzRvQ2M1WWlHNVl5NklHaG5jSFU0SU9TNGxPYVl2dVd0bUNEaWlhVWdOelVnUjJsQzRvQ2RJT1dHbWVhdHUrKzhqT2FZcitTL25lV3VpT1M4c09pdW9laUFqT21kbnVXdW51YTFpK21jZ09heGd1KzhtK2kvbVNBeE1pRGt1S3JsalpYbGhZUGxqNnJvb3F2b3I0SG1tSTdwbklEb3BvSG90b1hvdjRjZ01qTXVOU0JIUXVPQWd1YU1pZWEvZ09hMHUrbUhqK1drbHVhT3FPKzhqRFkwdzVjeU1PKzhpT2Uwb3VXOGxTQXo0b0NUTmUrOGllUzRqaUEyTk1PWE11V3hnc09YTVRYdnZJam50S0xsdkpVZ09lS0FrekV4Nzd5SjU3cW02WnlBSURJMjRvQ1RNekFnUjBMdnZJemxqNi9tbEw3bGhhVWdhR2R3ZFRRZzU1cUVJRTVXU1VSSlFTQkJORER2dklnME5DNHpOU0JIYVVMdnZJem5yS3dnTlRRZzVZKzM1bzZpNlpLSTVhNmU1cldMNzd5TVVIbFViM0pqYUNBeUxqUXVNQ0F2SUVOVlJFRWdNVEl1TVNBdklHTjFSRTVPSURrd01UQXdJT1M0anVXR3UrZTdrK2VPcitXaWcrUzRnT2lIdE8rOGllKzhtekV5T0NEbnU3VG5tb1FnTmlEa3VLcmxqWlhsaFlQdnZJam50S0xsdkpVZ01PS0FrekxqZ0lFMjRvQ1RPTys4aWVTOHNPaXVvU0EwTU9LQWt6VXpJRWRDNzd5TTVMaU41b3FWSUVFME1PT0FnZ29LSXlNZzVweXM1cDJoNW82STVwMkQ1WVdCNks2NENnb3hMaURtbHJEbHU3cm5pNnpucTR2b29hWG90NUVnWUVKZmJXVnRiM0o1WHpJd01qWXdPVEV4WDNKbGRISjVNbUR2dkl6b3Y1em5xSXZtb0xubm02N2x2WlVnWUM5a1lYUmhNUzlvYjIxbEwzTjFibmxwY1M5cllXeHRZVzV1WlhSZmQzSnlYMjF2WkdWc1gzTmxiR1ZqZEdsdmJsOHlNREkyTURrd09DOXlaWE52ZFhKalpWOXlaV052ZG1WeWVWOHlNREkyTURreE1TOUNYM0psZEhKNU1tRHZ2SXpsajZycGtvamxyN25sanAva3Zaemt1Sm9nWURJeU5ESTFOV0FnNTVxRTU3U2k1YnlWSUNvcU0rT0FnVFRqZ0lFMTQ0Q0JPZU9BZ1RFdzQ0Q0JNVEVxS3UrOGlPV1FoT2lIcXVXT24rbUZqZWU5cnVTNGp1V09uK21haithY3V1ZW5qZVd0a0NBME11S0FrelEwNzd5Sjc3eU01THVPNTZtNjU1dXU1YjJWNWJ5QTVhZUw3N3lNNVlpRzVZeTZJR0JvWjNCMU5HRHZ2SXptcjQvcG9ibmt1SURsdktEbW1MN2xqYUhqZ0lFMElPYWd1T09BZ1RJMElPV3dqK2FYdHVTNGl1bVprT09BZ1dBdExXNXZMWEpsY1hWbGRXVmc0NENCNXBXdzU3dUU1Ym0yNVkrUklHQWxNMkRqZ0lJS01pNGc1WkN2NVlxbzVabW82WmVvNXFlYjVwUzU1TGk2SU9LQW5PV0lodVdNdWlCb1ozQjFOQ0RrdUpUbW1MN2xyWmdnNG9tbElEUXdJRWRwUXVLQW5lKzhqT2FZdnVXTm9laTZxK1M3dlNCZ1RsWkpSRWxCSUVFME1HRHZ2SnZsaGJia3ZabmxrSy9saXFqbG1hanBnTHZvdnBIcGdKRGxyWmZtc3IvbmxLZ2djbVYwY25reDc3eUk1WTZmNWFTeDZMU2w2SytCNW8ydTVxQzQ1YSs1NDRDQjVZYTc1N3VUNXJxUTU2Q0I1TGlPNXBXdzVvMnU1Wk9JNWJpTTVxQzQ1YSs1NDRDQjZMK1E2S0dNNTQ2djVhS0Q1NG1JNXB5czVxQzQ1YSs1NDRDQjVvdVM1N3VkNWJleTVweUo2TDZUNVllNjQ0Q0I1TGlBNXF5aDVvQ242YUtHNVkrVzZLNnc1YjJWNDRDQjVMaU42Sys3NVkrVzVyV0w2SytWNlp1Rzc3eUo0NENDQ2pNdUlPUzR1dVd1aU9TOWp5RGlnSnptbklEbHBKb2dOaURsdktEbW1MN2xqYUhsdWJib29ZemlnSjBnNTVxRTVaQ0k1WkNNNUxpSzZabVE3N3lNNW8rUTVMcWs1b2lRNVlxZjVaQ081b3FLSUdBeU1qUXpPRGxnSU9lYWhPYVZzT2U3aE9XNXR1V1BrZVM3amlCZ0pUWmdJT21aamVTNHVpQmdKVE5nNzd5SVlITmpiMjUwY205c0lIVndaR0YwWlNCS2IySkpaRDB5TWpRek9Ea2dRWEp5WVhsVVlYTnJWR2h5YjNSMGJHVTlNMkR2dkludnZKdHlaWFJ5ZVRJZzU3dVQ1cDJmNVpDTzVvR2k1YVNOSUdBbE5tRGpnSUlLTkM0ZzVaQ001TGlBNVkyVjVZV0Q1TGlONWI2WDZLS3I1TGlrNUxpcTViQ2Q2SytWNVpDTTVwZTI2SzZ0NTd1RDc3eWFjbVYwY25reUlPZWFoT2Fma09taHVlbUFtdWkvaCtXUXIrV0txT21YcU9XNXR1V0dtZVdGcGVtaWh1V1BsdWl1c09XOWxlV1FqdSs4ak9XUGx1YTJpQ0JnTWpJME16ZzVZQ0RrdUszbHI3bmx1cFRubW9UcGdxUGt1SURwb2JudnZJaGdjMk5oYm1ObGJDQXlNalF6T0RsZlBPZTBvdVc4bFQ1Zzc3eU02WUNRNmFHNTQ0Q0I1b3lKNUwyYzVMaWE1WSszNzd5Sjc3eWI2SXVsSUhKbGRISjVNaURubW9UbW41RHBvYm5sbktqcGw2am1wNXZtaUpicHBwYm1pYm5saVkzbGtKSGxwTEhvdEtYdnZJeGdNakkwTXpnNVlDRGt1SzNscjdubHVwVHBvYm5rdjUzbmxabmt2WnprdUxybG01N3BnSURqZ0lMbGo1Ym10b2psaXFqa3ZaemxqNmJvb1l6cGdKRHBvYm5vcnJEbHZaWGpnSUlLQ2lNaklPYWNyT2Fkb2VhT2lPYWRnK1M0amVhMmllV1BpZ29LNW9tNTVhU241YkNQSURJd05EampnSUhtbGJEbGdMem11cERub0lIamdJSG1qWi9scExIamdJSG1sNm5sZ1p6amdJSGxyYWJrdWFEbmpvZm9zSVBsdXFiamdJSHBtby9tbkxybnA0M2xyWkRqZ0lFeU1EQWc2TDJ1NUxpSzZabVE0NENCNllDSjVaNkw2S2VFNVlpWjQ0Q0I1cldMNksrVjVweWY0NENCNTZ5czVMaUo2WmkyNXE2MTQ0Q0I2SzY2NXBhSDVMaU81NDZ3NTVTbzVxaWg1WjZMNVoySDVMaU41WStZNzd5YjVMaU42WWVONkxlUjVwV3c1WUM4NWFTeDZMU2w1WTJWNVlXRDc3eWI1TGlONXBhdzVhS2U1WUNaNllDSjc3eWI1TGlONVlxb0lHQXlNalF6T0RsZ0lPZWFoT2Uwb3VXOGxTQXc0b0NUTXVPQWdUYmlnSk00NDRDQzVhNmU2Wm1GNTZHczVMdTI3N3lJUVRRd0lPV3Z1U0JCT0RBd0x6TXdPVER2dklua3Zaemt1THJsaGF6bHZJRG5tb1RtaWFmb29Zem5qcS9sb29QbGo1amxqSmJvcnJEbHZaWHZ2SXpwbW8vbXI0L21uYUhvcnEzbnU0UG5tb1RvdjVEb29Zem1sN2JscnFIb3JxSGt1SURvdGJmbWlxdnBuTExqZ0lJS0NpTWpJT2FXaCtTN3Rnb0tMU0RwZzZqbnZiTGt2Wk1nWUdSbGNHeHZlVjlDWDIxbGJXOXllVjl5WlhSeWVUSmZNakF5TmpBNU1URXVjSGxnNDRDQjVaQ3Y1WXFvNVptb0lHQnNZWFZ1WTJoZlFsOXRaVzF2Y25sZmNtVjBjbmt5WHpJd01qWXdPVEV4TG5CNVlPT0FnZVM4b09pK2srYUprK1dNaFNCZ1luVnBiR1JmUWw5dFpXMXZjbmxmY21WMGNua3lYM1J5WVc1emNHOXlkRjh5TURJMk1Ea3hNUzV3ZVdBZzRvYVNJR0J6ZFdKdGFYUmZRbDl0WlcxdmNubGZjbVYwY25reVh6SXdNall3T1RFeExuTm9ZT09BZ2VhT3ArV0l0dWExaStpdmxTQmdkR1Z6ZEY5Q1gyMWxiVzl5ZVY5eVpYUnllVEpmTWpBeU5qQTVNVEV1Y0hsZzc3eWI1Wk9JNWJpTTVMaU81bytRNUxxazVadWU1b21uNks2dzVMcU9JSEJ5YjJkeVpYTnpMbTFrSUM4Z1EwOU9WRWxPVlVGVVNVOU9YME5QVGxSU1FVTlVMbTFrNDRDQ0NnPT0iLCAic2hhMjU2IjogImI3YmMzY2Y1MDE5YzlhNWFiYzg1MjhiYmM3Y2M4NDUzOWQwZDQ3ZTc4OWNlNDY2YmQ4ZDE1ZDI4NGFkNWNjZjcifSwgImxhdW5jaF9CX21lbW9yeV9yZXRyeTJfMjAyNjA5MTEucHkiOiB7ImJhc2U2NCI6ICJJaUlpU1hOdmJHRjBaV1FzSUc5dVpTMWhkSFJsYlhCMExYQmxjaTFqWld4c0lISmxjMjkxY21ObElISmxkSEo1SUNNeUlDaEJOREFnTHlCb1ozQjFOQ3dnYVc1a2FXTmxjeUF6TFRVZ1lXNWtJRGt0TVRFcE95Qm1jbTk2Wlc0Z2RISmhhVzVwYm1jZ1kyOWtaU0JwY3lCMWJtTm9ZVzVuWldRdUlpSWlDbVp5YjIwZ1gxOW1kWFIxY21WZlh5QnBiWEJ2Y25RZ1lXNXViM1JoZEdsdmJuTUtDbWx0Y0c5eWRDQmhjbWR3WVhKelpRcHBiWEJ2Y25RZ2FHRnphR3hwWWdwcGJYQnZjblFnYVcxd2IzSjBiR2xpTG5WMGFXd0thVzF3YjNKMElHcHpiMjRLYVcxd2IzSjBJRzl6Q21aeWIyMGdjR0YwYUd4cFlpQnBiWEJ2Y25RZ1VHRjBhQXBwYlhCdmNuUWdjbVVLYVcxd2IzSjBJSE41Y3dwbWNtOXRJR1JoZEdWMGFXMWxJR2x0Y0c5eWRDQmtZWFJsZEdsdFpTd2dkR2x0WlhwdmJtVUtDa1pCVFVsTVdTQTlJRkJoZEdnb0p5OWtZWFJoTVM5b2IyMWxMM04xYm5scGNTOXJZV3h0WVc1dVpYUmZkM0p5WDIxdlpHVnNYM05sYkdWamRHbHZibDh5TURJMk1Ea3dPQ2NwQ2xKUFQxUWdQU0JHUVUxSlRGa2dMeUFuY21WemIzVnlZMlZmY21WamIzWmxjbmxmTWpBeU5qQTVNVEV2UWw5eVpYUnllVEluQ2s5U1NVZEpUa0ZNSUQwZ1JrRk5TVXhaSUM4Z0ozTjBZV2RsY3k5Q0p3cFBVa2xIU1U1QlRGOU5RVTVKUmtWVFZGOVRTRUVnUFNBbll6Vm1PR1ExTmpRNE1EVXhNRGN5T1dSa01UUmtORFJqWWpBd1pEVmxOekF6TkRJMVpXSmtaV0k0TXpkaU1EVTVZalkzTkRrNU9HSTBNalUzT0RSaU1TY0tSVmhRSUQwZ1VHRjBhQ2duWlhod1pYSnBiV1Z1ZEhNdmIzQjBhVzFwZW1WZmFIbHdaWEpmY0dGeVlXMWxkR1Z5Y3k5M2NuSmZhSEJmWlhoMFpXNXphVzl1WHpJd01qWXdPVEF5SnlrS1IxQlZJRDBnSjA1V1NVUkpRU0JCTkRBbkNrRk1URTlYUlVSZlNVNUVTVU5GVXlBOUlGc3pMQ0EwTENBMUxDQTVMQ0F4TUN3Z01URmRDazFKVGw5SFVGVmZUVVZOVDFKWlgwSlpWRVZUSUQwZ05EQWdLaUF4TURJMEtpb3pDbEJCVWxSSlZFbFBUaUE5SUNkb1ozQjFOQ2NLUVZSVVJVMVFWRjlKUkNBOUlDZENYMjFsYlc5eWVWOHlNREkyTURreE1WOXlaWFJ5ZVRJbkNnb0taR1ZtSUhOb1lTaHdZWFJvS1RvS0lDQWdJSEpsZEhWeWJpQm9ZWE5vYkdsaUxuTm9ZVEkxTmlod1lYUm9MbkpsWVdSZllubDBaWE1vS1NrdWFHVjRaR2xuWlhOMEtDa0tDZ3BrWldZZ2JtOTNLQ2s2Q2lBZ0lDQnlaWFIxY200Z1pHRjBaWFJwYldVdWJtOTNLSFJwYldWNmIyNWxMblYwWXlrdWFYTnZabTl5YldGMEtDa0tDZ3BrWldZZ2IzSmthVzVoY25rb2NHRjBhQ2s2Q2lBZ0lDQnBaaUJ1YjNRZ2NHRjBhQzVwYzE5bWFXeGxLQ2tnYjNJZ2NHRjBhQzVwYzE5emVXMXNhVzVyS0NrZ2IzSWdjR0YwYUM1eVpYTnZiSFpsS0NrZ0lUMGdjR0YwYUM1aFluTnZiSFYwWlNncE9nb2dJQ0FnSUNBZ0lISmhhWE5sSUZKMWJuUnBiV1ZGY25KdmNpaG1KMFY0Y0dWamRHVmtJRzl5WkdsdVlYSjVJR1pwYkdVZ2QybDBhRzkxZENCemVXMXNhVzVySUdGdVkyVnpkRzl5Y3pvZ2UzQmhkR2g5SnlrS0lDQWdJSEpsZEhWeWJpQndZWFJvQ2dvS1pHVm1JSGR5YVhSbFgyNWxkeWh3WVhSb0xDQmtZWFJoS1RvS0lDQWdJSGRwZEdnZ2NHRjBhQzV2Y0dWdUtDZDRKeXdnWlc1amIyUnBibWM5SjNWMFppMDRKeWtnWVhNZ2MzUnlaV0Z0T2dvZ0lDQWdJQ0FnSUdwemIyNHVaSFZ0Y0Noa1lYUmhMQ0J6ZEhKbFlXMHNJR2x1WkdWdWREMHlMQ0J6YjNKMFgydGxlWE05VkhKMVpTa0tJQ0FnSUNBZ0lDQnpkSEpsWVcwdWQzSnBkR1VvSjF4dUp5a0tDZ3BrWldZZ2NtVmhaRjlqYjI1MGNtRmpkQ2h5YjI5MExDQnRZVzVwWm1WemRGOXphR0VwT2dvZ0lDQWdhV1lnY205dmRDQWhQU0JTVDA5VUlHOXlJSEp2YjNRdWNtVnpiMngyWlNncElDRTlJRkpQVDFRZ2IzSWdibTkwSUhKbExtWjFiR3h0WVhSamFDaHlKMXN3TFRsaExXWmRlelkwZlNjc0lHMWhibWxtWlhOMFgzTm9ZU2s2Q2lBZ0lDQWdJQ0FnY21GcGMyVWdVblZ1ZEdsdFpVVnljbTl5S0NkU1pYUnllU0J5YjI5MElHOXlJR1Y0ZEdWeWJtRnNJRzFoYm1sbVpYTjBJSEJwYmlCdGFYTnRZWFJqYUNjcENpQWdJQ0J3WVhSb0lEMGdiM0prYVc1aGNua29jbTl2ZENBdklDZFNSVlJTV1Y5TlFVNUpSa1ZUVkM1cWMyOXVKeWtLSUNBZ0lHbG1JSE5vWVNod1lYUm9LU0FoUFNCdFlXNXBabVZ6ZEY5emFHRTZDaUFnSUNBZ0lDQWdjbUZwYzJVZ1VuVnVkR2x0WlVWeWNtOXlLQ2RTWlhSeWVTQnRZVzVwWm1WemRDQmllWFJsY3lCa2FXWm1aWElnWm5KdmJTQnpkV0p0YVhSMFpXUWdjMk55YVhCMElIQnBiaWNwQ2lBZ0lDQnRJRDBnYW5OdmJpNXNiMkZrY3lod1lYUm9MbkpsWVdSZllubDBaWE1vS1NrS0lDQWdJR2xtSUNodFd5ZHliMjkwSjEwZ0lUMGdjM1J5S0ZKUFQxUXBJRzl5SUcxYkoyOXlhV2RwYm1Gc1gzSnZiM1FuWFNBaFBTQnpkSElvVDFKSlIwbE9RVXdwQ2lBZ0lDQWdJQ0FnSUNBZ0lHOXlJRzFiSjI5eWFXZHBibUZzWDJwdllsOXBaQ2RkSUNFOUlDY3lNalF5TlRVbklHOXlJRzFiSjJGc2JHOTNaV1JmYVc1a2FXTmxjeWRkSUNFOUlFRk1URTlYUlVSZlNVNUVTVU5GVXdvZ0lDQWdJQ0FnSUNBZ0lDQnZjaUJ0V3lkbmNIVW5YU0FoUFNCSFVGVWdiM0lnYlZzbmJXbHVYMmR3ZFY5dFpXMXZjbmxmWW5sMFpYTW5YU0FoUFNCTlNVNWZSMUJWWDAxRlRVOVNXVjlDV1ZSRlV3b2dJQ0FnSUNBZ0lDQWdJQ0J2Y2lCdFd5ZHdZWEowYVhScGIyNG5YU0FoUFNCUVFWSlVTVlJKVDA0S0lDQWdJQ0FnSUNBZ0lDQWdiM0lnYlZzblltRjBZMmhmYzJsNlpTZGRJQ0U5SURJd05EZ2diM0lnYlZzbmJXRjRYMlZ3YjJOb2N5ZGRJQ0U5SURJd01Bb2dJQ0FnSUNBZ0lDQWdJQ0J2Y2lCdFd5ZHRZWGhmWTI5dVkzVnljbVZ1ZEY5MGNtRnBibWx1WnlkZElDRTlJRE1nYjNJZ2JWc25kR2x0WlY5c2FXMXBkRjlvYjNWeWN5ZGRJQ0U5SURJMENpQWdJQ0FnSUNBZ0lDQWdJRzl5SUcxYkoyUmxjR1Z1WkdWdVkza25YU0JwY3lCdWIzUWdUbTl1WlNCdmNpQnRXeWRoZEhSbGJYQjBYMmxrSjEwZ0lUMGdRVlJVUlUxUVZGOUpSQ2s2Q2lBZ0lDQWdJQ0FnY21GcGMyVWdVblZ1ZEdsdFpVVnljbTl5S0NkU1pYUnllU0JqYjI1MGNtRmpkQ0JrYjJWeklHNXZkQ0J0WVhSamFDQmhkWFJvYjNKcGVtVmtJSEpsYzI5MWNtTmxJSEpsWTI5MlpYSjVKeWtLSUNBZ0lHWnZjaUJ5Wld3c0lHVjRjR1ZqZEdWa0lHbHVJRzFiSjJWNGRISmhYM04wWVhScFkxOW1hV3hsY3lkZExtbDBaVzF6S0NrNkNpQWdJQ0FnSUNBZ2FXWWdjbVZzTG5OMFlYSjBjM2RwZEdnb0p5OG5LU0J2Y2lBblhGd25JR2x1SUhKbGJDQnZjaUJoYm5rb2VDQnBiaUFvSnljc0lDY3VKeXdnSnk0dUp5a2dabTl5SUhnZ2FXNGdjbVZzTG5Od2JHbDBLQ2N2SnlrcE9nb2dJQ0FnSUNBZ0lDQWdJQ0J5WVdselpTQlNkVzUwYVcxbFJYSnliM0lvSjFWdWMyRm1aU0J5WlhSeWVTQnpkR0YwYVdNZ2NHRjBhQ2NwQ2lBZ0lDQWdJQ0FnYVdZZ2MyaGhLRzl5WkdsdVlYSjVLSEp2YjNRZ0x5QnlaV3dwS1NBaFBTQmxlSEJsWTNSbFpEb0tJQ0FnSUNBZ0lDQWdJQ0FnY21GcGMyVWdVblZ1ZEdsdFpVVnljbTl5S0dZblVtVjBjbmtnWTI5dWRISnZiQ0JvWVhOb0lHMXBjMjFoZEdOb09pQjdjbVZzZlNjcENpQWdJQ0JtYjNJZ2NHRnlaVzUwSUdsdUlDaHliMjkwTENCUFVrbEhTVTVCVENrNkNpQWdJQ0FnSUNBZ2FXWWdjMmhoS0c5eVpHbHVZWEo1S0hCaGNtVnVkQ0F2SUNkVFZFRkhSVjlDWDAxQlRrbEdSVk5VTG1wemIyNG5LU2tnSVQwZ1QxSkpSMGxPUVV4ZlRVRk9TVVpGVTFSZlUwaEJPZ29nSUNBZ0lDQWdJQ0FnSUNCeVlXbHpaU0JTZFc1MGFXMWxSWEp5YjNJb0owOXlhV2RwYm1Gc0lITjBZV2RsSUhOdmRYSmpaU0J0WVc1cFptVnpkQ0JwWkdWdWRHbDBlU0J0YVhOdFlYUmphQ2NwQ2lBZ0lDQnZjbWxuYVc1aGJGOXRZVzVwWm1WemRDQTlJR3B6YjI0dWJHOWhaSE1vS0hKdmIzUWdMeUFuVTFSQlIwVmZRbDlOUVU1SlJrVlRWQzVxYzI5dUp5a3VjbVZoWkY5aWVYUmxjeWdwS1FvZ0lDQWdJeUJVYUdWelpTQmhjbVVnZEdobElIVnViVzlrYVdacFpXUWdiM0pwWjJsdVlXd2dOamNnYzNSaGRHbGpJR1pwYkdWekxDQmhiSE52SUdOb1pXTnJaV1FnWVhRZ2MyOTFjbU5sTGdvZ0lDQWdabTl5SUhKbGJDd2daWGh3WldOMFpXUWdhVzRnYjNKcFoybHVZV3hmYldGdWFXWmxjM1JiSjNOMFlYUnBZMTltYVd4bGN5ZGRMbWwwWlcxektDazZDaUFnSUNBZ0lDQWdhV1lnY21Wc0xuTjBZWEowYzNkcGRHZ29KeThuS1NCdmNpQW5YRnduSUdsdUlISmxiQ0J2Y2lCaGJua29lQ0JwYmlBb0p5Y3NJQ2N1Snl3Z0p5NHVKeWtnWm05eUlIZ2dhVzRnY21Wc0xuTndiR2wwS0Njdkp5a3BPZ29nSUNBZ0lDQWdJQ0FnSUNCeVlXbHpaU0JTZFc1MGFXMWxSWEp5YjNJb0oxVnVjMkZtWlNCdmNtbG5hVzVoYkNCemRHRjBhV01nY0dGMGFDY3BDaUFnSUNBZ0lDQWdabTl5SUhCaGNtVnVkQ0JwYmlBb2NtOXZkQ3dnVDFKSlIwbE9RVXdwT2dvZ0lDQWdJQ0FnSUNBZ0lDQnBaaUJ6YUdFb2IzSmthVzVoY25rb2NHRnlaVzUwSUM4Z2NtVnNLU2tnSVQwZ1pYaHdaV04wWldRNkNpQWdJQ0FnSUNBZ0lDQWdJQ0FnSUNCeVlXbHpaU0JTZFc1MGFXMWxSWEp5YjNJb1ppZFBjbWxuYVc1aGJDQnpkR0YwYVdNZ1lubDBaWE1nWTJoaGJtZGxaRG9nZTNCaGNtVnVkQ0F2SUhKbGJIMG5LUW9nSUNBZ2IyeGtYMlY0Y0dWamRHVmtJRDBnYW5OdmJpNXNiMkZrY3lnb2NtOXZkQ0F2SUNkbGVIQmxZM1JsWkY5eWRXNTBhVzFsTG1wemIyNG5LUzV5WldGa1gySjVkR1Z6S0NrcENpQWdJQ0JsZUhCbFkzUmxaQ0E5SUdScFkzUW9iMnhrWDJWNGNHVmpkR1ZrTENCbmNIVTlSMUJWS1FvZ0lDQWdhV1lnYlZzbmNuVnVkR2x0WlY5bGVIQmxZM1JsWkNkZElDRTlJR1Y0Y0dWamRHVmtPZ29nSUNBZ0lDQWdJSEpoYVhObElGSjFiblJwYldWRmNuSnZjaWduVDI1c2VTQjBhR1VnUjFCVklHbGtaVzUwYVhSNUlHMWhlU0JrYVdabVpYSWdabkp2YlNCbWNtOTZaVzRnY25WdWRHbHRaU2NwQ2lBZ0lDQnlaWFIxY200Z2JTd2diM0pwWjJsdVlXeGZiV0Z1YVdabGMzUXNJR1Y0Y0dWamRHVmtDZ29LWkdWbUlHZDFZWEprWDI5eWFXZHBibUZzWDJaaGFXeDFjbVVvY205dmRDd2dhVzVrWlhnc0lHMHBPZ29nSUNBZ2FXWWdhWE5wYm5OMFlXNWpaU2hwYm1SbGVDd2dZbTl2YkNrZ2IzSWdibTkwSUdsemFXNXpkR0Z1WTJVb2FXNWtaWGdzSUdsdWRDa2diM0lnYVc1a1pYZ2dibTkwSUdsdUlFRk1URTlYUlVSZlNVNUVTVU5GVXpvS0lDQWdJQ0FnSUNCeVlXbHpaU0JTZFc1MGFXMWxSWEp5YjNJb0owOXViSGtnZEdobElHRjFkR2h2Y21sNlpXUWdiM0pwWjJsdVlXd2dRaUJ0WlcxdmNua3RabUZwYkdWa0lHbHVaR2xqWlhNZ015MDFJR0Z1WkNBNUxURXhJR05oYmlCeVpYUnllU0JvWlhKbEp5a0tJQ0FnSUdaaGFXeDFjbVVnUFNCdFd5ZG1ZV2xzZFhKbGN5ZGRXM04wY2locGJtUmxlQ2xkQ2lBZ0lDQm1iM0lnYkdGaVpXd2dhVzRnS0NkbGNuSnZjaWNzSUNkbVlXbHNaV1JmYldGeWEyVnlKeXdnSjJOc1lXbHRKeXdnSjJGMVpHbDBKeWs2Q2lBZ0lDQWdJQ0FnWlc1MGNua2dQU0JtWVdsc2RYSmxXMnhoWW1Wc1hRb2dJQ0FnSUNBZ0lIQmhkR2dnUFNCUVlYUm9LR1Z1ZEhKNVd5ZHdZWFJvSjEwcENpQWdJQ0FnSUNBZ2FXWWdibTkwSUhCaGRHZ3VhWE5mY21Wc1lYUnBkbVZmZEc4b1QxSkpSMGxPUVV3cElHOXlJSE5vWVNodmNtUnBibUZ5ZVNod1lYUm9LU2tnSVQwZ1pXNTBjbmxiSjNOb1lUSTFOaWRkT2dvZ0lDQWdJQ0FnSUNBZ0lDQnlZV2x6WlNCU2RXNTBhVzFsUlhKeWIzSW9aaWRQY21sbmFXNWhiQ0JtWVdsc2RYSmxJR1YyYVdSbGJtTmxJR05vWVc1blpXUTZJSHRzWVdKbGJIMHNJR2x1WkdWNElIdHBibVJsZUgwbktRb2dJQ0FnYVdZZ0ozUnZjbU5vTGs5MWRFOW1UV1Z0YjNKNVJYSnliM0k2SUVOVlJFRWdiM1YwSUc5bUlHMWxiVzl5ZVM0bklHNXZkQ0JwYmlCUVlYUm9LR1poYVd4MWNtVmJKMlZ5Y205eUoxMWJKM0JoZEdnblhTa3VjbVZoWkY5MFpYaDBLQ2s2Q2lBZ0lDQWdJQ0FnY21GcGMyVWdVblZ1ZEdsdFpVVnljbTl5S0NkUGNtbG5hVzVoYkNCbVlXbHNkWEpsSUdseklHNXZkQ0IwYUdVZ1lYVjBhRzl5YVhwbFpDQkhVRlVnYldWdGIzSjVJR1poYVd4MWNtVW5LUW9nSUNBZ1kyeGhhVzBnUFNCcWMyOXVMbXh2WVdSektGQmhkR2dvWm1GcGJIVnlaVnNuWTJ4aGFXMG5YVnNuY0dGMGFDZGRLUzV5WldGa1gySjVkR1Z6S0NrcENpQWdJQ0JwWmlCamJHRnBiVnNuYVc1a1pYZ25YU0FoUFNCcGJtUmxlQ0J2Y2lCemRISW9ZMnhoYVcxYkoyRnljbUY1WDNSaGMydGZhV1FuWFNrZ0lUMGdjM1J5S0dsdVpHVjRLVG9LSUNBZ0lDQWdJQ0J5WVdselpTQlNkVzUwYVcxbFJYSnliM0lvSjA5eWFXZHBibUZzSUdaaGFXeDFjbVVnWTJ4aGFXMGdhVzVrWlhnZ2JXbHpiV0YwWTJnbktRb2dJQ0FnSXlCVWFHVWdiRzlqWVd3Z1ptbHNaU0JwZEhObGJHWWdjM1Z3Y0d4cFpYTWdhVzF0ZFhSaFlteGxJR1YyYVdSbGJtTmxPeUJqZFhKeVpXNTBJRzl5YVdkcGJtRnNJR3B2WW5NS0lDQWdJQ01nWTJGdUlHdGxaWEFnZDNKcGRHbHVaeUIxYm5KbGJHRjBaV1FnYzNWalkyVnpjMloxYkNCc2IyZHpJSGRwZEdodmRYUWdZV3gwWlhKcGJtY2dkR2hwY3lCamFHRnBiaTRLSUNBZ0lISmxkSFZ5YmlCbVlXbHNkWEpsQ2dvS1pHVm1JR05zWVdsdFgyOXVZMlVvY205dmRDd2dhVzVrWlhnc0lIQmhlV3h2WVdRcE9nb2dJQ0FnY0dGMGFDQTlJSEp2YjNRZ0x5QW5ZMnhoYVcxekp5QXZJR1luYVc1a1pYaDdhVzVrWlhnNk1EUmtmUzVxYzI5dUp3b2dJQ0FnZDNKcGRHVmZibVYzS0hCaGRHZ3NJSEJoZVd4dllXUXBDaUFnSUNCeVpYUjFjbTRnY0dGMGFBb0tDbVJsWmlCc2IyRmtYMmQxWVhKa0tISnZiM1FwT2dvZ0lDQWdjM2x6TG5CaGRHZ3VhVzV6WlhKMEtEQXNJSE4wY2loeWIyOTBLU2tLSUNBZ0lITndaV01nUFNCcGJYQnZjblJzYVdJdWRYUnBiQzV6Y0dWalgyWnliMjFmWm1sc1pWOXNiMk5oZEdsdmJpZ25iV1Z0YjNKNVgzSmxkSEo1WDJaeWIzcGxibDluZFdGeVpDY3NJSEp2YjNRZ0x5QW5iR0YxYm1Ob1gyOXVZMlV1Y0hrbktRb2dJQ0FnYlc5a2RXeGxJRDBnYVcxd2IzSjBiR2xpTG5WMGFXd3ViVzlrZFd4bFgyWnliMjFmYzNCbFl5aHpjR1ZqS1FvZ0lDQWdjM0JsWXk1c2IyRmtaWEl1WlhobFkxOXRiMlIxYkdVb2JXOWtkV3hsS1FvZ0lDQWdjbVYwZFhKdUlHMXZaSFZzWlFvS0NtUmxaaUJ0WVdsdUtDazZDaUFnSUNCd1lYSnpaWElnUFNCaGNtZHdZWEp6WlM1QmNtZDFiV1Z1ZEZCaGNuTmxjaWdwQ2lBZ0lDQndZWEp6WlhJdVlXUmtYMkZ5WjNWdFpXNTBLQ2N0TFdsdVpHVjRKeXdnY21WeGRXbHlaV1E5VkhKMVpTd2dkSGx3WlQxcGJuUXBDaUFnSUNCd1lYSnpaWEl1WVdSa1gyRnlaM1Z0Wlc1MEtDY3RMVzFoYm1sbVpYTjBMWE5vWVRJMU5pY3NJSEpsY1hWcGNtVmtQVlJ5ZFdVcENpQWdJQ0JoY21keklEMGdjR0Z5YzJWeUxuQmhjbk5sWDJGeVozTW9LUW9nSUNBZ2NtOXZkQ0E5SUZCaGRHZ29YMTltYVd4bFgxOHBMbkpsYzI5c2RtVW9LUzV3WVhKbGJuUUtJQ0FnSUcwc0lHOXlhV2RwYm1Gc1gyMWhibWxtWlhOMExDQmxlSEJsWTNSbFpDQTlJSEpsWVdSZlkyOXVkSEpoWTNRb2NtOXZkQ3dnWVhKbmN5NXRZVzVwWm1WemRGOXphR0V5TlRZcENpQWdJQ0JtWVdsc2RYSmxJRDBnWjNWaGNtUmZiM0pwWjJsdVlXeGZabUZwYkhWeVpTaHliMjkwTENCaGNtZHpMbWx1WkdWNExDQnRLUW9nSUNBZ2FXWWdiM011Wlc1MmFYSnZiaTVuWlhRb0oxTk1WVkpOWDBGU1VrRlpYMHBQUWw5SlJDY3BJQ0U5SUNoeWIyOTBJQzhnSjJGeWNtRjVYMnB2WWw5cFpDNTBlSFFuS1M1eVpXRmtYM1JsZUhRb0tTNXpkSEpwY0NncE9nb2dJQ0FnSUNBZ0lISmhhWE5sSUZKMWJuUnBiV1ZGY25KdmNpZ25RM1Z5Y21WdWRDQnpZMmhsWkhWc1pYSWdZWEp5WVhrZ2FYTWdibTkwSUhSb1pTQjFibWx4ZFdWc2VTQnpkV0p0YVhSMFpXUWdjbVYwY25rbktRb2dJQ0FnYVdZZ2IzTXVaVzUyYVhKdmJpNW5aWFFvSjFOTVZWSk5YMEZTVWtGWlgxUkJVMHRmU1VRbktTQWhQU0J6ZEhJb1lYSm5jeTVwYm1SbGVDazZDaUFnSUNBZ0lDQWdjbUZwYzJVZ1VuVnVkR2x0WlVWeWNtOXlLQ2REZFhKeVpXNTBJSE5qYUdWa2RXeGxjaUIwWVhOcklHbHVaR1Y0SUcxcGMyMWhkR05vSnlrS0lDQWdJR2xtSUc5ekxtVnVkbWx5YjI0dVoyVjBLQ2RUVEZWU1RWOUtUMEpmVUVGU1ZFbFVTVTlPSnlrZ0lUMGdVRUZTVkVsVVNVOU9PZ29nSUNBZ0lDQWdJSEpoYVhObElGSjFiblJwYldWRmNuSnZjaWduVW1WMGNua2diWFZ6ZENCeWRXNGdhVzRnZEdobElHaGhjbVIzWVhKbExYWmxjbWxtYVdWa0lIQmhjblJwZEdsdmJpY3BDaUFnSUNCbmRXRnlaQ0E5SUd4dllXUmZaM1ZoY21Rb2NtOXZkQ2tLSUNBZ0lHZDFZWEprTG5abGNtbG1lVjl6YjNWeVkyVmZhR0Z6YUdWektISnZiM1FzSUc5eWFXZHBibUZzWDIxaGJtbG1aWE4wS1FvZ0lDQWdaVzUyYVhKdmJtMWxiblFnUFNCbmRXRnlaQzVwYm5Od1pXTjBYMlZ1ZG1seWIyNXRaVzUwS0NrS0lDQWdJR2QxWVhKa0xuWmhiR2xrWVhSbFgzSjFiblJwYldWZmMyNWhjSE5vYjNRb1pXNTJhWEp2Ym0xbGJuUXNJR1Y0Y0dWamRHVmtMQ0JuZFdGeVpDNVdSVkpUU1U5T1gxSlZUbFJKVFVWZlJrbEZURVJUS1FvZ0lDQWdhVzF3YjNKMElIUnZjbU5vQ2lBZ0lDQndjbTl3WlhKMGFXVnpJRDBnZEc5eVkyZ3VZM1ZrWVM1blpYUmZaR1YyYVdObFgzQnliM0JsY25ScFpYTW9NQ2tLSUNBZ0lHbG1JSEJ5YjNCbGNuUnBaWE11ZEc5MFlXeGZiV1Z0YjNKNUlEd2diVnNuYldsdVgyZHdkVjl0WlcxdmNubGZZbmwwWlhNblhUb0tJQ0FnSUNBZ0lDQnlZV2x6WlNCU2RXNTBhVzFsUlhKeWIzSW9KMEZzYkc5allYUmxaQ0JIVUZVZ2FHRnpJR2x1YzNWbVptbGphV1Z1ZENCMlpYSnBabWxsWkNCMGIzUmhiQ0J0WlcxdmNua25LUW9nSUNBZ2IzSnBaMmx1WVd3Z1BTQm5kV0Z5WkM1c2IyRmtYMjl5YVdkcGJtRnNYMnhoZFc1amFHVnlLSEp2YjNRZ0x5QW5jbVZ3YnljZ0x5QkZXRkFnTHlBbmNuVnVYMjl1WlY5alpXeHNMbkI1SnlrS0lDQWdJR052YldKdklEMGdiM0pwWjJsdVlXd3ViRzloWkY5amIyMWlieWhoY21kekxtbHVaR1Y0S1FvZ0lDQWdaM1ZoY21RdWRtRnNhV1JoZEdWZlkyOXRZbThvSjBJbkxDQmhjbWR6TG1sdVpHVjRMQ0JqYjIxaWJ5a0tJQ0FnSUdsbUlHTnZiV0p2SUNFOUlHWmhhV3gxY21WYkoyTnZiV0p2SjEwNkNpQWdJQ0FnSUNBZ2NtRnBjMlVnVW5WdWRHbHRaVVZ5Y205eUtDZFNaWFJ5ZVNCamIyNW1hV2QxY21GMGFXOXVMM05sWldRZ1pHbG1abVZ5Y3lCbWNtOXRJRzl5YVdkcGJtRnNJR1poYVd4bFpDQmpaV3hzSnlrS0lDQWdJRzl5YVdkcGJtRnNMbWQxWVhKa1gzTnZkWEpqWlY5amIyNTBjbUZqZENncENpQWdJQ0J2Y21sbmFXNWhiQzVuZFdGeVpGOWtZWFJoWDJOdmJuUnlZV04wS0NrS0lDQWdJRzkxZEhCMWRDQTlJRzl5YVdkcGJtRnNMbVY0Y0dWamRHVmtYM0oxYmw5a2FYSW9jbTl2ZENBdklDZHlaWEJ2SnlBdklFVllVQ0F2SUNkeWRXNXpKeUF2SUdZaVptOXliV0ZzWDNObFpXUjdZMjl0WW05YkozTmxaV1FuWFgxZlozQjFJaXdnWTI5dFltOHBDaUFnSUNCbmRXRnlaQzV5WldaMWMyVmZaWGhwYzNScGJtZGZiM1YwY0hWMEtHOTFkSEIxZENrS0lDQWdJSEJoZVd4dllXUWdQU0I3SjJGMGRHVnRjSFJmYVdRbk9pQnRXeWRoZEhSbGJYQjBYMmxrSjEwc0lDZHZjbWxuYVc1aGJGOXlkVzVmYVdRbk9pQmpiMjFpYjFzbmNuVnVYMmxrSjEwc0NpQWdJQ0FnSUNBZ0lDQWdJQ0FnSUNkdmNtbG5hVzVoYkY5cWIySmZhV1FuT2lBbk1qSTBNalUxSnl3Z0oybHVaR1Y0SnpvZ1lYSm5jeTVwYm1SbGVDd2dKMk52YldKdkp6b2dZMjl0WW04c0NpQWdJQ0FnSUNBZ0lDQWdJQ0FnSUNkcWIySmZhV1FuT2lCdmN5NWxiblpwY205dVd5ZFRURlZTVFY5S1QwSmZTVVFuWFN3Z0oyRnljbUY1WDJwdllsOXBaQ2M2SUc5ekxtVnVkbWx5YjI1YkoxTk1WVkpOWDBGU1VrRlpYMHBQUWw5SlJDZGRMQW9nSUNBZ0lDQWdJQ0FnSUNBZ0lDQW5ZWEp5WVhsZmRHRnphMTlwWkNjNklHRnlaM011YVc1a1pYZ3NJQ2RqYkdGcGJXVmtYMkYwWDNWMFl5YzZJRzV2ZHlncExBb2dJQ0FnSUNBZ0lDQWdJQ0FnSUNBbmNtVjBjbmxmYldGdWFXWmxjM1JmYzJoaE1qVTJKem9nWVhKbmN5NXRZVzVwWm1WemRGOXphR0V5TlRZc0lDZHlkVzUwYVcxbEp6b2daVzUyYVhKdmJtMWxiblFzQ2lBZ0lDQWdJQ0FnSUNBZ0lDQWdJQ2RuY0hWZmRHOTBZV3hmYldWdGIzSjVYMko1ZEdWekp6b2djSEp2Y0dWeWRHbGxjeTUwYjNSaGJGOXRaVzF2Y25sOUNpQWdJQ0JqYkdGcGJWOXZibU5sS0hKdmIzUXNJR0Z5WjNNdWFXNWtaWGdzSUhCaGVXeHZZV1FwQ2lBZ0lDQjFibU5vWVc1blpXUmZZMjl1Wm1sbmRYSmxJRDBnYjNKcFoybHVZV3d1WTI5dVptbG5kWEpsWDNKbGNISnZaSFZqYVdKcGJHbDBlUW9LSUNBZ0lHUmxaaUJqYjI1bWFXZDFjbVVvYzJWbFpDazZDaUFnSUNBZ0lDQWdhV1lnYzJWbFpDQWhQU0JqYjIxaWIxc25aV1ptWldOMGFYWmxYM05sWldRblhUb0tJQ0FnSUNBZ0lDQWdJQ0FnY21GcGMyVWdVblZ1ZEdsdFpVVnljbTl5S0NkRlptWmxZM1JwZG1VZ2MyVmxaQ0J0YVhOdFlYUmphQ0JpWldadmNtVWdZMjl1Wm1sbmRYSnBibWNnY25WdWRHbHRaU2NwQ2lBZ0lDQWdJQ0FnY25WdWRHbHRaU0E5SUhWdVkyaGhibWRsWkY5amIyNW1hV2QxY21Vb2MyVmxaQ2tLSUNBZ0lDQWdJQ0JwWmlCeWRXNTBhVzFsV3lkelpXVmtKMTBnSVQwZ1kyOXRZbTliSjJWbVptVmpkR2wyWlY5elpXVmtKMTA2Q2lBZ0lDQWdJQ0FnSUNBZ0lISmhhWE5sSUZKMWJuUnBiV1ZGY25KdmNpZ25SV1ptWldOMGFYWmxJSE5sWldRZ2JXbHpiV0YwWTJnZ1lXWjBaWElnWTI5dVptbG5kWEpwYm1jZ2NuVnVkR2x0WlNjcENpQWdJQ0FnSUNBZ2MyNWhjSE5vYjNRZ1BTQmthV04wS0hKMWJuUnBiV1VzSUhCNWRHaHZibDkyWlhKemFXOXVQV1Z1ZG1seWIyNXRaVzUwV3lkd2VYUm9iMjVmZG1WeWMybHZiaWRkTENCdWRXMXdlVjkyWlhKemFXOXVQV1Z1ZG1seWIyNXRaVzUwV3lkdWRXMXdlVjkyWlhKemFXOXVKMTBwQ2lBZ0lDQWdJQ0FnWjNWaGNtUXVkbUZzYVdSaGRHVmZjblZ1ZEdsdFpWOXpibUZ3YzJodmRDaHpibUZ3YzJodmRDd2daWGh3WldOMFpXUXBDaUFnSUNBZ0lDQWdjbVYwZFhKdUlISjFiblJwYldVS0NpQWdJQ0J2Y21sbmFXNWhiQzVqYjI1bWFXZDFjbVZmY21Wd2NtOWtkV05wWW1sc2FYUjVJRDBnWTI5dVptbG5kWEpsQ2lBZ0lDQnZiR1JmWVhKbmRpQTlJSE41Y3k1aGNtZDJXenBkQ2lBZ0lDQjBjbms2Q2lBZ0lDQWdJQ0FnY0hKcGJuUW9hbk52Ymk1a2RXMXdjeWg3SjJWMlpXNTBKem9nSjFKRlUwOVZVa05GWDFKRlZGSlpYMFZPVkVWU1NVNUhYMVZPUTBoQlRrZEZSRjlVVWtGSlRrbE9SeWNzSUNvcWNHRjViRzloWkgwcExDQm1iSFZ6YUQxVWNuVmxLUW9nSUNBZ0lDQWdJSE41Y3k1aGNtZDJJRDBnVzNOMGNpaHliMjkwSUM4Z0ozSmxjRzhuSUM4Z1JWaFFJQzhnSjNKMWJsOXZibVZmWTJWc2JDNXdlU2NwTENBbkxTMXBibVJsZUNjc0lITjBjaWhoY21kekxtbHVaR1Y0S1YwS0lDQWdJQ0FnSUNCdmNtbG5hVzVoYkM1dFlXbHVLQ2tLSUNBZ0lHWnBibUZzYkhrNkNpQWdJQ0FnSUNBZ2IzSnBaMmx1WVd3dVkyOXVabWxuZFhKbFgzSmxjSEp2WkhWamFXSnBiR2wwZVNBOUlIVnVZMmhoYm1kbFpGOWpiMjVtYVdkMWNtVUtJQ0FnSUNBZ0lDQnplWE11WVhKbmRpQTlJRzlzWkY5aGNtZDJDZ29LYVdZZ1gxOXVZVzFsWDE4Z1BUMGdKMTlmYldGcGJsOWZKem9LSUNBZ0lHMWhhVzRvS1FvPSIsICJzaGEyNTYiOiAiZWQ3M2QyYTU0NjNhYTBkNzI4MDM0NDg1NWQ0NmU4MDZjMDhiMGU0MTFjNTI3MmNhMjAwMjM0OTJlOTJiN2JhYiJ9fQ=='
"""Deployment body (retry2: A40/hgpu4, indices 3-5 and 9-11) embedded in a unique mailbox request by the local builder."""
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
PROBE_PARENT = FAMILY / 'resource_recovery_20260909'
RETRY1 = PROBE_PARENT / 'B_retry1'
RETRY1_JOB = '224389'
PARENT = FAMILY / 'resource_recovery_20260911'
ROOT = PARENT / 'B_retry2'
INDICES = [3, 4, 5, 9, 10, 11]
ATTEMPT_ID = 'B_memory_20260911_retry2'
JOB_NAME = 'ngf-B-memory-r2'
ARRAY = '3-5,9-11%3'
GPU_NAME = 'NVIDIA A40'
MIN_GPU_MEMORY_BYTES = 40 * 1024**3
PARTITION = 'hgpu4'
CONTROL_FILES = {'launch_B_memory_retry2_20260911.py', 'RESOURCE_RETRY_AUTHORIZATION_20260909.md', 'RETRY2_A40_AUTHORIZATION_20260911.md'}
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
    require(set(files) == CONTROL_FILES, 'Unexpected control bundle')
    for key, raw in files.items():
        require(digest(raw) == bundle[key]['sha256'], 'Control bytes mismatch')
    require(FAMILY.is_dir() and FAMILY.resolve() == FAMILY and not os.path.lexists(ROOT), 'Retry2 already exists or unsafe family; inspect, never overwrite')
    require(PROBE_PARENT.is_dir() and PROBE_PARENT.resolve() == PROBE_PARENT, 'Hardware probe parent missing')
    hardware = json.loads(file_bytes(PROBE_PARENT / 'HARDWARE_PROBE_RESULT.json'))
    match = [r for r in hardware['queries'] if '--partition=hgpu4' in r['command']]
    require(len(match) == 1 and match[0]['returncode'] == 0 and not match[0]['stderr'], 'No successful A40 hardware probe')
    gpu = json.loads(match[0]['stdout'])
    require(gpu['gpu'] == GPU_NAME and gpu['partition'] == PARTITION and gpu['total_memory_bytes'] >= MIN_GPU_MEMORY_BYTES, 'A40 hardware identity failed')
    require(gpu['torch_version'] == '2.4.0' and gpu['cuda_version'] == '12.1' and gpu['cudnn_version'] == 90100, 'A40 software compatibility failed')
    # The first retry attempt must still be a queued, unclaimed attempt for exactly these cells.
    require(file_bytes(RETRY1 / 'array_job_id.txt').decode().strip() == RETRY1_JOB, 'Retry1 job identity failed')
    retry1_queue = query(['squeue', '-r', '-j', RETRY1_JOB, '-h', '-o', '%i|%T|%r'])
    retry1_states = {line.split('|')[0]: line.split('|')[1] for line in retry1_queue['stdout'].splitlines() if line.strip()}
    for index in INDICES:
        require(retry1_states.get(f'{RETRY1_JOB}_{index}') == 'PENDING', f'Retry1 task for index {index} is not PENDING; do not double-train')
        require(not os.path.lexists(RETRY1 / 'claims' / f'index{index:04d}.json'), f'Retry1 already claimed index {index}')
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
    require(JOB_NAME not in queue['stdout'], 'A retry job with this unique name already exists')
    failures = {}
    for index in INDICES:
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
    manifest = {'schema_version': 1, 'attempt_id': ATTEMPT_ID,
        'root': str(ROOT), 'original_root': str(ORIGINAL), 'original_job_id': '224255',
        'original_manifest_sha256': EXPECTED_MANIFEST, 'allowed_indices': list(INDICES),
        'gpu': gpu['gpu'], 'min_gpu_memory_bytes': MIN_GPU_MEMORY_BYTES, 'node': None,
        'partition': PARTITION, 'batch_size': 2048, 'max_epochs': 200,
        'max_concurrent_training': 3, 'time_limit_hours': 24, 'dependency': None,
        'total_training_concurrency_cap': 6,
        'shared_cap_with': {'job_id': RETRY1_JOB, 'array_task_throttle_after_this_submission': 3},
        'supersedes_pending_attempt': {'attempt_id': 'B_memory_20260909_retry1', 'job_id': RETRY1_JOB,
            'indices': list(INDICES), 'retry1_queue_at_deployment': retry1_queue,
            'policy': 'cancel the matching retry1 task only after this attempt has claimed the cell; keep it as fallback if this attempt fails before training'},
        'runtime_expected': runtime, 'scientific_source_changed': False, 'failures': failures,
        'extra_static_files': {key: digest(raw) for key, raw in files.items()},
        'hardware_probe_sha256': digest(file_bytes(PROBE_PARENT / 'HARDWARE_PROBE_RESULT.json')),
        'created_at_utc': now()}
    manifest_raw = (json.dumps(manifest, indent=2, sort_keys=True) + '\n').encode()
    manifest_sha = digest(manifest_raw)
    script = f'''#!/usr/bin/env bash
#SBATCH -J {JOB_NAME}
#SBATCH -p {PARTITION}
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 1-00:00:00
#SBATCH --array={ARRAY}
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
python -B -u {ROOT}/launch_B_memory_retry2_20260911.py --index "${{SLURM_ARRAY_TASK_ID:?}}" --manifest-sha256 {manifest_sha}
'''.encode()
    # Exclusive retry-root creation consumes this attempt even on an uncertain response.
    PARENT.mkdir(exist_ok=True)
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
        'script_sha256': digest(script), 'dependency': None, 'time_utc': now(),
        'retry_indices': list(INDICES), 'protected_files_verified': len(protected)})
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
        'root': str(ROOT), 'retry_indices': list(INDICES), 'original_job_id': '224255',
        'array': ARRAY, 'gpu': gpu['gpu'], 'node': None, 'partition': PARTITION,
        'dependency': None, 'manifest_sha256': manifest_sha,
        'script_sha256': digest(script), 'protected_files_verified': len(protected),
        'training_started': False, 'time_utc': now()}
    write_json(ROOT / 'SUBMISSION_RECEIPT.json', receipt)
    print('MEMORY_RETRY_SUBMISSION=' + json.dumps(receipt, sort_keys=True), flush=True)
    # Shared concurrency cap: lower the first attempt's throttle to 3 so both attempts never exceed 6 GPUs.
    t = subprocess.run(['scontrol', 'update', f'JobId={RETRY1_JOB}', 'ArrayTaskThrottle=3'], capture_output=True, text=True, check=False, timeout=45)
    throttle = {'command': t.args, 'returncode': t.returncode, 'stdout': t.stdout, 'stderr': t.stderr, 'time_utc': now()}
    write_json(ROOT / 'RETRY1_THROTTLE_UPDATE.json', throttle)
    print('RETRY1_THROTTLE_UPDATE=' + json.dumps(throttle, sort_keys=True), flush=True)
    # Read-only confirmation follows the unique submission receipt.
    q = query(['squeue', '-r', '-j', job_id, '-h', '-o', '%i|%j|%P|%T|%E|%R'])
    j = query(['scontrol', 'show', 'job', job_id, '-o'])
    r1 = query(['scontrol', 'show', 'job', RETRY1_JOB, '-o'])
    report = {'receipt': receipt, 'manifest': manifest, 'queue': q, 'scheduler_job': j, 'retry1_throttle_update': throttle, 'retry1_job_after': r1}
    write_json(ROOT / 'INITIAL_QUEUE_OBSERVATION.json', report)
    blob = json.dumps(report, sort_keys=True, separators=(',', ':')).encode()
    print('MEMORY_RETRY_GZIP_BASE64=' + base64.b64encode(gzip.compress(blob, mtime=0)).decode())


if __name__ == '__main__':
    main()

PY
