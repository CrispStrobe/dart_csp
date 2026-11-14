"""Check the graph certificate and physical embeddings without any solver."""
import unittest

from fixtures import corpus, laman, request
from oracle import check


class CoupledFixtureTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cases = [laman(20), *corpus('coupled')]

    def test_henneberg_certificate_and_final_topology(self):
        for case in self.cases:
            f = case['fixture']
            with self.subTest(fixture=f['id']):
                edges = {(0, 1), (0, 2), (1, 2)}
                vertices = 3
                for vertex, a, b, c in f['henneberg_ii_steps']:
                    self.assertEqual(vertex, vertices)
                    self.assertEqual(len({a, b, c}), 3)
                    self.assertTrue(all(0 <= i < vertex for i in (a, b, c)))
                    self.assertIn((a, b), edges)
                    self.assertNotEqual((a, b), (0, 1))
                    edges.remove((a, b))
                    edges.update((old, vertex) for old in (a, b, c))
                    vertices += 1
                actual = {(r['a'], r['b']) for r in f['constraints']}
                self.assertEqual(edges, actual)
                self.assertEqual(len(edges), len(f['constraints']))
                self.assertEqual(len(edges), 2 * vertices - 3)
                self.assertEqual(2 * (vertices - 2), f['geometric_free_coordinates'])
                self.assertEqual(vertices, len(f['points']))
                adjacent = [set() for _ in range(vertices)]
                for a, b in edges:
                    adjacent[a].add(b)
                    adjacent[b].add(a)
                self.assertTrue(all(len(n) >= 3 for n in adjacent))
                self.assertTrue(all(not (adjacent[a] & adjacent[b]) for a, b in edges))
                visited, pending = set(), [0]
                while pending:
                    point = pending.pop()
                    if point in visited:
                        continue
                    visited.add(point)
                    pending.extend(adjacent[point] - visited)
                self.assertEqual(len(visited), vertices)

    def test_small_graph_independently_satisfies_all_laman_subsets(self):
        # Every subset of the 12-vertex case is checked independently of the
        # construction certificate; the larger cases are certified move by move.
        f = self.cases[0]['fixture']
        edge_masks = [(1 << r['a']) | (1 << r['b']) for r in f['constraints']]
        for subset in range(1 << len(f['points'])):
            count = subset.bit_count()
            if count < 2:
                continue
            contained = sum(mask & subset == mask for mask in edge_masks)
            self.assertLessEqual(contained, 2 * count - 3)

    def test_known_embeddings_and_jittered_start(self):
        for case in self.cases:
            f = case['fixture']
            req = request(case, 'fixture_verification', 'cold', 0, 2)
            with self.subTest(fixture=f['id']):
                self.assertEqual(f['points'][:2], [[0.0, 0.0], [0.0, 1.0]])
                for i, edit in enumerate(case['edits']):
                    self.assertEqual(edit['known_solution'][:2], f['points'][:2])
                    self.assertTrue(check(req, dict(index=i, coordinates=edit['known_solution']))['accepted'])
                initial = check(req, dict(index=0, coordinates=f['points']))
                self.assertFalse(initial['accepted'], 'the seed must not be an injected exact solution')
                self.assertFalse(any(v.startswith('orientation:') for v in initial['violations']))
                self.assertGreaterEqual(f['minimum_creation_sine'], 0.08)
                self.assertLessEqual(f['seed_jitter_component_bound'], 1e-3)

    def test_deterministic_generation_and_requested_sizes(self):
        self.assertEqual(laman(20), self.cases[0])
        self.assertEqual([c['fixture']['id'] for c in self.cases[1:]],
                         ['laman_free_100', 'laman_free_500', 'laman_free_2000'])


if __name__ == '__main__':
    unittest.main()
