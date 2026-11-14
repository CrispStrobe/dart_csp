import 'package:dart_csp/cad.dart';
import 'package:test/test.dart';

const _kernel = ReferenceCadKernel();

class _MutableParameters extends CadParameters {
  _MutableParameters() : super({'x': 1});
  final currentValues = {'x': 1.0};
  final currentRevisions = {'x': 0};
  int currentRevision = 0;
  int valueReads = 0;
  @override
  Map<String, double> get values {
    valueReads++;
    return currentValues;
  }

  @override
  Map<String, int> get revisions => currentRevisions;
  @override
  int get revision => currentRevision;
}

class _MutableReference extends TopologyRef {
  _MutableReference()
      : super(
            featureId: 'plate', semanticId: 'top', kind: CadTopologyKind.face);
  String currentFeature = 'plate', currentSemantic = 'top';
  CadTopologyKind currentKind = CadTopologyKind.face;
  @override
  String get featureId => currentFeature;
  @override
  String get semanticId => currentSemantic;
  @override
  CadTopologyKind get kind => currentKind;
}

class _OverriddenReferenceDocument extends CadFeatureDocument {
  _OverriddenReferenceDocument()
      : super(
          kernel: _kernel,
          parameters: CadParameters({}),
          features: [
            CadFeatureNode(
                id: 'value', evaluate: (_) => CadKernelResult.success(1))
          ],
          requiredReferences: const [
            TopologyRef(
                featureId: 'missing',
                semanticId: 'top',
                kind: CadTopologyKind.face)
          ],
        );
  int referenceReads = 0;
  @override
  List<TopologyRef> get requiredReferences {
    referenceReads++;
    return const [];
  }
}

CadFeatureDocument _scalarDocument(CadParameters parameters) =>
    CadFeatureDocument(kernel: _kernel, parameters: parameters, features: [
      CadFeatureNode(
          id: 'value',
          parameterDependencies: ['x'],
          evaluate: (context) =>
              CadKernelResult.success(context.parameters['x']))
    ]);

void main() {
  test('parameter subclasses cannot change historical state without an edit',
      () {
    final source = _MutableParameters();
    final document = _scalarDocument(source);
    // Capture once, then use only owned metadata to compile and regenerate.
    expect(source.valueReads, 1);
    final original = document.regenerate().state;
    source.currentValues['x'] = 20;
    source.currentRevisions['x'] = 7;
    source.currentRevision = 7;
    expect(document.regenerate().status, CadRegenerationStatus.unchanged);
    expect(original.parameters['x'], 1);
    expect(original.parameters.revisions, {'x': 0});
    expect(original.parameters.revision, 0);
    expect(original.output<double>('value'), 1);
    final edited = document.regenerate(changes: {'x': 3});
    expect(edited.status, CadRegenerationStatus.committed);
    expect(edited.state.parameters['x'], 3);
    expect(edited.state.parameters.revisions, {'x': 1});
    expect(edited.state.parameters.revision, 1);
    expect(edited.state.output<double>('value'), 3);
    expect(original.parameters['x'], 1);
    expect(source.valueReads, 1);
    expect(() => original.parameters.values['x'] = 99, throwsUnsupportedError);
  });

  test(
      'parameter snapshots preserve revisions when initializing a new document',
      () {
    final first = _scalarDocument(CadParameters({'x': 1}));
    first.regenerate();
    final parameters = first.regenerate(changes: {'x': 4}).state.parameters;
    final second = _scalarDocument(parameters);
    final rebuilt = second.regenerate();
    expect(rebuilt.state.output<double>('value'), 4);
    expect(rebuilt.state.parameters.revision, 1);
    expect(rebuilt.state.parameters.revisions, {'x': 1});
    expect(second.regenerate(changes: {'x': 5}).state.parameters.revision, 2);
    expect(first.state.parameters['x'], 4);
  });

  test('invalid subclass values and revision metadata fail at construction',
      () {
    final invalidValue = _MutableParameters()..currentValues['x'] = double.nan;
    expect(() => _scalarDocument(invalidValue), throwsArgumentError);
    final missingRevision = _MutableParameters()..currentRevisions.clear();
    expect(() => _scalarDocument(missingRevision), throwsArgumentError);
    final futureRevision = _MutableParameters()..currentRevisions['x'] = 2;
    expect(() => _scalarDocument(futureRevision), throwsArgumentError);
  });

  test('empty graphs reject missing mandatory references before a no-op', () {
    final document = CadFeatureDocument(
        kernel: _kernel,
        parameters: CadParameters({'x': 1}),
        features: [],
        requiredReferences: const [
          TopologyRef(
              featureId: 'missing',
              semanticId: 'top',
              kind: CadTopologyKind.face)
        ]);
    final initial = document.state;
    for (final changes in [
      <String, double>{},
      {'x': 2.0},
      <String, double>{}
    ]) {
      final result = document.regenerate(changes: changes);
      expect(result.status, CadRegenerationStatus.rejected);
      expect(result.isSuccess, isFalse);
      expect(result.failedFeature, 'missing');
      expect(result.issues.single.code, 'topology_missing');
      expect(result.rebuiltFeatures, isEmpty);
      expect(identical(result.state, initial), isTrue);
      expect(identical(document.state, initial), isTrue);
      expect(initial.parameters['x'], 1);
    }
  });

  test('mandatory reference metadata and its source list are captured', () {
    final reference = _MutableReference();
    final references = <TopologyRef>[reference];
    final document = CadFeatureDocument(
        kernel: _kernel,
        parameters: CadParameters({'depth': 2}),
        features: [
          CadFeatureNode.rectangularProfile(
              id: 'profile',
              width: CadExpression.constant(4),
              height: CadExpression.constant(3)),
          CadFeatureNode.extrude(
              id: 'plate',
              profile: 'profile',
              depth: CadExpression.parameter('depth'))
        ],
        requiredReferences: references);
    reference.currentFeature = 'missing';
    reference.currentSemantic = 'changed';
    reference.currentKind = CadTopologyKind.edge;
    references.clear();
    expect(document.requiredReferences.single.featureId, 'plate');
    expect(document.requiredReferences.single.semanticId, 'top');
    expect(document.requiredReferences.single.kind, CadTopologyKind.face);
    expect(document.requiredReferences.clear, throwsUnsupportedError);
    expect(document.regenerate().isSuccess, isTrue);
    expect(document.regenerate(changes: {'depth': 3}).isSuccess, isTrue);
  });

  test('document subclass reference getters cannot drop required obligations',
      () {
    final document = _OverriddenReferenceDocument();
    final initial = document.state;
    final result = document.regenerate();
    expect(result.status, CadRegenerationStatus.rejected);
    expect(result.issues.single.code, 'topology_missing');
    expect(identical(document.state, initial), isTrue);
    expect(document.referenceReads, 0);
  });
}
