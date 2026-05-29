/// FlatZinc tokenizer + recursive-descent parser.
///
/// Implements the M1 subset described in MINIZINC_PLAN.md:
///   - variable declarations: `var int: x;`, `var L..U: x;`,
///     `var bool: b;`, `var {v1,v2,...}: x;`
///   - array variable declarations: `array[1..N] of var T: a;` and the
///     aliased form `... : a = [...];`
///   - parameter declarations: `int: n = 5;`, `bool: b = true;`,
///     `array[1..N] of int: a = [...];`
///   - constraint items: `constraint name(arg, ...);` (stored, not yet
///     lowered until M2)
///   - solve directive: `solve [::annot]* satisfy|minimize|maximize ...;`
///
/// All errors are reported as `FormatException` with line/column. We
/// deliberately throw `FormatException` rather than `ArgumentError`
/// here so callers can distinguish parse errors from invalid problem
/// construction; the lowering pass uses `ArgumentError` to match the
/// rest of the library's convention.
library;

import 'ast.dart';

/// Parse a FlatZinc source string into an AST. Throws [FormatException]
/// on any tokenization or grammar error; the message embeds a
/// line/column and a one-line snippet to make it easy to locate the
/// problem in machine-generated `.fzn` files.
FlatZincModel parseFlatZinc(String source) {
  final tokens = _tokenize(source);
  final parser = _Parser(tokens, source);
  return parser.parseModel();
}

// ---------------------------------------------------------------------------
// Tokenizer
// ---------------------------------------------------------------------------

enum _TokKind {
  identifier,
  intLit,
  boolLit,
  // keywords
  kwVar,
  kwArray,
  kwOf,
  kwInt,
  kwBool,
  kwSet,
  kwSolve,
  kwSatisfy,
  kwMinimize,
  kwMaximize,
  kwConstraint,
  kwPredicate,
  kwAnnotation,
  // punctuation
  lparen,
  rparen,
  lbracket,
  rbracket,
  lbrace,
  rbrace,
  comma,
  semicolon,
  colon,
  doubleColon,
  equals,
  dotDot,
  eof,
}

class _Token {
  const _Token(this.kind, this.lexeme, this.line, this.column,
      {this.intValue, this.boolValue});

  final _TokKind kind;
  final String lexeme;
  final int line;
  final int column;
  // Populated for intLit tokens only.
  final int? intValue;
  // Populated for boolLit tokens only.
  final bool? boolValue;

  @override
  String toString() => '$kind($lexeme) @ $line:$column';
}

const _keywords = <String, _TokKind>{
  'var': _TokKind.kwVar,
  'array': _TokKind.kwArray,
  'of': _TokKind.kwOf,
  'int': _TokKind.kwInt,
  'bool': _TokKind.kwBool,
  'set': _TokKind.kwSet,
  'solve': _TokKind.kwSolve,
  'satisfy': _TokKind.kwSatisfy,
  'minimize': _TokKind.kwMinimize,
  'maximize': _TokKind.kwMaximize,
  'constraint': _TokKind.kwConstraint,
  'predicate': _TokKind.kwPredicate,
  'annotation': _TokKind.kwAnnotation,
};

List<_Token> _tokenize(String src) {
  final tokens = <_Token>[];
  var i = 0;
  var line = 1;
  var col = 1;
  final n = src.length;

  void advance(int count) {
    for (var k = 0; k < count; k++) {
      if (src.codeUnitAt(i) == 0x0A) {
        line++;
        col = 1;
      } else {
        col++;
      }
      i++;
    }
  }

  while (i < n) {
    final c = src.codeUnitAt(i);

    // Whitespace.
    if (c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D) {
      advance(1);
      continue;
    }

    // Line comment: `% ... newline`. FlatZinc allows these even though
    // generated files rarely contain them.
    if (c == 0x25) {
      while (i < n && src.codeUnitAt(i) != 0x0A) {
        advance(1);
      }
      continue;
    }

    final startLine = line;
    final startCol = col;

    // Identifier / keyword. FlatZinc identifiers can also contain
    // brackets in some encoders (`x[1]` is sometimes written as a
    // single identifier in the wild); we treat brackets as separate
    // tokens to keep the grammar regular.
    if (_isIdentStart(c)) {
      final start = i;
      while (i < n && _isIdentCont(src.codeUnitAt(i))) {
        advance(1);
      }
      final lex = src.substring(start, i);
      if (lex == 'true') {
        tokens.add(_Token(_TokKind.boolLit, lex, startLine, startCol,
            boolValue: true));
      } else if (lex == 'false') {
        tokens.add(_Token(_TokKind.boolLit, lex, startLine, startCol,
            boolValue: false));
      } else if (_keywords.containsKey(lex)) {
        tokens.add(_Token(_keywords[lex]!, lex, startLine, startCol));
      } else {
        tokens.add(_Token(_TokKind.identifier, lex, startLine, startCol));
      }
      continue;
    }

    // Integer literal (possibly signed `-`).
    if (_isDigit(c) ||
        (c == 0x2D && i + 1 < n && _isDigit(src.codeUnitAt(i + 1)))) {
      final start = i;
      if (c == 0x2D) advance(1);
      while (i < n && _isDigit(src.codeUnitAt(i))) {
        advance(1);
      }
      final lex = src.substring(start, i);
      tokens.add(_Token(_TokKind.intLit, lex, startLine, startCol,
          intValue: int.parse(lex)));
      continue;
    }

    // Two-character punctuation: `..` and `::`.
    if (c == 0x2E && i + 1 < n && src.codeUnitAt(i + 1) == 0x2E) {
      tokens.add(_Token(_TokKind.dotDot, '..', startLine, startCol));
      advance(2);
      continue;
    }
    if (c == 0x3A && i + 1 < n && src.codeUnitAt(i + 1) == 0x3A) {
      tokens.add(_Token(_TokKind.doubleColon, '::', startLine, startCol));
      advance(2);
      continue;
    }

    // Single-character punctuation.
    _TokKind? kind;
    switch (c) {
      case 0x28:
        kind = _TokKind.lparen;
        break;
      case 0x29:
        kind = _TokKind.rparen;
        break;
      case 0x5B:
        kind = _TokKind.lbracket;
        break;
      case 0x5D:
        kind = _TokKind.rbracket;
        break;
      case 0x7B:
        kind = _TokKind.lbrace;
        break;
      case 0x7D:
        kind = _TokKind.rbrace;
        break;
      case 0x2C:
        kind = _TokKind.comma;
        break;
      case 0x3B:
        kind = _TokKind.semicolon;
        break;
      case 0x3A:
        kind = _TokKind.colon;
        break;
      case 0x3D:
        kind = _TokKind.equals;
        break;
    }
    if (kind != null) {
      tokens.add(_Token(kind, String.fromCharCode(c), startLine, startCol));
      advance(1);
      continue;
    }

    throw FormatException('FlatZinc tokenizer: unexpected character '
        "'${String.fromCharCode(c)}' at line $startLine, column $startCol");
  }

  tokens.add(_Token(_TokKind.eof, '', line, col));
  return tokens;
}

bool _isIdentStart(int c) =>
    (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F;
bool _isIdentCont(int c) => _isIdentStart(c) || _isDigit(c);
bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

class _Parser {
  _Parser(this._toks, this._src);

  final List<_Token> _toks;
  final String _src;
  int _pos = 0;

  _Token get _peek => _toks[_pos];
  _Token _advance() => _toks[_pos++];

  bool _check(_TokKind kind) => _peek.kind == kind;

  bool _match(_TokKind kind) {
    if (_check(kind)) {
      _advance();
      return true;
    }
    return false;
  }

  _Token _expect(_TokKind kind, String context) {
    if (_peek.kind == kind) return _advance();
    throw _error(
        "expected $context, got '${_peek.lexeme}' (${_peek.kind.name})", _peek);
  }

  FormatException _error(String msg, _Token at) {
    final snippet = _lineSnippet(at.line);
    return FormatException(
        'FlatZinc parser: $msg at line ${at.line}, column ${at.column}\n'
        '  $snippet');
  }

  String _lineSnippet(int line) {
    var start = 0;
    var currentLine = 1;
    while (start < _src.length && currentLine < line) {
      if (_src.codeUnitAt(start) == 0x0A) currentLine++;
      start++;
    }
    var end = start;
    while (end < _src.length && _src.codeUnitAt(end) != 0x0A) {
      end++;
    }
    return _src.substring(start, end);
  }

  // model ::= predicate-decl* item* solve-item
  FlatZincModel parseModel() {
    final params = <ParamDecl>[];
    final vars = <VarDecl>[];
    final arrays = <ArrayVarDecl>[];
    final constraints = <ConstraintItem>[];
    SolveItem? solve;

    while (!_check(_TokKind.eof)) {
      // Predicate and annotation declarations are skipped — they
      // describe user-defined constraints that the MiniZinc compiler
      // has already expanded. FlatZinc files only contain them when
      // produced by certain pipelines.
      if (_check(_TokKind.kwPredicate) || _check(_TokKind.kwAnnotation)) {
        _skipDeclaration();
        continue;
      }
      if (_check(_TokKind.kwSolve)) {
        solve = _parseSolve();
        break; // solve is always last
      }
      if (_check(_TokKind.kwConstraint)) {
        constraints.add(_parseConstraint());
        continue;
      }
      if (_check(_TokKind.kwArray)) {
        _parseArrayDecl(params: params, arrays: arrays);
        continue;
      }
      if (_check(_TokKind.kwVar)) {
        vars.add(_parseVarDecl());
        continue;
      }
      // Parameter scalar: `int:` or `bool:` ...
      if (_check(_TokKind.kwInt) || _check(_TokKind.kwBool)) {
        params.add(_parseScalarParam());
        continue;
      }
      // Set parameter: `set of int: S = 1..5;` / `set of int: S = {1,3};`.
      if (_check(_TokKind.kwSet)) {
        params.add(_parseSetParam());
        continue;
      }

      throw _error("unexpected token '${_peek.lexeme}' at top level", _peek);
    }

    if (solve == null) {
      throw _error("missing 'solve' item at end of file", _peek);
    }
    if (!_check(_TokKind.eof)) {
      throw _error("expected end of file after 'solve' item", _peek);
    }

    return FlatZincModel(
      params: params,
      vars: vars,
      arrays: arrays,
      constraints: constraints,
      solve: solve,
    );
  }

  void _skipDeclaration() {
    while (!_check(_TokKind.semicolon) && !_check(_TokKind.eof)) {
      _advance();
    }
    if (_check(_TokKind.semicolon)) _advance();
  }

  // var-decl ::= 'var' type ':' identifier annotations [ '=' expr ] ';'
  VarDecl _parseVarDecl() {
    final start = _peek;
    _expect(_TokKind.kwVar, "'var'");
    final type = _parseVarType(forArray: false);
    _expect(_TokKind.colon, "':'");
    final nameTok = _expect(_TokKind.identifier, 'variable name');
    final annotations = _parseAnnotations();
    AstExpr? rhs;
    if (_match(_TokKind.equals)) {
      rhs = _parseExpr();
    }
    _expect(_TokKind.semicolon, "';'");
    return VarDecl(
      name: nameTok.lexeme,
      type: type,
      rhs: rhs,
      annotations: annotations,
      line: start.line,
      column: start.column,
    );
  }

  // type ::= 'int' | 'bool' | int '..' int | '{' int (',' int)* '}'
  //        | 'set' 'of' ('int' | int '..' int | '{' int (',' int)* '}')
  VarType _parseVarType({required bool forArray}) {
    if (_match(_TokKind.kwInt)) {
      return const VarTypeInt();
    }
    if (_match(_TokKind.kwBool)) {
      return const VarTypeBool();
    }
    if (_match(_TokKind.kwSet)) {
      _expect(_TokKind.kwOf, "'of' after 'set'");
      return _parseSetElementType();
    }
    if (_check(_TokKind.intLit)) {
      final lo = _advance().intValue!;
      _expect(_TokKind.dotDot, "'..'");
      final hiTok = _expect(_TokKind.intLit, 'upper bound');
      final hi = hiTok.intValue!;
      if (lo > hi) {
        throw _error('range lower bound $lo exceeds upper bound $hi', _peek);
      }
      return VarTypeRange(lo, hi);
    }
    if (_match(_TokKind.lbrace)) {
      final vals = <int>[];
      if (!_check(_TokKind.rbrace)) {
        vals.add(_expectInt('set element').intValue!);
        while (_match(_TokKind.comma)) {
          vals.add(_expectInt('set element').intValue!);
        }
      }
      _expect(_TokKind.rbrace, "'}'");
      if (vals.isEmpty) {
        throw _error('set-typed variable must have at least one value', _peek);
      }
      return VarTypeSet(vals);
    }
    throw _error(
        forArray
            ? 'expected element type after \'of\' (int, bool, or range)'
            : 'expected variable type (int, bool, or range)',
        _peek);
  }

  // set-element-type ::= 'int' | int '..' int | '{' int (',' int)* '}'
  // Consumes the element type after `set of` and returns the
  // corresponding set-variable type. `set of int` (unbounded) is
  // parsed but flagged `bounded: false`; the lowering pass rejects it
  // with a clear message rather than failing here, so a model that
  // declares an unbounded set var only as scratch (never solved) still
  // parses.
  VarTypeSetOfInt _parseSetElementType() {
    if (_match(_TokKind.kwInt)) {
      return const VarTypeSetOfInt(<int>[], bounded: false);
    }
    if (_check(_TokKind.intLit)) {
      final lo = _advance().intValue!;
      _expect(_TokKind.dotDot, "'..'");
      final hi = _expect(_TokKind.intLit, 'upper bound').intValue!;
      if (lo > hi) {
        throw _error('set range lower bound $lo exceeds upper bound $hi',
            _peek);
      }
      return VarTypeSetOfInt(<int>[for (var v = lo; v <= hi; v++) v]);
    }
    if (_match(_TokKind.lbrace)) {
      final vals = <int>{};
      if (!_check(_TokKind.rbrace)) {
        vals.add(_expectInt('set element').intValue!);
        while (_match(_TokKind.comma)) {
          vals.add(_expectInt('set element').intValue!);
        }
      }
      _expect(_TokKind.rbrace, "'}'");
      // An empty universe parses, but the lowering pass rejects it (the
      // set-variable layer needs at least one candidate element).
      final sorted = vals.toList()..sort();
      return VarTypeSetOfInt(sorted);
    }
    throw _error("expected 'int', a range, or '{...}' after 'set of'", _peek);
  }

  _Token _expectInt(String context) =>
      _expect(_TokKind.intLit, '$context (integer literal)');

  // array-decl ::= 'array' '[' int '..' int ']' 'of' [ 'var' ] type ':'
  //                identifier annotations [ '=' arrayLit ] ';'
  void _parseArrayDecl({
    required List<ParamDecl> params,
    required List<ArrayVarDecl> arrays,
  }) {
    final start = _peek;
    _expect(_TokKind.kwArray, "'array'");
    _expect(_TokKind.lbracket, "'['");
    final lo = _expectInt('array lower bound').intValue!;
    _expect(_TokKind.dotDot, "'..'");
    final hi = _expectInt('array upper bound').intValue!;
    _expect(_TokKind.rbracket, "']'");
    _expect(_TokKind.kwOf, "'of'");
    final isVar = _match(_TokKind.kwVar);
    final elemType = _parseVarType(forArray: true);
    _expect(_TokKind.colon, "':'");
    final nameTok = _expect(_TokKind.identifier, 'array name');
    final annotations = _parseAnnotations();
    AstExpr? rhs;
    if (_match(_TokKind.equals)) {
      rhs = _parseExpr();
    }
    _expect(_TokKind.semicolon, "';'");

    // FlatZinc arrays are 1-indexed; the lower bound must be 1 by the
    // spec. We accept anything but record the length as `hi - lo + 1`
    // to keep the AST robust.
    if (lo != 1) {
      throw _error(
          'array lower bound must be 1, got $lo (FlatZinc index convention)',
          start);
    }
    final length = hi - lo + 1;

    if (isVar) {
      List<AstExpr>? elements;
      if (rhs != null) {
        if (rhs is! AstArrayLit) {
          throw _error(
              "array variable rhs must be an array literal '[...]'", start);
        }
        if (rhs.elements.length != length) {
          throw _error(
              'array literal has ${rhs.elements.length} elements but '
              'array has length $length',
              start);
        }
        elements = rhs.elements;
      }
      arrays.add(ArrayVarDecl(
        name: nameTok.lexeme,
        length: length,
        elementType: elemType,
        elements: elements,
        annotations: annotations,
        line: start.line,
        column: start.column,
      ));
    } else {
      // Parameter array.
      if (rhs == null) {
        throw _error(
            "parameter array '${nameTok.lexeme}' must have an initializer",
            start);
      }
      String kind;
      switch (elemType) {
        case VarTypeInt():
        case VarTypeRange():
        case VarTypeSet():
          kind = 'array_int';
        case VarTypeBool():
          kind = 'array_bool';
        case VarTypeSetOfInt():
          throw _error(
              "parameter array of 'set of int' is not supported in this "
              'FlatZinc subset',
              start);
      }
      params.add(ParamDecl(name: nameTok.lexeme, kind: kind, value: rhs));
    }
  }

  // scalar-param ::= ('int' | 'bool') ':' identifier '=' expr ';'
  ParamDecl _parseScalarParam() {
    final kindTok = _advance();
    final kind = kindTok.kind == _TokKind.kwInt ? 'int' : 'bool';
    _expect(_TokKind.colon, "':'");
    final nameTok = _expect(_TokKind.identifier, 'parameter name');
    _expect(_TokKind.equals, "'='");
    final value = _parseExpr();
    _expect(_TokKind.semicolon, "';'");
    return ParamDecl(name: nameTok.lexeme, kind: kind, value: value);
  }

  // set-param ::= 'set' 'of' set-element-type ':' identifier '=' expr ';'
  // The declared element type only bounds the value, which is itself a
  // set literal (`1..5` or `{1, 3, 5}`); we discard the element type and
  // keep the literal as the parameter value (kind `'set'`).
  ParamDecl _parseSetParam() {
    _expect(_TokKind.kwSet, "'set'");
    _expect(_TokKind.kwOf, "'of' after 'set'");
    _parseSetElementType(); // bounds only; discarded for a constant set
    _expect(_TokKind.colon, "':'");
    final nameTok = _expect(_TokKind.identifier, 'parameter name');
    _expect(_TokKind.equals, "'='");
    final value = _parseExpr();
    _expect(_TokKind.semicolon, "';'");
    return ParamDecl(name: nameTok.lexeme, kind: 'set', value: value);
  }

  // constraint ::= 'constraint' identifier '(' arglist ')' annotations ';'
  ConstraintItem _parseConstraint() {
    final start = _peek;
    _expect(_TokKind.kwConstraint, "'constraint'");
    final nameTok = _expect(_TokKind.identifier, 'constraint name');
    _expect(_TokKind.lparen, "'('");
    final args = <AstExpr>[];
    if (!_check(_TokKind.rparen)) {
      args.add(_parseExpr());
      while (_match(_TokKind.comma)) {
        args.add(_parseExpr());
      }
    }
    _expect(_TokKind.rparen, "')'");
    final annotations = _parseAnnotations();
    _expect(_TokKind.semicolon, "';'");
    return ConstraintItem(
      name: nameTok.lexeme,
      args: args,
      annotations: annotations,
      line: start.line,
      column: start.column,
    );
  }

  // solve ::= 'solve' annotations ('satisfy' | 'minimize' expr | 'maximize' expr) ';'
  SolveItem _parseSolve() {
    _expect(_TokKind.kwSolve, "'solve'");
    final annotations = _parseAnnotations();
    String kind;
    AstExpr? objective;
    if (_match(_TokKind.kwSatisfy)) {
      kind = 'satisfy';
    } else if (_match(_TokKind.kwMinimize)) {
      kind = 'minimize';
      objective = _parseExpr();
    } else if (_match(_TokKind.kwMaximize)) {
      kind = 'maximize';
      objective = _parseExpr();
    } else {
      throw _error(
          "expected 'satisfy', 'minimize', or 'maximize' after 'solve'", _peek);
    }
    _expect(_TokKind.semicolon, "';'");
    return SolveItem(
      kind: kind,
      objective: objective,
      annotations: annotations,
    );
  }

  // annotations ::= ( '::' annotation-expr )*
  List<Annotation> _parseAnnotations() {
    final out = <Annotation>[];
    while (_match(_TokKind.doubleColon)) {
      final nameTok = _expect(_TokKind.identifier, 'annotation name');
      final args = <AstExpr>[];
      if (_match(_TokKind.lparen)) {
        if (!_check(_TokKind.rparen)) {
          args.add(_parseExpr());
          while (_match(_TokKind.comma)) {
            args.add(_parseExpr());
          }
        }
        _expect(_TokKind.rparen, "')'");
      }
      out.add(Annotation(nameTok.lexeme, args));
    }
    return out;
  }

  // expr ::= intLit | boolLit | identifier ['[' int ']'] | '[' exprs? ']'
  //        | '{' int (',' int)* '}' | int '..' int
  AstExpr _parseExpr() {
    final t = _peek;
    if (t.kind == _TokKind.intLit) {
      _advance();
      // Could be the start of a range literal `1..5`.
      if (_check(_TokKind.dotDot)) {
        _advance();
        final hi = _expectInt('range upper bound').intValue!;
        return AstSetLit([AstRange(t.intValue!, hi)]);
      }
      return AstIntLit(t.intValue!);
    }
    if (t.kind == _TokKind.boolLit) {
      _advance();
      return AstBoolLit(t.boolValue!);
    }
    if (t.kind == _TokKind.identifier) {
      _advance();
      if (_match(_TokKind.lbracket)) {
        final idx = _expectInt('array index').intValue!;
        _expect(_TokKind.rbracket, "']'");
        return AstIdent(t.lexeme, index: idx);
      }
      // Nested annotation call (only appears inside annotation arg
      // lists, e.g. `seq_search([int_search(...), int_search(...)])`).
      // Represented as a first-class expression node; lowering rejects
      // it in positions that don't expect an annotation.
      if (_match(_TokKind.lparen)) {
        final args = <AstExpr>[];
        if (!_check(_TokKind.rparen)) {
          args.add(_parseExpr());
          while (_match(_TokKind.comma)) {
            args.add(_parseExpr());
          }
        }
        _expect(_TokKind.rparen, "')'");
        return AstAnnotationCall(t.lexeme, args);
      }
      return AstIdent(t.lexeme);
    }
    if (_match(_TokKind.lbracket)) {
      final elems = <AstExpr>[];
      if (!_check(_TokKind.rbracket)) {
        elems.add(_parseExpr());
        while (_match(_TokKind.comma)) {
          elems.add(_parseExpr());
        }
      }
      _expect(_TokKind.rbracket, "']'");
      return AstArrayLit(elems);
    }
    if (_match(_TokKind.lbrace)) {
      final ranges = <AstRange>[];
      if (!_check(_TokKind.rbrace)) {
        final v = _expectInt('set element').intValue!;
        ranges.add(AstRange(v, v));
        while (_match(_TokKind.comma)) {
          final w = _expectInt('set element').intValue!;
          ranges.add(AstRange(w, w));
        }
      }
      _expect(_TokKind.rbrace, "'}'");
      return AstSetLit(ranges);
    }
    throw _error("expected expression, got '${t.lexeme}'", t);
  }
}
