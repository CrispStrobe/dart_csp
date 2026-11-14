"""A broken solver must not pass qualification merely by agreeing on rejection."""

import copy
import unittest

from fixtures import canonical, request
from sparse_step.verify_geometry import verify_operation


class SparseQualificationTest(unittest.TestCase):
    def row(self, req, coordinates, accepted, **extra):
        return dict(schema_version=1, fixture_id=req['fixture']['id'],
                    engine=req['engine'], mode=req['mode'], index=0,
                    warmup=False, build_ns=1, solve_ns=2, elapsed_ns=3,
                    coordinates=coordinates, accepted=accepted, **extra)

    def test_agreed_rejection_of_feasible_geometry_is_a_failure(self):
        req = request(canonical()[0], 'test', 'cold', 0, 1)
        points = copy.deepcopy(req['edits'][0]['known_solution'])
        points[0][0] += 0.1
        with self.assertRaisesRegex(RuntimeError, 'constructed feasibility'):
            verify_operation(req, self.row(req, points, False), 0)

    def test_accepted_constructed_geometry_passes(self):
        req = request(canonical()[0], 'test', 'cold', 0, 1)
        verdict = verify_operation(req, self.row(req, req['edits'][0]['known_solution'], True), 0)
        self.assertTrue(verdict['accepted'])

    def test_physical_contradiction_rejection_passes_but_exception_does_not(self):
        cases = canonical()
        req = request(cases[3], 'test', 'cold', 0, 1)
        points = cases[0]['edits'][0]['known_solution']
        row = self.row(req, points, False)
        self.assertFalse(verify_operation(req, row, 0)['accepted'])
        with self.assertRaisesRegex(RuntimeError, 'adapter exception'):
            verify_operation(req, {**row, 'adapter_error': 'deliberate failure'}, 0)


if __name__ == '__main__':
    unittest.main()
