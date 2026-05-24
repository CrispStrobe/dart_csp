// String constraint parsing functionality for the CSP library.

import 'builtin_constraints.dart';
import 'types.dart';

/// Exception thrown when a constraint string cannot be parsed
class ConstraintParseException implements Exception {
  ConstraintParseException(this.message, this.constraint);
  final String message;
  final String constraint;

  @override
  String toString() => 'ConstraintParseException: $message in "$constraint"';
}

/// Represents a parsed constraint with its variables and predicate
class ParsedConstraint {
  ParsedConstraint(this.predicate, this.variables, this.type);
  final dynamic
      predicate; // BinaryPredicate, NaryPredicate, or VariableConstraint
  final List<String> variables;
  final ConstraintType type;
}

/// Types of constraints for better handling
enum ConstraintType {
  binary,
  nary,
  variableSum,
  variableProduct,
}

/// Variable constraint where one variable equals a computed value from others
abstract class VariableConstraint {
  VariableConstraint(this.targetVariable, this.sourceVariables);
  final String targetVariable;
  final List<String> sourceVariables;

  NaryPredicate toPredicate();
}

/// Constraint where one variable equals the sum of others: C = A + B
class VariableSumConstraint extends VariableConstraint {
  VariableSumConstraint(super.targetVariable, super.sourceVariables,
      {this.multipliers});
  final List<num>? multipliers;

  @override
  NaryPredicate toPredicate() => (Map<String, dynamic> assignment) {
        final targetValue = assignment[targetVariable];
        if (targetValue == null) return true;

        num sum = 0;
        for (var i = 0; i < sourceVariables.length; i++) {
          final value = assignment[sourceVariables[i]];
          if (value == null) return true;
          final multiplier = multipliers?[i] ?? 1;
          sum += (value as num) * multiplier;
        }

        return sum == (targetValue as num);
      };
}

/// Constraint where one variable equals the product of others: C = A * B
class VariableProductConstraint extends VariableConstraint {
  VariableProductConstraint(super.targetVariable, super.sourceVariables);

  @override
  NaryPredicate toPredicate() => (Map<String, dynamic> assignment) {
        final targetValue = assignment[targetVariable];
        if (targetValue == null) return true;

        num product = 1;
        for (final varName in sourceVariables) {
          final value = assignment[varName];
          if (value == null) return true;
          product *= value as num;
        }

        return product == (targetValue as num);
      };
}

/// Advanced expression evaluator for mathematical expressions
class ExpressionEvaluator {
  /// Evaluates a mathematical expression with variables substituted
  static num evaluateNumeric(
      String expression, Map<String, dynamic> variables) {
    // Replace variables with their values
    var substituted = expression;

    // Sort variables by length (longest first) to avoid partial matches
    final sortedVars = variables.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final variable in sortedVars) {
      final value = variables[variable];
      if (value != null) {
        substituted = substituted.replaceAll(
            RegExp(r'\b' + RegExp.escape(variable) + r'\b'), value.toString());
      }
    }

    return _evaluateExpression(substituted);
  }

  /// Evaluates boolean expressions like "A + B > 5"
  static bool evaluateBoolean(
      String expression, Map<String, dynamic> variables) {
    // Handle comparison operators
    final comparisons = ['>=', '<=', '==', '!=', '>', '<'];

    for (final op in comparisons) {
      if (expression.contains(op)) {
        final parts = expression.split(op);
        if (parts.length == 2) {
          final left = _evaluateLeftSide(parts[0].trim(), variables);
          final right = _evaluateRightSide(parts[1].trim(), variables);

          switch (op) {
            case '>=':
              return left >= right;
            case '<=':
              return left <= right;
            case '==':
              return (left - right).abs() < 0.0001;
            case '!=':
              return (left - right).abs() >= 0.0001;
            case '>':
              return left > right;
            case '<':
              return left < right;
          }
        }
      }
    }

    throw ArgumentError('Cannot evaluate boolean expression: $expression');
  }

  static num _evaluateLeftSide(
      String expression, Map<String, dynamic> variables) {
    if (expression.contains('+') ||
        expression.contains('-') ||
        expression.contains('*') ||
        expression.contains('/')) {
      return evaluateNumeric(expression, variables);
    }

    // Single variable or number
    if (variables.containsKey(expression)) {
      return variables[expression] as num;
    }

    return double.tryParse(expression) ?? 0;
  }

  static num _evaluateRightSide(
      String expression, Map<String, dynamic> variables) {
    expression = expression.trim();

    // Check if it's a variable
    if (variables.containsKey(expression)) {
      return variables[expression] as num;
    }

    // Check if it's a number
    final number = double.tryParse(expression);
    if (number != null) {
      return number;
    }

    // Try to evaluate as expression
    return evaluateNumeric(expression, variables);
  }

  /// Expression evaluator with proper operator precedence
  static num _evaluateExpression(String expression) {
    expression = expression.replaceAll(' ', '');
    if (expression.isEmpty) return 0;

    // Handle simple cases
    final number = double.tryParse(expression);
    if (number != null) return number;

    // Evaluate with proper precedence: *, / first, then +, -
    return _evaluateAddSub(expression);
  }

  /// Evaluate addition and subtraction (lowest precedence)
  static num _evaluateAddSub(String expr) {
    // Find + and - operators, but ignore those that are part of negative numbers
    final tokens = <String>[];
    final operators = <String>[];

    var currentToken = '';
    var i = 0;

    while (i < expr.length) {
      final char = expr[i];

      if (char == '+' || char == '-') {
        // Check if this is a negative number at the start or after an operator
        final isNegativeNumber = char == '-' &&
            (i == 0 ||
                (i > 0 &&
                    (expr[i - 1] == '+' ||
                        expr[i - 1] == '-' ||
                        expr[i - 1] == '*' ||
                        expr[i - 1] == '/')));

        if (isNegativeNumber) {
          currentToken += char;
        } else {
          // This is an operator
          if (currentToken.isNotEmpty) {
            tokens.add(currentToken);
            currentToken = '';
          }
          operators.add(char);
        }
      } else {
        currentToken += char;
      }
      i++;
    }

    if (currentToken.isNotEmpty) {
      tokens.add(currentToken);
    }

    if (tokens.isEmpty) return 0;
    if (tokens.length == 1) return _evaluateMultDiv(tokens[0]);

    // Evaluate each token for multiplication and division first
    final values = tokens.map(_evaluateMultDiv).toList();

    // Apply addition and subtraction
    var result = values[0];
    for (var i = 0; i < operators.length && i + 1 < values.length; i++) {
      if (operators[i] == '+') {
        result += values[i + 1];
      } else if (operators[i] == '-') {
        result -= values[i + 1];
      }
    }

    return result;
  }

  /// Evaluate multiplication and division (higher precedence)
  static num _evaluateMultDiv(String expr) {
    // Split on * and / operators
    final tokens = <String>[];
    final operators = <String>[];

    var currentToken = '';
    for (var i = 0; i < expr.length; i++) {
      final char = expr[i];
      if (char == '*' || char == '/') {
        if (currentToken.isNotEmpty) {
          tokens.add(currentToken);
          currentToken = '';
        }
        operators.add(char);
      } else {
        currentToken += char;
      }
    }

    if (currentToken.isNotEmpty) {
      tokens.add(currentToken);
    }

    if (tokens.isEmpty) return 0;
    if (tokens.length == 1) return double.tryParse(tokens[0]) ?? 0;

    // Convert tokens to numbers
    final values = tokens.map((token) => double.tryParse(token) ?? 0).toList();

    // Apply multiplication and division left to right
    num result = values[0];
    for (var i = 0; i < operators.length && i + 1 < values.length; i++) {
      if (operators[i] == '*') {
        result *= values[i + 1];
      } else if (operators[i] == '/') {
        if (values[i + 1] != 0) {
          result /= values[i + 1];
        }
      }
    }

    return result;
  }
}

/// Parses string constraints into appropriate constraint objects
class ConstraintParser {
  /// Parse a constraint string and return appropriate constraint and variables
  static ParsedConstraint parseConstraint(
      String constraintStr, Map<String, List<dynamic>> variableDomains) {
    final cleanStr = constraintStr.trim();

    // Extract variable names from the constraint
    final variableNames =
        _extractVariables(cleanStr, variableDomains.keys.toSet());

    // Check if all referenced variables exist
    for (final varName in variableNames) {
      if (!variableDomains.containsKey(varName)) {
        throw ConstraintParseException(
            'Variable "$varName" is not defined', constraintStr);
      }
    }

    if (variableNames.isEmpty) {
      throw ConstraintParseException('No valid variables found', constraintStr);
    }

    // Parse the constraint
    return _parseConstraintLogic(cleanStr, variableNames, variableDomains);
  }

  /// Extract variable names from constraint string
  static List<String> _extractVariables(
      String constraint, Set<String> availableVars) {
    final variables = <String>[];

    // First, find all defined variables in the constraint
    final sortedVars = availableVars.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final variable in sortedVars) {
      // Use word boundary regex to match complete variable names
      if (RegExp(r'\b' + RegExp.escape(variable) + r'\b')
          .hasMatch(constraint)) {
        if (!variables.contains(variable)) {
          variables.add(variable);
        }
      }
    }

    // Also find any variable-like tokens (letters followed by letters/numbers)
    // that might not be defined - this allows us to catch undefined variables
    final allVariableTokens =
        RegExp(r'\b[A-Za-z_][A-Za-z0-9_]*\b').allMatches(constraint);
    for (final match in allVariableTokens) {
      final token = match.group(0)!;
      // Skip if it's a reserved word or number-like
      if (!['in', 'not', 'and', 'or'].contains(token.toLowerCase()) &&
          double.tryParse(token) == null) {
        if (!variables.contains(token)) {
          variables.add(token);
        }
      }
    }

    return variables;
  }

  /// Parse the constraint logic and return appropriate constraint
  static ParsedConstraint _parseConstraintLogic(String constraint,
      List<String> variables, Map<String, List<dynamic>> domains) {
    // 1. Range constraints: 5 <= A + B <= 7
    final rangeConstraint = _parseRangeConstraint(constraint, variables);
    if (rangeConstraint != null) return rangeConstraint;

    // 2. Chained inequalities: A != B != C
    if (constraint.contains('!=')) {
      if (_isChainedInequality(constraint)) {
        return ParsedConstraint(allDifferent(), variables, ConstraintType.nary);
      }
    }

    // 3. Simple binary variable-to-variable constraints: A < B, A > B, A == B, A != B
    if (variables.length == 2) {
      final binaryResult =
          _parseBinaryVariableConstraint(constraint, variables);
      if (binaryResult != null) return binaryResult;
    }

    // 4. Chained ordering: A < B < C
    final orderConstraint = _parseOrderingConstraint(constraint, variables);
    if (orderConstraint != null) return orderConstraint;

    // 5. Variable-to-constant constraints: A == 5, A != 3, A > 10
    if (variables.length == 1) {
      final varConstResult =
          _parseVariableConstantConstraint(constraint, variables);
      if (varConstResult != null) return varConstResult;
    }

    // 6. Variable equations: A + B == C, A * B == C
    final varEquationResult = _parseVariableEquation(constraint, variables);
    if (varEquationResult != null) return varEquationResult;

    // 7. Arithmetic equality: A + B == 10, A * B == 12
    final arithmeticEqualityResult =
        _parseArithmeticEquality(constraint, variables);
    if (arithmeticEqualityResult != null) return arithmeticEqualityResult;

    // 8. Arithmetic inequality: A + B > 5, A * B <= 20
    final arithmeticInequalityResult =
        _parseArithmeticInequality(constraint, variables);
    if (arithmeticInequalityResult != null) return arithmeticInequalityResult;

    // 9. Set membership: A in [1, 2, 3]
    final setConstraint = _parseSetConstraint(constraint, variables);
    if (setConstraint != null) return setConstraint;

    // 10. Fall back to general expression evaluation
    return _createExpressionConstraint(constraint, variables);
  }

  /// Parse binary variable-to-variable constraints like A < B, A == B
  static ParsedConstraint? _parseBinaryVariableConstraint(
      String constraint, List<String> variables) {
    if (variables.length != 2) return null;

    final var1 = variables[0];
    final var2 = variables[1];

    // Try exact matches first
    final exactMatches = [
      ('$var1 == $var2', allEqualBinary()),
      ('$var2 == $var1', allEqualBinary()),
      ('$var1 != $var2', allDifferentBinary()),
      ('$var2 != $var1', allDifferentBinary()),
    ];

    for (final (pattern, predicate) in exactMatches) {
      if (constraint == pattern) {
        return ParsedConstraint(predicate, variables, ConstraintType.binary);
      }
    }

    // Try regex patterns for comparisons
    final comparisonPatterns = [
      (
        RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)\s*>\s*([A-Za-z_][A-Za-z0-9_]*)$'),
        '>'
      ),
      (
        RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)\s*>=\s*([A-Za-z_][A-Za-z0-9_]*)$'),
        '>='
      ),
      (
        RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)\s*<\s*([A-Za-z_][A-Za-z0-9_]*)$'),
        '<'
      ),
      (
        RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)\s*<=\s*([A-Za-z_][A-Za-z0-9_]*)$'),
        '<='
      ),
    ];

    for (final (regex, op) in comparisonPatterns) {
      final match = regex.firstMatch(constraint);
      if (match != null) {
        final matchVar1 = match.group(1)!;
        final matchVar2 = match.group(2)!;

        if (variables.contains(matchVar1) && variables.contains(matchVar2)) {
          BinaryPredicate predicate;
          switch (op) {
            case '>':
              predicate = (a, b) => (a! as num) > (b! as num);
              break;
            case '>=':
              predicate = (a, b) => (a! as num) >= (b! as num);
              break;
            case '<':
              predicate = (a, b) => (a! as num) < (b! as num);
              break;
            case '<=':
              predicate = (a, b) => (a! as num) <= (b! as num);
              break;
            default:
              continue;
          }
          return ParsedConstraint(
              predicate, [matchVar1, matchVar2], ConstraintType.binary);
        }
      }
    }

    return null;
  }

  static bool _isChainedInequality(String constraint) =>
      constraint.split('!=').length > 2;

  static ParsedConstraint? _parseVariableConstantConstraint(
      String constraint, List<String> variables) {
    if (variables.length != 1) return null;

    final variable = variables[0];
    final patterns = [
      (RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)\s*==\s*(-?\d+(?:\.\d+)?)$'), '=='),
      (RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)\s*!=\s*(-?\d+(?:\.\d+)?)$'), '!='),
      (RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)\s*>\s*(-?\d+(?:\.\d+)?)$'), '>'),
      (RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)\s*>=\s*(-?\d+(?:\.\d+)?)$'), '>='),
      (RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)\s*<\s*(-?\d+(?:\.\d+)?)$'), '<'),
      (RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)\s*<=\s*(-?\d+(?:\.\d+)?)$'), '<='),
    ];

    for (final (regex, op) in patterns) {
      final match = regex.firstMatch(constraint);
      if (match != null && match.group(1) == variable) {
        final constant = double.parse(match.group(2)!);

        NaryPredicate predicate;
        switch (op) {
          case '==':
            predicate = (Map<String, dynamic> assignment) {
              final value = assignment[variable];
              return value != null &&
                  ((value as num) - constant).abs() < 0.0001;
            };
            break;
          case '!=':
            predicate = (Map<String, dynamic> assignment) {
              final value = assignment[variable];
              return value != null &&
                  ((value as num) - constant).abs() >= 0.0001;
            };
            break;
          case '>':
            predicate = (Map<String, dynamic> assignment) {
              final value = assignment[variable];
              return value != null && (value as num) > constant;
            };
            break;
          case '>=':
            predicate = (Map<String, dynamic> assignment) {
              final value = assignment[variable];
              return value != null && (value as num) >= constant;
            };
            break;
          case '<':
            predicate = (Map<String, dynamic> assignment) {
              final value = assignment[variable];
              return value != null && (value as num) < constant;
            };
            break;
          case '<=':
            predicate = (Map<String, dynamic> assignment) {
              final value = assignment[variable];
              return value != null && (value as num) <= constant;
            };
            break;
          default:
            continue;
        }
        return ParsedConstraint(predicate, [variable], ConstraintType.nary);
      }
    }

    return null;
  }

  static ParsedConstraint? _parseArithmeticEquality(
      String constraint, List<String> variables) {
    final match =
        RegExp(r'^(.+?)\s*==\s*(-?\d+(?:\.\d+)?)$').firstMatch(constraint);
    if (match == null) return null;

    final leftSide = match.group(1)!;
    final rightValue = double.parse(match.group(2)!);

    // Only use simple sum/product for basic cases without mixed operations
    // A + B == 10 (simple sum)
    if (leftSide.contains('+') &&
        !leftSide.contains('*') &&
        !leftSide.contains('/')) {
      final parts = leftSide.split('+').map((s) => s.trim()).toList();
      if (parts.every((part) => variables.contains(part))) {
        return ParsedConstraint(
            variables.length == 2
                ? exactSumBinary(rightValue)
                : exactSum(rightValue),
            variables,
            variables.length == 2
                ? ConstraintType.binary
                : ConstraintType.nary);
      }
    }

    // A * B == 12 (simple product)
    if (leftSide.contains('*') &&
        !leftSide.contains('+') &&
        !leftSide.contains('-')) {
      final parts = leftSide.split('*').map((s) => s.trim()).toList();
      if (parts.every((part) => variables.contains(part))) {
        return ParsedConstraint(
            variables.length == 2
                ? exactProductBinary(rightValue)
                : exactProduct(rightValue),
            variables,
            variables.length == 2
                ? ConstraintType.binary
                : ConstraintType.nary);
      }
    }

    // For complex expressions like A * B + C == 10, fall through to general expression evaluator
    return null;
  }

  static ParsedConstraint? _parseArithmeticInequality(
      String constraint, List<String> variables) {
    final patterns = [
      (RegExp(r'^(.+?)\s*>=\s*(-?\d+(?:\.\d+)?)$'), '>='),
      (RegExp(r'^(.+?)\s*>\s*(-?\d+(?:\.\d+)?)$'), '>'),
      (RegExp(r'^(.+?)\s*<=\s*(-?\d+(?:\.\d+)?)$'), '<='),
      (RegExp(r'^(.+?)\s*<\s*(-?\d+(?:\.\d+)?)$'), '<'),
    ];

    for (final (regex, op) in patterns) {
      final match = regex.firstMatch(constraint);
      if (match != null) {
        final leftSide = match.group(1)!;
        final rightValue = double.parse(match.group(2)!);

        if (leftSide.contains('+')) {
          switch (op) {
            case '>=':
              return ParsedConstraint(
                  variables.length == 2
                      ? minSumBinary(rightValue)
                      : minSum(rightValue),
                  variables,
                  variables.length == 2
                      ? ConstraintType.binary
                      : ConstraintType.nary);
            case '>':
              return ParsedConstraint(
                  variables.length == 2
                      ? minSumBinary(rightValue + 0.001)
                      : minSum(rightValue + 0.001),
                  variables,
                  variables.length == 2
                      ? ConstraintType.binary
                      : ConstraintType.nary);
            case '<=':
              return ParsedConstraint(
                  variables.length == 2
                      ? maxSumBinary(rightValue)
                      : maxSum(rightValue),
                  variables,
                  variables.length == 2
                      ? ConstraintType.binary
                      : ConstraintType.nary);
            case '<':
              return ParsedConstraint(
                  variables.length == 2
                      ? maxSumBinary(rightValue - 0.001)
                      : maxSum(rightValue - 0.001),
                  variables,
                  variables.length == 2
                      ? ConstraintType.binary
                      : ConstraintType.nary);
          }
        }

        if (leftSide.contains('*')) {
          switch (op) {
            case '>=':
              return ParsedConstraint(
                  variables.length == 2
                      ? minProductBinary(rightValue)
                      : minProduct(rightValue),
                  variables,
                  variables.length == 2
                      ? ConstraintType.binary
                      : ConstraintType.nary);
            case '>':
              return ParsedConstraint(
                  variables.length == 2
                      ? minProductBinary(rightValue + 0.001)
                      : minProduct(rightValue + 0.001),
                  variables,
                  variables.length == 2
                      ? ConstraintType.binary
                      : ConstraintType.nary);
            case '<=':
              return ParsedConstraint(
                  variables.length == 2
                      ? maxProductBinary(rightValue)
                      : maxProduct(rightValue),
                  variables,
                  variables.length == 2
                      ? ConstraintType.binary
                      : ConstraintType.nary);
            case '<':
              return ParsedConstraint(
                  variables.length == 2
                      ? maxProductBinary(rightValue - 0.001)
                      : maxProduct(rightValue - 0.001),
                  variables,
                  variables.length == 2
                      ? ConstraintType.binary
                      : ConstraintType.nary);
          }
        }
      }
    }

    return null;
  }

  static ParsedConstraint? _parseVariableEquation(
      String constraint, List<String> variables) {
    final match = RegExp(r'^(.+?)\s*==\s*([A-Za-z_][A-Za-z0-9_]*)$')
        .firstMatch(constraint);
    if (match == null) return null;

    final leftSide = match.group(1)!;
    final rightVar = match.group(2)!;

    if (variables.contains(rightVar)) {
      final leftVars = variables.where((v) => v != rightVar).toList();

      if (leftSide.contains('+')) {
        final sumConstraint = VariableSumConstraint(rightVar, leftVars);
        return ParsedConstraint(
            sumConstraint, variables, ConstraintType.variableSum);
      }

      if (leftSide.contains('*')) {
        final productConstraint = VariableProductConstraint(rightVar, leftVars);
        return ParsedConstraint(
            productConstraint, variables, ConstraintType.variableProduct);
      }
    }

    return null;
  }

  static ParsedConstraint? _parseRangeConstraint(
      String constraint, List<String> variables) {
    final rangeMatch =
        RegExp(r'^(-?\d+(?:\.\d+)?)\s*<=\s*(.+?)\s*(<=|<)\s*(-?\d+(?:\.\d+)?)$')
            .firstMatch(constraint);
    if (rangeMatch == null) return null;

    final minVal = double.parse(rangeMatch.group(1)!);
    final expression = rangeMatch.group(2)!;
    final operator = rangeMatch.group(3)!;
    final maxVal = double.parse(rangeMatch.group(4)!);

    if (expression.contains('+')) {
      final actualMax = operator == '<' ? maxVal - 0.001 : maxVal;

      return ParsedConstraint(
          variables.length == 2
              ? sumInRangeBinary(minVal, actualMax)
              : sumInRange(minVal, actualMax),
          variables,
          variables.length == 2 ? ConstraintType.binary : ConstraintType.nary);
    }

    return null;
  }

  static ParsedConstraint? _parseSetConstraint(
      String constraint, List<String> variables) {
    // Regex for 'not in'
    final notInSetMatch =
        RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)\s+not\s+in\s+\[(.+?)\]$')
            .firstMatch(constraint);
    if (notInSetMatch != null) {
      final setValues =
          notInSetMatch.group(2)!.split(',').map((s) => s.trim()).toList();
      final parsedValues = _parseSetValues(setValues);

      return ParsedConstraint(
        variables.length == 2
            ? notInSetBinary(parsedValues)
            : notInSet(parsedValues),
        variables,
        variables.length == 2 ? ConstraintType.binary : ConstraintType.nary,
      );
    }

    // Regex for 'in'
    final inSetMatch = RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)\s+in\s+\[(.+?)\]$')
        .firstMatch(constraint);
    if (inSetMatch != null) {
      final setValues =
          inSetMatch.group(2)!.split(',').map((s) => s.trim()).toList();
      final parsedValues = _parseSetValues(setValues);

      return ParsedConstraint(
        variables.length == 2 ? inSetBinary(parsedValues) : inSet(parsedValues),
        variables,
        variables.length == 2 ? ConstraintType.binary : ConstraintType.nary,
      );
    }

    return null;
  }

  /// Helper to parse values from a set string like "[1, 2, 'hello']"
  static Set<dynamic> _parseSetValues(List<String> stringValues) {
    final parsedValues = <dynamic>{};
    for (final value in stringValues) {
      final trimmed = value.replaceAll('"', '').replaceAll("'", '');
      final number = num.tryParse(trimmed);
      parsedValues.add(number ?? trimmed);
    }
    return parsedValues;
  }

  static ParsedConstraint? _parseOrderingConstraint(
      String constraint, List<String> variables) {
    if (constraint.contains('<') &&
        !constraint.contains('<=') &&
        !constraint.contains('==')) {
      final parts = constraint.split('<').map((s) => s.trim()).toList();
      if (parts.length > 2 && parts.every((part) => variables.contains(part))) {
        return ParsedConstraint(
            strictlyAscendingInOrder(parts), variables, ConstraintType.nary);
      }
    } else if (constraint.contains('<=') && !constraint.contains('==')) {
      final parts = constraint.split('<=').map((s) => s.trim()).toList();
      if (parts.length > 2 && parts.every((part) => variables.contains(part))) {
        return ParsedConstraint(
            ascendingInOrder(parts), variables, ConstraintType.nary);
      }
    }

    return null;
  }

  /// Create a general expression constraint using the improved evaluator
  static ParsedConstraint _createExpressionConstraint(
      String constraint, List<String> variables) {
    bool predicate(Map<String, dynamic> assignment) {
      try {
        // Check if all variables in the constraint are assigned
        for (final variable in variables) {
          if (!assignment.containsKey(variable)) {
            return true; // Skip evaluation if not all variables assigned
          }
        }

        return ExpressionEvaluator.evaluateBoolean(constraint, assignment);
      } catch (e) {
        // If we can't evaluate it, assume it's false
        return false;
      }
    }

    return ParsedConstraint(predicate, variables, ConstraintType.nary);
  }
}
