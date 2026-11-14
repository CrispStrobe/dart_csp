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
    raise ValueError(suite)


def request(case: dict, engine: str, mode: str, warmups: int, samples: int,
            tolerance: float = 1e-7) -> dict:
    return dict(schema_version=1, engine=engine, mode=mode,
                warmups=warmups, samples=samples,
                tolerance=tolerance * case['fixture'].get('unit_scale', 1.0), **case)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', choices=['smoke', 'screen', 'confirm', 'boundaries'],
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
