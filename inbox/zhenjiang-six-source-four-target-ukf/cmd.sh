#!/usr/bin/env bash
set -eo pipefail
CUDA_VISIBLE_DEVICES='' OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'A40_CPU_AUDIT'
import base64,json
namespace={'__name__':'saved_checkpoint_CPU_audit'}
exec(compile(base64.b64decode('IiIiSW5zcGVjdCBvbmUgaW1tdXRhYmxlIGZhaWxlZC1tZW1iZXIgZXBvY2ggYm91bmRhcnkgb24gQ1BVLCB3aXRob3V0IHJlcGxheS4iIiIKaW1wb3J0IGhhc2hsaWIKaW1wb3J0IGlvCmltcG9ydCBqc29uCmltcG9ydCBtYXRoCmltcG9ydCBvcwpmcm9tIHBhdGhsaWIgaW1wb3J0IFBhdGgKaW1wb3J0IHN0YXQKZnJvbSBkYXRldGltZSBpbXBvcnQgZGF0ZXRpbWUsIHRpbWV6b25lCgpNQVJLRVIgPSAiR1JVX0E0MF9TQVZFRF9NRU1CRVJfQ1BVX0FVRElUX0pTT04iCgoKZGVmIHJlYWRfZXhhY3QocGF0aCwgZGlnZXN0LCBzaXplPU5vbmUpOgogICAgcGF0aCA9IFBhdGgocGF0aCkKICAgIGJlZm9yZSA9IHBhdGgubHN0YXQoKQogICAgYXNzZXJ0IHBhdGguaXNfYWJzb2x1dGUoKSBhbmQgcGF0aC5yZXNvbHZlKCkgPT0gcGF0aCBhbmQgc3RhdC5TX0lTUkVHKGJlZm9yZS5zdF9tb2RlKQogICAgaWYgc2l6ZSBpcyBub3QgTm9uZToKICAgICAgICBhc3NlcnQgYmVmb3JlLnN0X3NpemUgPT0gc2l6ZQogICAgcmF3ID0gcGF0aC5yZWFkX2J5dGVzKCkKICAgIGFmdGVyID0gcGF0aC5sc3RhdCgpCiAgICBhc3NlcnQgKGJlZm9yZS5zdF9pbm8sIGJlZm9yZS5zdF9zaXplLCBiZWZvcmUuc3RfbXRpbWVfbnMsIGJlZm9yZS5zdF9jdGltZV9ucykgPT0gKGFmdGVyLnN0X2lubywgYWZ0ZXIuc3Rfc2l6ZSwgYWZ0ZXIuc3RfbXRpbWVfbnMsIGFmdGVyLnN0X2N0aW1lX25zKQogICAgYXNzZXJ0IGhhc2hsaWIuc2hhMjU2KHJhdykuaGV4ZGlnZXN0KCkgPT0gZGlnZXN0CiAgICByZXR1cm4gcmF3CgoKZGVmIG1haW4ocGxhbik6CiAgICBhc3NlcnQgb3MuZW52aXJvbi5nZXQoIkNVREFfVklTSUJMRV9ERVZJQ0VTIikgPT0gIiIKICAgIGltcG9ydCB0b3JjaAogICAgdG9yY2guc2V0X251bV90aHJlYWRzKDEpCiAgICBhc3NlcnQgbm90IHRvcmNoLmN1ZGEuaXNfaW5pdGlhbGl6ZWQoKQogICAgZGlyZWN0b3J5ID0gUGF0aChwbGFuWyJldmlkZW5jZV9kaXIiXSkKICAgIG1hbmlmZXN0ID0ganNvbi5sb2FkcyhyZWFkX2V4YWN0KGRpcmVjdG9yeSAvICJFVklERU5DRV9NQU5JRkVTVC5qc29uIiwgcGxhblsibWFuaWZlc3Rfc2hhMjU2Il0pKQogICAgYXNzZXJ0IG1hbmlmZXN0WyJzY2hlbWEiXSA9PSAiMDAzLUE0MC1mYWlsdXJlLXByZXNlcnZhdGlvbi12MSIKICAgIGJsb2JzID0ge30KICAgIGZvciBsYWJlbCwgZXhwZWN0ZWQgaW4gcGxhblsiYXJ0aWZhY3RzIl0uaXRlbXMoKToKICAgICAgICBpdGVtID0gbWFuaWZlc3RbImZpbGVzIl1bZXhwZWN0ZWRbIm1hbmlmZXN0X2tleSJdXQogICAgICAgIGFzc2VydCBpdGVtID09IGV4cGVjdGVkWyJtYW5pZmVzdF9lbnRyeSJdCiAgICAgICAgcGF0aCA9IFBhdGgoaXRlbS5nZXQoInJldXNlZF9mcm9tIiwgc3RyKGRpcmVjdG9yeSAvIGV4cGVjdGVkWyJtYW5pZmVzdF9rZXkiXSkpKQogICAgICAgIGlmICJyZXVzZWRfZnJvbSIgaW4gaXRlbToKICAgICAgICAgICAgYXNzZXJ0IGl0ZW1bInByaW9yX21hbmlmZXN0X3NoYTI1NiJdID09IG1hbmlmZXN0WyJwcmlvcl9ldmlkZW5jZV9tYW5pZmVzdF9zaGEyNTYiXQogICAgICAgICAgICBhc3NlcnQgUGF0aChtYW5pZmVzdFsicHJpb3JfZXZpZGVuY2VfZGlyIl0pIGluIHBhdGgucGFyZW50cwogICAgICAgIGVsc2U6CiAgICAgICAgICAgIGFzc2VydCBkaXJlY3RvcnkgaW4gcGF0aC5wYXJlbnRzCiAgICAgICAgYmxvYnNbbGFiZWxdID0gcmVhZF9leGFjdChwYXRoLCBpdGVtWyJzaGEyNTYiXSwgaXRlbVsic2l6ZSJdKQogICAgYXNzZXJ0IHNldChibG9icykgPT0geyJjaGVja3BvaW50IiwgImNvbmZpZyIsICJjb250aW51YXRpb25fdXRpbGl0eSJ9CiAgICBuYW1lc3BhY2UgPSB7Il9fbmFtZV9fIjogInBpbm5lZF9jaGVja3BvaW50X2luc3BlY3Rpb25fdXRpbGl0eSJ9CiAgICBleGVjKGNvbXBpbGUoYmxvYnNbImNvbnRpbnVhdGlvbl91dGlsaXR5Il0sICJwaW5uZWRfY29udGludWF0aW9uLnB5IiwgImV4ZWMiKSwgbmFtZXNwYWNlKQogICAgc3RhdGUgPSB0b3JjaC5sb2FkKGlvLkJ5dGVzSU8oYmxvYnNbImNoZWNrcG9pbnQiXSksIG1hcF9sb2NhdGlvbj0iY3B1Iiwgd2VpZ2h0c19vbmx5PVRydWUpCiAgICBjb25maWdfc2hhID0gaGFzaGxpYi5zaGEyNTYoYmxvYnNbImNvbmZpZyJdKS5oZXhkaWdlc3QoKQogICAgYXNzZXJ0IHN0YXRlWyJjb25maWdfc2hhMjU2Il0gPT0gY29uZmlnX3NoYSA9PSBwbGFuWyJjb25maWdfc2hhMjU2Il0KICAgIGFzc2VydCBsZW4oc3RhdGVbInZhbHVlcyJdKSA9PSBwbGFuWyJjb21wbGV0ZWRfZXBvY2hzIl0KICAgIHZhbGlkYXRpb24sIGVycm9yID0gTm9uZSwgTm9uZQogICAgdHJ5OgogICAgICAgIHZhbGlkYXRpb24gPSBuYW1lc3BhY2VbInZhbGlkYXRlX2NvbnRpbnVhdGlvbiJdKHN0YXRlLCBjb25maWdfc2hhLCAyMDApCiAgICBleGNlcHQgRXhjZXB0aW9uIGFzIGZhaWx1cmU6CiAgICAgICAgZXJyb3IgPSByZXByKGZhaWx1cmUpCgogICAgZGVmIHRlbnNvcl9zdW1tYXJ5KHRyZWUsIHByZWZpeD0iIik6CiAgICAgICAgcmVzdWx0ID0ge30KICAgICAgICBpZiBpc2luc3RhbmNlKHRyZWUsIGRpY3QpOgogICAgICAgICAgICBmb3Iga2V5LCB2YWx1ZSBpbiB0cmVlLml0ZW1zKCk6CiAgICAgICAgICAgICAgICByZXN1bHQudXBkYXRlKHRlbnNvcl9zdW1tYXJ5KHZhbHVlLCBwcmVmaXggKyAiLyIgKyBzdHIoa2V5KSkpCiAgICAgICAgZWxpZiBpc2luc3RhbmNlKHRyZWUsIChsaXN0LCB0dXBsZSkpOgogICAgICAgICAgICBmb3IgaSwgdmFsdWUgaW4gZW51bWVyYXRlKHRyZWUpOgogICAgICAgICAgICAgICAgcmVzdWx0LnVwZGF0ZSh0ZW5zb3Jfc3VtbWFyeSh2YWx1ZSwgcHJlZml4ICsgIi8iICsgc3RyKGkpKSkKICAgICAgICBlbGlmIGlzaW5zdGFuY2UodHJlZSwgdG9yY2guVGVuc29yKToKICAgICAgICAgICAgYXNzZXJ0IHRyZWUuZGV2aWNlLnR5cGUgPT0gImNwdSIKICAgICAgICAgICAgZmluaXRlID0gdG9yY2guaXNmaW5pdGUodHJlZSkKICAgICAgICAgICAgdmFsdWVzID0gdHJlZVtmaW5pdGVdLmRvdWJsZSgpCiAgICAgICAgICAgIHJlc3VsdFtwcmVmaXhdID0geyJkdHlwZSI6IHN0cih0cmVlLmR0eXBlKSwgInNoYXBlIjogbGlzdCh0cmVlLnNoYXBlKSwgIm51bWVsIjogdHJlZS5udW1lbCgpLAogICAgICAgICAgICAgICAgIm5vbmZpbml0ZV9jb3VudCI6IGludCgofmZpbml0ZSkuc3VtKCkpLCAiemVyb19jb3VudCI6IGludCgodHJlZSA9PSAwKS5zdW0oKSksCiAgICAgICAgICAgICAgICAibWF4X2Zpbml0ZV9hYnMiOiBmbG9hdCh2YWx1ZXMuYWJzKCkubWF4KCkpIGlmIHZhbHVlcy5udW1lbCgpIGVsc2UgTm9uZX0KICAgICAgICByZXR1cm4gcmVzdWx0CgogICAgZGVmIHNjYWxhcih2YWx1ZSk6CiAgICAgICAgdmFsdWUgPSB2YWx1ZS5pdGVtKCkgaWYgaXNpbnN0YW5jZSh2YWx1ZSwgdG9yY2guVGVuc29yKSBlbHNlIHZhbHVlCiAgICAgICAgcmV0dXJuIHZhbHVlIGlmIG5vdCBpc2luc3RhbmNlKHZhbHVlLCBmbG9hdCkgb3IgbWF0aC5pc2Zpbml0ZSh2YWx1ZSkgZWxzZSByZXByKHZhbHVlKQoKICAgIHZhbHVlcyA9IFtzY2FsYXIoeCkgZm9yIHggaW4gc3RhdGVbInZhbHVlcyJdXQogICAgc3RlcHMgPSB7c3RyKGspOiBzY2FsYXIodi5nZXQoInN0ZXAiKSkgZm9yIGssIHYgaW4gc3RhdGVbIm9wdGltaXplciJdWyJzdGF0ZSJdLml0ZW1zKCl9CiAgICBiYXRjaF9jb3VudHMgPSBbbGVuKHgpIGZvciB4IGluIHN0YXRlWyJ0cmFpbl9tZXRyaWNzIl1dCiAgICByZXBvcnQgPSB7CiAgICAgICAgInNjaGVtYSI6ICIwMDMtQTQwLXNhdmVkLW1lbWJlci1DUFUtYXVkaXQtdjEiLCAic3RhdHVzIjogInNhdmVkX2JvdW5kYXJ5X2luc3BlY3RlZF9ub19yZXBsYXkiLAogICAgICAgICJjaGVja2VkX2F0X3V0YyI6IGRhdGV0aW1lLm5vdyh0aW1lem9uZS51dGMpLmlzb2Zvcm1hdCgpLCAiam9iX2lkIjogcGxhblsiam9iX2lkIl0sCiAgICAgICAgIm1lbWJlciI6IHBsYW5bIm1lbWJlciJdLCAiY29tcGxldGVkX2Vwb2NocyI6IGxlbih2YWx1ZXMpLCAiY2hlY2twb2ludF9zaGEyNTYiOiBwbGFuWyJhcnRpZmFjdHMiXVsiY2hlY2twb2ludCJdWyJtYW5pZmVzdF9lbnRyeSJdWyJzaGEyNTYiXSwKICAgICAgICAiY29uZmlnX3NoYTI1NiI6IGNvbmZpZ19zaGEsICJtYW5pZmVzdF9zaGEyNTYiOiBwbGFuWyJtYW5pZmVzdF9zaGEyNTYiXSwKICAgICAgICAic3RhdGVfa2V5cyI6IHNvcnRlZChzdGF0ZSksICJybmdfbmFtZWRfdG9wX2xldmVsX2ZpZWxkcyI6IFtrIGZvciBrIGluIHN0YXRlIGlmICJybmciIGluIGsubG93ZXIoKSBvciAicmFuZG9tIiBpbiBrLmxvd2VyKCldLAogICAgICAgICJzdHJ1Y3R1cmFsX3ZhbGlkYXRpb24iOiB2YWxpZGF0aW9uLCAic3RydWN0dXJhbF92YWxpZGF0aW9uX2Vycm9yIjogZXJyb3IsCiAgICAgICAgImN1cnJlbnRfdGVuc29ycyI6IHRlbnNvcl9zdW1tYXJ5KHN0YXRlWyJjdXJyZW50Il0pLCAiYmVzdF90ZW5zb3JzIjogdGVuc29yX3N1bW1hcnkoc3RhdGVbImJlc3QiXSksCiAgICAgICAgIm9wdGltaXplcl90ZW5zb3JzIjogdGVuc29yX3N1bW1hcnkoc3RhdGVbIm9wdGltaXplciJdWyJzdGF0ZSJdKSwgIkFkYW1fc3RlcHMiOiBzdGVwcywKICAgICAgICAiYmF0Y2hfY291bnRzX2J5X2NvbXBsZXRlX2Vwb2NoIjogYmF0Y2hfY291bnRzLCAidmFsaWRhdGlvbl92YWx1ZXNfYnlfY29tcGxldGVfZXBvY2giOiB2YWx1ZXMsCiAgICAgICAgImNvbXBsZXRlX2hpc3RvcnlfbGVuZ3RocyI6IHtrOiBsZW4oc3RhdGVba10pIGZvciBrIGluICgidmFsdWVzIiwgInRyYWluX21ldHJpY3MiLCAic2h1ZmZsZV9oYXNoZXMiKX0sCiAgICAgICAgIm9wdGltaXplcl9wYXJhbWV0ZXJfZ3JvdXBzIjogc3RhdGVbIm9wdGltaXplciJdWyJwYXJhbV9ncm91cHMiXSwKICAgICAgICAiY3VycmVudF9zdGF0ZV9maWVsZHMiOiBzb3J0ZWQoc3RhdGVbImN1cnJlbnQiXSksICJiZXN0X3N0YXRlX2ZpZWxkcyI6IHNvcnRlZChzdGF0ZVsiYmVzdCJdKSwKICAgICAgICAiY3VkYV9pbml0aWFsaXplZCI6IHRvcmNoLmN1ZGEuaXNfaW5pdGlhbGl6ZWQoKSwgImFsbF9sb2FkZWRfdGVuc29yc19vbl9jcHUiOiBUcnVlLAogICAgICAgICJ0ZW5zb3JfZmlsZXNfbG9hZGVkIjogMSwgImZvcndhcmRfY2FsbHMiOiAwLCAiYmFja3dhcmRfY2FsbHMiOiAwLCAib3B0aW1pemVyX3N0ZXBzX2V4ZWN1dGVkIjogMCwKICAgICAgICAicm5nX3N0YXRlX2luamVjdGVkIjogRmFsc2UsICJzY2hlZHVsZXJfbXV0YXRpb25zIjogMCwgInJlbW90ZV9maWxlc193cml0dGVuIjogMCwKICAgICAgICAiZXhhY3RfZmFpbGluZ19iYXRjaF9yZXByb2R1Y2VkIjogRmFsc2UsICJjYW5vbmljYWxfY29udGludWF0aW9uX2F1dGhvcml6ZWQiOiBGYWxzZSwKICAgIH0KICAgIGFzc2VydCByZXBvcnRbImN1ZGFfaW5pdGlhbGl6ZWQiXSBpcyBGYWxzZQogICAgcHJpbnQoTUFSS0VSICsgIiAiICsganNvbi5kdW1wcyhyZXBvcnQsIHNvcnRfa2V5cz1UcnVlLCBhbGxvd19uYW49RmFsc2UpLCBmbHVzaD1UcnVlKQo='),'inspect_saved_checkpoint.py','exec'),namespace)
namespace['main'](json.loads(base64.b64decode('ewogICJhcnRpZmFjdHMiOiB7CiAgICAiY2hlY2twb2ludCI6IHsKICAgICAgIm1hbmlmZXN0X2VudHJ5IjogewogICAgICAgICJzaGEyNTYiOiAiM2JiYWFjMDcxODc3MDM4ZDRhN2JiNjllNTY5YjYwODZmMmFmYWVlZWE4MGZhMjgxZGUyNzU0ODU1YWY3YWZmOSIsCiAgICAgICAgInNpemUiOiA5MTY1MjM4MywKICAgICAgICAic291cmNlIjogIi9kYXRhMS9ob21lL3N1bnlpcS96aGVuamlhbmdfY29tcGxldGVfY29tcGFyaXNvbl9maXhlZDIwMF8yMDI2MTAxOV8wMDMvc3FydF9ncnVfcmVjb3ZlcnkvcnVucy9leHBsaWNpdF9ncnVfX2hpc3RvcmljYWxfY2FwYWNpdHlfX3R1bmVfYnJhbmNoX19maWx0ZXJfam9pbnRfX3MxMDFfX2xyMHAwMDMvY29udGludWF0aW9uLnB0IgogICAgICB9LAogICAgICAibWFuaWZlc3Rfa2V5IjogInNvdXJjZS9ydW5zL2V4cGxpY2l0X2dydV9faGlzdG9yaWNhbF9jYXBhY2l0eV9fdHVuZV9icmFuY2hfX2ZpbHRlcl9qb2ludF9fczEwMV9fbHIwcDAwMy9jb250aW51YXRpb24ucHQiCiAgICB9LAogICAgImNvbmZpZyI6IHsKICAgICAgIm1hbmlmZXN0X2VudHJ5IjogewogICAgICAgICJwcmlvcl9tYW5pZmVzdF9zaGEyNTYiOiAiY2RmNWFjYWJjMWU4ZmY3NmMwOTVjYzU2YTRhNjQ1NGM2N2Q1NzA2MWUyODQ3YjM4ZDAzODBiYTY5Y2VkMWU1YiIsCiAgICAgICAgInJldXNlZF9mcm9tIjogIi9kYXRhMS9ob21lL3N1bnlpcS96aGVuamlhbmdfY29tcGxldGVfY29tcGFyaXNvbl9maXhlZDIwMF8yMDI2MTAxOV8wMDMvc3FydF9ncnVfcmVjb3ZlcnkvcmVjb3Jkcy9leHBsaWNpdF9ncnVfX2hpc3RvcmljYWxfY2FwYWNpdHkvcmVwYWlycy9BNDBfYWZ0ZXJfMjU3Mjg0X3ByZXNlcnZhdGlvbl85NTlfMDAxL3NvdXJjZS9ydW5zL2V4cGxpY2l0X2dydV9faGlzdG9yaWNhbF9jYXBhY2l0eV9fdHVuZV9icmFuY2hfX2ZpbHRlcl9qb2ludF9fczEwMV9fbHIwcDAwMy9jb25maWcuanNvbiIsCiAgICAgICAgInNoYTI1NiI6ICI3MzVkNDRlOGNkMWY3NzVjZDJhYWExZDhjMWI0YWVlZjYyZDI0OTg4MDdmNzYyOTczMGNhOWMyOGJhMWFkNDk2IiwKICAgICAgICAic2l6ZSI6IDE0MDEyLAogICAgICAgICJzb3VyY2UiOiAiL2RhdGExL2hvbWUvc3VueWlxL3poZW5qaWFuZ19jb21wbGV0ZV9jb21wYXJpc29uX2ZpeGVkMjAwXzIwMjYxMDE5XzAwMy9zcXJ0X2dydV9yZWNvdmVyeS9ydW5zL2V4cGxpY2l0X2dydV9faGlzdG9yaWNhbF9jYXBhY2l0eV9fdHVuZV9icmFuY2hfX2ZpbHRlcl9qb2ludF9fczEwMV9fbHIwcDAwMy9jb25maWcuanNvbiIKICAgICAgfSwKICAgICAgIm1hbmlmZXN0X2tleSI6ICJzb3VyY2UvcnVucy9leHBsaWNpdF9ncnVfX2hpc3RvcmljYWxfY2FwYWNpdHlfX3R1bmVfYnJhbmNoX19maWx0ZXJfam9pbnRfX3MxMDFfX2xyMHAwMDMvY29uZmlnLmpzb24iCiAgICB9LAogICAgImNvbnRpbnVhdGlvbl91dGlsaXR5IjogewogICAgICAibWFuaWZlc3RfZW50cnkiOiB7CiAgICAgICAgInByaW9yX21hbmlmZXN0X3NoYTI1NiI6ICJjZGY1YWNhYmMxZThmZjc2YzA5NWNjNTZhNGE2NDU0YzY3ZDU3MDYxZTI4NDdiMzhkMDM4MGJhNjljZWQxZTViIiwKICAgICAgICAicmV1c2VkX2Zyb20iOiAiL2RhdGExL2hvbWUvc3VueWlxL3poZW5qaWFuZ19jb21wbGV0ZV9jb21wYXJpc29uX2ZpeGVkMjAwXzIwMjYxMDE5XzAwMy9zcXJ0X2dydV9yZWNvdmVyeS9yZWNvcmRzL2V4cGxpY2l0X2dydV9faGlzdG9yaWNhbF9jYXBhY2l0eS9yZXBhaXJzL0E0MF9hZnRlcl8yNTcyODRfcHJlc2VydmF0aW9uXzk1OV8wMDEvc291cmNlL3NyYy9jb250aW51YXRpb24ucHkiLAogICAgICAgICJzaGEyNTYiOiAiMjIyMjE1NDc5MjE5YjZmNWVkOTJhMmNkYTk3MmI4ZWFjOTkyYWFhYzUyYzA4ZjQ4NWVjOGE5NDNlODBhODcwMyIsCiAgICAgICAgInNpemUiOiAyNjE2NywKICAgICAgICAic291cmNlIjogIi9kYXRhMS9ob21lL3N1bnlpcS96aGVuamlhbmdfY29tcGxldGVfY29tcGFyaXNvbl9maXhlZDIwMF8yMDI2MTAxOV8wMDMvc3FydF9ncnVfcmVjb3Zlcnkvc3JjL2NvbnRpbnVhdGlvbi5weSIKICAgICAgfSwKICAgICAgIm1hbmlmZXN0X2tleSI6ICJzb3VyY2Uvc3JjL2NvbnRpbnVhdGlvbi5weSIKICAgIH0KICB9LAogICJjb21wbGV0ZV9sb2dfa2V5IjogImV4cGxpY2l0X2dydV9faGlzdG9yaWNhbF9jYXBhY2l0eS9BNDBfZmFpbHVyZV9zYXZlZF9sb2dfYWZ0ZXJfOTc3IiwKICAiY29tcGxldGVfbG9nX3Byb29mIjogIkc6XFxnaXRodWJcXHB5Y2hhcm1cXHByb2plY3RzXFx6aGVuamlhbmdfY29tcGxldGVfY29tcGFyaXNvbl8yMDI2MTAwNl8wMDJcXHJlc3VsdHNcXGZpeGVkMjAwXzAwM19hY3RpdmF0aW9uXzIwMjYxMDIwXzAwMVxccHJvamVjdGlvbl9yZXBhaXJfMjAyNjExMDVfMDAxXFxwYXJhbGxlbF9jb250aW51YXRpb25fMjAyNjExMDZfMDAxXFxBNDBfZmFpbHVyZV9zYXZlZF9sb2dfOTc3XzAwMVxcTE9DQUxfOTc4XFxWRVJJRklFRC5qc29uIiwKICAiY29tcGxldGVfbG9nX3Byb29mX3NoYTI1NiI6ICIxNTgzMzRkYjJjOTM3MzMwYzJhYTUwMGMwMjlmNzM4YjZiZmQyMzhlNTFhMDE4ZWI4ZGIxNGZiN2E3YTg4MmRmIiwKICAiY29tcGxldGVkX2Vwb2NocyI6IDE2NSwKICAiY29uZmlnX3NoYTI1NiI6ICI3MzVkNDRlOGNkMWY3NzVjZDJhYWExZDhjMWI0YWVlZjYyZDI0OTg4MDdmNzYyOTczMGNhOWMyOGJhMWFkNDk2IiwKICAiZXZpZGVuY2VfZGlyIjogIi9kYXRhMS9ob21lL3N1bnlpcS96aGVuamlhbmdfY29tcGxldGVfY29tcGFyaXNvbl9maXhlZDIwMF8yMDI2MTAxOV8wMDMvc3FydF9ncnVfcmVjb3ZlcnkvcmVjb3Jkcy9leHBsaWNpdF9ncnVfX2hpc3RvcmljYWxfY2FwYWNpdHkvcmVwYWlycy9BNDBfYWZ0ZXJfMjU4MTY2X2ZhaWx1cmVfcHJlc2VydmF0aW9uXzk3Nl8wMDEiLAogICJmYWlsZWRfb3duZXJfa2V5IjogImV4cGxpY2l0X2dydV9faGlzdG9yaWNhbF9jYXBhY2l0eS9BNDBfcmVzdW1lX2FmdGVyXzI1NzI4NCIsCiAgImpvYl9pZCI6ICIyNTgxNjYiLAogICJtYW5pZmVzdF9zaGEyNTYiOiAiZWY1MDczYzQ0NmUwOTU0OTE1MzE5MmQ4MmM3NjcyMTM3MWEzMDlkYWJjMTJkZjYwMGZmNzAwMGZmZGFkZmUzZSIsCiAgIm1lbWJlciI6ICJleHBsaWNpdF9ncnVfX2hpc3RvcmljYWxfY2FwYWNpdHlfX3R1bmVfYnJhbmNoX19maWx0ZXJfam9pbnRfX3MxMDFfX2xyMHAwMDMiLAogICJwcmVzZXJ2YXRpb25fa2V5IjogImV4cGxpY2l0X2dydV9faGlzdG9yaWNhbF9jYXBhY2l0eS9BNDBfYWZ0ZXJfMjU4MTY2X2ZhaWx1cmVfOTc2IiwKICAicHJlc2VydmF0aW9uX3Byb29mIjogIkc6XFxnaXRodWJcXHB5Y2hhcm1cXHByb2plY3RzXFx6aGVuamlhbmdfY29tcGxldGVfY29tcGFyaXNvbl8yMDI2MTAwNl8wMDJcXHJlc3VsdHNcXGZpeGVkMjAwXzAwM19hY3RpdmF0aW9uXzIwMjYxMDIwXzAwMVxccHJvamVjdGlvbl9yZXBhaXJfMjAyNjExMDVfMDAxXFxwYXJhbGxlbF9jb250aW51YXRpb25fMjAyNjExMDZfMDAxXFxBNDBfYWZ0ZXJfMjU4MTY2X2ZhaWx1cmVfOTc2XzAwMVxcRkFJTFVSRV9GVUxMX1NUQVRFU19QUkVTRVJWRUQuanNvbiIsCiAgInByZXNlcnZhdGlvbl9wcm9vZl9zaGEyNTYiOiAiY2M3ZWVhNjg2ZmQ2ZWUxZmIzNmEzOTcxZDljMDYyNDhjODFhODIwOGE2NDhlMGNmNmZkNmIwM2FjMTY4ZDNhYiIsCiAgInB1cnBvc2UiOiAiSW5zcGVjdCBvbmx5IHRoZSBmYWlsZWQgbWVtYmVyIHNhdmVkIGVwb2NoMTY1IG1vZGVsL2Jlc3QvQWRhbSBhbmQgaGlzdG9yeSB0byBhc3Nlc3Mgc3RydWN0dXJhbCBjb25zaXN0ZW5jeSwgZXh0cmVtZSB2YWx1ZXMgYW5kIFJORyBmaWVsZHM7IG5vIHJlcGxheSwgcmVwYWlyIG9yIGNvbnRpbnVhdGlvbi4iLAogICJweXRob24iOiAiL2RhdGExL2hvbWUvc3VueWlxL21pbmljb25kYTMvZW52cy9uaF9maW5hbC9iaW4vcHl0aG9uIiwKICAicHl0aG9uX2Vudmlyb25tZW50X2Jhc2lzIjogIkc6XFxnaXRodWJcXHB5Y2hhcm1cXHByb2plY3RzXFx6aGVuamlhbmdfY29tcGxldGVfY29tcGFyaXNvbl8yMDI2MTAwNl8wMDJcXHJlc3VsdHNcXGZpeGVkMjAwXzAwM19hY3RpdmF0aW9uXzIwMjYxMDIwXzAwMVxccHJvamVjdGlvbl9yZXBhaXJfMjAyNjExMDVfMDAxXFxwYXJhbGxlbF9jb250aW51YXRpb25fMjAyNjExMDZfMDAxXFxBNDBfYWZ0ZXJfMjU3Mjg0XFxyZXN1bWVfMDAxXFxydW4uc2x1cm0iLAogICJzY2hlbWEiOiAiMDAzLUE0MC1zYXZlZC1tZW1iZXItQ1BVLWF1ZGl0LXBsYW4tdjEiCn0K')))
A40_CPU_AUDIT
#!/usr/bin/env bash
set -eo pipefail
python3 - <<'READ_FIXED200_003'
"""Read fixed-200 allocation and committed-epoch evidence without loading tensors.

Example on HPC: python -B read_status.py
Reads the two activated cases, checkpoint heads/events and small record files.
Prints a status snapshot only; no scheduler submission or source writes.
"""
import datetime
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path('/data1/home/sunyiq/zhenjiang_complete_comparison_fixed200_20261019_003')
SLURM = Path('/usr/local/globle/softs/slurm/19.05.4.1/bin')
CASES = {'legacy_lstm__historical_capacity': 'base',
         'explicit_gru__historical_capacity': 'sqrt_gru_recovery'}


def read(path):
    return json.loads(path.read_bytes())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def query(command):
    result = subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=45)
    return {'command': list(map(str, command)), 'returncode': result.returncode,
            'stdout': result.stdout, 'stderr': result.stderr}


def final_stage_metadata(runtime, record, case, row):
    """Read bounded final-stage records and committed heads; never load tensors."""
    result = {'group_outcomes': {}, 'physical_members': {}, 'aliases': {},
              'checkpoints_loaded': False, 'scientific_files_changed': False}
    for suffix in ('tune_branch_group', 'final_foundation_group', 'all_final_branches_group'):
        path = record / (suffix + '_outcome.json')
        if not path.exists():
            continue
        outcome = read(path)
        seal = outcome['seal']
        result['group_outcomes'][suffix] = {
            'path': str(path), 'sha256': sha(path),
            'seal': {key: seal[key] for key in ('group_id', 'member_ids', 'epochs',
                     'checkpoint_hashes', 'status', 'budget_final', 'evidence_sha256')},
            'members': {name: {key: value.get(key) for key in ('case', 'seed', 'method',
                'type', 'epochs', 'budget_final', 'best_epoch', 'checkpoint_sha256',
                'checkpoint_path', 'learning_rate', 'normalization_hash', 'whitening_hash',
                'initializer_hash', 'device_identity')} for name, value in outcome['members'].items()}}
    path = record / 'aliases_before_final_training.json'
    if path.exists():
        aliases = read(path)
        result['alias_record_sha256'] = sha(path)
        result['effective_configs_sha256_before_aliases'] = aliases['effective_configs_sha256']
        result['aliases'] = {name: target for name, target in aliases['aliases'].items()
                             if name.startswith(case + '__')}
    path = record / 'all_final_branches_group_configs.json'
    if not path.exists():
        return result
    configs = read(path)
    result['physical_configs_sha256'] = sha(path)
    for name, config in configs.items():
        assert name.startswith(case + '__') and name not in result['aliases']
        run = config['registration']
        effective = config['effective_config']
        folder = runtime / 'runs' / name
        item = {'method': run['method'], 'type': run['type'], 'seed': run['seed'],
                'learning_rate': effective['learning_rate'],
                'parent_run_id': effective['parent_run_id'], 'parent_hash': effective['parent_hash'],
                'folder_exists': folder.exists(), 'continuation_file_exists': (folder / 'continuation.pt').is_file()}
        config_path = folder / 'config.json'
        if config_path.exists():
            item['config_sha256'] = sha(config_path)
            item['frozen_config_matches'] = read(config_path) == config
        head_path = folder / 'checkpoint_head.json'
        if head_path.exists():
            head = read(head_path)
            assert 0 <= head['completed_epochs'] <= 200
            item['head'] = head
            event_path = folder / 'checkpoint_events' / (head['checkpoint_sha256'][:16] + '.json')
            if head['completed_epochs'] > 0 and event_path.exists():
                event = read(event_path)
                assert event['completed_epochs'] == head['completed_epochs']
                assert event['checkpoint_sha256'] == head['checkpoint_sha256']
                assert event['previous_epochs'] == head['completed_epochs'] - 1
                item['latest_complete_epoch_event'] = event
            anchor_path = folder / 'continuation_anchor.json'
            if anchor_path.exists():
                item['anchor_sha256'] = sha(anchor_path)
                item['anchor'] = read(anchor_path)
                item['head_anchor_matches'] = head.get('anchor_sha256') == item['anchor_sha256']
        step_path = folder / 'first_optimizer_step.json'
        if step_path.exists():
            step = read(step_path)
            item['first_optimizer_step'] = {key: step.get(key) for key in
                ('status', 'epoch', 'training_batch_size', 'method', 'device_identity')}
        failure_path = folder / 'failure.json'
        if failure_path.exists():
            row['failure_records'][name] = read(failure_path)
        result['physical_members'][name] = item
    result['physical_member_count'] = len(configs)
    result['logical_member_count'] = len(configs) + len(result['aliases'])
    result['complete200_physical_members'] = sum(
        value.get('head', {}).get('completed_epochs') == 200 for value in result['physical_members'].values())
    result['complete_member_epochs'] = sum(
        value.get('head', {}).get('completed_epochs', 0) for value in result['physical_members'].values())
    result['all_alias_targets_are_physical'] = all(target in configs for target in result['aliases'].values())
    return result


report = {'schema': 'fixed200-activation-status-v1', 'root': str(ROOT),
          'checked_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'checkpoints_loaded': False, 'evaluation_values_read': False, 'cases': {}, 'errors': []}
report['queue'] = query([SLURM / 'squeue', '-h', '-u', 'sunyiq', '-o', '%i|%j|%T|%Z|%e|%l|%N|%R'])
for case, variant in CASES.items():
    runtime = ROOT / variant
    record = runtime / 'records' / case
    try:
        initial = read(record / 'activation_starting_members.json')
        job = str(read(runtime / 'records/scheduler_jobs.json')[case])
        auth = read(runtime / 'records/authorization.json')
        row = {'case': case, 'root': str(runtime), 'job_id': job,
               'authorization_sha256': sha(runtime / 'records/authorization.json'),
               'authorization': auth, 'migration_manifest': read(record / 'migration_manifest.json'),
               'data_preparation_complete': read(runtime / 'records/data_preparation_complete.json'),
               'scheduler_script': (runtime / 'hpc/fixed200_case.slurm').read_text(),
               'device_identity': auth['device_identity'], 'members': {},
               'queue_rows': [line for line in report['queue']['stdout'].splitlines() if line.startswith(job + '|')],
               'failure_records': {}}
        allocation = record / ('runtime_binding_' + job + '.json')
        if allocation.exists():
            row['runtime_binding'] = read(allocation)
            assert row['runtime_binding']['device_identity'] == auth['device_identity']
        for name in ('progress.json', 'training_complete.json', 'selected_rates_2021.json',
                     'scheduler_slice_end_' + job + '.json', 'startup_path_recovery_' + job + '.json',
                     'submission_context_repair.confirmed.json'):
            if (record / name).exists():
                row[name] = read(record / name)
        source_outcome = record / 'tune_foundation_group_outcome.json'
        if source_outcome.exists():
            source = read(source_outcome)
            row['tuning_foundation_source'] = {'seal_epochs': source['seal']['epochs'],
                'members': {name: {'epochs': value['epochs'], 'best_epoch': value['best_epoch'],
                           'checkpoint_sha256': value['checkpoint_sha256']}
                            for name, value in source['members'].items()}}
            assert row['tuning_foundation_source']['seal_epochs'] == 400
        for member, start in initial.items():
            folder = runtime / 'runs' / member
            head = read(folder / 'checkpoint_head.json')
            anchor = read(folder / 'continuation_anchor.json')
            assert anchor['initial_checkpoint_sha256'] == start['checkpoint_sha256']
            assert anchor['initial_epochs'] == start['completed_epochs']
            assert sha(folder / 'config.json') == start['config_sha256']
            assert sha(folder / 'migration_source.json') == start['receipt_sha256']
            n = head['completed_epochs']
            assert start['completed_epochs'] <= n <= 200
            item = {'initial_epochs': start['completed_epochs'], 'completed_epochs': n,
                    'new_complete_epochs': n - start['completed_epochs'],
                    'checkpoint_sha256_from_committed_head': head['checkpoint_sha256'],
                    'initial_identity_and_config_preserved': True}
            if n > start['completed_epochs']:
                event = read(folder / 'checkpoint_events' / (head['checkpoint_sha256'][:16] + '.json'))
                assert event['checkpoint_sha256'] == head['checkpoint_sha256']
                assert event['completed_epochs'] == n and event['previous_epochs'] == n - 1
                assert event['anchor_sha256'] == head['anchor_sha256'] == sha(folder / 'continuation_anchor.json')
                item['new_epoch_event'] = event
            if (folder / 'failure.json').exists():
                row['failure_records'][member] = read(folder / 'failure.json')
            row['members'][member] = item
        row['new_complete_member_epochs'] = sum(v['new_complete_epochs'] for v in row['members'].values())
        row['members_with_new_complete_epoch'] = sum(v['new_complete_epochs'] > 0 for v in row['members'].values())
        row['tune_branch_200_complete_members'] = sum(v['completed_epochs'] == 200 for v in row['members'].values())
        row['actual_training_progress_confirmed'] = bool(row.get('runtime_binding') and row['new_complete_member_epochs'] > 0)
        try:
            row['final_stage'] = final_stage_metadata(runtime, record, case, row)
        except Exception as error:
            row['final_stage_metadata_error'] = {'type': type(error).__name__, 'message': str(error)}
        row['logs'] = []
        for path in (runtime / 'logs').glob('*_' + job + '.out'):
            with path.open('rb') as handle:
                handle.seek(max(0, path.stat().st_size - 7000))
                row['logs'].append({'path': str(path), 'tail': handle.read().decode('utf-8', errors='replace')})
        report['cases'][case] = row
    except Exception as error:
        report['errors'].append({'case': case, 'type': type(error).__name__, 'message': str(error)})
jobs = [v['job_id'] for v in report['cases'].values()]
if jobs:
    report['accounting'] = query([SLURM / 'sacct', '-n', '-X', '-j', ','.join(jobs),
                                  '--format=JobID,State,ExitCode,Start,End,NodeList', '-P'])
report['summary'] = {'cases': len(report['cases']),
    'cases_with_new_complete_epoch': sum(v['actual_training_progress_confirmed'] for v in report['cases'].values()),
    'new_complete_member_epochs': sum(v['new_complete_member_epochs'] for v in report['cases'].values()),
    'members_with_new_complete_epoch': sum(v['members_with_new_complete_epoch'] for v in report['cases'].values()),
    'tune_branch_200_complete_members': sum(v['tune_branch_200_complete_members'] for v in report['cases'].values()),
    'failure_files': sum(len(v['failure_records']) for v in report['cases'].values())}
print(json.dumps(report, sort_keys=True), flush=True)

READ_FIXED200_003
