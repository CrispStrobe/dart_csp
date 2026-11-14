"""Deterministic physical sketches and edit traces shared by all adapters."""

from __future__ import annotations

import argparse
import json
import math
import pathlib
import random


def ladder(cells: int, *, components: int = 1, scale: float = 1.0,
           offset: float = 0.0, redundant: bool = False) -> dict:
    """A grounded triangulated ladder with 4*cells free planar coordinates.

    Every cell has bottom/top horizontal bars, a right rung and a diagonal.
    Only the first two points of each disconnected component are fixed. The
    equations are nonlinear distances; all known solutions follow from a
    constructed Cartesian embedding, not from a candidate solver.
    """
    rng = random.Random(20261114)
    points, fixed, constraints, orientations = [], [], [], []
    solutions = [[], []]
    values = [[], []]
    height = 0.7 * scale
    pitches = [scale, 1.003 * scale]
    for component in range(components):
        start = len(points)
        origin_y = offset + component * 3.0 * scale
        for col in range(cells + 1):
            for row in range(2):
                x, y = offset + col * scale, origin_y + row * height
                if col:
                    x += (rng.random() - 0.5) * 0.004 * scale
                    y += (rng.random() - 0.5) * 0.004 * scale
                points.append([x, y])
                for e, pitch in enumerate(pitches):
                    solutions[e].append([offset + col * pitch,
                                         origin_y + row * height])
        fixed.extend([start, start + 1])
        for col in range(cells):
            a, b = start + 2 * col, start + 2 * col + 1
            c, d = a + 2, b + 2
            for p, q, kind in [(a, c, 'pitch'), (b, d, 'pitch'),
                               (c, d, 'rung'), (a, d, 'diagonal')]:
                targets = [height if kind == 'rung' else pitch if kind == 'pitch'
                           else math.hypot(pitch, height) for pitch in pitches]
                constraints.append(dict(kind='distance', a=p, b=q,
                                        value=targets[0]))
                for e in range(2):
                    values[e].append(targets[e])
            orientations.extend([[a, c, d, 1], [a, d, b, 1]])
        if redundant:
            # An exact duplicate is redundant without changing physical roots.
            first = len(constraints) - 4 * cells
            constraints.append(dict(constraints[first]))
            for e in range(2):
                values[e].append(values[e][first])
    identity = f'ladder_{cells}_components_{components}'
    if redundant:
        identity += '_redundant'
    if scale != 1:
        identity += f'_scale_{scale:g}'
    if offset:
        identity += f'_offset_{offset:g}'
    fixture = dict(id=identity, family='nonlinear_triangulated_ladder',
                   points=points, fixed=fixed, constraints=constraints,
                   orientations=orientations, expected_feasible=True,
                   geometric_free_coordinates=4 * cells * components,
                   logical_components=components, unit_scale=scale,
                   description='One grounded nonlinear distance ladder per component; '
                               'consistent pitch edits and prescribed triangle branches.')
    return dict(fixture=fixture, edits=[dict(values=v, known_solution=s)
                                       for v, s in zip(values, solutions)])


def _henneberg_ii_graph(vertices: int) -> tuple[set[tuple[int, int]], list[list[int]],
                                             list[set[int]]]:
    """Return a Laman graph and its replayable Henneberg-II certificate.

    Each move deletes an existing edge and joins a new vertex to its two
    endpoints and a distinct third old vertex. This preserves (2,3)-tightness
    from the starting triangle. The anchor edge is never removed. The first
    three moves produce K3,3; later choices eliminate triangles where possible
    and prefer low-degree third vertices. All tie breaks use sorted candidates.
    """
    rng = random.Random(20261114)
    edges = {(0, 1), (0, 2), (1, 2)}
    adjacent = [{1, 2}, {0, 2}, {0, 1}]
    history = []
    initial_moves = [(0, 2, 1), (1, 3, 0), (0, 4, 2)]
    for vertex in range(3, vertices):
        if vertex < 6:
            a, b, c = initial_moves[vertex - 3]
        else:
            candidates = sorted(edge for edge in edges if edge != (0, 1))
            triangle_edges = [(len(adjacent[a] & adjacent[b]), a, b)
                              for a, b in candidates if adjacent[a] & adjacent[b]]
            if triangle_edges:
                most = max(count for count, _, _ in triangle_edges)
                candidates = [(a, b) for count, a, b in triangle_edges if count == most]
            a, b = rng.choice(candidates)
            thirds = [i for i in range(vertex) if i != a and i != b]
            costs = {i: (int(i in adjacent[a]) + int(i in adjacent[b]),
                         len(adjacent[i])) for i in thirds}
            best = min(costs.values())
            c = rng.choice([i for i in thirds if costs[i] == best])
        if (a, b) not in edges or (a, b) == (0, 1) or c in (a, b):
            raise AssertionError('invalid Henneberg-II construction move')
        edges.remove((a, b))
        adjacent[a].remove(b)
        adjacent[b].remove(a)
        adjacent.append({a, b, c})
        for old in (a, b, c):
            edges.add((old, vertex))
            adjacent[old].add(vertex)
        history.append([vertex, a, b, c])
    return edges, history, adjacent


def _cross(points: list[list[float]], a: int, b: int, c: int) -> float:
    pa, pb, pc = points[a], points[b], points[c]
    return ((pb[0] - pa[0]) * (pc[1] - pa[1])
            - (pb[1] - pa[1]) * (pc[0] - pa[0]))


def laman(free_coordinates: int) -> dict:
    """A triangle-free Henneberg-II framework, with two fixed anchor points.

    The graph has 2*V-3 edges; its protected anchor edge is a satisfied constant
    relation, leaving exactly 2*(V-2) unfixed scalar coordinates and that many
    variable distance relations. The construction certifies generic local
    rigidity, not global uniqueness or numerical conditioning of every pose.

    Coordinates are independently sampled in a moderate box, rejecting nearly
    collinear creation triples. Both target embeddings are constructed directly;
    the second stretches x by 1.003, which leaves the anchors unchanged. Solvers
    receive only the lightly jittered initial points as their initial state.
    This remains a distance-heavy, near-root experiment, not a global search test.
    """
    if free_coordinates < 20 or free_coordinates % 4:
        raise ValueError('free_coordinates must be a multiple of four and at least 20')
    vertices = free_coordinates // 2 + 2
    edges, history, adjacent = _henneberg_ii_graph(vertices)
    triangles = sum(len(adjacent[a] & adjacent[b]) for a, b in edges) // 3
    if triangles:
        raise AssertionError('coupled family must have no triangles in its final graph')

    geometry_rng = random.Random(20261115)
    ideal = [[0.0, 0.0], [0.0, 1.0], [1.1, 0.4]]
    triples = [[0, 1, 2]]
    minimum_sine = 1.0
    for vertex, a, b, c in history:
        pairs = [(a, b), (a, c), (b, c)]
        for _ in range(10000):
            candidate = [geometry_rng.uniform(-2.5, 2.5),
                         geometry_rng.uniform(-2.5, 2.5)]
            if min(math.dist(candidate, ideal[i]) for i in (a, b, c)) < 0.15:
                continue
            sines = []
            for p, q in pairs:
                u = [ideal[q][k] - ideal[p][k] for k in (0, 1)]
                v = [candidate[k] - ideal[p][k] for k in (0, 1)]
                denom = math.hypot(*u) * math.hypot(*v)
                sines.append(abs(u[0] * v[1] - u[1] * v[0]) / denom
                             if denom else 0.0)
            if min(sines) >= 0.08:
                break
        else:
            raise AssertionError('could not sample a nondegenerate creation pose')
        ideal.append(candidate)
        minimum_sine = min(minimum_sine, *sines)
        triples.extend([[p, q, vertex] for p, q in pairs])

    orientations = [[a, b, c, 1 if _cross(ideal, a, b, c) > 0 else -1]
                    for a, b, c in triples]
    jitter_rng = random.Random(20261116)
    jitter = [[0.0, 0.0], [0.0, 0.0]] + [
        [jitter_rng.uniform(-1, 1), jitter_rng.uniform(-1, 1)]
        for _ in range(vertices - 2)]
    amplitude = 1e-3
    for _ in range(40):
        points = [[p[k] + amplitude * j[k] for k in (0, 1)]
                  for p, j in zip(ideal, jitter)]
        if all(sign * _cross(points, a, b, c) > 0
               for a, b, c, sign in orientations):
            break
        amplitude *= 0.5
    else:
        raise AssertionError('could not preserve creation orientations in the jittered seed')

    solutions = [[list(p) for p in ideal], [[1.003 * x, y] for x, y in ideal]]
    ordered_edges = sorted(edges)
    values = [[math.dist(solution[a], solution[b]) for a, b in ordered_edges]
              for solution in solutions]
    constraints = [dict(kind='distance', a=a, b=b, value=values[0][i])
                   for i, (a, b) in enumerate(ordered_edges)]
    degrees = [len(neighbors) for neighbors in adjacent]
    fixture = dict(
        id=f'laman_free_{free_coordinates}', family='triangle_free_henneberg_ii',
        points=points, fixed=[0, 1], constraints=constraints,
        orientations=orientations, expected_feasible=True,
        geometric_free_coordinates=free_coordinates, logical_components=1,
        unit_scale=1.0, vertex_count=vertices, edge_count=len(edges),
        variable_distance_relations=len(edges) - 1, constant_anchor_relations=1,
        triangle_count=triangles, minimum_vertex_degree=min(degrees),
        maximum_vertex_degree=max(degrees),
        degree_histogram={str(d): degrees.count(d) for d in sorted(set(degrees))},
        henneberg_ii_steps=history,
        construction_seeds=dict(graph=20261114, geometry=20261115, jitter=20261116),
        minimum_creation_sine=minimum_sine, seed_jitter_component_bound=amplitude,
        description='A triangle-free Laman graph with a replayable Henneberg-II '
                    'construction, two fixed anchors, and consistent x-stretch edits. '
                    'Generic local rigidity does not certify global uniqueness; '
                    'these are distance-heavy solves from lightly jittered near-root seeds.')
    return dict(fixture=fixture, edits=[dict(values=v, known_solution=s)
                                       for v, s in zip(values, solutions)])


def canonical() -> list[dict]:
    triangle = ladder(1)
    triangle['fixture']['id'] = 'canonical_cell'
    contradictory = ladder(1)
    contradictory['fixture']['id'] = 'contradictory_distance'
    contradictory['fixture']['expected_feasible'] = False
    contradictory['fixture']['constraints'].append(
        dict(contradictory['fixture']['constraints'][0]))
    for edit in contradictory['edits']:
        edit['values'].append(edit['values'][0] * 1.2)
        edit.pop('known_solution')
    hv = dict(fixture=dict(
        id='axis_rectangle', family='canonical',
        points=[[0.0, 0.0], [2.1, 0.1], [2.0, 1.1], [0.1, 1.0]],
        fixed=[0], orientations=[[0, 1, 2, 1], [0, 2, 3, 1]],
        constraints=[dict(kind='horizontal', a=0, b=1),
                     dict(kind='vertical', a=1, b=2),
                     dict(kind='horizontal', a=2, b=3),
                     dict(kind='vertical', a=3, b=0),
                     dict(kind='distance', a=0, b=1, value=2.0),
                     dict(kind='distance', a=0, b=3, value=1.0)],
        expected_feasible=True, geometric_free_coordinates=6,
        logical_components=1),
        edits=[dict(values=[0, 0, 0, 0, 2.0, 1.0],
                    known_solution=[[0, 0], [2, 0], [2, 1], [0, 1]]),
               dict(values=[0, 0, 0, 0, 2.2, 1.0],
                    known_solution=[[0, 0], [2.2, 0], [2.2, 1], [0, 1]])])
    coincident = dict(fixture=dict(
        id='coincidence', family='canonical', points=[[0, 0], [0.1, -0.1]],
        fixed=[0], constraints=[dict(kind='coincident', a=0, b=1)],
        orientations=[], expected_feasible=True,
        geometric_free_coordinates=2, logical_components=1),
        edits=[dict(values=[0], known_solution=[[0, 0], [0, 0]])])
    return [triangle, hv, coincident, contradictory]


def corpus(suite: str) -> list[dict]:
    if suite == 'smoke':
        return canonical() + [ladder(3), ladder(1, scale=1e-6)]
    if suite == 'screen':
        return canonical() + [ladder(n) for n in [5, 25, 125, 500]] + [
            ladder(1, components=25), ladder(5, redundant=True),
            ladder(5, scale=1e-6), ladder(5, scale=1e6),
            ladder(5, offset=1e6)]
    if suite == 'boundaries':
        return [ladder(n) for n in [15, 16, 17, 23, 24, 25, 29, 30, 31, 74, 75, 76]]
    if suite == 'confirm':
        return [ladder(n) for n in [5, 25, 125, 500]] + [ladder(1, components=25)]
    if suite == 'coupled':
        return [laman(n) for n in [100, 500, 2000]]
    raise ValueError(suite)


def request(case: dict, engine: str, mode: str, warmups: int, samples: int,
            tolerance: float = 1e-7) -> dict:
    return dict(schema_version=1, engine=engine, mode=mode,
                warmups=warmups, samples=samples,
                tolerance=tolerance * case['fixture'].get('unit_scale', 1.0), **case)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', choices=['smoke', 'screen', 'confirm', 'boundaries', 'coupled'],
                        default='smoke')
    parser.add_argument('--engine', default='dart_2d_analytic')
    parser.add_argument('--mode', choices=['cold', 'warm'], default='warm')
    parser.add_argument('--warmups', type=int, default=1)
    parser.add_argument('--samples', type=int, default=3)
    parser.add_argument('--out', type=pathlib.Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    for case in corpus(args.suite):
        path = args.out / (case['fixture']['id'] + '.json')
        path.write_text(json.dumps(request(case, args.engine, args.mode,
                                           args.warmups, args.samples), indent=2) + '\n')
    print(json.dumps(dict(suite=args.suite, cases=len(corpus(args.suite)),
                          output=str(args.out))))


if __name__ == '__main__':
    main()
