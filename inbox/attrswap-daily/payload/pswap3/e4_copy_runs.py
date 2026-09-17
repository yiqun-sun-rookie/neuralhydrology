"""E4 helper (PREREG_20260916 section 5.2 / V18): copy the 26 Stage-2 run directories into runs_s2_copy/ (whole
directory: config.yml, output.log, train_data/, model_epoch010/020/030.pt, test/...), rewrite run_dir / train_dir /
img_log_dir in the copied config.yml to the copy, and register sha256 of every weight file and scaler.
The source is never written. Usage: e4_copy_runs.py --src DIR --dst DIR --manifest JSON
Written with a file-write tool (not a heredoc); the only backslashes are ordinary string escapes.
"""
import argparse
import datetime
import hashlib
import json
import pathlib
import shutil
import sys


def sha16(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()[:16]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', required=True)
    ap.add_argument('--dst', required=True)
    ap.add_argument('--manifest', required=True)
    a = ap.parse_args()
    src, dst = pathlib.Path(a.src), pathlib.Path(a.dst)
    runs = sorted(d for d in src.iterdir() if d.is_dir() and d.name.endswith('_ep30') and 'INCOMPLETE_' not in d.name)
    if len(runs) != 26:
        raise SystemExit('expected 26 Stage-2 run dirs, found %d' % len(runs))
    man = dict(generated=datetime.datetime.now().isoformat(timespec='seconds'), src=str(src), dst=str(dst), runs={})
    for r in runs:
        d = dst / r.name
        if d.exists():
            print('exists, skipping copy:', d.name)
        else:
            shutil.copytree(r, d)
        cfg = d / 'config.yml'
        lines = cfg.read_text().splitlines(keepends=True)
        out = []
        i = 0
        while i < len(lines):
            ln = lines[i]
            key = ln.split(':', 1)[0].strip() if (':' in ln and not ln[:1].isspace()) else None
            if key in ('run_dir', 'train_dir', 'img_log_dir'):
                # value may be on the same line or on the next (indented) line
                val_next = (i + 1 < len(lines)) and lines[i + 1][:1].isspace() and not lines[i + 1].lstrip().startswith('-')
                sub = {'run_dir': str(d), 'train_dir': str(d / 'train_data'), 'img_log_dir': str(d / 'img_log')}[key]
                out.append(key + ': ' + sub + '\n')
                i += 2 if val_next else 1
                continue
            out.append(ln)
            i += 1
        cfg.write_text(''.join(out))
        entry = {}
        for w in ('model_epoch010.pt', 'model_epoch020.pt', 'model_epoch030.pt'):
            p = d / w
            if not p.exists():
                raise SystemExit('missing %s in %s' % (w, d.name))
            entry[w] = sha16(p)
        sc = d / 'train_data' / 'train_data_scaler.yml'
        if not sc.exists():
            raise SystemExit('missing scaler in %s' % d.name)
        entry['train_data_scaler.yml'] = sha16(sc)
        src_entry = {w: sha16(r / w) for w in ('model_epoch010.pt', 'model_epoch020.pt', 'model_epoch030.pt')}
        src_entry['train_data_scaler.yml'] = sha16(r / 'train_data' / 'train_data_scaler.yml')
        if src_entry != entry:
            raise SystemExit('copy hash mismatch in %s' % d.name)
        man['runs'][r.name] = entry
        print('copied', r.name, entry['model_epoch030.pt'])
    pathlib.Path(a.manifest).write_text(json.dumps(man, indent=1), encoding='utf-8')
    print('manifest', a.manifest, len(man['runs']), 'runs')
    return 0


if __name__ == '__main__':
    sys.exit(main())
