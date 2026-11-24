import 'package:bare_kit/bare_kit.dart';

// The exit callback must not outlive the test isolate, which the test runner
// kills without waiting for running worklets.
Future<void> stop(Worklet worklet) async {
  worklet.destroy();

  await worklet.exitCode;
}
