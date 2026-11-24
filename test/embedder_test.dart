import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:bare_kit/bare_kit.dart';
import 'package:bare_kit/embedder.dart';
import 'package:test/test.dart';

final fixtures = Directory('test/fixtures').absolute.uri;

void main() {
  test('asks for the Android options of each worklet', () async {
    var calls = 0;

    configureAndroid(() {
      calls++;

      return (jvm: nullptr, context: nullptr);
    });

    final worklet = Worklet.start(
      '/app.js',
      source: utf8.encode("Bare.IPC.end('Hello world')"),
    );

    addTearDown(worklet.destroy);

    expect(await utf8.decoder.bind(worklet).join(), 'Hello world');
    expect(calls, 1);
  });

  test('resolves relative filenames', () async {
    final resolved = <String>[];

    configureFilenames((filename) {
      resolved.add(filename);

      return fixtures.resolve(filename).toFilePath();
    });

    final relative = Worklet.start('argv.js', args: ['relative']);
    final absolute = Worklet.start(
      fixtures.resolve('argv.js').toFilePath(),
      args: ['absolute'],
    );

    addTearDown(relative.destroy);
    addTearDown(absolute.destroy);

    expect(await utf8.decoder.bind(relative).join(), '["relative"]');
    expect(await utf8.decoder.bind(absolute).join(), '["absolute"]');
    expect(resolved, ['argv.js']);
  });
}
