import 'dart:convert';

import 'package:bare_kit/bare_kit.dart';

void main() async {
  final worklet = Worklet.start(
    '/app.js',
    source: utf8.encode("Bare.IPC.on('data', (data) => Bare.IPC.end(data))"),
  );

  worklet.add(utf8.encode('Hello world'));

  await for (final data in utf8.decoder.bind(worklet)) {
    print(data);
  }

  worklet.destroy();
}
