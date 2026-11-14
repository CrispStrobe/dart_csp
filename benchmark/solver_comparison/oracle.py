"""Independent physical acceptance; never consults a solver's own residuals."""

from __future__ import annotations

import math


def _finite_number(value: object) -> bool:
    # bool is an int subclass in Python, but is not a JSON coordinate.
    if type(value) not in (int, float):
        return False
    try:
        return math.isfinite(value)
    except OverflowError:
        # JSON integers can be larger than the finite double domain.
        return False


def check(request: dict, record: dict) -> dict:
    tolerance = request.get('tolerance')
    if not _finite_number(tolerance) or tolerance <= 0:
        raise ValueError('physical tolerance must be finite and positive')
    warmups, samples = request.get('warmups'), request.get('samples')
    if (type(warmups) is not int or warmups < 0 or
            type(samples) is not int or samples < 1):
        raise ValueError('invalid requested operation counts')
    index = record.get('index')
    if type(index) is not int or not -warmups <= index < samples:
        raise ValueError('index outside requested range')
    edits = request.get('edits')
    if not isinstance(edits, list) or not edits:
        raise ValueError('at least one physical edit is required')
    fixture = request['fixture']
    coordinates = record.get('coordinates')
    failures = []
    if not isinstance(coordinates, list) or len(coordinates) != len(fixture['points']):
        return dict(accepted=False, max_error=None, violations=['coordinate_count'])
    if any(not isinstance(p, list) or len(p) != 2 or any(
            not _finite_number(x) for x in p)
           for p in coordinates):
        return dict(accepted=False, max_error=None, violations=['nonfinite_coordinates'])
    edit = edits[(index + warmups) % len(edits)]
    max_error = 0.0
    nonfinite_error = False

    def observe_error(error: float, source: str) -> None:
        nonlocal max_error, nonfinite_error
        if not _finite_number(error):
            # Finite coordinates do not guarantee a finite subtraction or
            # Euclidean distance. Keep the ordinary location label as well
            # as the reason, and never emit Infinity/NaN as max_error.
            nonfinite_error = True
            failures.extend([source, f'nonfinite_error:{source}'])
            return
        max_error = max(max_error, error)
        if error > tolerance:
            failures.append(source)

    for i in fixture['fixed']:
        try:
            error = math.dist(coordinates[i], fixture['points'][i])
        except OverflowError:
            error = math.inf
        observe_error(error, f'fixed:{i}')
    for i, constraint in enumerate(fixture['constraints']):
        a, b = coordinates[constraint['a']], coordinates[constraint['b']]
        kind = constraint['kind']
        try:
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
        except OverflowError:
            error = math.inf
        observe_error(error, f'constraint:{i}')
    for i, (a, b, c, sign) in enumerate(fixture.get('orientations', [])):
        pa, pb, pc = coordinates[a], coordinates[b], coordinates[c]
        try:
            cross = (pb[0] - pa[0]) * (pc[1] - pa[1]) - (pb[1] - pa[1]) * (pc[0] - pa[0])
            signed_cross = sign * cross
        except OverflowError:
            signed_cross = math.inf
        if not _finite_number(signed_cross):
            nonfinite_error = True
            failures.extend([f'orientation:{i}', f'nonfinite_error:orientation:{i}'])
        elif signed_cross <= 0:
            failures.append(f'orientation:{i}')
    if record.get('adapter_error'):
        failures.append('adapter_error')
    return dict(accepted=not failures, max_error=None if nonfinite_error else max_error,
                violations=failures,
                expected_feasible=fixture['expected_feasible'])
