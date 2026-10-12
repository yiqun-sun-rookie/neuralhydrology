#!/bin/bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import base64,gzip,hashlib,io,json,tarfile
from pathlib import Path
root=Path('/data1/home/sunyiq/china_radiation_16_hpc_20261012_001/execution_v1/raw_recovery_attempt1/coordinate_diagnostic_v1')
assert root.parent.is_dir() and not root.parent.is_symlink()
assert not root.exists() and not root.is_symlink()
data=(root.parent/'FAILED_BATCH_INPUTS.json').read_bytes()
assert len(data)==375103 and hashlib.sha256(data).hexdigest()=='08dd954e645ec34442c874483e5e1fdbc3f862e72c2cb9e106e75a88ca301ae9'
packet=base64.b64decode('H4sIAAAAAAACCu0Z/W/buDU/+6/QcneQjNqybCdOGkwDnNi3ZkuTInF6OHgBQUu0rVaidCKV2C26v33vkZQtf6TXDUO3YSES23rffHx875GaZwEJ0jQPI04lI2FEZzwVMgrcbHnwbxoejN7RkfqGsfXd7rY7vRKm4e3usXdyYHkH32EUQtIc1B/8f47Dw8OBXnNmCfrIQmsdDVbOspwJxiWVUcot+KOWCOYsLGKWN9MnDuQX7+4tnobMBUm1KMnSXFqzT1FW/p5TMY+jSfn4QaS8/J2K2jRPEyujEkksA34HjyWJjBJWKx94kWRLiwqLZ7Xa7c3NyPIVsUPINIoZIXUXzE3jR+bU3YzmYHht0B/1gQypSxAVgoE0BeI0YZbvW/bePUAe23ZJngqX8ccoT7k7Y9Kx767ub9+Sv9yck8uBXbcoD3dILu4HffL+8u7y/GpIBsP3lxfDOyBFdXbtbtS/xQngDN0k5alMeRQ49RrQDYbXF0PAjR9qtZBNYR1o6KCX6mc1C0ZIJQU0QlzEkclSMgG8iCz5XZpljIdOGAVSMftC5lpKw1IMfsy4g7IAIOa0c9zzzWq5+lEj3TlbhNGMCenU61pHzmSRc2WHtpAuIkFgJ0nhPNK4YMZQmud0CZbyzKVCPWh0wwrlMmM+wKdxSmXvSMudRjyCuFMMkdBPjuIr9YoiloBXkwIjQUYcgWGKxlUAmIxmhLxWcOlHXDoa4IoigSk0lKjNwVO+w+T8XYPqJR/IzYUkagbC1ypz2DOxUx+ftXsPrkyVMcZJ0dQY4tIYSFSIGDujT+xsZYWelFtk4E7mJMCSFImv/GLmBTClPwE37+Do4pk54TAcENOwODxgRKYE5sZmLDdSwNMoAldoIrRMq4n+z9EH2vf1f07BnMbTb9LibKhpusf1V/D/FW1sQQNZii4XAgWAIFwkE2/+rv0rgbAq2nE8jBIk7ZxtKJumuYrmhhXTCYutiFtjx2tYdp4+2bAGTruB2SIuEm7XH852DBWSZUJHcBhNp9qChhLp40d9hwMsUkxbYVEdOkTGyqJXNkFyYgLFfgBl2slaig6WbxejF3BXjIorJYbFYidcx3Z1MyjusWZ/rOOMqhsYICjCuk45U/59RK/u7p+Ham7RanR2MRmZOTkLIE1D+ip4GJdJJgohq0cS84yd0ydiW68sTTi2J1REnEQhGPjKsjdQygu21pkwlVCxOLkwiVA4KuVi8WgpmWBNlnLBBJaEllOqBCciq4uMdhllkzREW75ZAtK7kwgFGAf8Bi6V+0QoxI6EUr1OubpcoVljWxRBwAQuDyYfDZtLmalUXahlgw3geRX0x4iHGo467V2ZpV5NtHL+WoIxk+gaosm26ooh2SgtVU1YmNAtqliWUrX/dK0zM9oSq1iqMvewl1aVKVqjgxRyCpeE8SCFNmBmPICNjL0OfbOyCHVDCKME2yOh1e7ZKRtue0bDypuKS6RFHrDNSFTS1QRgPxi7s2gBqoBOM4xtDTDYRcPCjAPRg7uyUns11Ribnoc9JVjtTdURwfZ07IUNmW6JH33IdNo+LLCo9zOSnVmq3KkUYGrvSkTDUmCdPpWoBSZPJW+pfvVtbWP94YuSPYepxEuyVqHBKHAasTjURl2gPW/wI0jwc57Y9bXHVfGuMJcCIKbZAgXklM+Yc+S9rm8mWqUVu7Eii5mz67KpPf+shJx53fAL+aws+mI/1M28N4RpK8bYbmksZkcNVI3hGtGwvDqkpPaKfcMJY6VlzbynBSrzm7+b8EwB87fyXWO1Zf3yx75qqwOLYHcqoEbIANpHE2ubKJNESi1pHs2gjY4JzqRC8xUdsxzs3xKOMLSVLTIWSBZqIp32x7bB7hEJnRaB1SVGTJanH4AfDi8ko1CvzEwczC+lxtLl2xxgtMofIG5vMVXtHDR2gmF7HeWK+HMZoF9W+Az2fm68tDkBg3im19EagFtC0AqI4mS/jCoaYz3DOEeDXF2bn2sGyr2BpMjyLf7Y25hVjk5gMcE9bQLY11+NMqwniFcw3WYLfyPe9wlf+JWjhdmMkE4eYOss96GWiNoXGGiV7kf8SZrGzuYJA9KQ7tLrOimRLBWRjB4NsaKw/gS71VCtOvyFa1KHb5nzh1q2qvRFvXIAqCKWBlHJXyxWaV3lVagyzqJskFZnC5j3DqyywmV3VlkUFfmqQ8OwVyp26QseQUkmz7JhlGvW+jOd4F7WsTJQb49qsClRX2/6EoqNrPbNNE8/Mb7ZEf3cv7waDsh5f3Txhlxev7sf3ZlGaLuT0Nxqf3ZPjttet0qw1UIY2u0mwvZOw/D18RHrHR2zoHt0dNQJTk+Ojk677Ji1p+Ek6E5Pex120gk6weQ1a3s9dnJMT08D2vXalL3W9V3v3c36bjTutD9mmycsmbC8TEbtnoqiKsGURjEkSE0HWwwSHCvJux3jXfDa5k2JaTXTJ6HvGcpsoPM4LtHvyN9pc7YvMuB8p+84/ghWeytqmS83Sy/asL6r2N/or2OOLQKWSWuovvBSigqL5Xmaf03ov1Yon82a2hBUSlQLhR+Oeq67hGD3Q0hDE6g7F41adffqLqu8wlB9uG/f9d9DLF/c3NwOLq/7oyEZXPb/fH1zN7q8AOjbd1fD0RAKyzwLyId0gvNYXzaNN++i9houUwk12cSS3+41DETPWfjdTkP5zMcPaBF4VkgVKsIv75P2iVUzgzQPR2977RBbdVrpkw4o+NaPAnIXi2kmIJoE6OWgdztomipkvtIslGcgH47k64wDhR2aamiXQoSDOQnNl+vz0oxxlgMZYveIzinEnWoSaIBhhfcYKAdkspgEkKOVOii0kLf5DH/HKYAJLxKWR/grzVABVknf0+v8FMm55eAlY8vev663w7v7q5HJWS5I4NAoT/AuUVgQNowm65jWz+5TjnXDUdkjLJIMz6kYTg3sNNIniD3u/0zhENJQLS+Xfqf+yv4bylfnDlY2A5m6HbFvfrn+/aCbxoWY+6O8gDa3BiWvDHGVFwnBPE2IOSXppF07eBn/I2P/ux+h0vz3ef/jtU+OT3bf/3gv73++x/jhD61JxFtQDee1H+5UM2U1m1BjmrjJ/WAOsdHubb8irJBmNIczJGQ+fz7Lik5WQeFrISg2VYik4uMmKMgK0YTs2UTUBgZKfVyEzOezwvM6FQQWDd/z4Ch+5nkb+poq5ResKn8eRrnfwlcV7dY8TVhLFHwZ/dZSUyPr3A+zxPLa8Tq9ttfuEAjMFluwoFDYx3ZLX8EF6SOD2kKlZEkm263nXhxVTEgLCeX0P2BDK05nooJt/vTBBWOqPlZNyn+HZWBLDY4ZVpOlVhZlDBvPmsSb0Ca3Dn+sNjmHGn7442cNhVKKfQNUrfvr0VnT+3IIDZZXYwvVa+17D+fbtvXu19Gbm+vBzfXol9vL0fD819Hw4mYwhCA0jFADyfX9WzJ6czvsD+78tnXzbnh9ftW/2wK//evVJqRWxFESgeWP1mn39LTnndYwasH54HQRzTiN/dHw9i08fYziuEmnkuX+sbDaJ56w9qwH3vZjy0S7LWj7RIvP8TRLY7V7s6WcQyvcPLeaheoRn3uj/1KYX8bLeBkv42W8jJdxcPAPSqCXbgAoAAA=',validate=True)
manifest=json.loads('{"bytes": 2717, "sha256": "458a8284c1e4fbb41c78ced000a40da59cf556deb13280d146ac0b525517e4f0", "files": [{"name": "hpc_coordinate_diagnostic.py", "bytes": 5718, "sha256": "c08ad14888b7a0b3d413ffae674a52b48e33c5adb4e643fb3d735523b41cdb75"}, {"name": "coordinate_diagnostic.sbatch", "bytes": 1007, "sha256": "2f263cb8b2072c04bd68894432fdf4674c6bc86a8076a02e1a10cd6072eb4ddf"}]}')
assert len(packet)==manifest['bytes']<=4194304 and hashlib.sha256(packet).hexdigest()==manifest['sha256']
plain=gzip.decompress(packet);assert len(plain)<=134217728
expected={row['name']:row for row in manifest['files']};prepared=[]
with tarfile.open(fileobj=io.BytesIO(plain),mode='r:') as archive:
    members=archive.getmembers()
    assert len(members)==len(expected)==2 and {item.name for item in members}==set(expected)
    for item in members:
        assert item.isfile() and item.name==Path(item.name).name and item.size<=67108864
        data=archive.extractfile(item).read();row=expected[item.name]
        assert len(data)==item.size==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256']
        prepared.append((item.name,data))
assert sum(p.stat().st_size for p in root.parent.rglob('*') if p.is_file())+len(packet)+sum(len(data) for _,data in prepared)<=4294967296
root.mkdir()
(root/'logs').mkdir()
for name,data in prepared:
    with (root/name).open('xb') as stream:stream.write(data)
    print('OWN_COORDINATE_SOURCE_SHA256='+hashlib.sha256(data).hexdigest()+' '+name)
with (root/'DEPLOYMENT_PACKET.tar.gz').open('xb') as stream:stream.write(packet)
print('OWN_COORDINATE_DEPLOYMENT_BYTES_DONE')
PY
ROOT='/data1/home/sunyiq/china_radiation_16_hpc_20261012_001/execution_v1/raw_recovery_attempt1/coordinate_diagnostic_v1'
set +e
task_submit=$(sbatch "$ROOT/coordinate_diagnostic.sbatch" 2>&1)
task_exit=$?
set -e
printf '%s\n' "$task_submit"
printf 'OWN_COORDINATE_SUBMIT_EXIT=%s\n' "$task_exit"
test "$task_exit" = 0
if [[ "$task_submit" =~ ^Submitted\ batch\ job\ ([0-9]+)$ ]]; then
    task_job=${BASH_REMATCH[1]}
else exit 1; fi
printf '%s\n' "$task_job" > "$ROOT/OWN_COORDINATE_DIAGNOSTIC_JOB_ID.txt"
printf 'OWN_REQUEST_BUILD_JOB_ID=%s\nOWN_COORDINATE_DIAGNOSTIC_JOB_ID=%s\n' "$task_job" "$task_job"
printf 'OWN_COORDINATE_SUBMIT_DONE\n'
