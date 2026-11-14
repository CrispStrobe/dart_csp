import copy
import json
import unittest

from fixtures import corpus, request
from oracle import check


class PhysicalOracleTest(unittest.TestCase):
    def test_constructed_solutions_independently_pass(self):
        for case in corpus('screen'):
            req = request(case, 'test', 'cold', 0, 2)
            for i, edit in enumerate(req['edits']):
                if 'known_solution' not in edit:
                    continue
                with self.subTest(fixture=case['fixture']['id'], edit=i):
                    self.assertTrue(check(req, dict(index=i,
                                                   coordinates=edit['known_solution']))['accepted'])

    def test_false_success_and_fixed_displacement_rejected(self):
        req = request(corpus('smoke')[0], 'test', 'cold', 0, 1)
        pts = copy.deepcopy(req['edits'][0]['known_solution'])
        pts[0][0] += 1e-3
        self.assertFalse(check(req, dict(index=0, coordinates=pts,
                                        reported_success=True))['accepted'])

    def test_reflected_valid_lengths_rejected_by_branch(self):
        req = request(corpus('smoke')[0], 'test', 'cold', 0, 1)
        pts = [[-x, y] for x, y in req['edits'][0]['known_solution']]
        result = check(req, dict(index=0, coordinates=pts))
        self.assertFalse(result['accepted'])
        self.assertLess(result['max_error'], 1e-12)
        self.assertTrue(any(x.startswith('orientation:') for x in result['violations']))

    def test_contradiction_rejects_original_solution(self):
        base = corpus('smoke')[0]
        bad = corpus('smoke')[3]
        req = request(bad, 'test', 'cold', 0, 1)
        self.assertFalse(check(req, dict(index=0,
                                        coordinates=base['edits'][0]['known_solution']))['accepted'])

    def test_nonfinite_and_wrong_size_rejected(self):
        req = request(corpus('smoke')[0], 'test', 'cold', 0, 1)
        self.assertFalse(check(req, dict(index=0, coordinates=[]))['accepted'])
        pts = copy.deepcopy(req['edits'][0]['known_solution'])
        pts[1][0] = float('nan')
        self.assertFalse(check(req, dict(index=0, coordinates=pts))['accepted'])

    def test_finite_coordinates_with_overflowing_constraint_errors_rejected(self):
        for kind in ['distance', 'coincident', 'horizontal', 'vertical']:
            with self.subTest(kind=kind):
                req = dict(warmups=0, tolerance=1e-7,
                           fixture=dict(points=[[0., 0.], [1., 1.]], fixed=[],
                                        constraints=[dict(kind=kind, a=0, b=1)],
                                        orientations=[], expected_feasible=True),
                           edits=[dict(values=[1.0])])
                result = check(req, dict(index=0, coordinates=[
                    [1e308, 1e308], [-1e308, -1e308]]))
                self.assertFalse(result['accepted'])
                self.assertIsNone(result['max_error'])
                self.assertIn('constraint:0', result['violations'])
                self.assertIn('nonfinite_error:constraint:0', result['violations'])
                json.dumps(result, allow_nan=False)

    def test_overflowing_fixed_point_error_rejected_and_serializable(self):
        req = dict(warmups=0, tolerance=1e-7,
                   fixture=dict(points=[[-1e308, 0.]], fixed=[0], constraints=[],
                                orientations=[], expected_feasible=True),
                   edits=[dict(values=[])])
        result = check(req, dict(index=0, coordinates=[[1e308, 0.]]))
        self.assertFalse(result['accepted'])
        self.assertIsNone(result['max_error'])
        self.assertIn('nonfinite_error:fixed:0', result['violations'])
        json.dumps(result, allow_nan=False)

    def test_nonfinite_derived_orientation_rejected_and_serializable(self):
        req = dict(warmups=0, tolerance=1e-7,
                   fixture=dict(points=[[0., 0.], [1., 0.], [0., 1.]], fixed=[],
                                constraints=[], orientations=[[0, 1, 2, 1]],
                                expected_feasible=True),
                   edits=[dict(values=[])])
        # The first cross product overflows to infinity; the second is NaN
        # from subtracting two infinite products. Every coordinate is finite.
        for points in [[[0., 0.], [1e308, 0.], [0., 1e308]],
                       [[0., 0.], [1e308, 1e308], [-1e308, -1e308]]]:
            with self.subTest(points=points):
                result = check(req, dict(index=0, coordinates=points))
                self.assertFalse(result['accepted'])
                self.assertIsNone(result['max_error'])
                self.assertIn('nonfinite_error:orientation:0', result['violations'])
                json.dumps(result, allow_nan=False)

    def test_large_finite_distance_remains_valid(self):
        req = dict(warmups=0, tolerance=1e-7,
                   fixture=dict(points=[[0., 0.], [1e308, 0.]], fixed=[],
                                constraints=[dict(kind='distance', a=0, b=1)],
                                orientations=[], expected_feasible=True),
                   edits=[dict(values=[1e308])])
        result = check(req, dict(index=0, coordinates=req['fixture']['points']))
        self.assertTrue(result['accepted'])
        self.assertEqual(result['max_error'], 0.0)
        json.dumps(result, allow_nan=False)

    def test_integer_coordinate_outside_float_domain_is_rejected(self):
        req = request(corpus('smoke')[0], 'test', 'cold', 0, 1)
        points = copy.deepcopy(req['edits'][0]['known_solution'])
        points[0][0] = 10 ** 400
        result = check(req, dict(index=0, coordinates=points))
        self.assertFalse(result['accepted'])
        self.assertIsNone(result['max_error'])
        self.assertEqual(result['violations'], ['nonfinite_coordinates'])
        json.dumps(result, allow_nan=False)


if __name__ == '__main__':
    unittest.main()
