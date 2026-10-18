#!/usr/bin/env bash
set -euo pipefail
python3 -B - <<'ENCODER_ONLY'
import datetime,hashlib,json,math,statistics
from pathlib import Path
def stats(values):
    finite = [v for v in values if math.isfinite(v)]
    return {'count': len(values), 'nonfinite_count': len(values)-len(finite),
            'min': min(finite, default=None),
            'median': statistics.median(finite) if finite else None,
            'max': max(finite, default=None)}

def batch_row(epoch, index, row):
    ledger = row.get('stability')
    return {'epoch': epoch, 'effective_batch_index_1based': index+1,
            **{k: row.get(k) for k in ('actual_batch_size', 'loss_cm', 'gradient_norm_before_clip')},
            'stability': None if ledger is None else {k: ledger.get(k) for k in
                          ('analysis_steps', 'max_jitter', 'large_jitter_fraction')}}

def summarize_epochs(metrics, epochs):
    out = []
    for epoch in epochs:
        if epoch > len(metrics.get('train_metrics', [])):
            out.append({'epoch': epoch, 'status': 'missing_saved_formal_batches'})
            continue
        rows = metrics['train_metrics'][epoch-1]
        losses = [r['loss_cm'] for r in rows]
        norms = [r['gradient_norm_before_clip'] for r in rows]
        n = sum(r['actual_batch_size'] for r in rows)
        recorded_ledgers = [r['stability'] for r in rows if r.get('stability') is not None]
        jitters = [j for ledger in recorded_ledgers for j in ledger.get('step_jitters', [])]
        windows, hits = set(), []
        for threshold in (100, 1e6):
            first = next((i for i, r in enumerate(rows) if r['loss_cm'] > threshold), None)
            hits.append({'descriptive_loss_threshold_cm': threshold,
                         'first_batch_1based': None if first is None else first+1})
            if first is not None:
                windows.update(range(max(0, first-2), min(len(rows), first+3)))
        out.append({'epoch': epoch, 'saved_effective_batch_count': len(rows),
                    'training_window_count': n, 'loss_cm': stats(losses),
                    'gradient_norm_before_clip': stats(norms),
                    'batch_size_weighted_mean_of_batch_losses_cm':
                        math.fsum(r['loss_cm']*r['actual_batch_size'] for r in rows)/n
                        if n and all(math.isfinite(v) for v in losses) else None,
                    'mean_interpretation': 'batch-local loss summary, not recomputed global training MAE',
                    'stability': {'batches_with_stability_records':len(recorded_ledgers),
                                  'batches_with_null_or_absent_stability':len(rows)-len(recorded_ledgers),
                                  'analysis_steps_from_saved_jitters': len(jitters) if recorded_ledgers else None,
                                  'max_jitter': max(jitters, default=None),
                                  'large_jitter_steps_gt1e_6': sum(j > 1e-6 for j in jitters) if recorded_ledgers else None},
                    'actual_shuffle_sha256': metrics.get('shuffle_hashes', [])[epoch-1]
                        if epoch <= len(metrics.get('shuffle_hashes', [])) else None,
                    'first_anomaly_thresholds': hits,
                    'near_first_anomaly_batches': [batch_row(epoch, i, rows[i]) for i in sorted(windows)]})
    return out

def safe_json(x):
    if isinstance(x, float) and not math.isfinite(x):
        return str(x)
    if isinstance(x, dict):
        return {k: safe_json(v) for k, v in x.items()}
    if isinstance(x, (list, tuple)):
        return [safe_json(v) for v in x]
    return x
def main():
    base=Path('/data1/home/sunyiq')
    run='explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p003'
    current=base/'zhenjiang_complete_comparison_20261017_sqrt_recovery_001/runs'/run/'metrics.json'
    raw=current.read_bytes();metrics=json.loads(raw)
    report={'status':'saved_encoder_formal_batches_readonly',
        'checked_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'repair_of_completed_receipt':640,'run':run,'metrics_path':str(current),
        'metrics_sha256':hashlib.sha256(raw).hexdigest(),'metrics_bytes':len(raw),
        'epochs40_42':summarize_epochs(metrics,(40,41,42)),
        'null_stability_preserved_as_missing_ledger':True,
        'model_constructed':False,'checkpoint_loaded':False,
        'forward_backward_or_optimizer_step':False,'filter_batches_read':False,
        'training_input_arrays_read':False}
    hits=[]
    for threshold in (100,1e6):
        hit=None
        for epoch,rows in enumerate(metrics['train_metrics'][:42],1):
            first=next((i for i,r in enumerate(rows) if r['loss_cm']>threshold),None)
            if first is not None:
                hit={'threshold_cm':threshold,'epoch':epoch,'batch_1based':first+1,
                     'nearby_existing_batches':[batch_row(epoch,i,rows[i])
                         for i in range(max(0,first-2),min(len(rows),first+3))]}
                break
        hits.append(hit)
    report['first_descriptive_loss_threshold_hits_through_epoch42']=hits
    sources=[]
    for name,epochs,known in [
        ('zhenjiang_complete_comparison_20261006_recovery_001',(40,41),'2f73cc3ada6a36bdedd4b4caf53edf51e93f83c5dd2ec109e92d0f8bc6a445fd'),
        ('zhenjiang_complete_comparison_20261016_recovery_006',(40,41,42),None)]:
        path=base/name/'runs'/run/'metrics.json'
        info={'path':str(path),'exists':path.exists()}
        if path.exists():
            old_raw=path.read_bytes();old=json.loads(old_raw)
            info.update(sha256=hashlib.sha256(old_raw).hexdigest(),compared_epochs=list(epochs),
                formal_batches_and_shuffle_equal_current=all(
                    old['train_metrics'][e-1]==metrics['train_metrics'][e-1]
                    and old['shuffle_hashes'][e-1]==metrics['shuffle_hashes'][e-1] for e in epochs))
            if known:info['equals_recorded217_sha256']=info['sha256']==known
        sources.append(info)
    report['frozen_source_metrics_comparison']=sources
    report['finished_at_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
    print(json.dumps(safe_json(report),sort_keys=True,allow_nan=False))
try:
    main()
except Exception as exc:
    print(json.dumps({'status':'saved_encoder_formal_batches_unavailable',
        'checked_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'error':type(exc).__name__+': '+str(exc)[:400],
        'forward_backward_or_optimizer_step':False}))

ENCODER_ONLY
