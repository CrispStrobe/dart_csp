"""Guard against deceptively successful partial or malformed benchmark output."""

import json
import pathlib
import sys
import tempfile
import unittest

from fixtures import canonical, request
from run import run_job, validate_record


class RunnerValidityTest(unittest.TestCase):
    def setUp(self):
        self.req = request(canonical()[0], 'test', 'cold', 0, 2)
        self.record = dict(schema_version=1, fixture_id='canonical_cell',
                           engine='test', mode='cold', index=0, warmup=False,
                           build_ns=20, solve_ns=50, elapsed_ns=80,
                           coordinates=self.req['edits'][0]['known_solution'],
                           reported_success=True, accepted=True)

    def test_clean_exit_with_missing_samples_is_not_rankable(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = pathlib.Path(temporary)
            script = path / 'fake.py'
            script.write_text('print(' + repr(json.dumps(self.record)) + ')\n')
            result = run_job([sys.executable, str(script)], self.req,
                             path / 'job', 5, None, 0)
            self.assertEqual(result['returncode'], 0)
            self.assertEqual(result['summary']['accepted_samples'], 1)
            self.assertFalse(result['summary']['complete'])
            self.assertFalse(result['summary']['ranking_eligible'])
            self.assertEqual(result['summary']['latency_evidence'], 'partial_or_invalid')

    def test_invalid_schema_indices_and_overlapping_times_are_rejected(self):
        for changes in (dict(schema_version=2), dict(schema_version=True),
                        dict(index=2), dict(index=True),
                        dict(elapsed_ns=50), dict(solve_ns=float('nan'))):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                validate_record({**self.record, **changes}, self.req, 0)

    def test_3d_lane_requires_usable_z_evidence(self):
        req = {**self.req, 'engine': 'dart_3d_ad'}
        record = {**self.record, 'engine': 'dart_3d_ad'}
        for z in (None, -1, float('inf')):
            with self.subTest(z=z), self.assertRaises(ValueError):
                validate_record({**record, 'max_z': z}, req, 0)
        validate_record({**record, 'max_z': 0.0}, req, 0)

    def test_boolean_coordinate_output_cannot_be_ranked(self):
        record = {**self.record, 'coordinates': [list(p) for p in self.record['coordinates']]}
        record['coordinates'][0][0] = False
        with tempfile.TemporaryDirectory() as temporary:
            path = pathlib.Path(temporary)
            script = path / 'fake.py'
            script.write_text('\n'.join('print(' + repr(json.dumps({**record, 'index': i})) + ')'
                                        for i in range(self.req['samples'])) + '\n')
            result = run_job([sys.executable, str(script)], self.req,
                             path / 'job', 5, None, 0)
            self.assertEqual(result['summary']['accepted_samples'], 0)
            self.assertGreater(result['summary']['acceptance_disagreements'], 0)
            self.assertFalse(result['summary']['ranking_eligible'])


if __name__ == '__main__':
    unittest.main()
