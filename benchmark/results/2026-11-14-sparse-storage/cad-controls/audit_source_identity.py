"""Cross-check serialized control source/config hashes against Git and live files.

No solver, compiler, collector, summarizer, or existing auditor is imported.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import urllib.parse
import urllib.request


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('raw', type=Path)
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--before', type=Path, required=True)
    parser.add_argument('--after', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    encoded = args.raw.read_bytes()
    raw = json.loads(encoded)
    findings = []
    checks = 0
    counts = {'committed_library_blobs': 0, 'live_library_files': 0,
              'committed_harness_and_fixture_blobs': 0}

    def check(condition, description):
        nonlocal checks
        checks += 1
        if not condition:
            findings.append(description)

    def git(*arguments, data=None):
        return subprocess.run(['git', '-C', str(args.repo), *arguments],
                              input=data, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, check=True).stdout

    def blob_hashes(commit, paths):
        query = ''.join(f'{commit}:{path}\n' for path in paths).encode()
        data = git('cat-file', '--batch', data=query)
        offset, hashes = 0, {}
        for path in paths:
            end = data.index(b'\n', offset)
            header = data[offset:end].decode().split()
            if len(header) != 3 or header[1] != 'blob':
                raise ValueError(f'Not a committed blob: {commit}:{path}')
            size = int(header[2])
            offset = end + 1
            hashes[path] = digest(data[offset:offset + size])
            offset += size + 1
        check(offset == len(data), [commit, 'complete Git blob stream'])
        return hashes

    expected = {
        'before': 'd43a8b0fca74c6bc893d68ca6ec8190e74b423c9',
        'after': '4325386e689566a903309accd66aca3ced1159f7',
    }
    check(raw['status'] == 'completed', 'completed cohort')
    check(raw['hardware']['cpu_affinity'] == [0], 'benchmark processes inherit CPU 0 affinity')
    check(raw['rounds'] == 3 and raw['modes'] == ['jit', 'aot'] and
          raw['diagnostic_only'] is False, 'three-round both-mode ordinary cohort')
    differences = git('diff', '--name-only', expected['before'], expected['after'],
                      '--', 'lib').decode().splitlines()
    check(differences == ['lib/src/geometry/sparse_ldlt.dart'],
          'sole library difference is packed sparse factor source')
    provenance = {}
    for label, root in [('before', args.before), ('after', args.after)]:
        identity = raw['revisions'][label]
        commit = expected[label]
        check(identity['commit'] == commit, [label, 'expected exact commit'])
        check(identity['library_diff_sha256'] is None, [label, 'clean recorded library'])
        tree = git('rev-parse', commit + ':lib').decode().strip()
        check(identity['library_tree'] == tree, [label, 'committed library tree'])
        entries = git('ls-tree', '-r', '-z', commit, '--', 'lib').split(b'\0')
        paths = [entry.split(b'\t', 1)[1].decode() for entry in entries if entry]
        hashes = blob_hashes(commit, paths)
        check(identity['library_file_sha256'] == hashes,
              [label, 'complete recorded source inventory and hashes'])
        counts['committed_library_blobs'] += len(paths)
        live = {str(path.relative_to(root)): digest(path.read_bytes())
                for path in sorted((root / 'lib').rglob('*')) if path.is_file()}
        check(live == hashes, [label, 'complete live source inventory and hashes'])
        counts['live_library_files'] += len(live)
        mapping = identity['package_mapping']
        config = Path(mapping['file'])
        check(Path(mapping['resolved_root']).resolve() == root.resolve(),
              [label, 'recorded root is supplied frozen worktree'])
        check(Path(mapping['resolved_library']).resolve() == (root / 'lib').resolve(),
              [label, 'recorded package library path'])
        check(digest(config.read_bytes()) == identity['package_config_sha256'],
              [label, 'live package configuration hash'])
        own = [item for item in json.loads(config.read_bytes())['packages']
               if item['name'] == 'dart_csp']
        check(len(own) == 1, [label, 'one actual dart_csp package mapping'])
        if len(own) != 1:
            raise ValueError('Cannot independently resolve dart_csp package')
        root_uri = urllib.parse.urljoin(config.resolve().as_uri(), own[0]['rootUri'])
        library_uri = urllib.parse.urljoin(root_uri, own[0].get('packageUri', ''))
        for uri, expected_path, kind in [(root_uri, root, 'root'),
                                         (library_uri, root / 'lib', 'library')]:
            parsed = urllib.parse.urlparse(uri)
            check(parsed.scheme == 'file' and parsed.netloc in ('', 'localhost')
                  and not parsed.query and not parsed.fragment,
                  [label, kind, 'package resolves to a local file URI'])
            check(Path(urllib.request.url2pathname(parsed.path)).resolve() == expected_path.resolve(),
                  [label, kind, 'independently resolved effective package path'])
        check(digest((root / 'pubspec.lock').read_bytes()) == identity['dependency_lock_sha256'],
              [label, 'live dependency lock hash'])
        for name, harness in raw['harnesses'].items():
            declared = {harness['file']: harness['sha256'],
                        **harness.get('dependency_sha256', {})}
            check(blob_hashes(commit, list(declared)) == declared,
                  [label, name, 'committed harness and fixture hashes'])
            check(all(digest((root / path).read_bytes()) == value
                      for path, value in declared.items()),
                  [label, name, 'live harness and fixture hashes'])
            counts['committed_harness_and_fixture_blobs'] += len(declared)
        provenance[label] = {'commit': commit, 'library_tree': tree,
                             'library_files': len(paths)}
    check(len({identity['dependency_lock_sha256']
               for identity in raw['revisions'].values()}) == 1,
          'same dependency lock for both sources')
    report = {'status': 'passed' if not findings else 'failed',
              'checks': checks, 'counts': counts, 'findings': findings,
              'source': args.raw.name, 'source_sha256': digest(encoded),
              'provenance': provenance,
              'library_differences': differences,
              'method': 'Independent committed blob stream, complete live file inventory, package config, lock and harness hash comparison.',
              'limitations': ['This collector does not hash SDK or AOT executable bytes or installed dependency package source bytes.',
                              'The recorded CPU affinity supports inherited pinning, not exclusive CPU ownership.']}
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    return int(bool(findings))


if __name__ == '__main__':
    raise SystemExit(main())
