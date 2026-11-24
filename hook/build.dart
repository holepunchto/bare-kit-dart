import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

// The SHA-256 checksums of the prebuilds attached to the release of this
// version, which the publish workflow checks before releasing them.
const checksums = <String, String>{};

const mirror = 'https://github.com/holepunchto/bare-kit-dart/releases/download';

final architectures = {
  Architecture.arm64,
  Architecture.x64,
  Architecture.ia32,
  Architecture.arm,
};

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final code = input.config.code;
    final target = _target(code);
    final name = code.targetOS.dylibFileName('bare-kit');

    final defined = input.userDefines.path('prebuilds');
    final bundled = input.packageRoot.resolve('prebuilds/');

    final Uri file;

    if (defined != null) {
      file = _local(defined, target, name);
    } else if (Directory.fromUri(bundled.resolve('$target/')).existsSync()) {
      file = _local(bundled, target, name);
    } else {
      file = (await _download(input, target)).resolve(name);
    }

    output.dependencies.add(file);

    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'src/bindings.dart',
        linkMode: DynamicLoadingBundled(),
        file: file,
      ),
    );
  });
}

Uri _local(Uri prebuilds, String target, String name) {
  final file = prebuilds.resolve('$target/$name');

  if (!File.fromUri(file).existsSync()) {
    throw StateError('No Bare Kit prebuild for $target in $prebuilds');
  }

  return file;
}

// Download the prebuild from the release of this version, and extract it to
// the shared output directory unless an earlier build already did.
Future<Uri> _download(BuildInput input, String target) async {
  final checksum = checksums[target];

  if (checksum == null) throw StateError('No Bare Kit prebuild for $target');

  final version = _version(input);

  final out = input.outputDirectoryShared.resolve('$version/');
  final archive = File.fromUri(out.resolve('$target.tar.gz'));
  final dir = out.resolve('prebuilds/$target/');

  if (Directory.fromUri(dir).existsSync() && _verify(archive, checksum)) {
    return dir;
  }

  final base = input.userDefines['mirror'] as String? ?? mirror;

  final url = Uri.parse('${_trimSlash(base)}/v$version/$target.tar.gz');

  final client = HttpClient()..findProxy = HttpClient.findProxyFromEnvironment;

  try {
    final response = await (await client.getUrl(url)).close();

    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Failed with status ${response.statusCode}',
        uri: url,
      );
    }

    await archive.parent.create(recursive: true);
    await response.pipe(archive.openWrite());
  } finally {
    client.close();
  }

  if (!_verify(archive, checksum)) {
    await archive.delete();

    throw StateError('Checksum mismatch for $url');
  }

  final result = await Process.run('tar', [
    '-xzf',
    archive.path,
    '-C',
    Directory.fromUri(out).path,
  ]);

  if (result.exitCode != 0) {
    throw ProcessException('tar', [], '${result.stderr}', result.exitCode);
  }

  return dir;
}

bool _verify(File archive, String checksum) =>
    archive.existsSync() &&
    sha256.convert(archive.readAsBytesSync()).toString() == checksum;

String _version(BuildInput input) {
  final pubspec = File.fromUri(input.packageRoot.resolve('pubspec.yaml'));

  final match = RegExp(
    r'^version:\s*(\S+)',
    multiLine: true,
  ).firstMatch(pubspec.readAsStringSync());

  if (match == null) throw StateError('No version in ${pubspec.path}');

  return match[1]!;
}

String _trimSlash(String url) =>
    url.endsWith('/') ? url.substring(0, url.length - 1) : url;

// The target named as by Bare, such as `darwin-arm64`.
String _target(CodeConfig code) {
  final os = code.targetOS;
  final arch = code.targetArchitecture;

  final platform = switch (os) {
    OS.macOS => 'darwin',
    OS.windows => 'win32',
    OS.iOS || OS.linux || OS.android => os.name,
    _ => throw UnsupportedError('Unsupported target OS $os'),
  };

  if (!architectures.contains(arch)) {
    throw UnsupportedError('Unsupported target architecture $arch');
  }

  if (os == OS.iOS && code.iOS.targetSdk == IOSSdk.iPhoneSimulator) {
    return '$platform-${arch.name}-simulator';
  }

  return '$platform-${arch.name}';
}
