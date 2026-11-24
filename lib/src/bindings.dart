import 'dart:ffi';

const readable = 0x1;
const writable = 0x2;

const wouldBlock = -1;
const error = -2;

const readBufferSize = 64 * 1024;

final class Worklet extends Opaque {}

final class Ipc extends Opaque {}

final class Poll extends Opaque {}

final class WorkletOptions extends Struct {
  @Int()
  external int version;

  @Size()
  external int memoryLimit;

  @Array(8)
  external Array<Pointer<Void>> platform;
}

typedef ExitCallback = Void Function(Int code, Pointer<Void> data);

typedef PollCallback = Void Function(Pointer<Poll> poll, Int events);

@Native<Int Function(Bool)>(symbol: 'bare_worklet_optimize_for_memory')
external int optimizeForMemory(bool enabled);

@Native<Int Function()>(symbol: 'bare_worklet_teardown')
external int teardown();

@Native<Int Function(Pointer<WorkletOptions>, Pointer<Pointer<Worklet>>)>(
  symbol: 'bare_worklet_create',
)
external int workletCreate(
  Pointer<WorkletOptions> options,
  Pointer<Pointer<Worklet>> result,
);

@Native<Void Function(Pointer<Worklet>)>(symbol: 'bare_worklet_destroy')
external void workletDestroy(Pointer<Worklet> worklet);

@Native<
  Int Function(
    Pointer<Worklet>,
    Pointer<NativeFunction<ExitCallback>>,
    Pointer<Void>,
  )
>(symbol: 'bare_worklet_on_exit')
external int workletOnExit(
  Pointer<Worklet> worklet,
  Pointer<NativeFunction<ExitCallback>> cb,
  Pointer<Void> data,
);

@Native<
  Int Function(
    Pointer<Worklet>,
    Pointer<Char>,
    Pointer<Void>,
    Size,
    Int,
    Pointer<Pointer<Char>>,
  )
>(symbol: 'bare_worklet_start')
external int workletStart(
  Pointer<Worklet> worklet,
  Pointer<Char> filename,
  Pointer<Void> source,
  int len,
  int argc,
  Pointer<Pointer<Char>> argv,
);

@Native<Int Function(Pointer<Worklet>, Int)>(symbol: 'bare_worklet_suspend')
external int workletSuspend(Pointer<Worklet> worklet, int linger);

@Native<Int Function(Pointer<Worklet>)>(symbol: 'bare_worklet_resume')
external int workletResume(Pointer<Worklet> worklet);

@Native<Int Function(Pointer<Worklet>, Int)>(symbol: 'bare_worklet_wakeup')
external int workletWakeup(Pointer<Worklet> worklet, int deadline);

@Native<Int Function(Pointer<Worklet>)>(symbol: 'bare_worklet_terminate')
external int workletTerminate(Pointer<Worklet> worklet);

@Native<Int Function(Pointer<Worklet>, Pointer<Pointer<Ipc>>)>(
  symbol: 'bare_ipc_create',
)
external int ipcCreate(Pointer<Worklet> worklet, Pointer<Pointer<Ipc>> result);

@Native<Void Function(Pointer<Ipc>)>(symbol: 'bare_ipc_close')
external void ipcClose(Pointer<Ipc> ipc);

@Native<Void Function(Pointer<Ipc>)>(symbol: 'bare_ipc_end')
external void ipcEnd(Pointer<Ipc> ipc);

@Native<Void Function(Pointer<Ipc>)>(symbol: 'bare_ipc_destroy')
external void ipcDestroy(Pointer<Ipc> ipc);

@Native<Int Function(Pointer<Ipc>, Pointer<Void>, Size)>(
  symbol: 'bare_ipc_read',
  isLeaf: true,
)
external int ipcRead(Pointer<Ipc> ipc, Pointer<Void> data, int len);

@Native<Int Function(Pointer<Ipc>, Pointer<Void>, Size)>(
  symbol: 'bare_ipc_write',
  isLeaf: true,
)
external int ipcWrite(Pointer<Ipc> ipc, Pointer<Void> data, int len);

@Native<Int Function(Pointer<Ipc>, Pointer<Pointer<Poll>>)>(
  symbol: 'bare_ipc_poll_create',
)
external int pollCreate(Pointer<Ipc> ipc, Pointer<Pointer<Poll>> result);

@Native<Void Function(Pointer<Poll>)>(symbol: 'bare_ipc_poll_destroy')
external void pollDestroy(Pointer<Poll> poll);

@Native<
  Int Function(Pointer<Poll>, Int, Pointer<NativeFunction<PollCallback>>)
>(symbol: 'bare_ipc_poll_start')
external int pollStart(
  Pointer<Poll> poll,
  int events,
  Pointer<NativeFunction<PollCallback>> cb,
);

@Native<Int Function(Pointer<Poll>)>(symbol: 'bare_ipc_poll_stop')
external int pollStop(Pointer<Poll> poll);

@Native<IntPtr Function(Pointer<Void>)>(symbol: 'Dart_InitializeApiDL')
external int initializeApi(Pointer<Void> data);

@Native<Pointer<Void> Function(Int64)>(symbol: 'bare_kit_dart_port_create')
external Pointer<Void> portCreate(int port);

@Native<Void Function(Pointer<Void>)>(symbol: 'bare_kit_dart_port_destroy')
external void portDestroy(Pointer<Void> port);

@Native<ExitCallback>(symbol: 'bare_kit_dart_on_exit')
external void onExit(int code, Pointer<Void> data);
