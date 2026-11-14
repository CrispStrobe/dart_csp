"""Small deterministic graph-model cross-check of exact minimum-degree ordering.

This is an algorithm model, not execution or performance evidence for Dart.
It compares a faithful indexed-heap translation with an independent scan oracle.
"""
import hashlib
import itertools
import json
import os
from pathlib import Path
import random


class Heap:
    def __init__(self, graph):
        self.heap = list(range(len(graph)))
        self.positions = list(self.heap)
        self.degrees = [len(row) for row in graph]
        for position in range(len(graph) // 2 - 1, -1, -1):
            self.down(position)

    def less(self, left, right):
        return (self.degrees[left], left) < (self.degrees[right], right)

    def swap(self, left, right):
        a, b = self.heap[left], self.heap[right]
        self.heap[left], self.heap[right] = b, a
        self.positions[a], self.positions[b] = right, left

    def down(self, position):
        while True:
            child = position * 2 + 1
            if child >= len(self.heap):
                return
            if child + 1 < len(self.heap) and self.less(self.heap[child + 1], self.heap[child]):
                child += 1
            if not self.less(self.heap[child], self.heap[position]):
                return
            self.swap(position, child)
            position = child

    def up(self, position):
        while position:
            parent = (position - 1) // 2
            if not self.less(self.heap[position], self.heap[parent]):
                return
            self.swap(position, parent)
            position = parent

    def pop(self):
        column = self.heap[0]
        last = self.heap.pop()
        self.positions[column] = -1
        if self.heap:
            self.heap[0] = last
            self.positions[last] = 0
            self.down(0)
        return column

    def update(self, column, degree):
        previous = self.degrees[column]
        self.degrees[column] = degree
        if degree < previous:
            self.up(self.positions[column])
        elif degree > previous:
            self.down(self.positions[column])

    def check(self):
        assert len(self.heap) == len(set(self.heap))
        for position, column in enumerate(self.heap):
            assert self.positions[column] == position
            if position:
                assert not self.less(column, self.heap[(position - 1) // 2])


def eliminate(n, edges, heap_selector):
    graph = [set() for _ in range(n)]
    for a, b in edges:
        graph[a].add(b)
        graph[b].add(a)
    alive = set(range(n))
    heap = Heap(graph) if heap_selector else None
    order, neighborhoods, factor_entries, numeric_work = [], [], n + len(edges), 0
    while alive:
        if heap:
            heap.check()
            assert all(heap.degrees[c] == len(graph[c]) for c in alive)
            pivot = heap.pop()
        else:
            pivot = min(alive, key=lambda c: (len(graph[c]), c))
        neighbors = sorted(graph[pivot])
        order.append(pivot)
        neighborhoods.append(neighbors)
        degree = len(neighbors)
        numeric_work += degree * (degree + 1) // 2
        for neighbor in neighbors:
            graph[neighbor].remove(pivot)
        for a, b in itertools.combinations(neighbors, 2):
            if b not in graph[a]:
                factor_entries += 1
                graph[a].add(b)
                graph[b].add(a)
        graph[pivot].clear()
        alive.remove(pivot)
        if heap:
            # Stored key snapshots make every individual update start from a
            # valid heap despite several actual graph degrees changing at once.
            for neighbor in neighbors:
                heap.update(neighbor, len(graph[neighbor]))
                heap.check()
    return order, neighborhoods, factor_entries, numeric_work


def main():
    allowed = sorted(os.sched_getaffinity(0)) if hasattr(os, 'sched_getaffinity') else []
    if len(allowed) > 1:
        os.sched_setaffinity(0, {next(cpu for cpu in allowed if cpu != 0)})
    cases = []
    pairs = list(itertools.combinations(range(5), 2))
    for mask in range(1 << len(pairs)):
        cases.append((5, [edge for index, edge in enumerate(pairs) if mask >> index & 1]))
    rng = random.Random(20261114)
    for n in [6, 9, 16, 32]:
        for probability in [.05, .15, .35, .7]:
            for _ in range(4):
                cases.append((n, [edge for edge in itertools.combinations(range(n), 2)
                                  if rng.random() < probability]))
    cases.extend([
        (256, []),
        (256, [(i, i + 1) for i in range(255)]),
        (256, [(0, i) for i in range(1, 256)]),
        (256, [(i, (i + 1) % 256) for i in range(256)]),
    ])
    for n, edges in cases:
        assert eliminate(n, edges, False) == eliminate(n, edges, True)
    source = Path('/workspace/scratch/a4f67f49ccab/dart_csp/lib/src/geometry/sparse_ldlt.dart')
    report = {
        'status': 'passed', 'graphs_checked': len(cases),
        'exhaustive_all_five_vertex_graphs': 1024,
        'seeded_varied_density_graphs': 64, 'large_boundary_graphs': 4,
        'matched': ['pivot_order', 'ordered_neighbor_sets', 'factor_entry_count', 'numeric_work'],
        'heap_invariants_checked_after_each_key_update': True,
        'reviewed_source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
        'cpu_affinity': sorted(os.sched_getaffinity(0)) if allowed else None,
        'limitation': 'Independent graph model, not compiled Dart coverage or performance evidence.',
    }
    Path(__file__).with_name('ordering-model-check.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report))


if __name__ == '__main__':
    main()
