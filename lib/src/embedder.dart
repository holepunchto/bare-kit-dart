import 'dart:ffi';

/// The Java virtual machine, as a `JavaVM *`, and the application context, as
/// a JNI reference to an `android.content.Context`.
typedef AndroidOptions = ({Pointer<Void> jvm, Pointer<Void> context});

AndroidOptions Function()? androidOptions;

String Function(String filename)? resolveFilename;

/// Give the worklets created afterwards the Java virtual machine and the
/// application context on Android, which Bare Kit cannot obtain itself when
/// loaded by Dart.
///
/// [options] is called on the thread that creates each worklet, which it must
/// attach to the virtual machine, and the context it returns need only be valid
/// until the worklet is created.
void configureAndroid(AndroidOptions Function() options) {
  androidOptions = options;
}

/// Resolve the relative filenames of the worklets started afterwards with
/// [resolve], such as against the assets of an application framework, before
/// Bare Kit resolves what remains relative against the resources of the
/// application.
void configureFilenames(String Function(String filename) resolve) {
  resolveFilename = resolve;
}
