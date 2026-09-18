#!/bin/bash
# seq=84 READ-ONLY status probe of the stage-3 chain submitted by seq 83 (jobs 226245-226287). Nothing is written.
# No backslash literals.
set -o pipefail
date "+wallclock %F %T %z"
date "+epoch %s"
R=/data1/home/sunyiq/precip_swap3_daily_2026_09
echo "=== A. partition ==="
sinfo -p hgpu4 -o '%.8P %.6a %.12l %.5D %.10T %N' 2>&1
echo "=== B. sacct 226245-226287 (terminal + running states) ==="
sacct -j 226245,226246,226247,226248,226249,226250,226251,226252,226253,226254,226255,226256,226257,226258,226259,226260,226261,226262,226263,226264,226265,226266,226267,226268,226269,226270,226271,226272,226273,226274,226275,226276,226277,226278,226279,226280,226281,226282,226283,226284,226285,226286,226287 -X --format=JobID,JobName%34,State%12,Elapsed,Start,End,ExitCode,NodeList%10 2>&1
echo "=== C. state counts ==="
sacct -j 226245,226246,226247,226248,226249,226250,226251,226252,226253,226254,226255,226256,226257,226258,226259,226260,226261,226262,226263,226264,226265,226266,226267,226268,226269,226270,226271,226272,226273,226274,226275,226276,226277,226278,226279,226280,226281,226282,226283,226284,226285,226286,226287 -X -n --format=State%12 2>/dev/null | sort | uniq -c
echo "=== D. queue (pswap3) ==="
squeue -u "$USER" -o '%.10i %.36j %.9T %.10M %.9P %R' 2>&1 | grep -Ei 'pswap3|JOBID'
echo "=== E. gate / guard markers and logs ==="
ls -la $R/logs/ 2>&1 | sed 's/^/  /'
for f in gate_ref.txt gate_era5l_refday.txt guard_T16_PASS.txt guard_T16.json e4_done.txt e4_not_executed.txt e4_ref_done.txt p7_hydro_year.json budget_ledger.txt; do
  [ -f "$R/logs/$f" ] && { echo "--- $f ---"; head -c 1500 "$R/logs/$f"; echo; }
done
for f in $R/logs/gate_*.txt; do [ -f "$f" ] && echo "  $(basename $f): $(head -1 $f)"; done
echo "=== F. slurm out tails (gate_ref, era5l gate, guard, any FAIL/ABORT/Error lines) ==="
for f in $(ls -t $R/logs/slurm_pswap3_gate_ref_*.out $R/logs/slurm_pswap3_gate_era5l_refday_*.out $R/logs/slurm_pswap3_guard_T16_*.out 2>/dev/null | head -3); do echo "--- $(basename $f) ---"; tail -n 12 "$f"; done
grep -lE 'FAIL|ABORT|Traceback|Error' $R/logs/slurm_*.out $R/logs/slurm_*.err 2>/dev/null | head -20 | sed 's/^/  ERRLOG /'
echo "=== G. runs/ progress ==="
echo "  run dirs: $(ls -d $R/runs/*/ 2>/dev/null | wc -l)  smoke dirs: $(ls -d $R/runs_smoke/*/ 2>/dev/null | wc -l)  s2 copies: $(ls -d $R/runs_s2_copy/*/ 2>/dev/null | wc -l)"
for d in $R/runs/*/; do [ -d "$d" ] || continue; n=$(ls $d/model_epoch*.pt 2>/dev/null | wc -l); t=$(ls $d/test/model_epoch*/test_metrics.csv 2>/dev/null | wc -l); echo "  $(basename $d) ckpt=$n test_metrics=$t"; done
echo "=== H. era5l rebuild (V25) marker + forcing dirs ==="
ls $R/data_shadow/camels_us/basin_mean_forcing/ 2>&1 | sed 's/^/  /'
echo "=== I. channel seq ==="
echo "  attrswap-daily seq now: $(cat ~/hpc_mailbox/inbox/attrswap-daily/seq 2>/dev/null)"
echo "=== DONE (read-only) ==="
