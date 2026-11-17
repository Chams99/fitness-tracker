import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fitness_tracker/features/update/android_release.dart';
import 'package:flutter_test/flutter_test.dart';

const _tag = 'v1.2.0';
const _assetRoot =
    'https://github.com/youssefsz/fitness-tracker/releases/download/$_tag';
const _apkName = 'Fitness-Tracker-$_tag.apk';
const _apkUrl = '$_assetRoot/$_apkName';
const _manifest = 'android-update.json';
const _latestPath = '/repos/youssefsz/fitness-tracker/releases/latest';
final _bytes = utf8.encode('Fictional APK payload');
final _digest = sha256.convert(_bytes).toString();

void main() {
  late HttpServer server;
  late Directory cache;
  late AndroidReleaseClient client;
  late List<Uri> requests;
  late Map<String, Object?> feed;
  late Map<String, Object?> metadata;
  late Future<void> Function(HttpResponse) serveApk;
  late bool offline;

  setUp(() async {
    requests = [];
    offline = false;
    feed = {
      'draft': false,
      'prerelease': false,
      'published_at': '2026-11-16T22:00:00Z',
      'tag_name': _tag,
      'assets': [_asset(_apkName, size: _bytes.length), _asset(_manifest)],
    };
    metadata = {
      'schemaVersion': 1,
      'versionCode': 42,
      'versionName': '1.2.0',
      'apkUrl': _apkUrl,
      'sha256': _digest,
      'notes': 'A short release note.',
    };
    serveApk = (response) async {
      response.add(_bytes);
      await response.close();
    };
    cache = await Directory.systemTemp.createTemp('android-update-test.');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final response = request.response;
      switch (request.uri.path) {
        case _latestPath:
          if (offline) {
            response.statusCode = HttpStatus.serviceUnavailable;
          } else {
            response.write(jsonEncode(feed));
          }
          await response.close();
        case '/fixture/$_manifest':
          response.write(jsonEncode(metadata));
          await response.close();
        case '/fixture/$_apkName':
          await serveApk(response);
        default:
          response.statusCode = HttpStatus.found;
          response.headers.set(
            HttpHeaders.locationHeader,
            'https://release-assets.githubusercontent.com/fixture/${request.uri.pathSegments.last}',
          );
          await response.close();
      }
    });
    client = AndroidReleaseClient(
      openRequest: (http, uri) {
        requests.add(uri);
        return http.getUrl(Uri.http('127.0.0.1:${server.port}', uri.path));
      },
    );
  });

  tearDown(() async {
    await server.close(force: true);
    await cache.delete(recursive: true);
  });

  DownloadUpdate download(
    AndroidRelease release, {
    int storage = 1024,
    void Function(double)? progress,
  }) => client.download(
    release,
    cache,
    availableBytes: () async => storage,
    onProgress: progress ?? (_) {},
  );

  test(
    'detects stable releases by versionCode without fetching the APK',
    () async {
      final release = (await client.check(41))!;
      expect(release.versionName, '1.2.0');
      expect(release.versionCode, 42);
      expect(release.notes, 'A short release note.');
      expect(requests.map((uri) => uri.pathSegments.last), [
        'latest',
        _manifest,
        _manifest,
      ]);
      expect(await client.check(42), isNull);
      expect(await client.check(43), isNull);
    },
  );

  test('distinguishes a feed failure from no available release', () async {
    offline = true;
    await expectLater(client.check(1), throwsA(isA<HttpException>()));
    offline = false;
    expect(await client.check(42), isNull);
  });

  test('skips draft, preview and incomplete releases', () async {
    feed['draft'] = true;
    expect(await client.check(1), isNull);
    feed['draft'] = false;
    feed['prerelease'] = true;
    expect(await client.check(1), isNull);
    feed['prerelease'] = false;
    feed['assets'] = [_asset(_apkName, size: _bytes.length)];
    expect(await client.check(1), isNull);
    expect(requests, hasLength(3));
  });

  test('rejects incompatible manifest and untrusted asset URLs', () async {
    metadata['apkUrl'] = 'https://example.com/$_apkName';
    expect(await client.check(1), isNull);
    metadata['apkUrl'] = _apkUrl;
    metadata['versionName'] = '1.0.0';
    expect(await client.check(1), isNull);
    metadata['versionName'] = '1.2.0';
    feed['assets'] = [
      _asset(_apkName, size: _bytes.length, digest: 'sha256:${'0' * 64}'),
      _asset(_manifest),
    ];
    expect(await client.check(1), isNull);
    expect(requests.where((uri) => uri.host == 'example.com'), isEmpty);
  });

  test('only accepts HTTPS redirects to known GitHub asset hosts', () async {
    final release = (await client.check(1))!;
    serveApk = (response) async {
      response.statusCode = HttpStatus.temporaryRedirect;
      response.headers.set(
        HttpHeaders.locationHeader,
        'http://release-assets.githubusercontent.com/$_apkName',
      );
      await response.close();
    };
    await expectLater(download(release).done, throwsA(isA<HttpException>()));
    expect(requests.every((uri) => uri.scheme == 'https'), isTrue);
    expect(await cache.list().toList(), isEmpty);
  });

  test('publishes a verified cached APK and reuses it on retry', () async {
    final release = (await client.check(1))!;
    final progress = <double>[];
    await download(release, progress: progress.add).done;
    final files = await cache.list().toList();
    expect(files, hasLength(1));
    expect(files.single.path, endsWith(release.fileName));
    expect(await File(files.single.path).readAsBytes(), _bytes);
    expect(progress.last, 1);
    final count = requests.length;
    await download(release).done;
    expect(requests, hasLength(count));
  });

  test('deletes incomplete or checksum-mismatched downloads', () async {
    var release = (await client.check(1))!;
    serveApk = (response) async {
      response.bufferOutput = false;
      response.add(_bytes.take(3).toList());
      await response.close();
    };
    await expectLater(download(release).done, throwsA(isA<UpdateFailure>()));
    expect(await cache.list().toList(), isEmpty);
    metadata['sha256'] = '0' * 64;
    release = (await client.check(1))!;
    serveApk = (response) async {
      response.add(_bytes);
      await response.close();
    };
    await expectLater(
      download(release).done,
      throwsA(
        isA<UpdateFailure>().having(
          (error) => error.message,
          'message',
          contains('checksum'),
        ),
      ),
    );
    expect(await cache.list().toList(), isEmpty);
  });

  test('cancellation drops partial bytes and a clean retry works', () async {
    final release = (await client.check(1))!;
    final partial = Completer<void>();
    final finish = Completer<void>();
    serveApk = (response) async {
      response.bufferOutput = false;
      response.add(_bytes.take(4).toList());
      await response.flush();
      await finish.future;
      await response.close();
    };
    try {
      final active = download(release, progress: (_) => partial.complete());
      final result = expectLater(active.done, throwsA(isA<UpdateCancelled>()));
      await partial.future;
      active.cancel();
      await result;
      expect(await cache.list().toList(), isEmpty);
    } finally {
      finish.complete();
    }
    serveApk = (response) async {
      response.add(_bytes);
      await response.close();
    };
    await download(release).done;
    expect(await cache.list().toList(), hasLength(1));
  });

  test(
    'requires space for both the download and the installer staging',
    () async {
      final release = (await client.check(1))!;
      final count = requests.length;
      await expectLater(
        download(release, storage: _bytes.length).done,
        throwsA(
          isA<UpdateFailure>().having(
            (error) => error.message,
            'message',
            contains('storage'),
          ),
        ),
      );
      expect(requests, hasLength(count));
      expect(await cache.list().toList(), isEmpty);
    },
  );
}

Map<String, Object> _asset(String name, {int size = 100, String? digest}) => {
  'name': name,
  'state': 'uploaded',
  'size': size,
  'browser_download_url': '$_assetRoot/$name',
  'digest': ?digest,
};
