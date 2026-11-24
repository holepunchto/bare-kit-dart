# bare-kit-dart

Dart bindings for [Bare Kit](https://github.com/holepunchto/bare-kit), which runs Bare in a thread of its own within the application, known as a worklet, with an IPC to it exposed as `Bare.IPC` inside the worklet.

```
dart pub add bare_kit
```

## Usage

```dart
import 'dart:convert';

import 'package:bare_kit/bare_kit.dart';

void main() async {
  final worklet = Worklet.start('/path/to/app.bundle');

  worklet.add(utf8.encode('Hello world'));

  await for (final data in utf8.decoder.bind(worklet)) {
    print(data);
  }

  worklet.destroy();
}
```

Where `app.bundle` is a Bare bundle using `Bare.IPC`:

```js
Bare.IPC.on('data', (data) => Bare.IPC.end(data))
```

Listening to a worklet yields the data that it writes to `Bare.IPC` until it ends its side. As `Bare.IPC` keeps the worklet alive, `close()` ends the data sent to it so that it may exit on its own, and `exitCode` completes with its exit code. Adding data throws a `StateError` once closed, and `done` completes with a `PeerClosedException` if the worklet closes its side before the data is sent. A worklet keeps the isolate alive until it exits, and destroying it terminates it, so keep it for as long as it should run and destroy it once done. Once destroyed, `terminate()` does nothing and `suspend()`, `resume()` and `wakeup()` throw a `StateError`.

These bindings are a thin layer over [Bare Kit](https://github.com/holepunchto/bare-kit), whose README covers the [lifecycle](https://github.com/holepunchto/bare-kit#lifecycle), [IPC](https://github.com/holepunchto/bare-kit#ipc), [suspension](https://github.com/holepunchto/bare-kit#suspension), [addons](https://github.com/holepunchto/bare-kit#addons), and [error handling](https://github.com/holepunchto/bare-kit#error-handling) of a worklet. In Dart terms:

- If `source` is `null`, `Worklet.start()` reads `filename` at runtime, so the worklet may be a module next to its `node_modules` rather than a bundle.
- The build hook bundles Bare Kit as a shared library, so native addons resolve the symbols of Bare from it as is.
- Bare Kit calls back on threads of its own, which the bindings hand to the isolate that started the worklet, so use the worklet from that isolate.
- An uncaught error in the worklet aborts the process, the Dart VM included, so report errors over `Bare.IPC` as described in [error handling](https://github.com/holepunchto/bare-kit#error-handling).

## Platforms

The package supports Android, iOS, Linux, macOS, and Windows. A relative filename names a resource of the application. In Flutter applications, use [`bare_kit_flutter`](https://github.com/holepunchto/bare-kit-flutter), which provides Bare Kit with what it needs from Flutter, such as the application context on Android.

The build hook downloads the Bare Kit prebuild for the target from the release of the package version. To use prebuilds of your own, such as from a mirror, configure the hook in the `pubspec.yaml` of your application:

```yaml
hooks:
  user_defines:
    bare_kit:
      prebuilds: path/to/prebuilds # A directory of `<target>/<library>`
      mirror: https://example.com/releases # Serving `v<version>/<target>.tar.gz`
```

## License

Apache-2.0
