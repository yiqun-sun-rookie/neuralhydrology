#!/bin/bash
# Run all adversarial experiments on CudaLSTM h256 model
# Usage: bash src/adversarial/scripts/run_h256_all_exps.sh
set -e
cd "$(dirname "$0")/../../.."

CONFIG="src/adversarial/configs/eval_cudalstm_h256_static.yaml"
export TQDM_DISABLE=1

echo "========== Exp2: Constraint Ablation =========="
# Need physical and statistical constraints at eps=0.05, 0.1, 0.2
for constraint in physical statistical; do
  for eps in 0.05 0.1 0.2; do
    echo "--- Exp2: $constraint eps=$eps ---"
    python src/adversarial/scripts/run_adversarial_eval.py \
      --config $CONFIG \
      --attack auto_pgd --epsilon $eps --constraint $constraint --target untargeted \
      --n-samples 1 --output-suffix exp2_${constraint}_eps${eps} 2>&1 | tail -1
  done
done

echo "========== Exp3: Targeted Attacks =========="
for target in flood lowflow; do
  echo "--- Exp3: $target ---"
  python src/adversarial/scripts/run_adversarial_eval.py \
    --config $CONFIG \
    --attack auto_pgd --epsilon 0.1 --constraint lp --target $target \
    --n-samples 1 --output-suffix exp3_${target} 2>&1 | tail -1
done

echo "========== Exp4: Causal Trigger =========="
echo "--- Exp4: causal_trigger ---"
python src/adversarial/scripts/run_adversarial_eval.py \
  --config $CONFIG \
  --attack causal_trigger --epsilon 0.1 --constraint lp --target untargeted \
  --n-samples 1 --output-suffix exp4_causal 2>&1 | tail -1

echo "========== Exp5: C&W =========="
echo "--- Exp5: cw_regression ---"
python src/adversarial/scripts/run_adversarial_eval.py \
  --config $CONFIG \
  --attack cw_regression --epsilon 0.1 --constraint lp --target untargeted \
  --n-samples 1 --output-suffix exp5_cw 2>&1 | tail -1

echo "========== ALL EXPERIMENTS COMPLETE =========="
