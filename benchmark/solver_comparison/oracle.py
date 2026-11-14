"""Independent physical acceptance; never consults a solver's own residuals."""

from __future__ import annotations

import math


def check(request: dict, record: dict) -> dict:
    fixture = request['fixture']
    coordinates = record.get('coordinates')
    failures = []
    if not isinstance(coordinates, list) or len(coordinates) != len(fixture['points']):
        return dict(accepted=False, max_error=None, violations=['coordinate_count'])
    if any(not isinstance(p, list) or len(p) != 2 or any(
            not isinstance(x, (int, float)) or not math.isfinite(x) for x in p)
           for p in coordinates):
        return dict(accepted=False, max_error=None, violations=['nonfinite_coordinates'])
    tolerance = request['tolerance']
    index = int(record['index'])
    edit = request['edits'][(index + request['warmups']) % len(request['edits'])]
    max_error = 0.0
    for i in fixture['fixed']:
        error = math.dist(coordinates[i], fixture['points'][i])
        max_error = max(max_error, error)
        if error > tolerance:
            failures.append(f'fixed:{i}')
    for i, constraint in enumerate(fixture['constraints']):
        a, b = coordinates[constraint['a']], coordinates[constraint['b']]
        kind = constraint['kind']
        if kind == 'distance':
            error = abs(math.dist(a, b) - edit['values'][i])
        elif kind == 'coincident':
            error = math.dist(a, b)
        elif kind == 'horizontal':
            error = abs(a[1] - b[1])
        elif kind == 'vertical':
            error = abs(a[0] - b[0])
        else:
            raise ValueError(f'Unknown physical constraint {kind}')
        max_error = max(max_error, error)
        if error > tolerance:
            failures.append(f'constraint:{i}')
    for i, (a, b, c, sign) in enumerate(fixture.get('orientations', [])):
        pa, pb, pc = coordinates[a], coordinates[b], coordinates[c]
        cross = (pb[0] - pa[0]) * (pc[1] - pa[1]) - (pb[1] - pa[1]) * (pc[0] - pa[0])
        if not math.isfinite(cross) or sign * cross <= 0:
            failures.append(f'orientation:{i}')
    if record.get('adapter_error'):
        failures.append('adapter_error')
    return dict(accepted=not failures, max_error=max_error,
                violations=failures,
                expected_feasible=fixture['expected_feasible'])
