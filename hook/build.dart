import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

// The SHA-256 checksums of the prebuilds attached to the release of this
// version, which the publish workflow checks before releasing them.
const checksums = <String, String>{
  'android-arm':
      '2259b1b0667266a849befd1f1e2da751ccd2587d1ebe954719109b135f19380c',
  'android-arm64':
      'd553b5518bfc438452079b688d86b3db817cab9f6fa2b97ee9f6bdfc1c7c8b98',
  'android-ia32':
      '65892d0025577140745a8b18d4f770353b5a50c0baaaa216afbe276953fb5e50',
  'android-x64':
      '8e13fe73c41e6f57f05f200425648a4d55bafd183b67865222bd8869272a8152',
  'darwin-arm64':
      'c7e7b1f84837cc523315f84c6bdda031c1e24f0ba7ceca75774b3a2b565036f5',
  'darwin-x64':
      '9a197720370d02bff0902bc35017127ad6ac8454a024eccc5e58d2e0d0278161',
  'ios-arm64':
      'c6e384500df99f33607a15235c4cdb4d38faf6e5e9789dae867825d17fd2df7c',
  'ios-arm64-simulator':
      'b730645740bda0967deb4552fad43d44d97eab47c9593e611a6ac44d4566d0fd',
  'ios-x64-simulator':
      'd88c311aa8f942023918c204673c9f6e3d08d86cf5f7e931391d8798a929667f',
  'linux-arm64':
      '58b9084eca95c18bcb7bbcfe6444db8a0a0b55e57ec5d1cff34a0006fdf42cf1',
  'linux-x64':
      '31ca63c1a0f829fd261b0348dedbee609f89841888836546dabb070e92b9d0a2',
  'win32-arm64':
      'b95b0e8673a16a3f1535b1b8d9b8632e94783fb08e5c1655f8cec204c0b7cf7b',
  'win32-x64':
      '18d9a0cc1db7dc8fc199c21ce965e2062f45ec3b086bef2656e5d7bb731a1e0a',
};

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
