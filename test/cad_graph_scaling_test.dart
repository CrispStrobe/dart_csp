import 'dart:math' as math;

import 'package:dart_csp/cad.dart';
import 'package:test/test.dart';

const _kernel = ReferenceCadKernel();

final class _Value {
  const _Value(this.number);
  final int number;
}

CadFeatureNode _constant(String id, int value) => CadFeatureNode(
    id: id, evaluate: (_) => CadKernelResult.success(_Value(value)));

class _MutableDeclaration extends CadFeatureNode {
  _MutableDeclaration()
      : super(
            id: 'value',
            evaluate: (context) =>
                CadKernelResult.success(context.parameters['x']));

  final inputs = <String>[];
  final parameters = <String>{'x'};
  @override
  List<String> get dependencies => inputs;
  @override
  Set<String> get parameterDependencies => parameters;
}

class _RuntimeTypeSpoof extends CadFeatureNode {
  _RuntimeTypeSpoof()
      : super(id: 'value', evaluate: (_) => CadKernelResult.success(0));

  String selected = 'x';
  String featureName = 'value';
  @override
  Type get runtimeType => CadFeatureNode;
  @override
  String get id => featureName;
  @override
  Set<String> get parameterDependencies => {selected};
  @override
  CadKernelResult<Object> Function(CadFeatureContext) get evaluate {
    final parameter = selected;
    return (context) => CadKernelResult.success(context.parameters[parameter]);
  }
}

class _SelectableDeclaration extends CadFeatureNode {
  _SelectableDeclaration()
      : super(
            id: 'value',
            evaluate: (context) => CadKernelResult.success(
                context.parameters.values.values.single));

  String selected = 'x';
  @override
  Set<String> get parameterDependencies => {selected};
}

class _OverriddenDocumentFeatures extends CadFeatureDocument {
  _OverriddenDocumentFeatures(this.originalFeatures)
      : super(
            kernel: _kernel,
            parameters: CadParameters({'x': 1, 'y': 10}),
            features: originalFeatures);

  final List<CadFeatureNode> originalFeatures;
  int publicGetterCalls = 0;
  @override
  List<CadFeatureNode> get features {
    publicGetterCalls++;
    return originalFeatures;
  }
}

void main() {
  test('iterative compilation preserves dependency-first DFS order', () {
    CadFeatureNode node(String id, List<String> inputs, String? parameter) =>
        CadFeatureNode(
            id: id,
            dependencies: inputs,
            parameterDependencies: parameter == null ? [] : [parameter],
            evaluate: (context) => CadKernelResult.success(_Value(
                (parameter == null
                        ? 0
                        : context.parameters[parameter].toInt()) +
                    inputs.fold(
                        0,
                        (sum, input) =>
                            sum + context.input<_Value>(input).number))));
    final document = CadFeatureDocument(
        kernel: _kernel,
        parameters: CadParameters({'x': 2, 'y': 3}),
        features: [
          node('sink', ['left', 'right'], null),
          node('right', ['root'], 'y'),
          node('unrelated', [], null),
          node('left', ['root'], null),
          node('root', [], 'x'),
        ]);
    expect(document.regenerate().rebuiltFeatures,
        ['root', 'left', 'right', 'sink', 'unrelated']);
    expect(document.state.output<_Value>('sink').number, 7);
    final previous = document.state;
    final edited = document.regenerate(changes: {'y': 8});
    expect(edited.rebuiltFeatures, ['right', 'sink']);
    expect(edited.stats.scheduledFeatures, 2);
    expect(edited.stats.dependencyEdgesVisited, 1);
    expect(edited.state.output<_Value>('sink').number, 12);
    expect(identical(previous.outputs['left'], edited.state.outputs['left']),
        isTrue);
    expect(edited.state.outputs.keys,
        ['root', 'left', 'right', 'sink', 'unrelated']);
  });

  test('twenty-thousand-deep reverse-listed history does not use recursion',
      () {
    const count = 20000;
    final document = CadFeatureDocument(
        kernel: _kernel,
        parameters: CadParameters({'origin': 1}),
        features: [
          for (var i = count - 1; i >= 0; i--)
            CadFeatureNode(
                id: 'f$i',
                dependencies: i == 0 ? [] : ['f${i - 1}'],
                parameterDependencies: i == 0 ? ['origin'] : [],
                evaluate: (context) => CadKernelResult.success(i == 0
                    ? context.parameters['origin'].toInt()
                    : context.input<int>('f${i - 1}') + 1)),
        ]);
    final result = document.regenerate();
    expect(result.status, CadRegenerationStatus.committed);
    expect(result.rebuiltFeatures.length, count);
    expect(result.rebuiltFeatures.first, 'f0');
    expect(result.rebuiltFeatures.last, 'f${count - 1}');
    expect(result.state.output<int>('f${count - 1}'), count);
    final edit = document.regenerate(changes: {'origin': 5});
    expect(edit.state.output<int>('f${count - 1}'), count + 4);
    expect(result.state.output<int>('f${count - 1}'), count);
    expect(edit.stats.dependencyEdgesVisited, count - 1);
  });

  test('sparse edit copies only affected chunks and keeps all historical maps',
      () {
    const independent = 4096;
    final document = CadFeatureDocument(
        kernel: _kernel,
        parameters: CadParameters({'x': 0, 'unused': 0}),
        features: [
          for (var i = 0; i < independent; i++)
            if (i == 5)
              CadFeatureNode(
                  id: 'f$i',
                  parameterDependencies: ['x'],
                  evaluate: (context) => CadKernelResult.success(
                      _Value(context.parameters['x'].toInt())))
            else
              _constant('f$i', i),
          CadFeatureNode(
              id: 'tail',
              dependencies: ['f5'],
              evaluate: (context) => CadKernelResult.success(
                  _Value(2 * context.input<_Value>('f5').number))),
        ]);
    expect(document.regenerate().isSuccess, isTrue);
    final states = [document.state];
    for (var edit = 1; edit <= 40; edit++) {
      final result = document.regenerate(changes: {'x': edit.toDouble()});
      expect(result.rebuiltFeatures, ['f5', 'tail']);
      expect(result.stats.scheduledFeatures, 2);
      expect(result.stats.dependencyEdgesVisited, 1);
      expect(result.stats.stateChunksCopied, 2);
      expect(result.stats.stateEntriesCopied, 129);
      expect(result.stats.stateDirectoryEntriesCopied, 33);
      expect(
          identical(states.first.outputs['f128'], result.state.outputs['f128']),
          isTrue);
      states.add(result.state);
    }
    for (var edit = 0; edit < states.length; edit++) {
      final state = states[edit];
      expect(state.output<_Value>('f5').number, edit);
      expect(state.output<_Value>('tail').number, 2 * edit);
      expect(state.featureRevisions['f5'], edit + 1);
      expect(state.featureRevisions['tail'], edit + 1);
      expect(state.featureRevisions['f128'], 1);
      expect(state.parameters['x'], edit.toDouble());
      expect(state.outputs.length, independent + 1);
      expect(state.outputs.keys.first, 'f0');
      expect(state.outputs.keys.last, 'tail');
    }
    final old = document.state;
    final unchanged = document.regenerate(changes: {'x': 40});
    expect(unchanged.status, CadRegenerationStatus.unchanged);
    expect(identical(unchanged.state, old), isTrue);
    expect(unchanged.stats.scheduledFeatures, 0);
    expect(unchanged.stats.stateEntriesCopied, 0);
    final unrelated = document.regenerate(changes: {'unused': 1});
    expect(unrelated.status, CadRegenerationStatus.committed);
    expect(unrelated.rebuiltFeatures, isEmpty);
    expect(identical(unrelated.state.outputs, old.outputs), isTrue);
    expect(identical(unrelated.state.featureRevisions, old.featureRevisions),
        isTrue);
    expect(unrelated.stats.stateDirectoryEntriesCopied, 0);
    expect(old.parameters['unused'], 0);
    expect(unrelated.state.parameters['unused'], 1);
  });

  test('public output and revision maps retain the complete read-only Map API',
      () {
    final document = CadFeatureDocument(
        kernel: _kernel,
        parameters: CadParameters({}),
        features: [_constant('a', 1), _constant('b', 2)]);
    expect(document.state.outputs, isEmpty);
    expect(document.regenerate().isSuccess, isTrue);
    final outputs = document.state.outputs;
    final revisions = document.state.featureRevisions;
    expect(outputs.keys, ['a', 'b']);
    expect(outputs.values.map((value) => (value as _Value).number), [1, 2]);
    expect(outputs.entries.map((entry) => entry.key), ['a', 'b']);
    expect(outputs.containsKey('a'), isTrue);
    expect(outputs.containsKey('missing'), isFalse);
    final Map<Object?, Object?> broad = outputs;
    expect(broad.containsKey(123), isFalse);
    expect(broad[123], isNull);
    expect(broad[null], isNull);
    expect(outputs.containsValue(outputs['b']), isTrue);
    expect(revisions, {'a': 1, 'b': 1});
    expect(revisions.cast<String, num>()['a'], 1);
    final seen = <String>[];
    outputs.forEach((key, value) => seen.add(key));
    expect(seen, ['a', 'b']);
    expect(() => outputs['a'] = const _Value(9), throwsUnsupportedError);
    expect(
        () => outputs.addAll({'c': const _Value(9)}), throwsUnsupportedError);
    expect(() => outputs.addEntries([const MapEntry('c', _Value(9))]),
        throwsUnsupportedError);
    expect(() => outputs.remove('a'), throwsUnsupportedError);
    expect(
        () => outputs.removeWhere((_, value) => true), throwsUnsupportedError);
    expect(outputs.clear, throwsUnsupportedError);
    expect(() => outputs.update('a', (_) => const _Value(9)),
        throwsUnsupportedError);
    expect(() => outputs.updateAll((_, value) => const _Value(9)),
        throwsUnsupportedError);
    expect(() => outputs.putIfAbsent('c', () => const _Value(9)),
        throwsUnsupportedError);
    expect(() => (outputs.keys as List<String>)[0] = 'changed',
        throwsUnsupportedError);
    expect(() => revisions['a'] = 5, throwsUnsupportedError);
    expect(revisions.clear, throwsUnsupportedError);
    expect(
        () => revisions.cast<String, num>()['a'] = 2, throwsUnsupportedError);
  });

  test('rejected downstream candidates never enter the shared committed store',
      () {
    final previousValues = <int?>[];
    final document = CadFeatureDocument(
        kernel: _kernel,
        parameters: CadParameters({'x': 1}),
        features: [
          CadFeatureNode(
              id: 'root',
              parameterDependencies: ['x'],
              evaluate: (context) {
                previousValues.add(context.previousOutput<_Value>()?.number);
                return CadKernelResult.success(
                    _Value(context.parameters['x'].toInt()));
              }),
          for (var i = 1; i < 260; i++) _constant('unrelated$i', i),
          CadFeatureNode(
              id: 'checked',
              dependencies: ['root'],
              evaluate: (context) {
                final value = context.input<_Value>('root');
                if (value.number < 0) {
                  return CadKernelResult.failure(CadKernelStatus.invalidInput,
                      [const CadIssue('negative', 'Expected positive value.')]);
                }
                return CadKernelResult.success(_Value(value.number * 3));
              }),
        ]);
    expect(document.regenerate().isSuccess, isTrue);
    final initial = document.state;
    final failure = document.regenerate(changes: {'x': -2});
    expect(failure.status, CadRegenerationStatus.rejected);
    expect(failure.failedFeature, 'checked');
    expect(identical(failure.state, initial), isTrue);
    expect(failure.state.output<_Value>('root').number, 1);
    expect(failure.state.output<_Value>('checked').number, 3);
    expect(failure.stats.stateEntriesCopied, 0);
    final success = document.regenerate(changes: {'x': 4});
    expect(success.state.output<_Value>('checked').number, 12);
    expect(previousValues, [null, 1, 1]);
    expect(initial.output<_Value>('checked').number, 3);
    expect(initial.featureRevisions['checked'], 1);
    expect(success.state.featureRevisions['checked'], 2);
    expect(
        identical(initial.outputs['unrelated150'],
            success.state.outputs['unrelated150']),
        isTrue);
  });

  test('random DAG edits match an independent full-recomputation oracle', () {
    for (var seed = 0; seed < 30; seed++) {
      final random = math.Random(seed);
      const count = 80;
      final dependencies = <List<int>>[];
      final parameter = <int?>[];
      for (var i = 0; i < count; i++) {
        dependencies.add({
          for (var j = 0; j < 3 && i > 0; j++) random.nextInt(i),
        }.toList());
        parameter.add(random.nextBool() ? random.nextInt(3) : null);
      }
      final features = [
        for (var i = 0; i < count; i++)
          CadFeatureNode(
              id: 'f$i',
              dependencies: [
                for (final dependency in dependencies[i]) 'f$dependency'
              ],
              parameterDependencies:
                  parameter[i] == null ? [] : ['p${parameter[i]}'],
              evaluate: (context) => CadKernelResult.success(_Value((i +
                      (parameter[i] == null
                          ? 0
                          : context.parameters['p${parameter[i]}'].toInt()) +
                      dependencies[i].fold<int>(
                          0,
                          (sum, dependency) =>
                              sum +
                              context.input<_Value>('f$dependency').number)) %
                  1000003))),
      ]..shuffle(random);
      final document = CadFeatureDocument(
          kernel: _kernel,
          parameters: CadParameters({'p0': 1, 'p1': 2, 'p2': 3}),
          features: features);
      final first = document.regenerate();
      expect(first.isSuccess, isTrue);
      final order = first.rebuiltFeatures;
      final p = [1, 2, 3];
      final revisions = List.filled(count, 1);
      for (var edit = 0; edit < 20; edit++) {
        final changed = random.nextInt(3);
        p[changed]++;
        final dirty = <int>{};
        final expected = <int>[];
        for (var i = 0; i < count; i++) {
          if (parameter[i] == changed || dependencies[i].any(dirty.contains)) {
            dirty.add(i);
            revisions[i]++;
          }
          expected.add((i +
                  (parameter[i] == null ? 0 : p[parameter[i]!]) +
                  dependencies[i].fold<int>(
                      0, (sum, dependency) => sum + expected[dependency])) %
              1000003);
        }
        final previous = document.state;
        final result =
            document.regenerate(changes: {'p$changed': p[changed].toDouble()});
        expect(result.isSuccess, isTrue, reason: 'seed=$seed edit=$edit');
        expect(result.rebuiltFeatures,
            order.where((id) => dirty.contains(int.parse(id.substring(1)))));
        for (var i = 0; i < count; i++) {
          expect(result.state.output<_Value>('f$i').number, expected[i],
              reason: 'seed=$seed edit=$edit feature=$i');
          expect(result.state.featureRevisions['f$i'], revisions[i]);
          if (!dirty.contains(i)) {
            expect(
                identical(previous.outputs['f$i'], result.state.outputs['f$i']),
                isTrue);
          }
        }
      }
    }
  });

  test('compiled declarations snapshot mutable subclass metadata', () {
    final node = _MutableDeclaration();
    final nodes = <CadFeatureNode>[node];
    final document = CadFeatureDocument(
        kernel: _kernel, parameters: CadParameters({'x': 2}), features: nodes);
    nodes.clear();
    node.inputs.add('missing');
    node.parameters.clear();
    expect(document.features.single.dependencies, isEmpty);
    expect(document.features.single.parameterDependencies, {'x'});
    expect(document.regenerate().state.output<double>('value'), 2);
    expect(document.regenerate(changes: {'x': 3}).state.output<double>('value'),
        3);
  });

  test('spoofed runtimeType cannot bypass the declaration snapshot', () {
    final node = _RuntimeTypeSpoof();
    final document = CadFeatureDocument(
        kernel: _kernel,
        parameters: CadParameters({'x': 1, 'y': 10}),
        features: [node]);
    expect(document.regenerate().state.output<double>('value'), 1);
    node.selected = 'y';
    node.featureName = 'changed';
    final unrelated = document.regenerate(changes: {'y': 20});
    expect(unrelated.rebuiltFeatures, isEmpty);
    expect(document.features.single.id, 'value');
    expect(document.features.single.parameterDependencies, {'x'});
    expect(document.state.output<double>('value'), 1);
    final edited = document.regenerate(changes: {'x': 2});
    expect(edited.rebuiltFeatures, ['value']);
    expect(edited.state.output<double>('value'), 2);
    expect(edited.state.outputs.keys, ['value']);
    expect(edited.state.featureRevisions['value'], 2);
  });

  test('document subclass getters cannot replace private compiled declarations',
      () {
    final node = _SelectableDeclaration();
    final original = <CadFeatureNode>[node];
    final document = _OverriddenDocumentFeatures(original);
    expect(document.publicGetterCalls, 0);
    expect(document.regenerate().state.output<double>('value'), 1);
    node.selected = 'y';
    original.add(_constant('late', 99));
    final unrelated = document.regenerate(changes: {'y': 20});
    expect(unrelated.rebuiltFeatures, isEmpty);
    expect(unrelated.state.output<double>('value'), 1);
    final edited = document.regenerate(changes: {'x': 5});
    expect(edited.rebuiltFeatures, ['value']);
    expect(edited.state.output<double>('value'), 5);
    expect(edited.state.outputs.keys, ['value']);
    expect(document.publicGetterCalls, 0);
  });

  test('empty graphs and invalid graph declarations preserve their contracts',
      () {
    final empty = CadFeatureDocument(
        kernel: _kernel, parameters: CadParameters({'x': 1}), features: []);
    expect(empty.regenerate().status, CadRegenerationStatus.unchanged);
    final changed = empty.regenerate(changes: {'x': 2});
    expect(changed.status, CadRegenerationStatus.committed);
    expect(changed.state.outputs, isEmpty);
    expect(changed.state.featureRevisions, isEmpty);
    expect(empty.regenerate().status, CadRegenerationStatus.unchanged);
    CadFeatureDocument document(List<CadFeatureNode> features) =>
        CadFeatureDocument(
            kernel: _kernel, parameters: CadParameters({}), features: features);
    CadFeatureNode node(String id, List<String> dependencies) => CadFeatureNode(
        id: id,
        dependencies: dependencies,
        evaluate: (_) => CadKernelResult.success(0));
    expect(
        () => document([node('a', []), node('a', [])]),
        throwsA(isA<ArgumentError>().having(
            (e) => e.message, 'message', contains('Duplicate feature ID a'))));
    expect(
        () => document([
              node('a', []),
              node('b', ['a', 'a'])
            ]),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message',
            contains('Duplicate dependency on b'))));
    expect(
        () => document([
              node('a', ['missing'])
            ]),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message',
            contains('Missing feature dependency missing'))));
    expect(
        () => document([
              node('a', ['b']),
              node('b', ['a'])
            ]),
        throwsA(isA<ArgumentError>().having((e) => e.message, 'message',
            contains('Feature dependency cycle at a'))));
    expect(
        () => document([
              CadFeatureNode(
                  id: 'a',
                  parameterDependencies: ['missing'],
                  evaluate: (_) => CadKernelResult.success(0))
            ]),
        throwsArgumentError);
  });
}
