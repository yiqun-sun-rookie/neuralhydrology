#!/bin/bash
# seq=8 — 严格重测网络（TCP 层 vs 应用层，各测 3 次看稳定性）。
# 起因：seq=7 的 TCP 探测结果与更早的 curl 测试矛盾，需要判定到底哪层被挡。

echo "=== A TCP LAYER x3 ==="
for round in 1 2 3; do
  printf "round%d: " $round
  printf "gh22="; timeout 6 bash -c '</dev/tcp/20.205.243.166/22'  2>/dev/null && printf "OK " || printf "FAIL "
  printf "gh443="; timeout 6 bash -c '</dev/tcp/20.205.243.166/443' 2>/dev/null && printf "OK " || printf "FAIL "
  printf "pypi443="; timeout 6 bash -c '</dev/tcp/151.101.128.223/443' 2>/dev/null && printf "OK" || printf "FAIL"
  echo
done

echo; echo "=== B APPLICATION LAYER (curl, 20s timeout each) ==="
echo -n "github.com     : "
timeout 25 curl -sS -o /dev/null -m 20 -w "http=%{http_code} tls=%{time_appconnect}s total=%{time_total}s\n" https://github.com 2>&1 | tail -1
echo -n "api.github.com : "
timeout 25 curl -sS -o /dev/null -m 20 -w "http=%{http_code} total=%{time_total}s\n" https://api.github.com 2>&1 | tail -1
echo -n "pypi.org       : "
timeout 25 curl -sS -o /dev/null -m 20 -w "http=%{http_code} total=%{time_total}s\n" https://pypi.org/simple/ 2>&1 | tail -1
echo -n "files.pythonhosted: "
timeout 25 curl -sS -o /dev/null -m 20 -w "http=%{http_code} total=%{time_total}s\n" https://files.pythonhosted.org 2>&1 | tail -1

echo; echo "=== C REAL GIT OPS (the thing that actually matters) ==="
cd /tmp && rm -rf _nettest && mkdir _nettest && cd _nettest && git init -q 2>/dev/null
echo -n "git ls-remote via HTTPS: "
timeout 40 git ls-remote https://github.com/yiqun-sun-rookie/neuralhydrology.git HEAD 2>&1 | head -1
echo -n "git ls-remote via SSH  : "
timeout 40 git ls-remote git@github.com:yiqun-sun-rookie/neuralhydrology.git HEAD 2>&1 | head -1
cd /tmp && rm -rf _nettest

echo; echo "=== D REAL PIP (dry, no install) ==="
source /data1/home/$USER/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null
timeout 40 pip download --no-deps --dest /tmp/_piptest six 2>&1 | tail -3
rm -rf /tmp/_piptest

echo; echo "=== E PROXY ENV ==="
env | grep -i proxy || echo "(none)"
cat ~/.condarc 2>/dev/null | head -10 || echo "(no .condarc)"
grep -is "index-url\|proxy" ~/.pip/pip.conf ~/.config/pip/pip.conf 2>/dev/null || echo "(no pip.conf proxy/index)"

echo; echo "=== F WHERE ARE THE 531 RESULTS? ==="
ls -d ~/neuralhydrology/results/*/ 2>/dev/null | head -20 || echo "no results/ subdirs"
echo "--- any 531 anywhere ---"
find ~/neuralhydrology/results -maxdepth 2 -name "*531*" 2>/dev/null | head -10 || echo none
