#!/bin/bash
# Read-only retrieval for the authorized LOCAL size-16 candidate evaluation.
set -eo pipefail
EXP=/data1/home/sunyiq/kalmannet_wrr_hp_extension_20260902/repo/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902
cd "$EXP"
sha256sum -c <<'CHECKPOINT_HASHES'
9ecbbfc4605f4bb3e99975f05fd1924f81aa3d85568f460498bf3e372278368d  runs/formal_seed42_gpu/idx0003_lr0p01_hs32_nl1_mult10/results/best_model.pt
e97a2b7468e8c7adad339beccffb86a1f70b5a0fcccaf73ff39d48e72044aafc  runs/formal_seed42_gpu/idx0009_lr0p01_hs16_nl1_mult10/results/best_model.pt
b572c8e8278b038cff7d0bc278ca276947dd63cd02e4d77df5a630db893c5516  runs/formal_seed43_gpu/idx0015_lr0p01_hs32_nl1_mult10/results/best_model.pt
6c8b9c8e132d60f0b423cc81c3d190b1eaf8ea17e12b4901ceeaa20172fcc003  runs/formal_seed44_gpu/idx0016_lr0p01_hs32_nl1_mult10/results/best_model.pt
62ad6a9f2d73073405a1d155316041af80f2f4819fff3467c318f52a27f655cb  runs/formal_seed43_gpu/idx0018_lr0p01_hs16_nl1_mult10/results/best_model.pt
9a4e49c0e68374f89acd622e189558ba89df1053bfa0645a881c7c85bf1df2af  runs/formal_seed44_gpu/idx0019_lr0p01_hs16_nl1_mult10/results/best_model.pt
CHECKPOINT_HASHES
echo '=== CHECKPOINT_ARCHIVE_B64 ==='
tar -cf - -- \
 runs/formal_seed42_gpu/idx0003_lr0p01_hs32_nl1_mult10/results/best_model.pt \
 runs/formal_seed42_gpu/idx0003_lr0p01_hs32_nl1_mult10/config_used.yaml \
 runs/formal_seed42_gpu/idx0009_lr0p01_hs16_nl1_mult10/results/best_model.pt \
 runs/formal_seed42_gpu/idx0009_lr0p01_hs16_nl1_mult10/config_used.yaml \
 runs/formal_seed43_gpu/idx0015_lr0p01_hs32_nl1_mult10/results/best_model.pt \
 runs/formal_seed43_gpu/idx0015_lr0p01_hs32_nl1_mult10/config_used.yaml \
 runs/formal_seed44_gpu/idx0016_lr0p01_hs32_nl1_mult10/results/best_model.pt \
 runs/formal_seed44_gpu/idx0016_lr0p01_hs32_nl1_mult10/config_used.yaml \
 runs/formal_seed43_gpu/idx0018_lr0p01_hs16_nl1_mult10/results/best_model.pt \
 runs/formal_seed43_gpu/idx0018_lr0p01_hs16_nl1_mult10/config_used.yaml \
 runs/formal_seed44_gpu/idx0019_lr0p01_hs16_nl1_mult10/results/best_model.pt \
 runs/formal_seed44_gpu/idx0019_lr0p01_hs16_nl1_mult10/config_used.yaml \
 | gzip -n | base64 -w 120
echo '=== END_CHECKPOINT_ARCHIVE_B64 ==='
