import copy
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


if __name__ == '__main__':
    unittest.main()
