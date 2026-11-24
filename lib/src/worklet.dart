import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings.dart' as bare;
import 'embedder.dart';

/// A call into Bare Kit failed with [status].
class BareKitException implements Exception {
  final int status;

  const BareKitException(this.status);

  @override
  String toString() => 'BareKitException: Bare Kit failed with status $status';
}

/// The worklet closed its end of the IPC before the data added could be sent.
class PeerClosedException implements Exception {
  const PeerClosedException();

  @override
  String toString() => 'PeerClosedException: The worklet closed the IPC';
}

void _check(int status) {
  if (status != 0) throw BareKitException(status);
}

final _api = bare.initializeApi(NativeApi.initializeApiDLData);

/// Trade performance for memory. Must be configured before starting the first
/// worklet.
void optimizeForMemory(bool enabled) {
  _check(bare.optimizeForMemory(enabled));
}

/// Tear down the state shared by the worklets of the process.
///
/// Every worklet must have been destroyed first. Must be called at most once,
/// after which starting a worklet fails. A process that runs worklets for as
/// long as it lives need not call it.
void teardown() {
  _check(bare.teardown());
}

/// A Bare runtime running on a thread of its own, connected to its `Bare.IPC`.
///
/// Listening yields the data that the worklet writes to `Bare.IPC` until it
/// ends its side of the connection, and adding data sends it to the worklet.
/// Closing ends the data sent to the worklet, while [destroy] closes the
/// connection and terminates the worklet. Use [Worklet.start] to start one.
final class Worklet extends Stream<Uint8List> implements StreamSink<List<int>> {
  late final Pointer<bare.Worklet> _handle;
  late final Pointer<bare.Ipc> _ipc;
  late final Pointer<bare.Poll> _poll;

  late final RawReceivePort _exitPort;
  late final NativeCallable<bare.PollCallback> _onPollCallable;

  late final Pointer<Uint8> _buffer;

  late final _controller = StreamController<Uint8List>(
    onListen: _update,
    onPause: _update,
    onResume: _update,
    onCancel: _update,
  );

  final _exitCode = Completer<int>();
  final _done = Completer<void>();

  final _writes = Queue<_Write>();

  Completer<void>? _flushed;

  var _events = 0;
  var _destroyed = false;
  var _ending = false;
  var _adding = false;

  /// Start [filename] in a worklet with an IPC connection to it. A relative
  /// [filename] names a resource of the application.
  ///
  /// [args] are passed to the worklet as `Bare.argv`. [source] is the source of
  /// the module, read from [filename] if `null`. [memoryLimit] is the memory
  /// limit of each JavaScript heap in bytes, or 0 to infer it from the amount
  /// of physical memory of the device.
  static Worklet start(
    String filename, {
    Iterable<String> args = const [],
    List<int>? source,
    int memoryLimit = 0,
  }) {
    final worklet = Worklet._(memoryLimit);

    try {
      worklet._start(filename, args.toList(), source);
    } catch (_) {
      worklet.destroy();
      rethrow;
    }

    return worklet;
  }

  Worklet._(int memoryLimit) {
    using((arena) {
      final options = arena<bare.WorkletOptions>()
        ..ref.version = 0
        ..ref.memoryLimit = memoryLimit;

      if (androidOptions?.call() case final android?) {
        options.ref.platform[0] = android.jvm;
        options.ref.platform[1] = android.context;
      }

      final handle = arena<Pointer<bare.Worklet>>();

      _check(bare.workletCreate(options, handle));

      _handle = handle.value;

      final ipc = arena<Pointer<bare.Ipc>>();
      final poll = arena<Pointer<bare.Poll>>();

      try {
        _check(bare.ipcCreate(_handle, ipc));

        _ipc = ipc.value;

        _check(bare.pollCreate(_ipc, poll));

        _poll = poll.value;
      } catch (_) {
        if (ipc.value != nullptr) bare.ipcDestroy(ipc.value);

        bare.workletDestroy(_handle);
        rethrow;
      }
    });

    _buffer = malloc<Uint8>(bare.readBufferSize);

    _onPollCallable = NativeCallable<bare.PollCallback>.listener(_onPoll)
      ..keepIsolateAlive = false;

    // An error is reported to the listeners of `done`, if any, rather than as
    // unhandled.
    _done.future.ignore();
  }

  void _start(String filename, List<String> args, List<int>? source) {
    if (resolveFilename case final resolve? when _isRelative(filename)) {
      filename = resolve(filename);
    }

    if (_api != 0) throw StateError('Incompatible Dart API');

    // Kept open until the worklet exits, which keeps the isolate alive until
    // then. The callback is only called once the worklet has started.
    _exitPort = RawReceivePort(_onExit);

    final port = bare.portCreate(_exitPort.sendPort.nativePort);

    if (port == nullptr) {
      _exitPort.close();

      throw OutOfMemoryError();
    }

    bare.workletOnExit(
      _handle,
      Native.addressOf<NativeFunction<bare.ExitCallback>>(bare.onExit),
      port,
    );

    using((arena) {
      final argv = arena<Pointer<Char>>(args.length + 1);

      for (var i = 0; i < args.length; i++) {
        argv[i] = args[i].toNativeUtf8(allocator: arena).cast();
      }

      argv[args.length] = nullptr;

      var data = nullptr.cast<Void>();

      if (source != null) {
        final bytes = arena<Uint8>(source.length);

        bytes.asTypedList(source.length).setAll(0, source);

        data = bytes.cast();
      }

      final status = bare.workletStart(
        _handle,
        filename.toNativeUtf8(allocator: arena).cast(),
        data,
        source?.length ?? 0,
        args.length,
        argv,
      );

      if (status != 0) {
        bare.portDestroy(port);

        _exitPort.close();

        throw BareKitException(status);
      }
    });

    _update();
  }

  /// The exit code of the worklet, which completes once it has exited.
  Future<int> get exitCode => _exitCode.future;

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List data)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  /// Send [data] to the worklet. Throws a [StateError] once closed or
  /// destroyed.
  ///
  /// If the worklet closes its end before the data is sent, [done] completes
  /// with a [PeerClosedException] and the data added afterwards is dropped.
  @override
  void add(List<int> data) {
    if (_adding) throw StateError('Cannot add while adding a stream');

    _write(data);
  }

  void _write(List<int> data) {
    if (_ending) throw StateError('Cannot add after closing');

    if (_done.isCompleted || data.isEmpty) return;

    final pointer = malloc<Uint8>(data.length);

    pointer.asTypedList(data.length).setAll(0, data);

    _writes.add(_Write(pointer, data.length));
    _flush();
    _update();
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    throw UnsupportedError('Cannot send errors to a worklet');
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    if (_adding) throw StateError('Cannot add while adding a stream');

    _adding = true;

    try {
      await for (final data in stream) {
        _write(data);

        await flush();
      }
    } finally {
      _adding = false;
    }
  }

  /// Wait for the data added so far to be sent to the worklet.
  Future<void> flush() {
    if (_writes.isEmpty) return Future.value();

    return (_flushed ??= Completer()).future;
  }

  /// End the data sent to the worklet once the added data has been sent, after
  /// which `Bare.IPC` reads end-of-stream while listening continues.
  @override
  Future<void> close() {
    if (_adding) throw StateError('Cannot close while adding a stream');

    if (!_ending) {
      _ending = true;
      _flush();
      _update();
    }

    return done;
  }

  /// Completes once the data sent to the worklet has ended, or with a
  /// [PeerClosedException] if the worklet closes its end first.
  @override
  Future<void> get done => _done.future;

  /// Suspend the worklet, emitting `suspend` on `Bare`. It may keep running for
  /// [linger] before it goes idle, or for as long as the platform allows if
  /// `null`.
  void suspend({Duration? linger}) {
    bare.workletSuspend(_open(), _milliseconds(linger));
  }

  /// Resume a suspended worklet, emitting `resume` on `Bare`.
  void resume() {
    bare.workletResume(_open());
  }

  /// Wake up a suspended worklet, emitting `wakeup` on `Bare`. It may run for
  /// [deadline] before it goes idle again, or for as long as the platform
  /// allows if `null`.
  void wakeup({Duration? deadline}) {
    bare.workletWakeup(_open(), _milliseconds(deadline));
  }

  /// Ask the worklet to exit unless it has already exited or been destroyed.
  void terminate() {
    if (!_destroyed) bare.workletTerminate(_handle);
  }

  /// Close the connection, terminating the worklet if it is still running, and
  /// release its resources. Afterwards, [terminate] does nothing and [suspend],
  /// [resume] and [wakeup] throw a [StateError], while [exitCode] still
  /// completes once the worklet has exited.
  void destroy() {
    if (_destroyed) return;

    _destroyed = true;

    bare.ipcClose(_ipc);

    _dropWrites();

    _ending = true;

    if (!_done.isCompleted) _done.complete();
    if (!_controller.isClosed) _controller.close();

    bare.pollDestroy(_poll);

    _onPollCallable.close();

    bare.ipcDestroy(_ipc);
    bare.workletDestroy(_handle);

    malloc.free(_buffer);
  }

  // The native worklet is freed once destroyed.
  Pointer<bare.Worklet> _open() {
    if (_destroyed) throw StateError('The worklet is destroyed');

    return _handle;
  }

  void _onExit(Object? code) {
    _exitPort.close();
    _exitCode.complete(code as int);
  }

  // The poll stays started between callbacks, which Bare Kit calls when the
  // connection changes rather than for as long as it is ready.
  void _onPoll(Pointer<bare.Poll> poll, int events) {
    if (_destroyed) return;

    _drain();
    _flush();
    _update();
  }

  bool get _reading =>
      !_controller.isClosed && _controller.hasListener && !_controller.isPaused;

  void _drain() {
    while (_reading) {
      final read = bare.ipcRead(_ipc, _buffer.cast(), bare.readBufferSize);

      if (read == bare.wouldBlock) break;

      if (read > 0) {
        _controller.add(Uint8List.fromList(_buffer.asTypedList(read)));
      } else {
        _controller.close();
      }
    }
  }

  void _flush() {
    while (_writes.isNotEmpty) {
      final write = _writes.first;

      final result = bare.ipcWrite(
        _ipc,
        (write.data + write.offset).cast(),
        write.length - write.offset,
      );

      if (result == bare.wouldBlock) break;

      if (result == bare.error) {
        _fail();
        break;
      }

      write.offset += result;

      if (write.offset == write.length) {
        _writes.removeFirst();

        malloc.free(write.data);
      }
    }

    if (_writes.isEmpty) _complete();

    if (_ending && _writes.isEmpty && !_done.isCompleted) {
      bare.ipcEnd(_ipc);

      _done.complete();
    }
  }

  void _fail() {
    _dropWrites();

    if (!_done.isCompleted) _done.completeError(const PeerClosedException());
  }

  void _dropWrites() {
    for (final write in _writes) {
      malloc.free(write.data);
    }

    _writes.clear();
    _complete();
  }

  void _complete() {
    _flushed?.complete();
    _flushed = null;
  }

  void _update() {
    if (_destroyed) return;

    var events = 0;

    if (_reading) events |= bare.readable;
    if (_writes.isNotEmpty) events |= bare.writable;

    if (events == _events) return;

    _events = events;

    if (events != 0) {
      bare.pollStart(_poll, events, _onPollCallable.nativeFunction);
    } else {
      bare.pollStop(_poll);
    }
  }
}

final class _Write {
  final Pointer<Uint8> data;
  final int length;

  var offset = 0;

  _Write(this.data, this.length);
}

// Relative as by Bare Kit, which takes URLs as they are.
bool _isRelative(String filename) =>
    !filename.startsWith('/') &&
    !filename.startsWith(r'\') &&
    !RegExp(r'^[A-Za-z]:[\\/]').hasMatch(filename) &&
    !(Uri.tryParse(filename)?.hasScheme ?? false);

int _milliseconds(Duration? duration) {
  if (duration == null) return -1;

  return duration.inMilliseconds.clamp(0, 0x7fffffff);
}
