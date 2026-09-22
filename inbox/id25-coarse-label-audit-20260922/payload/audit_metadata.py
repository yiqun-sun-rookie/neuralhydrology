#!/usr/bin/env python3
"""Read-only, value-free check of registered coarse spatial memberships."""

import hashlib
import json
import sys
import tarfile


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def main(archive_path):
    names = ('folds.json', 'folds_checkerboard.json', '2026-09-22-id25-coarse-label-use-path-evidence.json')
    with tarfile.open(archive_path, 'r:gz') as archive:
        require(set(archive.getnames()) == set(names), 'archive members differ')
        raw = {}
        for name in names:
            member = archive.getmember(name)
            require(member.isfile(), 'non-file archive member: ' + name)
            raw[name] = archive.extractfile(member).read()
    evidence = json.loads(raw[names[2]].decode('utf-8'))
    require(hashlib.sha256(raw[names[0]]).hexdigest() == evidence['source_hashes']['band_folds'], 'band hash mismatch')
    require(hashlib.sha256(raw[names[1]]).hexdigest() == evidence['source_hashes']['checker_folds'], 'checker hash mismatch')
    band = json.loads(raw[names[0]].decode('utf-8'))
    checker = json.loads(raw[names[1]].decode('utf-8'))
    universe = set()
    for group_ids in band['group_support_ids'].values():
        universe.update(group_ids)
    scored = set(checker['scoring_support_ids'])
    remaining = universe - scored
    records = evidence['partitions']
    require(len(universe) == 180, 'universe count mismatch')
    require(len(scored) == 119 and scored <= universe, 'scored membership mismatch')
    require(len(remaining) == 61, 'remaining count mismatch')
    require(set(row['id'] for row in records) == remaining, 'remaining IDs mismatch')
    band_folds = band['outer_folds']
    checker_folds = checker['folds']
    require(len(band_folds) == len(checker_folds) == 5, 'fold count mismatch')
    ever_band_train = 0
    ever_checker_train = 0
    hp_train = 0
    for row in records:
        support_id = row['id']
        own_band = [f['outer_fold'] for f in band_folds if support_id in f['test_support_ids']]
        band_train = sorted(f['outer_fold'] for f in band_folds if support_id in f['train_support_ids'])
        checker_test = sorted(f['fold'] for f in checker_folds if support_id in f['test_support_ids'])
        checker_train = sorted(f['fold'] for f in checker_folds if support_id in f['train_support_ids'])
        require(own_band == [row['band_test']], 'band test mismatch: ' + support_id)
        require(band_train == sorted(row['band_train']), 'band training mismatch: ' + support_id)
        require(checker_test == [row['checker_test']], 'checker test mismatch: ' + support_id)
        require(checker_train == sorted(row['checker_train']), 'checker training mismatch: ' + support_id)
        require(row['band_test'] not in band_train, 'own-fold band training: ' + support_id)
        require(row['ownfold_train_excluded'] is True, 'reported exclusion mismatch: ' + support_id)
        expected_hp = 16 * len(set(band_train) & set((0, 2)))
        require(row['hyperparameter_training_runs'] == expected_hp, 'search training mismatch: ' + support_id)
        ever_band_train += bool(band_train)
        ever_checker_train += bool(checker_train)
        hp_train += bool(expected_hp)
    require(ever_band_train == 61, 'band ever-trained count mismatch')
    require(ever_checker_train == 59, 'checker ever-trained count mismatch')
    require(hp_train == 43, 'search-trained count mismatch')
    require(evidence['summary']['issues'] == 0 and evidence['issues'] == [], 'source evidence has issues')
    print('AUDIT_PASS universe=180 scored=119 remaining=61')
    print('AUDIT_PASS own_band_fold_excluded=61 band_other_fold_training=61')
    print('AUDIT_PASS checker_other_fold_training=59 hyperparameter_training=43')
    print('NO_TARGET_VALUES_READ NO_TRAINING NO_SCORING')


if __name__ == '__main__':
    main(sys.argv[1])
