import 'dart:collection';

import 'package:dart_csp/cad.dart';
import 'package:test/test.dart';

class _Reads {
  final events = <String>[];
  final values = <String, Object?>{};
  int? failAt;
  bool unsupported = false;

  T read<T>(String name, T fallback) {
    events.add(name);
    if (events.length == failAt) {
      if (unsupported) throw UnsupportedError(name);
      throw StateError(name);
    }
    return values.containsKey(name) ? values[name] as T : fallback;
  }
}

class _ReadList<T> extends ListBase<T> {
  _ReadList(this.reads, this.name, this.values);
  final _Reads reads;
  final String name;
  final List<T> values;
  @override
  int get length => values.length;
  @override
  set length(int value) => throw UnsupportedError('Read-only test list.');
  @override
  T operator [](int index) => values[index];
  @override
  void operator []=(int index, T value) =>
      throw UnsupportedError('Read-only test list.');
  @override
  Iterator<T> get iterator =>
      reads.read('$name.iterator', _ReadIterator(reads, name, values.iterator));
}

class _ReadIterator<T> implements Iterator<T> {
  _ReadIterator(this.reads, this.name, this.inner);
  final _Reads reads;
  final String name;
  final Iterator<T> inner;
  @override
  T get current => reads.read('$name.current', inner.current);
  @override
  bool moveNext() => reads.read('$name.moveNext', inner.moveNext());
}

class _BoundsPoint extends CadPoint3 {
  _BoundsPoint(this.reads, this.name, double coordinate)
      : super(coordinate, coordinate, coordinate);
  final _Reads reads;
  final String name;
  @override
  double get x => reads.read('$name.x', super.x);
  @override
  double get y => reads.read('$name.y', super.y);
  @override
  double get z => reads.read('$name.z', super.z);
}

class _Bounds extends CadBounds {
  _Bounds(this.reads)
      : super(_BoundsPoint(reads, 'min', -4), _BoundsPoint(reads, 'max', 4));
  final _Reads reads;
  @override
  bool get isFinite => reads.read('bounds.isFinite', true);
  @override
  CadPoint3 get min => reads.read('bounds.min', super.min);
  @override
  CadPoint3 get max => reads.read('bounds.max', super.max);
}

class _Vertex extends CadVertex {
  _Vertex(this.reads)
      : super(
            id: 'vertex',
            semanticId: 'vertex',
            point: const CadPoint3(1, 2, 3));
  final _Reads reads;
  @override
  String get id => reads.read('vertex.id', super.id);
  @override
  String get semanticId => reads.read('vertex.semantic', super.semanticId);
  @override
  CadPoint3 get point => reads.read('vertex.point', super.point);
}

class _Line extends CadLineCurve {
  _Line(this.reads) : super(const CadPoint3(0, 0, 0), const CadPoint3(1, 0, 0));
  final _Reads reads;
  @override
  CadPoint3 get start => reads.read('line.start', super.start);
  @override
  CadPoint3 get end => reads.read('line.end', super.end);
}

class _Circle extends CadCircleCurve {
  _Circle(this.reads) : super(center: const CadPoint3(0, 0, 0), radius: 1);
  final _Reads reads;
  @override
  CadPoint3 get center => reads.read('circle.center', super.center);
  @override
  double get radius => reads.read('circle.radius', super.radius);
  @override
  CadPoint3 get normal => reads.read('circle.normal', super.normal);
}

class _Edge extends CadEdge {
  _Edge(this.reads, this.name, CadCurve curve)
      : super(id: name, semanticId: name, curve: curve);
  final _Reads reads;
  final String name;
  @override
  CadCurve get curve => reads.read('$name.curve', super.curve);
  @override
  String get id => reads.read('$name.id', super.id);
  @override
  String get semanticId => reads.read('$name.semantic', super.semanticId);
  @override
  String? get startVertex => reads.read('$name.startVertex', super.startVertex);
  @override
  String? get endVertex => reads.read('$name.endVertex', super.endVertex);
}

class _Plane extends CadPlaneSurface {
  _Plane(this.reads)
      : super(
            origin: const CadPoint3(0, 0, 0), normal: const CadPoint3(0, 0, 1));
  final _Reads reads;
  @override
  CadPoint3 get origin => reads.read('plane.origin', super.origin);
  @override
  CadPoint3 get normal => reads.read('plane.normal', super.normal);
}

class _Cylinder extends CadCylinderSurface {
  _Cylinder(this.reads) : super(origin: const CadPoint3(0, 0, 0), radius: 1);
  final _Reads reads;
  @override
  CadPoint3 get origin => reads.read('cylinder.origin', super.origin);
  @override
  double get radius => reads.read('cylinder.radius', super.radius);
  @override
  CadPoint3 get axis => reads.read('cylinder.axis', super.axis);
  @override
  bool get inward => reads.read('cylinder.inward', super.inward);
}

class _OrientedEdge extends CadOrientedEdge {
  _OrientedEdge(this.reads) : super('line');
  final _Reads reads;
  @override
  String get edgeId => reads.read('oriented.edgeId', super.edgeId);
  @override
  bool get reversed => reads.read('oriented.reversed', super.reversed);
}

class _Loop extends CadBoundaryLoop {
  _Loop(this.reads)
      : edgeValues = _ReadList(reads, 'edges', [_OrientedEdge(reads)]),
        super(const []);
  final _Reads reads;
  final List<CadOrientedEdge> edgeValues;
  @override
  List<CadOrientedEdge> get edges => reads.read('loop.edges', edgeValues);
}

class _Face extends CadFace {
  _Face(this.reads, this.name, CadSurface surface, {bool loop = false})
      : loopValues = _ReadList(reads, '$name.loops', [if (loop) _Loop(reads)]),
        super(id: name, semanticId: name, surface: surface, loops: const []);
  final _Reads reads;
  final String name;
  final List<CadBoundaryLoop> loopValues;
  @override
  CadSurface get surface => reads.read('$name.surface', super.surface);
  @override
  String get id => reads.read('$name.id', super.id);
  @override
  String get semanticId => reads.read('$name.semantic', super.semanticId);
  @override
  List<CadBoundaryLoop> get loops => reads.read('$name.loops', loopValues);
}

// This fixture isolates placement's public-value consumption from the backend
// policy. Its topology is deliberately small, not an independently valid solid.
class _PolicyKernel extends ReferenceCadKernel {
  int validations = 0;
  bool reject = false;
  @override
  List<CadIssue> validate(CadBody body) {
    validations++;
    return [if (reject) const CadIssue('policy', 'Backend rejection.')];
  }
}

CadBodyInstance _instance(_Reads reads,
        {CadRigidTransform? placement, double tolerance = 1e-7}) =>
    CadBodyInstance(
        featureId: 'placed',
        placement: placement ?? CadRigidTransform(),
        linearTolerance: tolerance,
        body: CadBody(
            featureId: 'prototype',
            bounds: const CadBounds(CadPoint3(-4, -4, -4), CadPoint3(4, 4, 4)),
            volume: 1,
            vertices: [
              _Vertex(reads)
            ],
            edges: [
              _Edge(reads, 'line', _Line(reads)),
              _Edge(reads, 'circle', _Circle(reads))
            ],
            faces: [
              _Face(reads, 'face', _Plane(reads), loop: true),
              _Face(reads, 'wall', _Cylinder(reads))
            ]));

// This is the materializing implementation's constructor-argument order,
// including custom collection iteration. Validation must consume it unchanged.
const _expectedReads = [
  'vertex.id',
  'vertex.semantic',
  'vertex.point',
  'line.curve',
  'line.start',
  'line.end',
  'line.id',
  'line.semantic',
  'line.startVertex',
  'line.endVertex',
  'circle.curve',
  'circle.center',
  'circle.radius',
  'circle.normal',
  'circle.id',
  'circle.semantic',
  'circle.startVertex',
  'circle.endVertex',
  'face.surface',
  'plane.origin',
  'plane.normal',
  'face.id',
  'face.semantic',
  'face.loops',
  'face.loops.iterator',
  'face.loops.moveNext',
  'face.loops.current',
  'loop.edges',
  'edges.iterator',
  'edges.moveNext',
  'edges.current',
  'oriented.edgeId',
  'oriented.reversed',
  'edges.moveNext',
  'face.loops.moveNext',
  'wall.surface',
  'cylinder.origin',
  'cylinder.radius',
  'cylinder.axis',
  'cylinder.inward',
  'wall.id',
  'wall.semantic',
  'wall.loops',
  'wall.loops.iterator',
  'wall.loops.moveNext',
];

void main() {
  test('bounds transformation preserves public getter and failure order', () {
    final expected = [
      'bounds.isFinite',
      // Ordered-bound checks, followed by scalar endpoint capture.
      for (var pass = 0; pass < 2; pass++)
        for (final axis in ['x', 'y', 'z']) ...[
          'bounds.min',
          'min.$axis',
          'bounds.max',
          'max.$axis',
        ],
    ];
    final transform = CadRigidTransform();
    final reads = _Reads();
    transform.transformBounds(_Bounds(reads));
    expect(reads.events, expected);
    for (var failure = 1; failure <= expected.length; failure++) {
      final failing = _Reads()..failAt = failure;
      expect(
          () => transform.transformBounds(_Bounds(failing)), throwsStateError,
          reason: 'Getter $failure: ${expected[failure - 1]}');
      expect(failing.events, expected.take(failure));
    }
    final nonfinite = _Reads()..values['bounds.isFinite'] = false;
    expect(() => transform.transformBounds(_Bounds(nonfinite)),
        throwsArgumentError);
    expect(nonfinite.events, expected.take(1));
    for (var axis = 0; axis < 3; axis++) {
      final unordered = _Reads()..values['min.${['x', 'y', 'z'][axis]}'] = 8.0;
      expect(() => transform.transformBounds(_Bounds(unordered)),
          throwsArgumentError);
      expect(unordered.events, expected.take(1 + 4 * (axis + 1)));
    }
  });

  test('placement validation preserves public metadata and iteration order',
      () {
    final reads = _Reads();
    final instance = _instance(reads);
    final kernel = _PolicyKernel();
    expect(instance.validate(kernel), isEmpty);
    expect(reads.events, _expectedReads);
    expect(kernel.validations, 1);
  });

  test('every throwing metadata getter or iterator still rejects placement',
      () {
    for (var failure = 1; failure <= _expectedReads.length; failure++) {
      final reads = _Reads()..failAt = failure;
      final instance = _instance(reads);
      final kernel = _PolicyKernel();
      final issues = instance.validate(kernel);
      expect(issues, hasLength(1), reason: _expectedReads[failure - 1]);
      expect(issues.single.code, 'invalid_instance_placement');
      expect(issues.single.entity, 'placed');
      expect(reads.events, _expectedReads.take(failure));
      expect(kernel.validations, 1);
    }
    final reads = _Reads()
      ..failAt = _expectedReads.indexOf('oriented.edgeId') + 1
      ..unsupported = true;
    expect(_instance(reads).validate(_PolicyKernel()).single.code,
        'unsupported_instance_geometry');
  });

  test('custom bodies and backend policy are freshly validated on every call',
      () {
    final reads = _Reads();
    final instance = _instance(reads);
    final kernel = _PolicyKernel();
    expect(instance.validate(kernel), isEmpty);
    reads.events.clear();
    reads.values['vertex.point'] = const CadPoint3(double.infinity, 0, 0);
    expect(instance.validate(kernel).single.code, 'invalid_instance_placement');
    reads.values.clear();
    reads.events.clear();
    expect(instance.validate(kernel), isEmpty);
    expect(reads.events, _expectedReads);
    reads.events.clear();
    kernel.reject = true;
    expect(instance.validate(kernel).single.code, 'policy');
    expect(reads.events, isEmpty);
    expect(kernel.validations, 4);
  });

  test('resolved topology still materializes independent immutable snapshots',
      () {
    final reads = _Reads();
    final instance = _instance(reads);
    final circle =
        instance.resolve(CadTopologyKind.edge, 'circle').entity! as CadEdge;
    final face =
        instance.resolve(CadTopologyKind.face, 'face').entity! as CadFace;
    reads.values.addAll({
      'circle.id': 'changed',
      'circle.radius': 2.0,
      'oriented.edgeId': 'changed',
      'oriented.reversed': true,
    });
    expect(instance.validate(_PolicyKernel()), isEmpty);
    final changedCircle =
        instance.resolve(CadTopologyKind.edge, 'circle').entity! as CadEdge;
    final changedFace =
        instance.resolve(CadTopologyKind.face, 'face').entity! as CadFace;
    expect(circle.id, 'circle');
    expect((circle.curve as CadCircleCurve).radius, 1);
    expect(changedCircle.id, 'changed');
    expect((changedCircle.curve as CadCircleCurve).radius, 2);
    expect(face.loops.single.edges.single.edgeId, 'line');
    expect(face.loops.single.edges.single.reversed, isFalse);
    expect(changedFace.loops.single.edges.single.edgeId, 'changed');
    expect(changedFace.loops.single.edges.single.reversed, isTrue);
    expect(face.loops.clear, throwsUnsupportedError);
    expect(face.loops.single.edges.clear, throwsUnsupportedError);
  });

  test(
      'validation still checks directions, point precision and collapsed lines',
      () {
    for (final field in [
      'circle.normal',
      'plane.origin',
      'plane.normal',
      'cylinder.origin',
      'cylinder.axis',
    ]) {
      final reads = _Reads()
        ..values[field] = const CadPoint3(double.infinity, 0, 0);
      expect(_instance(reads).validate(_PolicyKernel()).single.code,
          'invalid_instance_placement',
          reason: field);
    }
    final placement =
        CadRigidTransform(translation: const CadPoint3(1e20, 1e20, 1e20));
    final tight =
        _instance(_Reads(), placement: placement).validate(_PolicyKernel());
    expect(tight.single.message, contains('rounding error'));
    final coarse = _instance(_Reads(), placement: placement, tolerance: 1e5)
        .validate(_PolicyKernel());
    expect(coarse.single.message, contains('edge collapsed'));
  });
}
