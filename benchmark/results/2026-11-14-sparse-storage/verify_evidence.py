"""Verify this cohort's preserved bytes without extraction or timing reruns.

This checks local evidence only. It does not contact GitHub or attest that a
remote branch contains these files. Run from any directory with Python 3.10+.
"""

import argparse
import datetime
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys
import tarfile


SOURCE_COMMIT = '4325386e689566a903309accd66aca3ced1159f7'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f'Duplicate JSON key: {key!r}')
        result[key] = value
    return result


def parse(data):
    return json.loads(data, object_pairs_hook=unique_object)


def safe_name(name, basename=False):
    require(isinstance(name, str) and name, 'Missing file name')
    path = PurePosixPath(name)
    require(not path.is_absolute() and '\\' not in name and '\0' not in name
            and ':' not in path.parts[0]
            and all(part not in ('', '.', '..') for part in name.split('/')),
            f'Unsafe path: {name!r}')
    require(not basename or len(path.parts) == 1, f'Expected basename: {name}')
    return name


def read_regular(directory, name):
    path = directory / safe_name(name)
    require(path.is_file() and not path.is_symlink(),
            f'Missing/nonregular local file: {path}')
    # Reject a parent symlink as well, so the verifier remains inside its input.
    require(path.resolve().is_relative_to(directory.resolve()),
            f'Local file escapes evidence directory: {path}')
    for parent in path.relative_to(directory).parents:
        require(not (directory / parent).is_symlink(),
                f'Symlinked parent for local file: {path}')
    return path.read_bytes()


def check_bytes(data, entry, label):
    require(type(entry.get('bytes')) is int and entry['bytes'] >= 0,
            f'Invalid byte count: {label}')
    require(isinstance(entry.get('sha256'), str)
            and re.fullmatch(r'[0-9a-f]{64}', entry['sha256']),
            f'Invalid SHA256: {label}')
    require(len(data) == entry['bytes'], f'Byte count mismatch: {label}')
    require(digest(data) == entry['sha256'], f'SHA256 mismatch: {label}')


def read_members(data, expected, label, hashes_only=False):
    require(isinstance(expected, dict), f'Invalid member manifest: {label}')
    for name in expected:
        safe_name(name)
    members = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:*') as archive:
        for member in archive:
            name = safe_name(member.name)
            require(member.isreg() and not member.issparse(),
                    f'Nonregular/sparse tar member: {label}:{name}')
            require(name not in members, f'Duplicate tar member: {label}:{name}')
            require(name in expected, f'Unlisted tar member: {label}:{name}')
            if not hashes_only:
                require(member.size == expected[name].get('bytes'),
                        f'Tar header size mismatch: {label}:{name}')
            stream = archive.extractfile(member)
            require(stream is not None, f'Unreadable member: {label}:{name}')
            content = stream.read()
            require(len(content) == member.size,
                    f'Truncated tar member: {label}:{name}')
            if hashes_only:
                require(digest(content) == expected[name],
                        f'Nested source SHA256 mismatch: {label}:{name}')
            else:
                check_bytes(content, expected[name], f'{label}:{name}')
            members[name] = content
    require(set(members) == set(expected),
            f'Missing tar members in {label}: {sorted(set(expected) - set(members))}')
    return members


def verify_archive(directory, manifest_name):
    manifest_bytes = read_regular(directory, manifest_name)
    manifest = parse(manifest_bytes)
    require(manifest.get('schema_version') == 1, 'Unknown evidence schema')
    archive_name = safe_name(manifest['archive'], basename=True)
    parts = manifest.get('archive_parts')
    parts_checked = []
    if parts is not None:
        require(isinstance(parts, list) and parts, 'Empty archive_parts')
        expected_names = [archive_name + f'.part{i:03d}' for i in range(len(parts))]
        require([part['file'] for part in parts] == expected_names,
                f'Incorrect archive part order or names: {archive_name}')
        require(sorted(path.name for path in directory.glob(archive_name + '.part*'))
                == expected_names, f'Missing/extra archive parts: {archive_name}')
        chunks = []
        for part in parts:
            safe_name(part['file'], basename=True)
            chunk = read_regular(directory, part['file'])
            check_bytes(chunk, part, part['file'])
            chunks.append(chunk)
            parts_checked.append(part['file'])
        data = b''.join(chunks)
        # A materialized joined copy, if supplied, must agree too.
        if (directory / archive_name).exists():
            require(read_regular(directory, archive_name) == data,
                    f'Joined copy disagrees with parts: {archive_name}')
    else:
        require(not list(directory.glob(archive_name + '.part*')),
                f'Unlisted archive parts: {archive_name}')
        data = read_regular(directory, archive_name)
    check_bytes(data, {'bytes': manifest['archive_bytes'],
                       'sha256': manifest['archive_sha256']}, archive_name)
    members = read_members(data, manifest['files'], archive_name)
    omitted = manifest.get('omitted_files', {})
    require(not set(omitted).intersection(members),
            f'Omitted file unexpectedly included: {archive_name}')
    for name, entry in omitted.items():
        safe_name(name)
        require(type(entry.get('bytes')) is int and entry['bytes'] >= 0
                and re.fullmatch(r'[0-9a-f]{64}', entry.get('sha256', '')),
                f'Invalid omitted-file metadata: {name}')
    return ({
        'manifest': manifest_name,
        'manifest_sha256': digest(manifest_bytes),
        'archive': archive_name,
        'archive_bytes': len(data),
        'archive_sha256': digest(data),
        'ordered_parts_verified': parts_checked,
        'regular_unique_members_verified': len(members),
        'member_bytes_verified': sum(map(len, members.values())),
        'exact_membership': True,
        'each_member_size_and_sha256': True,
        'omitted_files_not_archived': omitted,
        'passed': True,
    }, manifest, members)


def git_tree(files, prefix):
    """Reconstruct all-100644 lib/test Git trees from preserved source bytes."""
    root = {}
    for name, content in files.items():
        if not name.startswith(prefix + '/'):
            continue
        parts = name[len(prefix) + 1:].split('/')
        node = root
        for part in parts[:-1]:
            node = node.setdefault(part, {})
        node[parts[-1]] = content

    def object_id(kind, content):
        return hashlib.sha1(kind + b' ' + str(len(content)).encode() + b'\0'
                            + content).digest()

    def visit(node):
        entries = []
        for name, value in sorted(node.items(), key=lambda item:
                                  (item[0] + ('/' if isinstance(item[1], dict)
                                               else '')).encode()):
            directory = isinstance(value, dict)
            oid = visit(value) if directory else object_id(b'blob', value)
            mode = b'40000' if directory else b'100644'
            entries.append(mode + b' ' + name.encode() + b'\0' + oid)
        return object_id(b'tree', b''.join(entries))

    return visit(root).hex()


def verify_cross_references(directory, archives, source_commit):
    checks = []

    def check(condition, description):
        require(condition, description)
        checks.append(description)

    prep_name = 'preparation-4325386-evidence.json'
    _, prep_manifest, prep_files = archives[prep_name]
    prepared = parse(prep_files['prepared.json'])
    runtime_bytes = read_regular(directory, 'runtime-setup.json')
    runtime = parse(runtime_bytes)
    check(prepared['status'] == 'complete', 'Preparation status complete')
    check(runtime['compiler']['sha256'] == prepared['dart']['sha256']
          and runtime['compiler']['version'] == prepared['dart']['version'],
          'Runtime compiler identity matches preparation')
    source_results, sources = {}, {}
    for variant, item in prepared['variants'].items():
        source = item['source']
        data = prep_files[item['source_archive']]
        check(digest(data) == item['source_archive_sha256'],
              f'{variant} nested source archive SHA256 matches preparation')
        sources[variant] = read_members(data, source['source_sha256'],
                                        item['source_archive'], hashes_only=True)
        for kind in ('library', 'test'):
            prefix = 'lib' if kind == 'library' else 'test'
            check(git_tree(sources[variant], prefix) == source[kind + '_tree'],
                  f'{variant} archived {prefix} bytes reconstruct recorded Git tree')
        check(digest(sources[variant]['pubspec.lock'])
              == runtime['pubspec_lock_sha256'],
              f'{variant} archived dependency lock matches runtime')
        check(digest(sources[variant]['.dart_tool/package_config.json'])
              == runtime['package_config_sha256'],
              f'{variant} archived package configuration matches runtime')
        check(len(parse(sources[variant]['.dart_tool/package_config.json'])['packages'])
              == runtime['package_count'], f'{variant} package count matches runtime')
        build = item['build']
        check(build['exit_code'] == 0 and build['timed_out'] is False,
              f'{variant} build completed successfully')
        check(digest(json.dumps(build['command']).encode()) == build['command_sha256'],
              f'{variant} build command SHA256 matches')
        for stream in ('stdout', 'stderr'):
            check(digest(prep_files[f'{variant}/build.{stream}.log'])
                  == build[stream + '_sha256'], f'{variant} build {stream} hash matches')
        omitted = prep_manifest.get('omitted_files', {}).get(item['executable'])
        check(omitted is not None and omitted['sha256'] == item['executable_sha256'],
              f'{variant} omitted executable digest matches preparation metadata')
        source_results[variant] = dict(
            source_commit=source['source_commit'],
            library_tree=source['library_tree'], test_tree=source['test_tree'],
            source_files_verified=len(sources[variant]),
            source_bytes_verified=sum(map(len, sources[variant].values())))
    check(prepared['variants']['after']['source']['source_commit'] == source_commit,
          'Prepared candidate commit is the requested source checkpoint')

    validation = archives['validation-4325386-evidence.json'][2]
    summary_bytes = read_regular(directory, 'validation-summary.json')
    check(summary_bytes == validation['full-validation-summary.json'],
          'Standalone validation summary exactly matches archived summary')
    summary = parse(summary_bytes)
    check(summary['source_commit'] == source_commit and summary['all_passed'] is True,
          'Validation summary names the source checkpoint and passed gates')
    for kind in ('library_tree', 'test_tree'):
        check(summary[kind] == prepared['variants']['after']['source'][kind],
              f'Validation {kind} matches preserved candidate source')
    required_gates = {'format', 'analyze', 'native', 'portable-dart2js',
                      'portable-dart2wasm', 'python-comparison', 'python-tools'}
    check({gate['name'] for gate in summary['gates']} == required_gates
          and len(summary['gates']) == len(required_gates), 'Exactly seven required gates')
    gate_counts = {}
    for gate in summary['gates']:
        label = gate['name']
        metadata_bytes = validation[gate['metadata']]
        check(digest(metadata_bytes) == gate['metadata_sha256'],
              f'{label} metadata hash matches standalone validation summary')
        metadata = parse(metadata_bytes)
        for key in ('command', 'exit_code', 'frozen_source_unchanged', 'stdout',
                    'stderr', 'stdout_sha256', 'stderr_sha256'):
            check(gate[key] == metadata[key], f'{label} summary {key} matches metadata')
        check(metadata['exit_code'] == 0 and metadata['frozen_source_unchanged'] is True,
              f'{label} exit and frozen-source status passed')
        check(metadata['compiler_sha256'] == runtime['compiler']['sha256'],
              f'{label} compiler identity matches runtime')
        for stream in ('stdout', 'stderr'):
            check(digest(validation[metadata[stream]]) == metadata[stream + '_sha256'],
                  f'{label} complete {stream} log hash matches')
        for phase in ('before', 'after'):
            state = metadata[phase]
            check(not state['source_status'] and state['library_tree'] == summary['library_tree']
                  and state['test_tree'] == summary['test_tree'],
                  f'{label} {phase} frozen source trees match')
            check(state['library_file_sha256']
                  == digest(sources['after']['lib/src/geometry/sparse_ldlt.dart'])
                  and state['storage_test_sha256']
                  == digest(sources['after']['test/geometry_sparse_storage_test.dart'])
                  and state['lock_sha256'] == runtime['pubspec_lock_sha256'],
                  f'{label} {phase} library, test and lock content match archives')
        if 'dart_tests_passed' in metadata:
            output = validation[metadata['stdout']].decode()
            counts = re.findall(r'\+(\d+)(?:\s+~\d+)?(?::|\s+-\d+:) All tests passed!', output)
            check(bool(counts) and int(counts[-1]) == metadata['dart_tests_passed']
                  == gate['dart_tests_passed'], f'{label} test count matches complete log')
            gate_counts[label] = int(counts[-1])
        if 'python_tests_run' in metadata:
            output = validation[metadata['stderr']].decode()
            counts = re.findall(r'Ran (\d+) tests? in ', output)
            check(bool(counts) and int(counts[-1]) == metadata['python_tests_run']
                  == gate['python_tests_run'] and output.rstrip().endswith('OK'),
                  f'{label} test count and OK match complete log')
            gate_counts[label] = int(counts[-1])

    standalone_copies = []
    for cohort in ('targets', 'small-controls', 'dense-fill'):
        name = cohort + '-comparison.json'
        check(read_regular(directory, name)
              == archives[cohort + '-4325386-evidence.json'][2]['comparison.json'],
              f'{cohort} standalone comparison exactly matches archive')
        standalone_copies.append(name)
    cad = archives.get('cad-controls-4325386-evidence.json')
    if cad is not None:
        for path in sorted((directory / 'cad-controls').iterdir()):
            require(path.is_file() and not path.is_symlink(), 'Nonregular CAD copy')
            relative = path.relative_to(directory).as_posix()
            check(path.name in cad[2] and read_regular(directory, relative) == cad[2][path.name],
                  f'{relative} exactly matches CAD archive')
            standalone_copies.append(relative)
        for name, field in [('source-audit.json', 'source_sha256'),
                            ('process-audit.json', 'input_sha256')]:
            audit = parse(cad[2][name])
            check(audit['status'] == 'passed' and not audit['findings']
                  and audit[field] == digest(cad[2]['raw.json']),
                  f'CAD {name} refers to the preserved complete raw report')
    return dict(
        checks_passed=len(checks), checks=checks, sources=source_results,
        gate_test_counts=gate_counts, standalone_copies_verified=standalone_copies,
        runtime_metadata_sha256=digest(runtime_bytes),
        validation_summary_sha256=digest(summary_bytes),
        scope='Byte preservation and cross-reference reconciliation; no timings, numerical audits, or remote checks rerun.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=Path(__file__).resolve().parent)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--expected-archives', type=int, default=8)
    parser.add_argument('--source-commit', default=SOURCE_COMMIT)
    args = parser.parse_args()
    directory = args.directory.resolve()
    output = args.output or directory / 'archive-verification.json'
    report = dict(
        schema_version=1, verified_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        command=[sys.executable, *sys.argv], cwd=str(Path.cwd()), directory=str(directory),
        affinity=sorted(os.sched_getaffinity(0)) if hasattr(os, 'sched_getaffinity') else None,
        source_commit=args.source_commit, verifier_sha256=digest(Path(__file__).read_bytes()),
        remote_verification=False, archives=[], errors=[],
        limitations=['This is a local content-integrity check, not verification of GitHub main.',
                     'Omitted temporary AOT executables are not byte-verified; their preserved metadata is reconciled.',
                     'Runtime identities are reconciled with archived inputs; SDK binaries are not embedded here.'])
    manifests = sorted(directory.glob('*-evidence.json'))
    archives = {}
    if len(manifests) != args.expected_archives:
        report['errors'].append(f'Expected {args.expected_archives} archives, found {len(manifests)}')
    for manifest in manifests:
        try:
            result = verify_archive(directory, manifest.name)
            archives[manifest.name] = result
            report['archives'].append(result[0])
        except (ValueError, KeyError, TypeError, OSError, tarfile.TarError) as error:
            report['errors'].append(f'{manifest.name}: {error}')
    if not report['errors']:
        try:
            report['cross_references'] = verify_cross_references(directory, archives, args.source_commit)
        except (ValueError, KeyError, TypeError, OSError, tarfile.TarError) as error:
            report['errors'].append(f'Cross-reference verification: {error}')
    report['counts'] = dict(
        archive_manifests=len(manifests), archives_verified=len(archives),
        ordered_parts_verified=sum(len(a[0]['ordered_parts_verified']) for a in archives.values()),
        regular_members_verified=sum(a[0]['regular_unique_members_verified'] for a in archives.values()),
        archive_bytes_verified=sum(a[0]['archive_bytes'] for a in archives.values()),
        member_bytes_verified=sum(a[0]['member_bytes_verified'] for a in archives.values()))
    report['all_passed'] = not report['errors']
    output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'output': str(output), 'all_passed': report['all_passed'],
                      'counts': report['counts'], 'errors': report['errors']}, indent=2))
    return 0 if report['all_passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
