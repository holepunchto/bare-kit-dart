import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bare_kit/bare_kit.dart';
import 'package:test/test.dart';

import 'stop.dart';

String fixture(String name) =>
    File('test/fixtures/$name').absolute.uri.toFilePath();

Worklet start(
  String filename, {
  Iterable<String> args = const [],
  List<int>? source,
}) {
  final worklet = Worklet.start(filename, args: args, source: source);

  addTearDown(() => stop(worklet));

  return worklet;
}

Future<String> collect(Stream<List<int>> stream) =>
    utf8.decoder.bind(stream).join();

void main() {
  test('echoes IPC data', () async {
    final worklet = start(fixture('echo.js'));

    worklet.add(utf8.encode('Hello world'));

    expect(utf8.decode(await worklet.first), 'Hello world');
  });

  test('ends IPC data', () async {
    final worklet = start(fixture('collect.js'));

    worklet
      ..add(utf8.encode('Hello '))
      ..add(utf8.encode('world'));

    await worklet.close();

    expect(() => worklet.add(utf8.encode('!')), throwsStateError);
    expect(await collect(worklet), 'Hello world');
    expect(await worklet.exitCode, 0);
  });

  test('passes arguments', () async {
    final worklet = start(fixture('argv.js'), args: ['foo', 'bar']);

    expect(await collect(worklet), '["foo","bar"]');
  });

  test('runs source', () async {
    final worklet = start(
      '/app.js',
      source: utf8.encode("Bare.IPC.end('Hello world')"),
    );

    expect(await collect(worklet), 'Hello world');
  });

  test('reports the exit code', () async {
    final worklet = start(fixture('exit.js'));

    expect(await worklet.exitCode, 3);
    expect(await worklet.toList(), isEmpty);
  });

  test('terminates', () async {
    final worklet = start(fixture('sleep.js'));

    worklet.terminate();

    await worklet.exitCode;

    expect(await worklet.toList(), isEmpty);
  });

  test('suspends and resumes', () async {
    final worklet = start(fixture('lifecycle.js'));

    final events = <String>[];

    await for (final data in worklet) {
      final event = utf8.decode(data);

      events.add(event);

      if (event == 'ready') {
        worklet.suspend(linger: Duration.zero);
      } else if (event == 'suspend') {
        worklet.resume();
      } else {
        break;
      }
    }

    expect(events, ['ready', 'suspend', 'resume']);
  });

  test('rejects data once destroyed', () async {
    final worklet = start(fixture('echo.js'));

    worklet.destroy();

    expect(() => worklet.add(utf8.encode('Hello world')), throwsStateError);
    expect(await worklet.toList(), isEmpty);
    expect(await worklet.exitCode, isA<int>());
  });

  test('fails done once the worklet has exited', () async {
    final worklet = start(fixture('exit.js'));

    await worklet.exitCode;

    worklet.add(utf8.encode('Hello world'));

    await expectLater(worklet.done, throwsA(isA<PeerClosedException>()));
  });

  test('ignores terminate once destroyed and rejects other calls', () {
    final worklet = start(fixture('echo.js'));

    worklet.destroy();
    worklet.terminate();

    expect(worklet.suspend, throwsStateError);
  });

  test('streams large data', () async {
    final data = Uint8List(256 * 4096);

    for (var i = 0; i < data.length; i++) {
      data[i] = i % 256;
    }

    final worklet = start(fixture('collect.js'));

    worklet.add(data);

    await worklet.close();

    final chunks = await worklet.toList();

    expect(chunks.expand((chunk) => chunk), data);
  });

  test('pipes a stream', () async {
    final worklet = start(fixture('collect.js'));

    await Stream<List<int>>.fromIterable([
      utf8.encode('Hello '),
      utf8.encode('world'),
    ]).pipe(worklet);

    expect(await collect(worklet), 'Hello world');
  });
}
