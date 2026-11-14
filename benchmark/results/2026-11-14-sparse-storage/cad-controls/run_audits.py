"""Wait for the original collector, then summarize and independently audit it.

Runs no Dart compiler, solver or benchmark. Invoke under taskset -c 8.
"""
from datetime import datetime, timezone
import json
from pathlib import Path
import subprocess
import sys
import time

root = Path(__file__).resolve().parent
workspace = root.parents[1]
repo = workspace / 'dart_csp'
before = workspace / 'dart_csp_baseline'
after = workspace / 'dart_csp_candidate'
previous = None
while True:
    raw = json.loads((root / 'raw.json').read_bytes())
    status = raw['status'], len(raw['runs'])
    if status != previous:
        print(f'collector status={status[0]} reports={status[1]}', flush=True)
        previous = status
    if raw['status'] == 'completed':
        break
    if raw['status'] != 'running':
        raise SystemExit('Collector did not complete successfully; do not qualify it.')
    time.sleep(10)

commands = [
    ('summary', [sys.executable, str(repo / 'tool/summarize_performance.py'),
                 'raw.json', '--output', 'summary.json']),
    ('independent-audit', [sys.executable, 'audit_control_cohort.py',
                           'raw.json', 'summary.json',
                           '--expected-before', 'd43a8b0fca74c6bc893d68ca6ec8190e74b423c9',
                           '--expected-after', '4325386e689566a903309accd66aca3ced1159f7',
                           '--rounds', '3', '--samples', '101', '--warmups', '20',
                           '--before', str(before), '--after', str(after),
                           '--output', 'independent-audit.json']),
    ('process-audit', [sys.executable, 'audit_processes.py', 'raw.json',
                       '--output', 'process-audit.json']),
    ('source-audit', [sys.executable, 'audit_source_identity.py', 'raw.json',
                      '--repo', str(repo), '--before', str(before), '--after', str(after),
                      '--output', 'source-audit.json']),
    ('independent-review', [sys.executable, 'review_storage_controls.py', '.']),
]
records = []
for label, command in commands:
    start = datetime.now(timezone.utc).isoformat()
    completed = subprocess.run(command, cwd=root, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT)
    (root / (label + '.log')).write_bytes(completed.stdout)
    records.append({'stage': label, 'command': command, 'cwd': str(root),
                    'started_at_utc': start,
                    'finished_at_utc': datetime.now(timezone.utc).isoformat(),
                    'exit_code': completed.returncode,
                    'log': label + '.log'})
    (root / 'audit-command-records.json').write_text(json.dumps(records, indent=2) + '\n')
    print(f'{label}: exit {completed.returncode}', flush=True)
    if completed.returncode:
        print(completed.stdout.decode(errors='replace'), flush=True)
        raise SystemExit(completed.returncode)
print((root / 'independent-review.log').read_text(), flush=True)
