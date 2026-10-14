#!/bin/bash
set -eo pipefail
ROOT=/data1/home/sunyiq/china_soil_classification_12_hpc_20261014_001/runtime_recovery_v2
test ! -e "$ROOT"
test ! -e /data1/home/sunyiq/china_soil_classification_12_hpc_20261014_001/deps_v2
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY_COPY'
import hashlib,json,os,pathlib
root=pathlib.Path('/data1/home/sunyiq/china_soil_classification_12_hpc_20261014_001/runtime_recovery_v2')
source=pathlib.Path(os.environ['HOME'])/'hpc_mailbox/inbox/china-soil12-20261014/payload/runtime_recovery_v2'
members=json.loads('[{"name":"B_MISSING_SAMPLE_GEOMETRY_BYTES.geojson","local_path":"inputs/runtime_payload_v2/B_MISSING_SAMPLE_GEOMETRY_BYTES.geojson","bytes":97391,"sha256":"7c95350f5c283d73651b42dfce404615359a2feed09c719616541a0b07eea7e1","git_blob_sha1":"5779915b8427c7d34d9b5e1cb3ddc7763e2335c9"},{"name":"RUNTIME_INSTALL_CONTRACT.json","local_path":"inputs/runtime_payload_v2/RUNTIME_INSTALL_CONTRACT.json","bytes":5049,"sha256":"78eab5e89c38ab9640503ca1592558ec82b149a232da767af1a8050536f66403","git_blob_sha1":"135bcab72b5450166ac3763d8ac81e159f4ebdf7"},{"name":"runtime_install_v2.py","local_path":"inputs/runtime_payload_v2/runtime_install_v2.py","bytes":8437,"sha256":"2758ac180c2f51607c4ff0e63a04862a81fe2daf7c16ddad678d69c597eee823","git_blob_sha1":"ea2aa2ff1eae14242cf9802ab85c3159040c6eac"},{"name":"runtime_install_v2.sbatch","local_path":"inputs/runtime_payload_v2/runtime_install_v2.sbatch","bytes":986,"sha256":"f7a78068804b7d49769af66a9254e8ea56fddcb9c701d6a67dc95a9ba1583db0","git_blob_sha1":"c0ff03c557adfb89f64146d2d7033edbfce46559"},{"name":"wheel_archive_000.bin","local_path":"inputs/runtime_payload_v2/wheel_archive_000.bin","bytes":2097152,"sha256":"808404a19fa99b652b36f272ced42869521dbc13c44263a75508e4ba1315600a","git_blob_sha1":"aa42dd4da94926ef5bfd04f896cc5fb3073a4689"},{"name":"wheel_archive_001.bin","local_path":"inputs/runtime_payload_v2/wheel_archive_001.bin","bytes":2097152,"sha256":"9dfc5ea2a4a587b855adf48f4509d85c534a97dda457e97b481ddeb91d8147f0","git_blob_sha1":"f535465b1576e839d523abda48aae51eb08f0f92"},{"name":"wheel_archive_002.bin","local_path":"inputs/runtime_payload_v2/wheel_archive_002.bin","bytes":2097152,"sha256":"08bf3e87d6f119353d5edcec8c5b8d7beb1e14d071c63b5ef73b2ca668c3449d","git_blob_sha1":"b9bd0e7a3cc1d1f16344badd1dfdef4d095960a7"},{"name":"wheel_archive_003.bin","local_path":"inputs/runtime_payload_v2/wheel_archive_003.bin","bytes":2097152,"sha256":"af59b56aa62c0b790b3ff901fa01ee9516d807609a848f294610f5a10629c405","git_blob_sha1":"35a82ae0e9cbdb9ad3de6a975cf4fc29f0d616e0"},{"name":"wheel_archive_004.bin","local_path":"inputs/runtime_payload_v2/wheel_archive_004.bin","bytes":2097152,"sha256":"f923f800cfc2725f5776f7a6b205094fe0b215393d388b876843d46099ca04f3","git_blob_sha1":"fac39ce56983888fe8117e41ba0ac36d482d0223"},{"name":"wheel_archive_005.bin","local_path":"inputs/runtime_payload_v2/wheel_archive_005.bin","bytes":2097152,"sha256":"38c6603e84d0e8e8cc6051835a71b42c1a0831b5c6d185c5d20381e7fc7820ff","git_blob_sha1":"a0fcfbbe56079b0332ab9457dc89da08fe1c6c49"},{"name":"wheel_archive_006.bin","local_path":"inputs/runtime_payload_v2/wheel_archive_006.bin","bytes":2097152,"sha256":"3c2893d054407460629035f5e00a1f9812787097fb1ddece47c2004b9faca370","git_blob_sha1":"7b0351c77cb9cbb6e0e5b3919f737f66725a8265"},{"name":"wheel_archive_007.bin","local_path":"inputs/runtime_payload_v2/wheel_archive_007.bin","bytes":2097152,"sha256":"8a0f2c19ff8d7f19aea13b2e136eb8a59bb433b488b1aa50e3b0087abadfdd92","git_blob_sha1":"92d28c56337c547f64d09740063cff13be1773e4"},{"name":"wheel_archive_008.bin","local_path":"inputs/runtime_payload_v2/wheel_archive_008.bin","bytes":2097152,"sha256":"1a7e7c99187c769339cc32f83c79247d5f19fc04bafc0eb5d86ddb78b458570b","git_blob_sha1":"8038dd18c3f3e0e71436e863ffb65631bcbf9731"},{"name":"wheel_archive_009.bin","local_path":"inputs/runtime_payload_v2/wheel_archive_009.bin","bytes":2097152,"sha256":"e67d6748ad0674371aa145a2887e7b9935bd899a5066a4678292551f21459e99","git_blob_sha1":"e561086c246d14a2078982913df1a3b1ce14a655"},{"name":"wheel_archive_010.bin","local_path":"inputs/runtime_payload_v2/wheel_archive_010.bin","bytes":2097152,"sha256":"b474de3cd9a9c9dd59a45fc26878bc38c8bbc3a4ee2335c18b65e973497ec6d0","git_blob_sha1":"b05948d14d7ffc730a7d91da2dc0b46f7a5bac25"},{"name":"wheel_archive_011.bin","local_path":"inputs/runtime_payload_v2/wheel_archive_011.bin","bytes":2097152,"sha256":"41923048bdb7da7414a408a86c513c57a5f55b0cc03dd89c22ac50e28d4df143","git_blob_sha1":"830e26147af3cd98e5b3fefe3538970a857dd50d"},{"name":"wheel_archive_012.bin","local_path":"inputs/runtime_payload_v2/wheel_archive_012.bin","bytes":2097152,"sha256":"8a094cd5018440e63e8a905c3779e9ab1768b945e38bd2f6031caabd8b211b02","git_blob_sha1":"d3aac74939bd8f4895ed1e422e8289e6c976cf13"},{"name":"wheel_archive_013.bin","local_path":"inputs/runtime_payload_v2/wheel_archive_013.bin","bytes":2097152,"sha256":"12ca2823fbefaa8eb5c67aeb1cf9fc86781d85f9d17c4dc1258e09c2e0d90127","git_blob_sha1":"56efd84d7e4fe79dfb64d5b1e2da3ae96b2e2d8b"},{"name":"wheel_archive_014.bin","local_path":"inputs/runtime_payload_v2/wheel_archive_014.bin","bytes":2097152,"sha256":"12607e6c3d0a013e929f53614cf898d409bfec90106cfe842018f5276434f6b6","git_blob_sha1":"d37e00f44f776124f680a51b28e557a2daccd8ff"},{"name":"wheel_archive_015.bin","local_path":"inputs/runtime_payload_v2/wheel_archive_015.bin","bytes":2097152,"sha256":"246997789438ed24faa822bf3cceae32188441cddb9f4c41d9194a7fb430fe1d","git_blob_sha1":"46d6487b699b21593f4b8d16a214970d1e27e9b8"},{"name":"wheel_archive_016.bin","local_path":"inputs/runtime_payload_v2/wheel_archive_016.bin","bytes":806898,"sha256":"accde21925cc9f101b7a85a3802041e1cf84daa80e9b581870141e69b6a9c844","git_blob_sha1":"e1cc6994b97e30f3bad6987eaddabc2e7f0d81e0"}]')
archive=json.loads('{"bytes":34361330,"sha256":"3a1436ba60b74410fa13a809659a7ce77a2cb1ae58b44b616f871fb85a86a4c3"}')
chunks=json.loads('["wheel_archive_000.bin","wheel_archive_001.bin","wheel_archive_002.bin","wheel_archive_003.bin","wheel_archive_004.bin","wheel_archive_005.bin","wheel_archive_006.bin","wheel_archive_007.bin","wheel_archive_008.bin","wheel_archive_009.bin","wheel_archive_010.bin","wheel_archive_011.bin","wheel_archive_012.bin","wheel_archive_013.bin","wheel_archive_014.bin","wheel_archive_015.bin","wheel_archive_016.bin"]')
assert not root.exists() and len(members)<=24 and sum(x['bytes'] for x in members)<=41943040
contents={}
for row in members:
    assert pathlib.Path(row['name']).name==row['name'] and 0<row['bytes']<=2097152
    path=source/row['name']
    assert path.is_file() and not path.is_symlink() and path.stat().st_size==row['bytes']
    raw=path.read_bytes()
    assert len(raw)==row['bytes'] and hashlib.sha256(raw).hexdigest()==row['sha256']
    contents[row['name']]=raw
raw_archive=b''.join(contents[x] for x in chunks)
assert len(raw_archive)==archive['bytes'] and hashlib.sha256(raw_archive).hexdigest()==archive['sha256']
assert set(contents)-set(chunks)=={'runtime_install_v2.py','runtime_install_v2.sbatch','RUNTIME_INSTALL_CONTRACT.json','B_MISSING_SAMPLE_GEOMETRY_BYTES.geojson'}
root.mkdir()
(root/'logs').mkdir()
for name,raw in contents.items():
    if name not in chunks:
        with (root/name).open('xb') as f:f.write(raw)
with (root/'WHEEL_ORIGINAL_BYTES.zip').open('xb') as f:f.write(raw_archive)
print('OWN_RUNTIME_PAYLOAD_FILES='+str(len(members)))
print('OWN_RUNTIME_PAYLOAD_BYTES='+str(sum(x['bytes'] for x in members)))
print('OWN_RUNTIME_ORIGINAL_ARRAY_READS=0')
print('OWN_RUNTIME_WHEEL_EXTERNAL_GETS=0')
PY_COPY
cd "$ROOT"
test ! -e OWN_RUNTIME_SUBMIT_STARTED
test ! -e OWN_RUNTIME_JOB_ID
printf 'ONE_SUBMISSION_ONLY\n' > OWN_RUNTIME_SUBMIT_STARTED
set +e
submit_output=$(sbatch runtime_install_v2.sbatch 2>&1)
submit_exit=$?
set -e
printf '%s\n' "$submit_output"
printf 'OWN_RUNTIME_SUBMIT_EXIT=%s\n' "$submit_exit"
test "$submit_exit" = 0
job=$(printf '%s\n' "$submit_output" | sed -n 's/^Submitted batch job \([0-9][0-9]*\)$/\1/p')
test -n "$job"
test "$(printf '%s\n' "$job" | wc -l)" = 1
printf '%s\n' "$job" > OWN_RUNTIME_JOB_ID
printf 'OWN_RUNTIME_JOB_ID=%s\n' "$job"
printf 'OWN_RUNTIME_SUBMIT_DONE\n'
