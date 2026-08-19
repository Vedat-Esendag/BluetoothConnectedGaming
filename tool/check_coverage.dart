// Fails the build when line coverage drops below a floor (#25).
//
// Run as `dart run tool/check_coverage.dart` after `flutter test --coverage`.
// Written in Dart rather than shell so CI needs no extra tooling (`lcov` is not
// installed on the default runner image) and so the same command works on a
// developer's machine.
import 'dart:io';

/// The floor, in percent.
///
/// Set just under where the suite actually sits, so it catches a real
/// regression — a feature landing with no tests — without failing on the noise
/// of a few uncovered lines. Raise it as coverage climbs; never lower it to
/// make a red build green.
const double minimumLineCoverage = 80;

/// Files excluded from the measurement.
///
/// Only the radio adapters, and only because they cannot be unit-tested at all:
/// every line in them is a call into a platform channel that needs a real
/// Bluetooth stack. Counting them would drag the floor down until it stopped
/// catching anything, and raising it would just push people to write mock-only
/// tests that assert the adapter calls the plugin. They are covered by the
/// real-device runbook instead (docs/testing/bluetooth-smoke-test.md, #26).
///
/// This list is deliberately short and deliberately awkward to add to: a file
/// that "can't be tested" is usually a file that needs an interface extracted,
/// which is exactly what `BleScanner`/`BleHost` are.
const List<String> untestableOnCi = <String>[
  'lib/core/transport/ble/bluetooth_low_energy_scanner.dart',
  'lib/core/transport/ble/bluetooth_low_energy_host.dart',
  'lib/core/bluetooth_service.dart',
];

void main(List<String> args) {
  final report = File(args.isNotEmpty ? args.first : 'coverage/lcov.info');
  if (!report.existsSync()) {
    stderr.writeln(
      'No coverage report at ${report.path}. '
      'Run `flutter test --coverage` first.',
    );
    exit(2);
  }

  var found = 0;
  var hit = 0;
  var excluded = 0;
  var counting = true;

  for (final line in report.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      final path = line.substring(3).replaceAll(r'\', '/');
      counting = !untestableOnCi.any(path.endsWith);
      if (!counting) excluded++;
    } else if (counting && line.startsWith('LF:')) {
      found += int.parse(line.substring(3));
    } else if (counting && line.startsWith('LH:')) {
      hit += int.parse(line.substring(3));
    }
  }

  if (found == 0) {
    stderr.writeln('Coverage report contains no lines.');
    exit(2);
  }

  final percent = 100 * hit / found;
  final summary =
      'Line coverage: ${percent.toStringAsFixed(1)}% ($hit/$found lines), '
      'floor ${minimumLineCoverage.toStringAsFixed(0)}%, '
      '$excluded file(s) excluded as hardware-only.';

  if (percent < minimumLineCoverage) {
    stderr.writeln('$summary FAILED');
    exit(1);
  }
  stdout.writeln('$summary OK');
}
