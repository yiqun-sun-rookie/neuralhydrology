#!/usr/bin/env bash
set -eo pipefail
python3 - <<'IMMUTABLE_A40_EXPORT'
import base64,json
namespace={'__name__':'immutable_export'}
exec(compile(base64.b64decode('IiIiUGFja2FnZSB0aGUgZXhpc3RpbmcgbmF0aXZlOTc3IGltbXV0YWJsZSBldmlkZW5jZSBvbmNlIGZvciBhdXRob3JpemVkIEF1dG9ETCB0cmFuc2Zlci4KCkludm9rZWQgYnkgYSBwaW5uZWQgbWFpbGJveCByZXF1ZXN0OyBzdGFuZGFyZCBsaWJyYXJ5IG9ubHksIG5vIHRlbnNvciBsb2FkaW5nLAp0cmFpbmluZywgc2NoZWR1bGVyIG11dGF0aW9uLCBzb3VyY2Utc3RhdGUgcHJlc2VydmF0aW9uIG9yIGNhbm9uaWNhbCB3cml0ZXMuCiIiIgpmcm9tIGRhdGV0aW1lIGltcG9ydCBkYXRldGltZSwgdGltZXpvbmUKaW1wb3J0IGd6aXAKaW1wb3J0IGhhc2hsaWIKaW1wb3J0IGpzb24KZnJvbSBwYXRobGliIGltcG9ydCBQYXRoLCBQdXJlUG9zaXhQYXRoCmltcG9ydCBzaHV0aWwKaW1wb3J0IHN0YXQKaW1wb3J0IHN1YnByb2Nlc3MKaW1wb3J0IHRhcmZpbGUKCk1BUktFUiA9ICdHUlVfQTQwX0FVVE9ETF9JTU1VVEFCTEVfRVhQT1JUX0pTT04nClBBUlRfQllURVMgPSA4XzAwMF8wMDAKCgpkZWYgc2hhKHBhdGgpOgogICAgaCA9IGhhc2hsaWIuc2hhMjU2KCkKICAgIHdpdGggUGF0aChwYXRoKS5vcGVuKCdyYicpIGFzIHN0cmVhbToKICAgICAgICBmb3IgYmxvY2sgaW4gaXRlcihsYW1iZGE6IHN0cmVhbS5yZWFkKDQgKiAxMDI0ICogMTAyNCksIGInJyk6CiAgICAgICAgICAgIGgudXBkYXRlKGJsb2NrKQogICAgcmV0dXJuIGguaGV4ZGlnZXN0KCkKCgpkZWYgbmV3KHBhdGgsIHZhbHVlKToKICAgIHdpdGggUGF0aChwYXRoKS5vcGVuKCd4JywgZW5jb2Rpbmc9J3V0Zi04JykgYXMgc3RyZWFtOgogICAgICAgIGpzb24uZHVtcCh2YWx1ZSwgc3RyZWFtLCBzb3J0X2tleXM9VHJ1ZSwgaW5kZW50PTIsIGFsbG93X25hbj1GYWxzZSkKICAgICAgICBzdHJlYW0ud3JpdGUoJ1xuJykKCgpkZWYgY2hlY2tlZChwYXRoLCBleHBlY3RlZCk6CiAgICBwYXRoID0gUGF0aChwYXRoKQogICAgc3QgPSBwYXRoLmxzdGF0KCkKICAgIGFzc2VydCBzdGF0LlNfSVNSRUcoc3Quc3RfbW9kZSkgYW5kIHBhdGgucmVzb2x2ZSgpID09IHBhdGgKICAgIGFzc2VydCBzdC5zdF9zaXplID09IGV4cGVjdGVkWydzaXplJ10gYW5kIHNoYShwYXRoKSA9PSBleHBlY3RlZFsnc2hhMjU2J10sIHN0cihwYXRoKQogICAgcmV0dXJuIHBhdGgKCgpkZWYgcXVlcnkodG9vbCwgYXJncyk6CiAgICBiaW5hcnkgPSBzaHV0aWwud2hpY2godG9vbCkgb3IgJy91c3IvbG9jYWwvZ2xvYmxlL3NvZnRzL3NsdXJtLzE5LjA1LjQuMS9iaW4vJyArIHRvb2wKICAgIHAgPSBzdWJwcm9jZXNzLnJ1bihbYmluYXJ5XSArIGFyZ3MsIGNhcHR1cmVfb3V0cHV0PVRydWUsIHRleHQ9VHJ1ZSwgdGltZW91dD0zMCkKICAgIGFzc2VydCBwLnJldHVybmNvZGUgPT0gMCwgdG9vbCArICcgcmVhZCBmYWlsZWQnCiAgICByZXR1cm4geydzdGRvdXQnOiBwLnN0ZG91dCwgJ3N0ZGVycic6IHAuc3RkZXJyLCAncmV0dXJuY29kZSc6IHAucmV0dXJuY29kZX0KCgpkZWYgcGFja2FnZShhcmNoaXZlX3BhdGgsIGZpbGVzLCBpZGVudGl0aWVzKToKICAgICIiIlN0cmVhbSBleGFjdCBmcm96ZW4gYnl0ZXM7IGFzc2VydCBpZGVudGl0aWVzIGFnYWluIGFmdGVyIHBhY2thZ2luZy4iIiIKICAgIGZvciBuYW1lLCBzb3VyY2UgaW4gZmlsZXMuaXRlbXMoKToKICAgICAgICBwdXJlID0gUHVyZVBvc2l4UGF0aChuYW1lKQogICAgICAgIGFzc2VydCBub3QgcHVyZS5pc19hYnNvbHV0ZSgpIGFuZCAnLi4nIG5vdCBpbiBwdXJlLnBhcnRzCiAgICAgICAgY2hlY2tlZChzb3VyY2UsIGlkZW50aXRpZXNbbmFtZV0pCiAgICB3aXRoIFBhdGgoYXJjaGl2ZV9wYXRoKS5vcGVuKCd4YicpIGFzIHJhdzoKICAgICAgICB3aXRoIGd6aXAuR3ppcEZpbGUoZmlsZW5hbWU9JycsIGZpbGVvYmo9cmF3LCBtb2RlPSd3YicsIGNvbXByZXNzbGV2ZWw9MSwgbXRpbWU9MCkgYXMgemlwcGVkOgogICAgICAgICAgICB3aXRoIHRhcmZpbGUub3BlbihmaWxlb2JqPXppcHBlZCwgbW9kZT0nd3wnKSBhcyB0YXI6CiAgICAgICAgICAgICAgICBmb3IgbmFtZSwgc291cmNlIGluIHNvcnRlZChmaWxlcy5pdGVtcygpKToKICAgICAgICAgICAgICAgICAgICBpbmZvID0gdGFyZmlsZS5UYXJJbmZvKG5hbWUpCiAgICAgICAgICAgICAgICAgICAgaW5mby5zaXplID0gaWRlbnRpdGllc1tuYW1lXVsnc2l6ZSddCiAgICAgICAgICAgICAgICAgICAgaW5mby5tb2RlLCBpbmZvLm10aW1lID0gMG82NDQsIDAKICAgICAgICAgICAgICAgICAgICB3aXRoIFBhdGgoc291cmNlKS5vcGVuKCdyYicpIGFzIHN0cmVhbToKICAgICAgICAgICAgICAgICAgICAgICAgdGFyLmFkZGZpbGUoaW5mbywgc3RyZWFtKQogICAgZm9yIG5hbWUsIHNvdXJjZSBpbiBmaWxlcy5pdGVtcygpOgogICAgICAgIGNoZWNrZWQoc291cmNlLCBpZGVudGl0aWVzW25hbWVdKQoKCmRlZiBzcGxpdChhcmNoaXZlLCBhc3NldHMpOgogICAgcGFydHMgPSBbXQogICAgd2l0aCBQYXRoKGFyY2hpdmUpLm9wZW4oJ3JiJykgYXMgc3RyZWFtOgogICAgICAgIHdoaWxlIFRydWU6CiAgICAgICAgICAgIHJhdyA9IHN0cmVhbS5yZWFkKFBBUlRfQllURVMpCiAgICAgICAgICAgIGlmIG5vdCByYXc6CiAgICAgICAgICAgICAgICBicmVhawogICAgICAgICAgICBpbmRleCA9IGxlbihwYXJ0cykKICAgICAgICAgICAgbmFtZSA9ICdBNDBfc3RhdGVzLnBhcnQlMDRkLnAnICUgaW5kZXgKICAgICAgICAgICAgd2l0aCAoYXNzZXRzIC8gbmFtZSkub3BlbigneGInKSBhcyBvdXRwdXQ6CiAgICAgICAgICAgICAgICBvdXRwdXQud3JpdGUocmF3KQogICAgICAgICAgICBwYXJ0cy5hcHBlbmQoeyduYW1lJzogbmFtZSwgJ29mZnNldCc6IGluZGV4ICogUEFSVF9CWVRFUywgJ2J5dGVzJzogbGVuKHJhdyksCiAgICAgICAgICAgICAgICAnc2hhMjU2JzogaGFzaGxpYi5zaGEyNTYocmF3KS5oZXhkaWdlc3QoKSwKICAgICAgICAgICAgICAgICdnaXRfYmxvYl9vaWQnOiBoYXNobGliLnNoYTEoYidibG9iICcgKyBzdHIobGVuKHJhdykpLmVuY29kZSgpICsgYidcMCcgKyByYXcpLmhleGRpZ2VzdCgpfSkKICAgIGFzc2VydCBzdW0ocFsnYnl0ZXMnXSBmb3IgcCBpbiBwYXJ0cykgPT0gUGF0aChhcmNoaXZlKS5zdGF0KCkuc3Rfc2l6ZQogICAgcmV0dXJuIHBhcnRzCgoKZGVmIG1haW4ocGxhbik6CiAgICBpbXBvcnQgZmNudGwKICAgIGFzc2VydCBwbGFuWydzb3VyY2VfcHJlc2VydmF0aW9uX3NlcXVlbmNlJ10gPT0gOTc3IGFuZCBwbGFuWydzb3VyY2VfZmFpbGVkX2pvYiddID09ICcyNTgxNjYnCiAgICBhc3NlcnQgcGxhblsnc2VsZWN0ZWRfcmVjZWl2ZXInXSA9PSAnYXV0b2RsLTAwNCcgYW5kIHBsYW5bJ2ZpbGVfY291bnQnXSA9PSA2ODgKICAgIHJvb3QgPSBQYXRoKHBsYW5bJ2Nhbm9uaWNhbF9yb290J10pCiAgICBldmlkZW5jZSA9IFBhdGgocGxhblsnZXZpZGVuY2VfZGlyJ10pCiAgICBkaXJlY3RvcnkgPSBQYXRoKHBsYW5bJ2V4cG9ydF9kaXJlY3RvcnknXSkKICAgIGFzc2VydCBkaXJlY3RvcnkucGFyZW50ID09IGV2aWRlbmNlLnBhcmVudCBhbmQgZGlyZWN0b3J5Lm5hbWUgPT0gJ0E0MF9BdXRvREwwMDRfaW1tdXRhYmxlX2V4cG9ydF9hZnRlcl85NzlfMjAyNjExMTBfMDAxJwogICAgZGlyZWN0b3J5Lm1rZGlyKGV4aXN0X29rPUZhbHNlKQogICAgbmV3KGRpcmVjdG9yeSAvICdQTEFOLmpzb24nLCBwbGFuKQogICAgbmV3KGRpcmVjdG9yeSAvICdBVFRFTVBULmpzb24nLCB7J2F0X3V0Yyc6IGRhdGV0aW1lLm5vdyh0aW1lem9uZS51dGMpLmlzb2Zvcm1hdCgpLCAnbWF4aW11bV9hdHRlbXB0cyc6IDF9KQogICAgcmVwb3J0ID0geydzY2hlbWEnOiAnMDAzLUE0MC1BdXRvREwtaW1tdXRhYmxlLWV4cG9ydC12MScsICdzdGF0dXMnOiAnc3RhcnRlZCcsICdlcnJvcnMnOiBbXSwKICAgICAgICAnc291cmNlX3ByZXNlcnZhdGlvbl9zZXF1ZW5jZSc6IDk3NywgJ3NvdXJjZV9mYWlsZWRfam9iJzogJzI1ODE2NicsICdzZWxlY3RlZF9yZWNlaXZlcic6ICdhdXRvZGwtMDA0JywKICAgICAgICAnc291cmNlX2ZpbGVzX3dyaXR0ZW4nOiAwLCAnb3B0aW1pemVyX3N0ZXBzJzogMCwgJ3RlbnNvcl9maWxlc19sb2FkZWQnOiBGYWxzZSwKICAgICAgICAnc2NoZWR1bGVyX211dGF0aW9ucyc6IDAsICdvd25lcnNoaXBfY2hhbmdlZCc6IEZhbHNlLCAndHJhaW5pbmdfc3RhcnRlZCc6IEZhbHNlfQogICAgdHJ5OgogICAgICAgIHdvcmtlciA9IFBhdGgocGxhblsnd29ya2VyX2FjdGl2ZV9wYXRoJ10pCiAgICAgICAgYXNzZXJ0IHNoYSh3b3JrZXIpID09IHBsYW5bJ2V4cGVjdGVkX3dvcmtlcl9zaGEyNTYnXQogICAgICAgIG1hbmlmZXN0X3BhdGggPSBjaGVja2VkKGV2aWRlbmNlIC8gJ0VWSURFTkNFX01BTklGRVNULmpzb24nLCBwbGFuWydtYW5pZmVzdF9pZGVudGl0eSddKQogICAgICAgIG1hbmlmZXN0ID0ganNvbi5sb2FkcyhtYW5pZmVzdF9wYXRoLnJlYWRfYnl0ZXMoKSkKICAgICAgICBhc3NlcnQgbWFuaWZlc3RbJ3NjaGVtYSddID09ICcwMDMtQTQwLWZhaWx1cmUtcHJlc2VydmF0aW9uLXYxJwogICAgICAgIGFzc2VydCBsZW4obWFuaWZlc3RbJ2ZpbGVzJ10pID09IHBsYW5bJ2ZpbGVfY291bnQnXQogICAgICAgIGFzc2VydCBzdW0oeFsnc2l6ZSddIGZvciB4IGluIG1hbmlmZXN0WydmaWxlcyddLnZhbHVlcygpKSA9PSBwbGFuWydzb3VyY2VfdG90YWxfYnl0ZXMnXQogICAgICAgIHByaW9yID0gUGF0aChtYW5pZmVzdFsncHJpb3JfZXZpZGVuY2VfZGlyJ10pCiAgICAgICAgYXNzZXJ0IHByaW9yLnBhcmVudCA9PSBldmlkZW5jZS5wYXJlbnQKICAgICAgICBhc3NlcnQgc2hhKHByaW9yIC8gJ0VWSURFTkNFX01BTklGRVNULmpzb24nKSA9PSBtYW5pZmVzdFsncHJpb3JfZXZpZGVuY2VfbWFuaWZlc3Rfc2hhMjU2J10KICAgICAgICBmaWxlcywgaWRlbnRpdGllcyA9IHt9LCB7fQogICAgICAgIGZvciBuYW1lLCBpdGVtIGluIG1hbmlmZXN0WydmaWxlcyddLml0ZW1zKCk6CiAgICAgICAgICAgIHB1cmUgPSBQdXJlUG9zaXhQYXRoKG5hbWUpCiAgICAgICAgICAgIGFzc2VydCBub3QgcHVyZS5pc19hYnNvbHV0ZSgpIGFuZCAnLi4nIG5vdCBpbiBwdXJlLnBhcnRzCiAgICAgICAgICAgIHNvdXJjZSA9IFBhdGgoaXRlbS5nZXQoJ3JldXNlZF9mcm9tJywgc3RyKGV2aWRlbmNlIC8gbmFtZSkpKQogICAgICAgICAgICBpZiAncmV1c2VkX2Zyb20nIGluIGl0ZW06CiAgICAgICAgICAgICAgICBhc3NlcnQgc291cmNlID09IHByaW9yIC8gbmFtZSBhbmQgaXRlbVsncHJpb3JfbWFuaWZlc3Rfc2hhMjU2J10gPT0gbWFuaWZlc3RbJ3ByaW9yX2V2aWRlbmNlX21hbmlmZXN0X3NoYTI1NiddCiAgICAgICAgICAgIGVsc2U6CiAgICAgICAgICAgICAgICBhc3NlcnQgZXZpZGVuY2UgaW4gc291cmNlLnBhcmVudHMKICAgICAgICAgICAgZmlsZXNbbmFtZV0gPSBzb3VyY2UKICAgICAgICAgICAgaWRlbnRpdGllc1tuYW1lXSA9IHsnc2l6ZSc6IGl0ZW1bJ3NpemUnXSwgJ3NoYTI1Nic6IGl0ZW1bJ3NoYTI1NiddfQogICAgICAgIGZpbGVzWydFVklERU5DRV9NQU5JRkVTVC5qc29uJ10gPSBtYW5pZmVzdF9wYXRoCiAgICAgICAgaWRlbnRpdGllc1snRVZJREVOQ0VfTUFOSUZFU1QuanNvbiddID0gcGxhblsnbWFuaWZlc3RfaWRlbnRpdHknXQogICAgICAgICMgTG9jayBpcyBleGlzdGluZyBhbmQgb3BlbmVkIHdpdGhvdXQgdHJ1bmNhdGlvbjsgbm8gc291cmNlIG93bmVyIGlzIGNyZWF0ZWQuCiAgICAgICAgd2l0aCAocm9vdCAvICdyZWNvcmRzL2V4cGxpY2l0X2dydV9faGlzdG9yaWNhbF9jYXBhY2l0eS93cml0ZXIubG9jaycpLm9wZW4oJ3IrYicpIGFzIGxvY2s6CiAgICAgICAgICAgIGZjbnRsLmZsb2NrKGxvY2ssIGZjbnRsLkxPQ0tfRVggfCBmY250bC5MT0NLX05CKQogICAgICAgICAgICByZXBvcnRbJ2V4Y2x1c2l2ZV9leGlzdGluZ193cml0ZXJfbG9ja19hY3F1aXJlZCddID0gVHJ1ZQogICAgICAgICAgICByZXBvcnRbJ2FjY291bnRpbmcnXSA9IHF1ZXJ5KCdzYWNjdCcsIFsnLW4nLCAnLWonLCAnMjU4MTY2JywgJy0tZm9ybWF0PUpvYklEUmF3LFN0YXRlLEV4aXRDb2RlJywgJy1QJ10pCiAgICAgICAgICAgIHJvd3MgPSBbeC5zcGxpdCgnfCcpIGZvciB4IGluIHJlcG9ydFsnYWNjb3VudGluZyddWydzdGRvdXQnXS5zcGxpdGxpbmVzKCkgaWYgeC5zdHJpcCgpXQogICAgICAgICAgICBhc3NlcnQgYW55KHhbOjNdID09IFsnMjU4MTY2JywgJ0ZBSUxFRCcsICcxOjAnXSBmb3IgeCBpbiByb3dzKQogICAgICAgICAgICBhc3NlcnQgcm93cyBhbmQgYWxsKHhbMV0uc3BsaXQoKVswXSBpbiB7J0ZBSUxFRCcsICdDT01QTEVURUQnLCAnQ0FOQ0VMTEVEJywgJ1RJTUVPVVQnLCAnUFJFRU1QVEVEJywgJ05PREVfRkFJTCcsICdPVVRfT0ZfTUVNT1JZJ30gZm9yIHggaW4gcm93cykKICAgICAgICAgICAgcmVwb3J0WydxdWV1ZV9iZWZvcmUnXSA9IHF1ZXJ5KCdzcXVldWUnLCBbJy1oJywgJy11JywgJ3N1bnlpcScsICctbycsICclaXwlVHwlWnwlaiddKQogICAgICAgICAgICBhc3NlcnQgbm90IGFueShzdHIocm9vdCkgaW4gbGluZSBvciAnZXhwbGljaXRfZ3J1X19oaXN0b3JpY2FsX2NhcGFjaXR5JyBpbiBsaW5lIGZvciBsaW5lIGluIHJlcG9ydFsncXVldWVfYmVmb3JlJ11bJ3N0ZG91dCddLnNwbGl0bGluZXMoKSkKICAgICAgICAgICAgZm9yIG1lbWJlciwgZXhwZWN0ZWQgaW4gcGxhblsnbWVtYmVycyddLml0ZW1zKCk6CiAgICAgICAgICAgICAgICBjdXJyZW50ID0gcm9vdCAvICdydW5zJyAvIG1lbWJlcgogICAgICAgICAgICAgICAgYXNzZXJ0IHNoYShjdXJyZW50IC8gJ2NoZWNrcG9pbnRfaGVhZC5qc29uJykgPT0gZXhwZWN0ZWRbJ2hlYWRfZmlsZV9zaGEyNTYnXQogICAgICAgICAgICAgICAgYXNzZXJ0IHNoYShjdXJyZW50IC8gJ2NvbnRpbnVhdGlvbi5wdCcpID09IGV4cGVjdGVkWydjb250aW51YXRpb25fc2hhMjU2J10KICAgICAgICAgICAgICAgIGhlYWQgPSBqc29uLmxvYWRzKChjdXJyZW50IC8gJ2NoZWNrcG9pbnRfaGVhZC5qc29uJykucmVhZF9ieXRlcygpKQogICAgICAgICAgICAgICAgYXNzZXJ0IGhlYWRbJ2NvbXBsZXRlZF9lcG9jaHMnXSA9PSBleHBlY3RlZFsnY29tcGxldGVkX2Vwb2NocyddCiAgICAgICAgICAgICAgICBhc3NlcnQgaWRlbnRpdGllc1snc291cmNlL3J1bnMvJyArIG1lbWJlciArICcvY29udGludWF0aW9uLnB0J11bJ3NoYTI1NiddID09IGV4cGVjdGVkWydjb250aW51YXRpb25fc2hhMjU2J10KICAgICAgICAgICAgYXNzZXRzID0gZGlyZWN0b3J5IC8gJ2Fzc2V0c190b19wdWJsaXNoJwogICAgICAgICAgICBhc3NldHMubWtkaXIoKQogICAgICAgICAgICBhcmNoaXZlID0gZGlyZWN0b3J5IC8gJ0E0MF9zdGF0ZXMudGFyLmd6JwogICAgICAgICAgICBwYWNrYWdlKGFyY2hpdmUsIGZpbGVzLCBpZGVudGl0aWVzKQogICAgICAgICAgICBwYXJ0cyA9IHNwbGl0KGFyY2hpdmUsIGFzc2V0cykKICAgICAgICAgICAgcmVwb3J0WydxdWV1ZV9hZnRlciddID0gcXVlcnkoJ3NxdWV1ZScsIFsnLWgnLCAnLXUnLCAnc3VueWlxJywgJy1vJywgJyVpfCVUfCVafCVqJ10pCiAgICAgICAgICAgIGFzc2VydCBub3QgYW55KHN0cihyb290KSBpbiBsaW5lIG9yICdleHBsaWNpdF9ncnVfX2hpc3RvcmljYWxfY2FwYWNpdHknIGluIGxpbmUgZm9yIGxpbmUgaW4gcmVwb3J0WydxdWV1ZV9hZnRlciddWydzdGRvdXQnXS5zcGxpdGxpbmVzKCkpCiAgICAgICAgICAgIGZvciBtZW1iZXIsIGV4cGVjdGVkIGluIHBsYW5bJ21lbWJlcnMnXS5pdGVtcygpOgogICAgICAgICAgICAgICAgYXNzZXJ0IHNoYShyb290IC8gJ3J1bnMnIC8gbWVtYmVyIC8gJ2NoZWNrcG9pbnRfaGVhZC5qc29uJykgPT0gZXhwZWN0ZWRbJ2hlYWRfZmlsZV9zaGEyNTYnXQogICAgICAgICAgICBkZXN0aW5hdGlvbiA9IFBhdGgocGxhblsnb3V0Ym94X2Fzc2V0X2RpcmVjdG9yeSddKQogICAgICAgICAgICBhc3NlcnQgZGVzdGluYXRpb24ucGFyZW50ID09IFBhdGgoJy9kYXRhMS9ob21lL3N1bnlpcS9ocGNfbWFpbGJveC9vdXRib3gvemhlbmppYW5nLXNpeC1zb3VyY2UtZm91ci10YXJnZXQtdWtmJykKICAgICAgICAgICAgYXNzZXJ0IGRlc3RpbmF0aW9uLm5hbWUgPT0gJ2dydV9BNDBfQXV0b0RMMDA0X2V4cG9ydF8yMDI2MTExMF8wMDEnIGFuZCBub3QgZGVzdGluYXRpb24uZXhpc3RzKCkKICAgICAgICAgICAgYXNzZXJ0IGFzc2V0cy5zdGF0KCkuc3RfZGV2ID09IGRlc3RpbmF0aW9uLnBhcmVudC5zdGF0KCkuc3RfZGV2CiAgICAgICAgICAgIHJlcG9ydC51cGRhdGUoc3RhdHVzPSdpbW11dGFibGVfOTc3X2Z1bGxfc3RhdGVzX2V4cG9ydGVkX2Zvcl90cmFuc2ZlcicsCiAgICAgICAgICAgICAgICBjaGVja2VkX2F0X3V0Yz1kYXRldGltZS5ub3codGltZXpvbmUudXRjKS5pc29mb3JtYXQoKSwKICAgICAgICAgICAgICAgIHNvdXJjZV9tYW5pZmVzdF9zaGEyNTY9cGxhblsnbWFuaWZlc3RfaWRlbnRpdHknXVsnc2hhMjU2J10sIHNvdXJjZV9maWxlX2NvdW50PTY4OCwKICAgICAgICAgICAgICAgIHNvdXJjZV90b3RhbF9ieXRlcz1wbGFuWydzb3VyY2VfdG90YWxfYnl0ZXMnXSwgb3V0Ym94X2Fzc2V0X2RpcmVjdG9yeT1zdHIoZGVzdGluYXRpb24pLAogICAgICAgICAgICAgICAgYXJjaGl2ZXM9eydBNDBfc3RhdGVzJzogeydieXRlcyc6IGFyY2hpdmUuc3RhdCgpLnN0X3NpemUsICdzaGEyNTYnOiBzaGEoYXJjaGl2ZSksCiAgICAgICAgICAgICAgICAgICAgJ2ZpbGVzJzoge2s6IHsnYnl0ZXMnOiB2WydzaXplJ10sICdzaGEyNTYnOiB2WydzaGEyNTYnXX0gZm9yIGssIHYgaW4gaWRlbnRpdGllcy5pdGVtcygpfSwgJ3BhcnRzJzogcGFydHN9fSkKICAgICAgICAgICAgbmV3KGFzc2V0cyAvICdFWFBPUlRfTUFOSUZFU1QuanNvbicsIHJlcG9ydCkKICAgICAgICAgICAgYXNzZXRzLnJlbmFtZShkZXN0aW5hdGlvbikKICAgICAgICAgICAgYXNzZXJ0IGFsbChzaGEoZGVzdGluYXRpb24gLyBwWyduYW1lJ10pID09IHBbJ3NoYTI1NiddIGZvciBwIGluIHBhcnRzKQogICAgICAgIHJlcG9ydFsnd3JpdGVyX2xvY2tfcmVsZWFzZWQnXSA9IFRydWUKICAgIGV4Y2VwdCBFeGNlcHRpb24gYXMgZXJyb3I6CiAgICAgICAgcmVwb3J0LnVwZGF0ZShzdGF0dXM9J2V4cG9ydF9mYWlsZWRfcHJlc2VydmVfbm9fcmVwZWF0JywgZXJyb3JzPVtyZXByKGVycm9yKV0pCiAgICBuZXcoZGlyZWN0b3J5IC8gJ0VYUE9SVF9SRVBPUlQuanNvbicsIHJlcG9ydCkKICAgIHByaW50KE1BUktFUiArICcgJyArIGpzb24uZHVtcHMocmVwb3J0LCBzb3J0X2tleXM9VHJ1ZSksIGZsdXNoPVRydWUpCiAgICBhc3NlcnQgbm90IHJlcG9ydFsnZXJyb3JzJ10sIHJlcG9ydFsnZXJyb3JzJ10K'),'export_immutable_states_once.py','exec'),namespace)
namespace['main'](json.loads(base64.b64decode('ewogICJhdF91dGMiOiAiMjAyNi0xMS0xMFQwMjo1MTozOC43MTQxNDUrMDA6MDAiLAogICJjYW5vbmljYWxfcm9vdCI6ICIvZGF0YTEvaG9tZS9zdW55aXEvemhlbmppYW5nX2NvbXBsZXRlX2NvbXBhcmlzb25fZml4ZWQyMDBfMjAyNjEwMTlfMDAzL3NxcnRfZ3J1X3JlY292ZXJ5IiwKICAiY2FwYWNpdHlfcHJvb2YiOiAiRzpcXGdpdGh1YlxccHljaGFybVxccHJvamVjdHNcXHpoZW5qaWFuZ19jb21wbGV0ZV9jb21wYXJpc29uXzIwMjYxMDA2XzAwMlxccmVzdWx0c1xcZml4ZWQyMDBfMDAzX2FjdGl2YXRpb25fMjAyNjEwMjBfMDAxXFxwcm9qZWN0aW9uX3JlcGFpcl8yMDI2MTEwNV8wMDFcXHBhcmFsbGVsX2NvbnRpbnVhdGlvbl8yMDI2MTEwNl8wMDFcXEE0MF90b19BdXRvRExfYWZ0ZXJfOTc5XzIwMjYxMTEwXzAwMVxcQ0FQQUNJVFlfU0VMRUNUSU9OX1ZFUklGSUVELmpzb24iLAogICJjYXBhY2l0eV9wcm9vZl9zaGEyNTYiOiAiNTQyZGRjOGZkNzkwNTc4Y2Q3YTg0YzkyMmVhNWJhZmFjODhiN2M0YWM4ZDc3YWIwZWMzMTExZTE4OGY4ZjA5OCIsCiAgImV2aWRlbmNlX2RpciI6ICIvZGF0YTEvaG9tZS9zdW55aXEvemhlbmppYW5nX2NvbXBsZXRlX2NvbXBhcmlzb25fZml4ZWQyMDBfMjAyNjEwMTlfMDAzL3NxcnRfZ3J1X3JlY292ZXJ5L3JlY29yZHMvZXhwbGljaXRfZ3J1X19oaXN0b3JpY2FsX2NhcGFjaXR5L3JlcGFpcnMvQTQwX2FmdGVyXzI1ODE2Nl9mYWlsdXJlX3ByZXNlcnZhdGlvbl85NzZfMDAxIiwKICAiZXhjbHVkZWRfZXh0ZXJuYWxfc2V2ZW4iOiBbCiAgICAiZXhwbGljaXRfZ3J1X19oaXN0b3JpY2FsX2NhcGFjaXR5X190dW5lX2JyYW5jaF9fZW5jb2Rlcl9maXhlZF9fczEwMV9fbHIwcDAwMDMiLAogICAgImV4cGxpY2l0X2dydV9faGlzdG9yaWNhbF9jYXBhY2l0eV9fdHVuZV9icmFuY2hfX2VuY29kZXJfZml4ZWRfX3MxMDFfX2xyMHAwMDEiLAogICAgImV4cGxpY2l0X2dydV9faGlzdG9yaWNhbF9jYXBhY2l0eV9fdHVuZV9icmFuY2hfX2ZpbHRlcl9maXhlZF9fczEwMV9fbHIwcDAwMDMiLAogICAgImV4cGxpY2l0X2dydV9faGlzdG9yaWNhbF9jYXBhY2l0eV9fdHVuZV9icmFuY2hfX2ZpbHRlcl9maXhlZF9fczEwMV9fbHIwcDAwMSIsCiAgICAiZXhwbGljaXRfZ3J1X19oaXN0b3JpY2FsX2NhcGFjaXR5X190dW5lX2JyYW5jaF9fZmlsdGVyX2ZpeGVkX19zMTAxX19scjBwMDAzIiwKICAgICJleHBsaWNpdF9ncnVfX2hpc3RvcmljYWxfY2FwYWNpdHlfX3R1bmVfYnJhbmNoX19maWx0ZXJfam9pbnRfX3MxMDFfX2xyMHAwMDAzIiwKICAgICJleHBsaWNpdF9ncnVfX2hpc3RvcmljYWxfY2FwYWNpdHlfX3R1bmVfYnJhbmNoX19maWx0ZXJfam9pbnRfX3MxMDFfX2xyMHAwMDEiCiAgXSwKICAiZXhwZWN0ZWRfd29ya2VyX3NoYTI1NiI6ICIxOTIyMDQ4MzFkYzYyMmI0NTdlOWM4MGE5MzMxY2ExZDk2NTlmYmU0NjQxMjQzNjgxZmE1MmQ0ZWYzMDMwYTA4IiwKICAiZXhwb3J0X2RpcmVjdG9yeSI6ICIvZGF0YTEvaG9tZS9zdW55aXEvemhlbmppYW5nX2NvbXBsZXRlX2NvbXBhcmlzb25fZml4ZWQyMDBfMjAyNjEwMTlfMDAzL3NxcnRfZ3J1X3JlY292ZXJ5L3JlY29yZHMvZXhwbGljaXRfZ3J1X19oaXN0b3JpY2FsX2NhcGFjaXR5L3JlcGFpcnMvQTQwX0F1dG9ETDAwNF9pbW11dGFibGVfZXhwb3J0X2FmdGVyXzk3OV8yMDI2MTExMF8wMDEiLAogICJmaWxlX2NvdW50IjogNjg4LAogICJsb2NhbF9tYW5pZmVzdCI6ICJHOlxcZ2l0aHViXFxweWNoYXJtXFxwcm9qZWN0c1xcemhlbmppYW5nX2NvbXBsZXRlX2NvbXBhcmlzb25fMjAyNjEwMDZfMDAyXFxyZXN1bHRzXFxmaXhlZDIwMF8wMDNfYWN0aXZhdGlvbl8yMDI2MTAyMF8wMDFcXHByb2plY3Rpb25fcmVwYWlyXzIwMjYxMTA1XzAwMVxccGFyYWxsZWxfY29udGludWF0aW9uXzIwMjYxMTA2XzAwMVxcQTQwX2ZhaWx1cmVfc2F2ZWRfbG9nXzk3N18wMDFcXExPQ0FMXzk3OFxcRVZJREVOQ0VfTUFOSUZFU1QuanNvbiIsCiAgIm1hbmlmZXN0X2lkZW50aXR5IjogewogICAgInNoYTI1NiI6ICJlZjUwNzNjNDQ2ZTA5NTQ5MTUzMTkyZDgyYzc2NzIxMzcxYTMwOWRhYmMxMmRmNjAwZmY3MDAwZmZkYWRmZTNlIiwKICAgICJzaXplIjogNTgzODY5CiAgfSwKICAibWF4aW11bV9vcHRpbWl6ZXJfc3RlcHMiOiAwLAogICJtZW1iZXJzIjogewogICAgImV4cGxpY2l0X2dydV9faGlzdG9yaWNhbF9jYXBhY2l0eV9fdHVuZV9icmFuY2hfX2VuY29kZXJfZml4ZWRfX3MxMDFfX2xyMHAwMDMiOiB7CiAgICAgICJjb21wbGV0ZWRfZXBvY2hzIjogMTY2LAogICAgICAiY29uZmlnX3NoYTI1NiI6ICIzMGM3NzM2N2NlNjEwMDJkZDllZDg3ZGM4ZmY3ZDljM2QwZTg0YmExNWY4MWIzM2M2YTYxMTJlNWRhZDJkZmFjIiwKICAgICAgImNvbnRpbnVhdGlvbl9zaGEyNTYiOiAiODg5YWY4MjlmNWM0MTEzOWY3NTYyZWU0YzIyNzIxYTAwYWYxMDE2NGRhNWEwYzgwMmZjMmE5ZjM0NjUxNzBjOSIsCiAgICAgICJoZWFkX2ZpbGVfc2hhMjU2IjogImU3NzJjNzI0NDUxOTliZGE5MTgzZWNiNzIxNzk3ZTllOTliNzI2ZTI0NGUwMjU1Yjg1Mzg4NDkxMjk0MGUwMjYiCiAgICB9LAogICAgImV4cGxpY2l0X2dydV9faGlzdG9yaWNhbF9jYXBhY2l0eV9fdHVuZV9icmFuY2hfX2VuY29kZXJfam9pbnRfX3MxMDFfX2xyMHAwMDAzIjogewogICAgICAiY29tcGxldGVkX2Vwb2NocyI6IDE2NiwKICAgICAgImNvbmZpZ19zaGEyNTYiOiAiMjBkNWY5ZjZlYmVlZTJlZTRhYmU2NWQ2YmNkZWJjNzYwNDU3NTE4NmYyMDdiNTA0MzUzOGU3NGVmZTIwZWIzYSIsCiAgICAgICJjb250aW51YXRpb25fc2hhMjU2IjogIjdjYzM1OGZkZmE3MmMzZTllZjQ3ODZkNTdiNmRkNTM2M2U5YzQ4ZDNjNjg3Nzg0OWQwZmEyOGZmMTlhNjI3YWQiLAogICAgICAiaGVhZF9maWxlX3NoYTI1NiI6ICIyYzNjZmI1ZWRlYjI1Y2M5YTc3MzdlMmUzNjg4NDljNGMzMzUwNzEzZDdiNTU0NDZlMDU0NDg2NDY5NDEwNmFmIgogICAgfSwKICAgICJleHBsaWNpdF9ncnVfX2hpc3RvcmljYWxfY2FwYWNpdHlfX3R1bmVfYnJhbmNoX19lbmNvZGVyX2pvaW50X19zMTAxX19scjBwMDAxIjogewogICAgICAiY29tcGxldGVkX2Vwb2NocyI6IDE2NiwKICAgICAgImNvbmZpZ19zaGEyNTYiOiAiYWNkZTQwNmIwNmJlM2Q0NDI4NmFmYTY5NjMwM2ZlZjg4NWQyZTdjNjA0ODU2ODM1N2YxMzE3MzhkYjU4NTg1OSIsCiAgICAgICJjb250aW51YXRpb25fc2hhMjU2IjogImFkMTA5MjBhYzAwZmNkYzZlMTUxYzQzNzZhZTlhNzAyODhiMmNjY2NhNTVlMjAzNDhhMjNjZTU3NTNmMjc3NzciLAogICAgICAiaGVhZF9maWxlX3NoYTI1NiI6ICIxMTU4MWNlMzlkZGYwNjM0NjIzN2I2YWUwNmNhOGU4MDA2ZDc2NzUyZTJiYzViMjMxOWQ0MmQ4NTIwZmE1MjA3IgogICAgfSwKICAgICJleHBsaWNpdF9ncnVfX2hpc3RvcmljYWxfY2FwYWNpdHlfX3R1bmVfYnJhbmNoX19lbmNvZGVyX2pvaW50X19zMTAxX19scjBwMDAzIjogewogICAgICAiY29tcGxldGVkX2Vwb2NocyI6IDE2NiwKICAgICAgImNvbmZpZ19zaGEyNTYiOiAiZjUzODM0OGNjZGUxMGZhYjQzZDQwN2IzOTkxYWJjNTViOThhNTJlN2ZhM2ExOGI2NmQyM2E1YzgzMGMyNTAzMCIsCiAgICAgICJjb250aW51YXRpb25fc2hhMjU2IjogImM3NmFiYTM2MGEzNTk3NjdmYmY1ODYyYWY4YjMzMTQyYWRlZDM2YjY1MzFiNjE4ZjAzNzYyNzU5MzNhMTVkMmYiLAogICAgICAiaGVhZF9maWxlX3NoYTI1NiI6ICIzMzk3YWMzY2E0OTlmZTFhOTAzMzc1YzY5YmNmZjIyMjFlZDQ5YjgwNjRjYjQ3NmUzN2ZmM2UzNjQyOTJhYmNmIgogICAgfSwKICAgICJleHBsaWNpdF9ncnVfX2hpc3RvcmljYWxfY2FwYWNpdHlfX3R1bmVfYnJhbmNoX19maWx0ZXJfam9pbnRfX3MxMDFfX2xyMHAwMDMiOiB7CiAgICAgICJjb21wbGV0ZWRfZXBvY2hzIjogMTY1LAogICAgICAiY29uZmlnX3NoYTI1NiI6ICI3MzVkNDRlOGNkMWY3NzVjZDJhYWExZDhjMWI0YWVlZjYyZDI0OTg4MDdmNzYyOTczMGNhOWMyOGJhMWFkNDk2IiwKICAgICAgImNvbnRpbnVhdGlvbl9zaGEyNTYiOiAiM2JiYWFjMDcxODc3MDM4ZDRhN2JiNjllNTY5YjYwODZmMmFmYWVlZWE4MGZhMjgxZGUyNzU0ODU1YWY3YWZmOSIsCiAgICAgICJoZWFkX2ZpbGVfc2hhMjU2IjogIjY1NTAxNDhhMjBlNjNlYjk3ODFhMjk0ZDk5NTIwZjljNzYyZjM0MGM2YzIwZjc2ODlhMTNiMDUxODAxODYyMGEiCiAgICB9CiAgfSwKICAibm9fY2Fub25pY2FsX3NvdXJjZV93cml0ZXMiOiB0cnVlLAogICJub19vd25lcnNoaXBfY2hhbmdlIjogdHJ1ZSwKICAibm9fc2NoZWR1bGVyX211dGF0aW9ucyI6IHRydWUsCiAgIm91dGJveF9hc3NldF9kaXJlY3RvcnkiOiAiL2RhdGExL2hvbWUvc3VueWlxL2hwY19tYWlsYm94L291dGJveC96aGVuamlhbmctc2l4LXNvdXJjZS1mb3VyLXRhcmdldC11a2YvZ3J1X0E0MF9BdXRvREwwMDRfZXhwb3J0XzIwMjYxMTEwXzAwMSIsCiAgInByZXNlcnZhdGlvbl9wcm9vZiI6ICJHOlxcZ2l0aHViXFxweWNoYXJtXFxwcm9qZWN0c1xcemhlbmppYW5nX2NvbXBsZXRlX2NvbXBhcmlzb25fMjAyNjEwMDZfMDAyXFxyZXN1bHRzXFxmaXhlZDIwMF8wMDNfYWN0aXZhdGlvbl8yMDI2MTAyMF8wMDFcXHByb2plY3Rpb25fcmVwYWlyXzIwMjYxMTA1XzAwMVxccGFyYWxsZWxfY29udGludWF0aW9uXzIwMjYxMTA2XzAwMVxcQTQwX2FmdGVyXzI1ODE2Nl9mYWlsdXJlXzk3Nl8wMDFcXEZBSUxVUkVfRlVMTF9TVEFURVNfUFJFU0VSVkVELmpzb24iLAogICJwcmVzZXJ2YXRpb25fcHJvb2Zfc2hhMjU2IjogImNjN2VlYTY4NmZkNmVlMWZiMzZhMzk3MWQ5YzA2MjQ4YzgxYTgyMDhhNjQ4ZTBjZjZmZDZiMDNhYzE2OGQzYWIiLAogICJyZXVzZV9leGlzdGluZ19wcmVzZXJ2YXRpb25fb25seSI6IHRydWUsCiAgInNjaGVtYSI6ICIwMDMtQTQwLWZyb3plbi1ldmlkZW5jZS1leHBvcnQtcGxhbi12MSIsCiAgInNlbGVjdGVkX3JlY2VpdmVyIjogImF1dG9kbC0wMDQiLAogICJzb3VyY2VfZmFpbGVkX2pvYiI6ICIyNTgxNjYiLAogICJzb3VyY2VfcHJlc2VydmF0aW9uX3NlcXVlbmNlIjogOTc3LAogICJzb3VyY2VfdG90YWxfYnl0ZXMiOiAzODYwMjQ3MjMsCiAgIndvcmtlcl9hY3RpdmVfcGF0aCI6ICIvZGF0YTEvaG9tZS9zdW55aXEvLmhwY19ydW5uZXJfYWN0aXZlLnNoIgp9Cg==')))
IMMUTABLE_A40_EXPORT
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
