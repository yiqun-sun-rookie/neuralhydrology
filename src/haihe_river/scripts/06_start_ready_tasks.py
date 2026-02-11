#!/usr/bin/env python3
import subprocess
import sys
import re


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True, shell=False)


def parse_ready_ids(text: str):
    ids = []
    for line in text.splitlines():
        if 'READY' in line and not line.strip().startswith(('Task', 'ID', '---')):
            parts = re.split(r"\s+", line.strip())
            if parts:
                ids.append(parts[0])
    return ids


def summarize_states(text: str):
    counts = {}
    for line in text.splitlines():
        if any(s in line for s in ('READY', 'RUNNING', 'COMPLETED', 'FAILED', 'CANCELLED', 'CANCELLED')) and not line.strip().startswith(('Task', 'ID', '---')):
            parts = re.split(r"\s+", line.strip())
            if len(parts) >= 3:
                state = parts[2]
                counts[state] = counts.get(state, 0) + 1
    return counts


def main():
    # 列出任务
    lst = run(['earthengine', 'task', 'list'])
    if lst.returncode != 0:
        print('[ERROR] 无法列出任务:', lst.stderr or lst.stdout)
        sys.exit(1)
    print(lst.stdout)

    # 启动 READY 任务
    ready_ids = parse_ready_ids(lst.stdout)
    if not ready_ids:
        print('[INFO] 未发现 READY 任务。')
    else:
        print(f'[INFO] 发现 READY 任务 {len(ready_ids)} 个，开始启动...')
        for tid in ready_ids:
            p = run(['earthengine', 'task', 'start', tid])
            if p.returncode == 0:
                print('[STARTED]', tid)
            else:
                print('[WARN] 启动失败', tid, p.stderr or p.stdout)

    # 再次汇总状态
    lst2 = run(['earthengine', 'task', 'list'])
    if lst2.returncode == 0:
        counts = summarize_states(lst2.stdout)
        print('[SUMMARY]', counts)
    else:
        print('[WARN] 无法刷新任务列表')


if __name__ == '__main__':
    main()


