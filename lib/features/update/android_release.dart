import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

const _repository = 'youssefsz/fitness-tracker';
const _manifestName = 'android-update.json';
const _maxApkBytes = 512 * 1024 * 1024;
const _metadataTimeout = Duration(seconds: 12);
const _transferTimeout = Duration(seconds: 20);
final _stableTag = RegExp(
  r'^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$',
);
final _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');
final _latest = Uri.https(
  'api.github.com',
  '/repos/$_repository/releases/latest',
);

class AndroidRelease {
  const AndroidRelease({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    required this.sha256,
    required this.size,
    this.notes,
  });

  final String versionName;
  final int versionCode;
  final Uri apkUrl;
  final String sha256;
  final int size;
  final String? notes;

  String get fileName => '$versionCode-$sha256.apk';
}

class UpdateFailure implements Exception {
  const UpdateFailure(this.message);
  final String message;
}

class UpdateCancelled implements Exception {
  const UpdateCancelled();
}

class AndroidReleaseClient {
  const AndroidReleaseClient({this.openRequest = _openRequest});

  // Tests can supply a fixture transport while exercising the production URLs.
  final Future<HttpClientRequest> Function(HttpClient, Uri) openRequest;

  Future<AndroidRelease?> check(int installedVersionCode) async {
    final client = HttpClient()..connectionTimeout = _metadataTimeout;
    Future<AndroidRelease?> discover() async {
      final feed = await _json(client, _latest, maxBytes: 256 * 1024);
      if (feed
          case {
            'draft': false,
            'prerelease': false,
            'published_at': final String publishedAt,
            'tag_name': final String tag,
            'assets': final List<Object?> assets,
          }
          when _stableTag.hasMatch(tag) &&
              DateTime.tryParse(publishedAt) != null) {
        final apk = _asset(tag, 'Fitness-Tracker-$tag.apk');
        final manifest = _asset(tag, _manifestName);
        final apkAsset = _uploaded(assets, apk);
        if (apkAsset case {'size': final int size}
            when size > 0 &&
                size <= _maxApkBytes &&
                _uploaded(assets, manifest) != null) {
          final metadata = await _json(client, manifest, maxBytes: 8 * 1024);
          if (metadata
              case {
                'schemaVersion': 1,
                'versionName': final String name,
                'versionCode': final int code,
                'apkUrl': final String url,
                'sha256': final String digest,
              }
              when 'v$name' == tag &&
                  code > installedVersionCode &&
                  code <= 2100000000 &&
                  url == apk.toString() &&
                  _sha256Pattern.hasMatch(digest) &&
                  (apkAsset['digest'] == null ||
                      apkAsset['digest'] == 'sha256:$digest')) {
            final note = metadata['notes'];
            return AndroidRelease(
              versionName: name,
              versionCode: code,
              apkUrl: apk,
              sha256: digest,
              size: size,
              notes: note is String && note.trim().isNotEmpty
                  ? String.fromCharCodes(note.trim().runes.take(280))
                  : null,
            );
          }
        }
      }
      return null;
    }

    try {
      return await discover().timeout(_metadataTimeout);
    } finally {
      client.close(force: true);
    }
  }

  DownloadUpdate download(
    AndroidRelease release,
    Directory directory, {
    required Future<int> Function() availableBytes,
    required void Function(double) onProgress,
  }) => DownloadUpdate._(this, release, directory, availableBytes, onProgress);

  Future<Object?> _json(
    HttpClient client,
    Uri uri, {
    required int maxBytes,
  }) async {
    final response = await _get(
      client,
      uri,
      accept: 'application/vnd.github+json',
    );
    final bytes = <int>[];
    await for (final chunk in response.timeout(_transferTimeout)) {
      if (bytes.length + chunk.length > maxBytes) {
        throw const FormatException('Release metadata is too large.');
      }
      bytes.addAll(chunk);
    }
    return jsonDecode(utf8.decode(bytes));
  }

  Future<HttpClientResponse> _get(
    HttpClient client,
    Uri initial, {
    required String accept,
  }) async {
    var uri = initial;
    for (var redirect = 0; redirect < 4; redirect++) {
      final request = await openRequest(client, uri).timeout(_transferTimeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, accept);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Fitness-Tracker-Android',
      );
      final response = await request.close().timeout(_transferTimeout);
      if (response.statusCode == HttpStatus.ok) return response;
      final location = response.headers.value(HttpHeaders.locationHeader);
      // Discard the response without reading an unbounded error or redirect body.
      final subscription = response.listen(null);
      await subscription.cancel();
      if (!response.isRedirect || location == null || initial == _latest) break;
      uri = uri.resolve(location);
      if (uri.scheme != 'https' ||
          uri.port != 443 ||
          uri.userInfo.isNotEmpty ||
          !const {
            'release-assets.githubusercontent.com',
            'objects.githubusercontent.com',
          }.contains(uri.host)) {
        break;
      }
    }
    throw const HttpException('Could not fetch the GitHub release asset.');
  }
}

class DownloadUpdate {
  DownloadUpdate._(
    this._releaseClient,
    this._release,
    this._directory,
    this._availableBytes,
    this._onProgress,
  ) {
    done = _run();
  }

  final AndroidReleaseClient _releaseClient;
  final AndroidRelease _release;
  final Directory _directory;
  final Future<int> Function() _availableBytes;
  final void Function(double) _onProgress;
  final _client = HttpClient()..connectionTimeout = _transferTimeout;
  late final Future<void> done;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _client.close(force: true);
  }

  void _checkCancellation() {
    if (_cancelled) throw const UpdateCancelled();
  }

  Future<void> _run() async {
    final apk = File(p.join(_directory.path, _release.fileName));
    final partial = File('${apk.path}.part');
    var kept = false;
    try {
      await _directory.create(recursive: true);
      _checkCancellation();
      if (await apk.exists() &&
          await apk.length() == _release.size &&
          await _checksum(apk.path) == _release.sha256) {
        _checkCancellation();
        kept = true;
        return;
      }
      await removeUpdateFile(apk);
      // Android needs a second copy while the installer stages the update.
      if (await _availableBytes() < 2 * _release.size) {
        throw const UpdateFailure('Free some storage to download this update.');
      }
      _checkCancellation();
      final response = await _releaseClient._get(
        _client,
        _release.apkUrl,
        accept: 'application/octet-stream',
      );
      if (response.contentLength >= 0 &&
          response.contentLength != _release.size) {
        throw const UpdateFailure('The update download is incomplete.');
      }
      var received = 0;
      final output = await partial.open(mode: FileMode.write);
      try {
        await for (final chunk in response.timeout(_transferTimeout)) {
          _checkCancellation();
          received += chunk.length;
          if (received > _release.size) {
            throw const UpdateFailure(
              'The update has an unexpected file size.',
            );
          }
          await output.writeFrom(chunk);
          _onProgress(received / _release.size);
        }
      } finally {
        await output.close();
      }
      if (received != _release.size) {
        throw const UpdateFailure('The update download is incomplete.');
      }
      if (await _checksum(partial.path) != _release.sha256) {
        throw const UpdateFailure('The update failed its checksum check.');
      }
      _checkCancellation();
      await partial.rename(apk.path);
      _checkCancellation();
      kept = true;
    } on Exception catch (error) {
      _checkCancellation();
      if (error is FileSystemException && error.osError?.errorCode == 28) {
        throw const UpdateFailure('Free some storage to download this update.');
      }
      rethrow;
    } finally {
      _client.close(force: true);
      await removeUpdateFile(partial);
      if (!kept) await removeUpdateFile(apk);
    }
  }
}

Future<HttpClientRequest> _openRequest(HttpClient client, Uri uri) =>
    client.getUrl(uri);

Uri _asset(String tag, String name) =>
    Uri.https('github.com', '/$_repository/releases/download/$tag/$name');

Map<Object?, Object?>? _uploaded(List<Object?> assets, Uri uri) {
  for (final asset in assets) {
    if (asset
        case {
          'name': final String name,
          'state': 'uploaded',
          'browser_download_url': final String url,
        }
        when name == uri.pathSegments.last && url == uri.toString()) {
      return asset;
    }
  }
  return null;
}

Future<String> _checksum(String path) => Isolate.run(
  () async => (await sha256.bind(File(path).openRead()).first).toString(),
);

Future<void> removeUpdateFile(File file) async {
  try {
    await file.delete();
  } on FileSystemException {
    // The cache can also be cleared by Android.
  }
}
