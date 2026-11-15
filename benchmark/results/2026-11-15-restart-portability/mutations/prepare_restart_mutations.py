#!/usr/bin/env python3
"""Prepare isolated, precisely documented restart fault-injection copies."""
import difflib
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import tarfile

ROOT = Path('/workspace/scratch/b51b355c4f64')
REPO = ROOT / 'dart_csp'
BASE = '2596d1d1ab08b7ea2f60b50427ce161f1ebfc6d4'
OUT = ROOT / 'source_review/restart-mutations'
TEST = Path('test/lcg/restart_test.dart')
SOLVER = Path('lib/src/solver.dart')

def sha(data):
    return hashlib.sha256(data).hexdigest()

archive = subprocess.check_output(
    ['git', 'archive', BASE, 'lib', 'pubspec.yaml',
     'analysis_options.yaml', 'dart_test.yaml'], cwd=REPO)
source = subprocess.check_output(['git', 'show', f'{BASE}:{SOLVER}'], cwd=REPO).decode()
test = (REPO / TEST).read_bytes()
assert (REPO / SOLVER).read_text() == source
anchor = '        stats.restarts++;\n        _backjumpTo(0);\n'
assert source.count(anchor) == 1
variants = {
    'control': (source, 'The retained production implementation, no mutation.'),
    'phase-disabled': (
        source.replace('final saved = useRestarts ? _savedPhase[pick] : null;',
                       'final dynamic saved = null;'),
        'Ignore saved phases in the iterative decision chooser.'),
    'activity-dropped': (
        source.replace(anchor, anchor + '        _varActivity.clear();\n'),
        'Forget VSIDS variable activities immediately after restart rollback.'),
    'learned-dropped': (
        source.replace(anchor, anchor + '''        // Mutation only: delete all learned constraints after root rollback.
        for (final clause in _learnedClauses) {
          _csp.naryConstraints.removeWhere((c) => identical(c, clause));
          for (final variable in clause.vars) {
            _naryIdx[variable]?.removeWhere((c) => identical(c, clause));
          }
          _clauseWatchIndex.unregister(clause);
          _learnedClauseIdentities.remove(clause);
          _usedLearnedClauses.remove(clause);
        }
        _learnedClauses.clear();
'''),
        'Unregister and remove all learned constraints after restart rollback; keep phases/activity.'),
}
assert all(mutated != source for key, (mutated, _) in variants.items() if key != 'control')
manifest = {
    'base_commit': BASE,
    'base_lib_tree': subprocess.check_output(
        ['git', 'rev-parse', f'{BASE}:lib'], cwd=REPO, text=True).strip(),
    'base_solver_sha256': sha(source.encode()),
    'updated_test_sha256': sha(test),
    'archive_sha256': sha(archive),
    'variants': {},
}
OUT.mkdir(parents=True, exist_ok=True)
for name, (mutated, description) in variants.items():
    target = OUT / name
    target.mkdir()
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(target, filter='data')
    shutil.copy2(REPO / 'pubspec.lock', target / 'pubspec.lock')
    (target / '.dart_tool').mkdir()
    for config in ['package_config.json', 'package_graph.json']:
        path = REPO / '.dart_tool' / config
        if path.exists():
            shutil.copy2(path, target / '.dart_tool' / config)
    (target / TEST.parent).mkdir(parents=True)
    (target / TEST).write_bytes(test)
    (target / SOLVER).write_text(mutated)
    diff = ''.join(difflib.unified_diff(source.splitlines(keepends=True),
                                      mutated.splitlines(keepends=True),
                                      fromfile=str(SOLVER), tofile=str(SOLVER)))
    manifest['variants'][name] = {
        'root': str(target), 'description': description,
        'solver_sha256': sha(mutated.encode()), 'diff': diff,
    }
    (OUT / (name + '.patch')).write_text(diff)
assert (REPO / SOLVER).read_text() == source
(OUT / 'mutations.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps({'base_commit': BASE, 'variants': list(variants),
                  'updated_test_sha256': sha(test)}, indent=2))
