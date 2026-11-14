"""A correct HEAD alone must not qualify a modified dependency build."""

from pathlib import Path
import subprocess
import tempfile
import unittest

from ceres_adapter.write_manifest import verified_source


class DependencyProvenanceTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name) / 'source'
        self.root.mkdir()
        self.git('init', '--quiet')
        self.git('config', 'user.name', 'Provenance test')
        self.git('config', 'user.email', 'provenance@example.invalid')
        (self.root / 'header.h').write_text('const int source_value = 1;\n')
        (self.root / '.gitignore').write_text('ignored.h\n')
        self.git('add', '.')
        self.git('commit', '--quiet', '-m', 'Pinned source')
        self.pin = self.git('rev-parse', 'HEAD')

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.root), *args],
                                       text=True, stderr=subprocess.STDOUT).strip()

    def test_clean_checkout_has_relocatable_content_identity(self):
        original = verified_source(self.root, self.pin)
        moved = self.root.with_name('relocated')
        self.root.rename(moved)
        self.assertEqual(original, verified_source(moved, self.pin))
        self.assertEqual(original['tracked_files'], 2)
        self.assertTrue(original['clean'])

    def test_changed_head_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'revision'):
            verified_source(self.root, '0' * 40)

    def test_tracked_edit_is_rejected(self):
        (self.root / 'header.h').write_text('const int source_value = 2;\n')
        with self.assertRaisesRegex(ValueError, 'clean'):
            verified_source(self.root, self.pin)

    def test_hidden_tracked_edit_is_rejected_by_actual_bytes(self):
        self.git('update-index', '--skip-worktree', 'header.h')
        (self.root / 'header.h').write_text('const int source_value = 2;\n')
        self.assertEqual(self.git('status', '--porcelain'), '')
        with self.assertRaisesRegex(ValueError, 'source bytes'):
            verified_source(self.root, self.pin)

    def test_untracked_and_ignored_headers_are_rejected(self):
        for name in ('extra.h', 'ignored.h'):
            with self.subTest(name=name):
                header = self.root / name
                header.write_text('const int unexpected = 1;\n')
                with self.assertRaisesRegex(ValueError, 'clean'):
                    verified_source(self.root, self.pin)
                header.unlink()


if __name__ == '__main__':
    unittest.main()
