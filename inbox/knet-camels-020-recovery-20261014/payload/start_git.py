"""Restore only this experiment's two channels in an independent transport root.

Git-only transport; the pinned runner source is embedded and hash-verified.
No shared receiver/environment changes. Original seq29/deploy guard retains the
single-submission protection. Model computation remains inside its Slurm job.
"""
import os,sys,json,hashlib,base64,subprocess,datetime,time,fcntl
from pathlib import Path

ROOT=Path('/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/020_snow_training_20261014_001/transport_recovery')
CHANNELS=['knet-camels-hpc-20261012-001','knet-camels-020-recovery-20261014']
SOURCE_COMMIT='0a3e0f4342454f2f14a28bdb3279050bb1de4b40'
SOURCE_SHA='192204831dc622b457e9c80a9331ca1d9659fbe4641243681fa52d4ef3030a08'
PYTHON='/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python'
def emit(event,**data):
    payload=dict(event=event,utc=datetime.datetime.now(datetime.timezone.utc).isoformat());payload.update(data)
    print(json.dumps(payload),flush=True)
def run(args,timeout=180,cwd=None):
    reply=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,timeout=timeout,cwd=cwd)
    if reply.returncode:raise RuntimeError('Command failed: '+repr(args)+'\n'+reply.stdout+'\n'+reply.stderr)
    return reply.stdout
def verify_path(path):
    assert path.is_absolute() and '..' not in path.parts
    for p in (path,*path.parents):assert not p.is_symlink(),'linked path '+str(p)
# Original runner bytes, retrieved and hash-verified before publication.
EMBEDDED_RUNNER_BASE64='IyEvYmluL2Jhc2gKIyA9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PQojIEhQQyDkv6HnrrHlrojmiqTov5vnqIsgdjIg4oCU4oCUIOWkmuS7u+WKoeW5tuWPkeeJiAojCiMg55u45q+UIHYxIOeahOaUueWPmO+8mgojICAgMS4g5aSaIGNoYW5uZWwg6ZqU56a777yaaW5ib3gvPGNoYW5uZWw+L3tjbWQuc2gsc2VxfSAtPiBvdXRib3gvPGNoYW5uZWw+L3Jlc3VsdF88c2VxPi50eHQKIyAgICAgIOS4jeWQjOS7u+WKoS/kvJror53nlKjkuI3lkIwgY2hhbm5lbO+8jOS6kuS4jeimhuebluOAggojICAgMi4g5bm25Y+R77ya5LiN5ZCMIGNoYW5uZWwg55qE5Lu75Yqh5ZCO5Y+w5bm26KGM6LeR77yI6buY6K6k5LiK6ZmQIDE277yM5Y+v55SoIE1BWF9XT1JLRVJTIOimhueblu+8ie+8jAojICAgICAg5LiA5LiqIGNoYW5uZWwg6YeM562JIDEyIOWIhumSn+eahOS9nOS4muS4jeWGjemYu+WhnuWFtuS7liBjaGFubmVs44CCCiMgICAgICDlkIzkuIAgY2hhbm5lbCDlhoXkuKXmoLzkuLLooYzjgIIKIyAgICAgIOKaoO+4jyDlubblj5HnmoTliY3mj5DmmK8gY21kLnNoIOWPquWBmui9u+mHj+S6i++8iGdpdC9zYWNjdC9zbGVlcCDnrYnkvZzkuJrvvInjgIIKIyAgICAgICAgIOeZu+W9leiKgueCueemgeatoui3keiuoeeul++8jOecn+ato+eahOiuoeeul+S4gOW+iyBzYmF0Y2jjgIIKIyAgIDMuIOe7k+aenOWFiOWGmSBnaXQg5bel5L2c5Yy65LmL5aSW55qEIHN0YWdpbmfvvIxwdXNoIOaXtuaJjeaLt+i/m+adpQojICAgICAg4oCU4oCUIOmBv+WFjeS4u+W+queOr+eahCBgZ2l0IHJlc2V0IC0taGFyZGAg5oqK5q2j5Zyo5YaZ55qE57uT5p6c5Yay5o6J44CCCiMgICA0LiBwdXNoIOeUqOmUgeS4suihjOWMlu+8jOmBv+WFjeWkmuS4qiB3b3JrZXIg5ZCM5pe2IHB1c2gg5omT5p6244CCCiMgICA1LiDoh6rmiJHkv53miqTvvJrlkK/liqjml7bmioroh6rlt7HlpI3liLbliLAgJEhPTUUvLmhwY19ydW5uZXJfYWN0aXZlLnNoIOWGjSBleGVj77yMCiMgICAgICDov5nmoLcgYGdpdCByZXNldCAtLWhhcmRgIOimhuebluS7k+W6k+mHjOeahCBydW5uZXIyLnNoIOS4jeS8muW9seWTjei/kOihjOS4reeahOi/m+eoi+OAggojICAgNi4g5ZCR5ZCO5YW85a6577ya5pen55qEIGluYm94L2NtZC5zaCArIGluYm94L3NlcSDooqvlvZPkvZwgY2hhbm5lbCAiZGVmYXVsdCLjgIIKIwojIOWQr+WKqO+8mgojICAgKCBjZCB+L2hwY19tYWlsYm94ICYmIG5vaHVwIGJhc2ggcnVubmVyMi5zaCA+IHJ1bm5lcjIubG9nIDI+JjEgJiApCiMg5YGc5q2i77yaCiMgICBwa2lsbCAtZiAiaHBjX3J1bm5lcl9hY3RpdmUuc2giOyBwa2lsbCAtZiAiYmFzaCBydW5uZXIyLnNoIgojID09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09CiMg44CQ5LiN6KaB5YqgIHNldCAtdeOAkeS4pOS4quWOn+WboO+8mgojICAgMS4gSFBDIOaYryBDZW50T1MgNyAvIGJhc2ggNC4y44CCc2V0IC11IOS4i+WxleW8gOepuuWFs+iBlOaVsOe7hAojICAgICAg77yIJHshYXJyW0BdfSAvICR7I2FycltAXX3vvInkvJrmiqUgdW5ib3VuZCB2YXJpYWJsZSDnm7TmjqXpgIDlh7rvvIwKIyAgICAgIOiAjOS4lOS4jeWQjCBiYXNoIOeJiOacrOihjOS4uuS4jeS4gOiHtO+8iDQuNCDkv67kuobkuIDpg6jliIbvvIw1Lngg5Y+I5LiN5ZCM77yJ77yMCiMgICAgICDpnaDniYjmnKzliKTmlq3nrYnkuo7otYzljZrjgILmnKzohJrmnKzlhajnqIvnlKggJHtWQVI6LWRlZmF1bHR977yM5LiN6ZyA6KaBIC1144CCCiMgICAyLiBzZXQgLXUg6L+Y5Lya6K6pIGNvbmRhIGFjdGl2YXRlIOmdmem7mOmAgOWHuu+8iOingSBIUENfUExBWUJPT0sg6ZOB5b6LIDLvvInjgIIKc2V0IC1vIHBpcGVmYWlsCgpNQUlMQk9YX0RJUj0iJHtNQUlMQk9YX0RJUjotJEhPTUUvaHBjX21haWxib3h9IgpTVEFHSU5HPSIke1NUQUdJTkc6LSRIT01FLy5ocGNfbWFpbGJveF9zdGFnaW5nfSIKTE9DS0RJUj0iJHtMT0NLRElSOi0kSE9NRS8uaHBjX21haWxib3hfcHVzaGxvY2t9IgpBQ1RJVkVfQ09QWT0iJEhPTUUvLmhwY19ydW5uZXJfYWN0aXZlLnNoIgpCUkFOQ0g9ImhwYy1tYWlsYm94IgpQT0xMX0lOVEVSVkFMPSIke1BPTExfSU5URVJWQUw6LTIwfSIKIyDlubblj5HkuIrpmZDjgIJ3b3JrZXIg5Zyo55m75b2V6IqC54K55LiK5Yeg5LmO5Y+q5YGaIGdpdCAvIHNhY2N0IC8gc2xlZXDvvIjnrYkgc2JhdGNo77yJ77yMCiMg5LiN5ZCDIENQVe+8jOaJgOS7peWPr+S7peW8gOWkp+OAguecn+ato+eahOS4suihjOeCueaYryBwdXNoIOmUge+8jOavj+asoSBwdXNoIOWPquWNoOWHoOenkuOAggojIOmcgOimgeabtOWkmuWwseWQr+WKqOaXtuimhueblu+8mk1BWF9XT1JLRVJTPTMyIGJhc2ggcnVubmVyMi5zaApNQVhfV09SS0VSUz0iJHtNQVhfV09SS0VSUzotMTZ9IgpXT1JLRVJfVElNRU9VVD0iJHtXT1JLRVJfVElNRU9VVDotNzIwMH0iICAgIyDljZXkuKrku7vliqHmnIDplb8gMiDlsI/ml7bvvIzpmLLljaHmrbsKIyDjgJDlv4XpobvjgJHmiYDmnIkgZ2l0IOe9kee7nOaTjeS9nOmDveimgeaciei2heaXtuOAgjIwMjYtMDgtMTgg5pWZ6K6t77ya5LuT5bqT5paH5Lu25aSa5Yiw6Kem5Y+RIGdpdCBhdXRvLWdj77yMCiMg6ICBIGdpdCgxLjguMy4xKSArIOW5tuihjOWtmOWCqOS4iuaJk+WMheaegeaFou+8jOaXoOi2heaXtueahCBmZXRjaCDkvJrmsLjkuYXljaHmrbvkuLvlvqrnjq/vvIwKIyDooajnjrDkuLoi6L+b56iL5rS7552A44CB5pel5b+X5LiN6ZW/44CB6L+c56uv5LiN5YqoIu+8jOaegemavuaOkuafpeOAggpHSVRfVElNRU9VVD0iJHtHSVRfVElNRU9VVDotMTIwfSIKCiMgLS0tLSDoh6rmiJHkv53miqTvvJrku44gZ2l0IOW3peS9nOWMuuWklueahOWJr+acrOi/kOihjCAtLS0tCmlmIFsgIiR7SFBDX1JVTk5FUl9ERVRBQ0hFRDotMH0iICE9ICIxIiBdOyB0aGVuCiAgICBjcCAtZiAiJE1BSUxCT1hfRElSL3J1bm5lcjIuc2giICIkQUNUSVZFX0NPUFkiIDI+L2Rldi9udWxsIHx8IFwKICAgIGNwIC1mICIkMCIgIiRBQ1RJVkVfQ09QWSIgMj4vZGV2L251bGwKICAgIGV4cG9ydCBIUENfUlVOTkVSX0RFVEFDSEVEPTEKICAgIGV4ZWMgYmFzaCAiJEFDVElWRV9DT1BZIgpmaQoKY2QgIiRNQUlMQk9YX0RJUiIgfHwgeyBlY2hvICJbRkFUQUxdIGNhbm5vdCBjZCAkTUFJTEJPWF9ESVIiOyBleGl0IDE7IH0KbWtkaXIgLXAgIiRTVEFHSU5HIgoKIyDlhbPmjokgZ2l0IOiHquWKqOaJk+WMhe+8muS7k+W6k+mHjOe7k+aenOaWh+S7tuWkmu+8jGF1dG8tZ2Mg5Zyo5bm26KGM5a2Y5YKo5LiK5Lya5Y2h5q27IGZldGNo77yI6KeBIEdJVF9USU1FT1VUIOazqOmHiu+8iQpnaXQgY29uZmlnIGdjLmF1dG8gMCAyPi9kZXYvbnVsbApnaXQgY29uZmlnIGdjLmF1dG9EZXRhY2ggZmFsc2UgMj4vZGV2L251bGwKCmVjaG8gIj09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PSIKZWNobyAiWyQoZGF0ZSldIG1haWxib3ggcnVubmVyIHYyIHN0YXJ0ZWQiCmVjaG8gIltJTkZPXSBkaXI9JE1BSUxCT1hfRElSIHN0YWdpbmc9JFNUQUdJTkciCmVjaG8gIltJTkZPXSBob3N0PSQoaG9zdG5hbWUpIHBpZD0kJCB3b3JrZXJzPD0kTUFYX1dPUktFUlMgaW50ZXJ2YWw9JHtQT0xMX0lOVEVSVkFMfXMiCmVjaG8gIltJTkZPXSBydW5uaW5nIGZyb20gZGV0YWNoZWQgY29weTogJEFDVElWRV9DT1BZIgplY2hvICI9PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT0iCgojIC0tLS0gcHVzaCDplIHvvIhta2RpciDmmK/ljp/lrZDmk43kvZzvvIktLS0tCmFjcXVpcmVfbG9jayAoKSB7CiAgICBsb2NhbCB0cmllcz0wCiAgICB3aGlsZSAhIG1rZGlyICIkTE9DS0RJUiIgMj4vZGV2L251bGw7IGRvCiAgICAgICAgdHJpZXM9JCgodHJpZXMrMSkpCiAgICAgICAgIyDplIHotoXov4cgNSDliIbpkp/op4bkuLrpmYjml6fvvIzlvLrooYzmjqXnrqEKICAgICAgICBpZiBbIC1kICIkTE9DS0RJUiIgXSAmJiBbICIkdHJpZXMiIC1ndCAxNTAgXTsgdGhlbgogICAgICAgICAgICBlY2hvICJbV0FSTl0gc3RhbGUgcHVzaCBsb2NrLCB0YWtpbmcgb3ZlciIKICAgICAgICAgICAgcm0gLXJmICIkTE9DS0RJUiI7IGNvbnRpbnVlCiAgICAgICAgZmkKICAgICAgICBzbGVlcCAyCiAgICBkb25lCn0KcmVsZWFzZV9sb2NrICgpIHsgcm0gLXJmICIkTE9DS0RJUiI7IH0KCiMgLS0tLSB3b3JrZXLvvJrmiafooYzmn5DkuKogY2hhbm5lbCDnmoTkuIDmnaHlkb3ku6QgLS0tLQpydW5fY2hhbm5lbCAoKSB7CiAgICBsb2NhbCBDSD0iJDEiIFNFUT0iJDIiIENNRF9TUkM9IiQzIgogICAgbG9jYWwgV0RJUj0iJFNUQUdJTkcvJENIIgogICAgbWtkaXIgLXAgIiRXRElSIgoKICAgICMg5oqK5ZG95Luk5ou35Ye6IGdpdCDlt6XkvZzljLrlho3miafooYzvvIzpgb/lhY3kuLvlvqrnjq8gcmVzZXQg5pe25oqK5a6D5o2i5o6JCiAgICBjcCAtZiAiJENNRF9TUkMiICIkV0RJUi9jbWRfJHtTRVF9LnNoIiAyPi9kZXYvbnVsbCB8fCByZXR1cm4KICAgIGxvY2FsIE9VVD0iJFdESVIvcmVzdWx0XyR7U0VRfS50eHQiCgogICAgewogICAgICAgIGVjaG8gIiMjIyBjaGFubmVsPSRDSCBzZXE9JFNFUSIKICAgICAgICBlY2hvICIjIyMgaG9zdD0kKGhvc3RuYW1lKSIKICAgICAgICBlY2hvICIjIyMgc3RhcnRlZD0kKGRhdGUgLUlzZWNvbmRzKSIKICAgICAgICBlY2hvICIjIyMgLS0tLS0tLS0tLSBvdXRwdXQgLS0tLS0tLS0tLSIKICAgIH0gPiAiJE9VVCIKCiAgICB0aW1lb3V0ICIkV09SS0VSX1RJTUVPVVQiIGJhc2ggIiRXRElSL2NtZF8ke1NFUX0uc2giID4+ICIkT1VUIiAyPiYxCiAgICBsb2NhbCBSQz0kPwogICAgWyAkUkMgLWVxIDEyNCBdICYmIGVjaG8gIiMjIyBUSU1FT1VUIGFmdGVyICR7V09SS0VSX1RJTUVPVVR9cyIgPj4gIiRPVVQiCgogICAgewogICAgICAgIGVjaG8gIiMjIyAtLS0tLS0tLS0tIGVuZCAtLS0tLS0tLS0tIgogICAgICAgIGVjaG8gIiMjIyBleGl0X2NvZGU9JFJDIgogICAgICAgIGVjaG8gIiMjIyBmaW5pc2hlZD0kKGRhdGUgLUlzZWNvbmRzKSIKICAgIH0gPj4gIiRPVVQiCgogICAgcHVzaF9yZXN1bHQgIiRDSCIgIiRTRVEiCiAgICBybSAtZiAiJFdESVIvY21kXyR7U0VRfS5zaCIKICAgIGVjaG8gIlskKGRhdGUpXSBkb25lIGNoYW5uZWw9JENIIHNlcT0kU0VRIHJjPSRSQyIKfQoKIyAtLS0tIOWPqui0n+i0o+aKiiBzdGFnaW5nIOmHjOW3suacieeahOe7k+aenOaOqOS4iuWOu++8iOWPr+WPjeWkjemHjeivle+8jOS4jemHjei3keWRveS7pO+8iS0tLS0KcHVzaF9yZXN1bHQgKCkgewogICAgbG9jYWwgQ0g9IiQxIiBTRVE9IiQyIgogICAgbG9jYWwgT1VUPSIkU1RBR0lORy8kQ0gvcmVzdWx0XyR7U0VRfS50eHQiCiAgICBbIC1mICIkT1VUIiBdIHx8IHJldHVybgogICAgYWNxdWlyZV9sb2NrCiAgICBjZCAiJE1BSUxCT1hfRElSIgogICAgdGltZW91dCAkR0lUX1RJTUVPVVQgZ2l0IGZldGNoIC1xIG9yaWdpbiAiKyR7QlJBTkNIfTpyZWZzL3JlbW90ZXMvb3JpZ2luLyR7QlJBTkNIfSIgMj4vZGV2L251bGwKICAgIHRpbWVvdXQgNjAgZ2l0IHJlc2V0IC1xIC0taGFyZCAicmVmcy9yZW1vdGVzL29yaWdpbi8ke0JSQU5DSH0iIDI+L2Rldi9udWxsCiAgICBta2RpciAtcCAib3V0Ym94LyRDSCIKICAgIGNwIC1mICIkT1VUIiAib3V0Ym94LyRDSC9yZXN1bHRfJHtTRVF9LnR4dCIKICAgIGdpdCBhZGQgLUEgb3V0Ym94CiAgICBnaXQgY29tbWl0IC1xIC1tICJtYWlsYm94WyRDSF06IHJlc3VsdCBzZXE9JFNFUSIgMj4vZGV2L251bGwKICAgIGlmICEgdGltZW91dCAkR0lUX1RJTUVPVVQgZ2l0IHB1c2ggLXEgb3JpZ2luICIkQlJBTkNIIiAyPi9kZXYvbnVsbDsgdGhlbgogICAgICAgICMg5o6o5LiN5Yqo5pe25YWI5oqK5pWj6JC955qEIG91dGJveCDmlLnliqjmlLbov5vmnaXlho0gcmViYXNl77yI6ZiyIFNMVVJNIOaXpeW/l+i+ueWGmei+uemVv+aMoeS9jyByZWJhc2XvvIkKICAgICAgICBnaXQgYWRkIC1BIG91dGJveCAmJiBnaXQgY29tbWl0IC1xIC1tICJtYWlsYm94OiBzdHJheSBvdXRib3ggZmlsZXMiIDI+L2Rldi9udWxsCiAgICAgICAgdGltZW91dCAkR0lUX1RJTUVPVVQgZ2l0IHB1bGwgLS1yZWJhc2UgLXEgb3JpZ2luICIkQlJBTkNIIiAyPi9kZXYvbnVsbAogICAgICAgIHRpbWVvdXQgJEdJVF9USU1FT1VUIGdpdCBwdXNoIC1xIG9yaWdpbiAiJEJSQU5DSCIgMj4vZGV2L251bGwgXAogICAgICAgICAgICB8fCBlY2hvICJbRVJST1JdIHB1c2ggZmFpbGVkOiAkQ0gvJFNFUSAocmVzdWx0IGtlcHQgaW4gc3RhZ2luZywgd2lsbCByZXRyeSBwdXNoIG9ubHkpIgogICAgZmkKICAgIHJlbGVhc2VfbG9jawp9CgpkZWNsYXJlIC1BIFJVTk5JTkcgICAjIGNoYW5uZWwgLT4gcGlkCgp3aGlsZSB0cnVlOyBkbwogICAgIyDlm57mlLblt7Lnu5PmnZ/nmoQgd29ya2Vy77yI5pegIHNldCAtde+8jOepuuaVsOe7hOWxleW8gOaYr+WuieWFqOeahO+8iQogICAgZm9yIENIIGluICIkeyFSVU5OSU5HW0BdfSI7IGRvCiAgICAgICAga2lsbCAtMCAiJHtSVU5OSU5HWyRDSF19IiAyPi9kZXYvbnVsbCB8fCB1bnNldCAiUlVOTklOR1skQ0hdIgogICAgZG9uZQoKICAgICMg5Y+q5pyJ5Zyo5rKh5pyJIHdvcmtlciDlnKjot5Hml7bmiY0gcmVzZXTvvIjlkKbliJnkvJrliqjliLDliKvkurrnmoTmlofku7bvvIkKICAgIGlmIFsgJHsjUlVOTklOR1tAXX0gLWVxIDAgXTsgdGhlbgogICAgICAgIGFjcXVpcmVfbG9jawogICAgICAgIHRpbWVvdXQgJEdJVF9USU1FT1VUIGdpdCBmZXRjaCAtcSBvcmlnaW4gIiske0JSQU5DSH06cmVmcy9yZW1vdGVzL29yaWdpbi8ke0JSQU5DSH0iIDI+L2Rldi9udWxsCiAgICAgICAgdGltZW91dCA2MCBnaXQgcmVzZXQgLXEgLS1oYXJkICJyZWZzL3JlbW90ZXMvb3JpZ2luLyR7QlJBTkNIfSIgMj4vZGV2L251bGwKICAgICAgICByZWxlYXNlX2xvY2sKICAgIGVsc2UKICAgICAgICB0aW1lb3V0ICRHSVRfVElNRU9VVCBnaXQgZmV0Y2ggLXEgb3JpZ2luICIrJHtCUkFOQ0h9OnJlZnMvcmVtb3Rlcy9vcmlnaW4vJHtCUkFOQ0h9IiAyPi9kZXYvbnVsbAogICAgZmkKCiAgICAjIOaJq+aPj+aJgOaciSBjaGFubmVs77yaaW5ib3gvPGNoPi9zZXHvvIzlpJbliqDlkJHlkI7lhbzlrrnnmoQgaW5ib3gvc2VxCiAgICBDSEFOTkVMUz0iIgogICAgZm9yIGQgaW4gaW5ib3gvKi87IGRvCiAgICAgICAgWyAtZiAiJHtkfXNlcSIgXSAmJiBbIC1mICIke2R9Y21kLnNoIiBdICYmIENIQU5ORUxTPSIkQ0hBTk5FTFMgJHtkJS99IgogICAgZG9uZQogICAgWyAtZiBpbmJveC9zZXEgXSAmJiBbIC1mIGluYm94L2NtZC5zaCBdICYmIENIQU5ORUxTPSIkQ0hBTk5FTFMgaW5ib3giCgogICAgZm9yIENIRElSIGluICRDSEFOTkVMUzsgZG8KICAgICAgICBDSD0kKGJhc2VuYW1lICIkQ0hESVIiKQogICAgICAgIFsgIiRDSERJUiIgPSAiaW5ib3giIF0gJiYgQ0g9ImRlZmF1bHQiCgogICAgICAgIFNFUT0kKGNhdCAiJENIRElSL3NlcSIgMj4vZGV2L251bGwgfCB0ciAtZCAnWzpzcGFjZTpdJykKICAgICAgICBbIC16ICIkU0VRIiBdICYmIGNvbnRpbnVlCiAgICAgICAgWyAtZiAib3V0Ym94LyRDSC9yZXN1bHRfJHtTRVF9LnR4dCIgXSAmJiBjb250aW51ZSAgICAgICAgICAjIOW3sui3kei/h+S4lOW3suaOqOmAgQogICAgICAgIFsgIiRDSCIgPSAiZGVmYXVsdCIgXSAmJiBbIC1mICJvdXRib3gvcmVzdWx0XyR7U0VRfS50eHQiIF0gJiYgY29udGludWUgICMgdjEg6YGX55WZ5L2N572uCiAgICAgICAgWyAtbiAiJHtSVU5OSU5HWyRDSF06LX0iIF0gJiYgY29udGludWUgICAgICAgICAgICAgICAgICAgICAjIOivpSBjaGFubmVsIOato+WcqOi3kQogICAgICAgIFsgJHsjUlVOTklOR1tAXX0gLWdlICIkTUFYX1dPUktFUlMiIF0gJiYgY29udGludWUgICAgICAgICAgIyDlubblj5Hlt7Lmu6EKCiAgICAgICAgIyDjgJDlhbPplK7jgJFzdGFnaW5nIOmHjOW3suaciee7k+aenCA9IOWRveS7pOi3kei/h+S9hiBwdXNoIOWksei0pe+8iOWmgiBETlMg5pat77yJ44CCCiAgICAgICAgIyDlj6rph43or5XmjqjpgIHvvIznu53kuI3ph43ot5Hlkb3ku6Qg4oCU4oCUIOWQpuWImee9kee7nOaVhemanOS8muaKiiBzYmF0Y2gg5Y+N5aSN5omn6KGM44CCCiAgICAgICAgaWYgWyAtZiAiJFNUQUdJTkcvJENIL3Jlc3VsdF8ke1NFUX0udHh0IiBdOyB0aGVuCiAgICAgICAgICAgIGVjaG8gIlskKGRhdGUpXSAtLS0gcmV0cnkgcHVzaCBvbmx5OiBjaGFubmVsPSRDSCBzZXE9JFNFUSAtLS0iCiAgICAgICAgICAgIHB1c2hfcmVzdWx0ICIkQ0giICIkU0VRIiAmCiAgICAgICAgICAgIFJVTk5JTkdbJENIXT0kIQogICAgICAgICAgICBjb250aW51ZQogICAgICAgIGZpCgogICAgICAgIGVjaG8gIlskKGRhdGUpXSAtLS0gc3RhcnQgY2hhbm5lbD0kQ0ggc2VxPSRTRVEgLS0tIgogICAgICAgIHJ1bl9jaGFubmVsICIkQ0giICIkU0VRIiAiJENIRElSL2NtZC5zaCIgJgogICAgICAgIFJVTk5JTkdbJENIXT0kIQogICAgZG9uZQoKICAgIHNsZWVwICIkUE9MTF9JTlRFUlZBTCIKZG9uZQo='

def save_exact(path,value):
    verify_path(path)
    if path.exists():assert path.read_bytes()==value,'existing transport file differs: '+str(path)
    else:
        with path.open('xb') as handle:handle.write(value)
def serve():
    lock=(ROOT/'receiver.lock').open('a')
    try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    except BlockingIOError:emit('OWN_RECEIVER_ALREADY_RUNNING');return
    os.nice(10)
    record=dict(pid=os.getpid(),process_start_ticks=Path('/proc/self/stat').read_text().split()[21],
        utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),channels=CHANNELS,
        original_sequence=29,shared_runner_changed=False,shared_environment_changed=False,
        scientific_conditions_changed=False,receiver_source_sha256=SOURCE_SHA)
    (ROOT/'receiver_started.json').write_text(json.dumps(record,indent=2))
    emit('OWN_RECEIVER_STARTED',**record)
    env=dict(os.environ,MAILBOX_DIR=str(ROOT/'repo'),STAGING=str(ROOT/'staging'),
        LOCKDIR=str(ROOT/'pushlock'),HPC_RUNNER_DETACHED='1',MAX_WORKERS='2',POLL_INTERVAL='20',GIT_TIMEOUT='120')
    reply=subprocess.run(['bash',str(ROOT/'owned_receiver.sh')],cwd=ROOT/'repo',env=env)
    emit('OWN_RECEIVER_EXITED',exit_code=reply.returncode)
    raise SystemExit(reply.returncode)

if '--serve' in sys.argv:serve();raise SystemExit(0)
verify_path(ROOT);ROOT.mkdir(parents=True,exist_ok=True)
main_lock=(ROOT/'bootstrap.lock').open('a')
try:fcntl.flock(main_lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
except BlockingIOError:emit('BOOTSTRAP_ALREADY_RUNNING');raise SystemExit(0)
started=ROOT/'receiver_started.json'
if started.exists():
    previous=json.loads(started.read_text());pid=previous['pid']
    try:command=Path('/proc/'+str(pid)+'/cmdline').read_bytes()
    except FileNotFoundError:command=b''
    if any(str(ROOT/name).encode() in command for name in ['start_owned_receiver.py','start_git.py']):
        emit('OWN_RECEIVER_ALREADY_RUNNING',pid=pid);raise SystemExit(0)
original=base64.b64decode(EMBEDDED_RUNNER_BASE64,validate=True);assert hashlib.sha256(original).hexdigest()==SOURCE_SHA
source=original.decode()
before='for d in inbox/*/; do'
after='for d in '+' '.join('inbox/'+c+'/' for c in CHANNELS)+'; do'
assert source.count(before)==1
source=source.replace(before,after)
default='    [ -f inbox/seq ] && [ -f inbox/cmd.sh ] && CHANNELS="$CHANNELS inbox"'
assert source.count(default)==1;source=source.replace(default,'    # This receiver never scans the legacy default channel.')
assert source.count('git add -A outbox')==2
source=source.replace('git add -A outbox','git add "outbox/$CH/result_${SEQ}.txt"')
save_exact(ROOT/'owned_receiver.sh',source.encode())
save_exact(ROOT/'original_receiver_source.sh',original)
save_exact(ROOT/'start_git.py',Path(__file__).read_bytes())
repo=ROOT/'repo'
if not (repo/'.git').is_dir():
    emit('ISOLATED_REPOSITORY_PREPARATION')
    bootstrap_repo=Path(__file__).resolve().parent
    assert (bootstrap_repo/'.git').is_dir(),'Launch the downloaded file from its isolated Git repository.'
    run(['git','clone','--shared','--no-checkout',str(bootstrap_repo),str(repo)],timeout=120)
run(['git','config','remote.origin.url','git@github.com:yiqun-sun-rookie/neuralhydrology.git'],cwd=repo)
for name in ['gc.auto','gc.autoDetach']:
    run(['git','config',name,'0' if name=='gc.auto' else 'false'],cwd=repo)
for name,fallback in [('user.name','sunyiq'),('user.email','yiqun.sun.hydro.gee@gmail.com')]:
    p=subprocess.run(['git','config','--get',name],cwd=Path.home()/'hpc_mailbox',capture_output=True,text=True)
    run(['git','config',name,p.stdout.strip() or fallback],cwd=repo)
run(['git','config','core.sparseCheckout','true'],cwd=repo)
sparse='\n'.join(['/.gitattributes',*['/inbox/'+c+'/' for c in CHANNELS],*['/outbox/'+c+'/' for c in CHANNELS]])+'\n'
(repo/'.git/info/sparse-checkout').write_text(sparse)
emit('FETCH_LATEST_MAILBOX_METADATA')
run(['git','fetch','--depth=1','-q','origin','+hpc-mailbox:refs/remotes/origin/hpc-mailbox'],timeout=300,cwd=repo)
run(['git','checkout','-B','hpc-mailbox','refs/remotes/origin/hpc-mailbox'],timeout=120,cwd=repo)
seq=(repo/'inbox'/CHANNELS[0]/'seq').read_text().strip()
assert seq=='29','Primary sequence changed; inspect before activation.'
cmd=(repo/'inbox'/CHANNELS[0]/'cmd.sh').read_bytes()
assert hashlib.sha256(cmd).hexdigest()=='5b5a66727a106f6fa07541f93f157c7b46b715aff228a5e97b41941524d9ea63'
save_exact(ROOT/'activation_review.json',(json.dumps(dict(status='PASS',channels=CHANNELS,
    original_seq29_command_exact=True,new_scientific_submissions_issued_by_bootstrap=0,
    independent_repository=True,independent_staging=True,independent_pushlock=True,
    no_shared_receiver_restart=True,science_files_unchanged=True),indent=2)+'\n').encode())
emit('ACTIVATION_REVIEW_PASS')
with (ROOT/'receiver.log').open('ab') as log:
    child=subprocess.Popen([PYTHON,'-u','-B',str(ROOT/'start_git.py'),'--serve'],
        stdout=log,stderr=subprocess.STDOUT,stdin=subprocess.DEVNULL,start_new_session=True)
emit('OWN_RECEIVER_LAUNCHED',pid=child.pid,log=str(ROOT/'receiver.log'))
for i in range(20):
    if child.poll() is not None:raise RuntimeError('Owned receiver exited; inspect '+str(ROOT/'receiver.log'))
    time.sleep(1)
print((ROOT/'receiver.log').read_text(errors='replace')[-7000:])
emit('BOOTSTRAP_COMPLETE',original_training_submission='Only the existing pending seq29 is eligible; no new seq or duplicate job.')
