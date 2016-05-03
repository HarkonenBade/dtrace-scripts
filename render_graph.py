#! /usr/bin/env python2

import json
import sys

ev_trace = []

with open(sys.argv[1], "r") as tr:
    ev_trace = json.load(tr)

files = set()
processes = {}
reads = set()
writes = set()
bins = set()
spawn = set()

for ev in ev_trace:
    if('read' in ev['event'] or
       'mmap' in ev['event']):
        reads.add((ev['path'], ev['pid'], ev['event'].split(":")[-2]))

    if 'write' in ev['event']:
        writes.add((ev['pid'], ev['path'], ev['event'].split(":")[-2]))

    if 'exec' in ev['event']:
        spawn.add((ev['ppid'], ev['pid']))
        bins.add((ev['new_exec'], ev['pid']))
    else:
        processes[ev['pid']] = ev['exec']

    if 'fork' in ev['event']:
        spawn.add((ev['pid'], ev['new_pid']))


while True:
    for ppid, pid in spawn:
        for r_path, r_pid, _ in reads:
            if r_pid == pid:
                # Process read at least one file.
                break
        else:
            for w_path, w_pid, _ in writes:
                if w_pid == pid:
                    # Process wrote at least one file.
                    break
            else:
                # New links from nodes parents to it's children
                new = [(ppid, p) for (pp, p) in spawn if pp == pid]
                # Remove node from spawn list and add new links
                spawn = set([(pp, p)
                             for (pp, p) in spawn
                             if p != pid and pp != pid] + new)
                # Remove node from binary loads
                bins = set([(f, p) for (f, p) in bins if p != pid])
                # Remove node from process list
                del processes[pid]
                break
    else:
        break

for path, pid, _ in reads:
    files.add(path)

for path, pid in bins:
    files.add(path)

for pid, path, _ in writes:
    files.add(path)

print 'strict digraph prov {'
print '    rankdir="LR";'

for path in files:
    print '    "f_{path}" [label="{path}"];'.format(path=path)

for pid, ex in processes.items():
    print('    "p{pid}" '
          '[label="{ex}\\np{pid}", shape="box"];'.format(pid=pid, ex=ex))

for path, pid, call in reads:
    print('    "f_{path}" -> "p{pid}" '
          '[label="{call}", color="black"];'.format(path=path,
                                                    pid=pid,
                                                    call=call))

for path, pid in bins:
    print('    "f_{path}" -> "p{pid}" '
          '[label="binary", color="black"];'.format(path=path, pid=pid))

for pid, path, call in writes:
    print('    "p{pid}" -> "f_{path}" '
          '[label="{call}", color="saddlebrown"];'.format(path=path,
                                                          pid=pid,
                                                          call=call))

for parent, child in spawn:
    print('    "p{parent}" -> "p{child}" '
          '[label="spawn", color="green"];'.format(parent=parent, child=child))

print '}'
