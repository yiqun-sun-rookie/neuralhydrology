#!/bin/bash
# Restore model weights from git history (commit 62ce1ab)
set -e
cd ~/neuralhydrology

DIR=results/05_full_531_basins/full_training_nse_2025_1025_1821_ep50
mkdir -p $DIR/train_data

git show 62ce1ab:$DIR/model_epoch050.pt > $DIR/model_epoch050.pt
git show 62ce1ab:$DIR/config.yml > $DIR/config.yml
git show 62ce1ab:$DIR/train_data/train_data_scaler.yml > $DIR/train_data/train_data_scaler.yml

echo "Restored:"
ls -lh $DIR/model_epoch050.pt $DIR/config.yml $DIR/train_data/train_data_scaler.yml
