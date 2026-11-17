import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app/theme.dart';
import '../../shared/widgets/ui.dart';
import 'android_release.dart';

class UpdateNavigatorObserver extends NavigatorObserver {
  final top = ValueNotifier<Route<dynamic>?>(null);

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    top.value = topRoute;
  }
}

class AndroidUpdateHost extends StatefulWidget {
  const AndroidUpdateHost({
    required this.router,
    required this.observer,
    required this.installedVersionCode,
    required this.child,
    this.releases = const AndroidReleaseClient(),
    super.key,
  });

  final GoRouter router;
  final UpdateNavigatorObserver observer;
  final Future<int?> Function() installedVersionCode;
  final AndroidReleaseClient releases;
  final Widget child;

  @override
  State<AndroidUpdateHost> createState() => _AndroidUpdateHostState();
}

enum _Phase {
  idle,
  downloading,
  downloadFailed,
  downloadCancelled,
  ready,
  permission,
  installing,
  cannotInstall,
  installed,
}

class _AndroidUpdateHostState extends State<AndroidUpdateHost> {
  static const _platform = MethodChannel('tn.dhibi.fitness_tracker/update');

  late final AppLifecycleListener _lifecycle;
  late Directory _directory;
  bool _checked = false;
  bool _prompted = false;
  bool _frameScheduled = false;
  bool _detailsOpen = false;
  bool _openingSettings = false;
  bool _legacyInstallSettings = false;
  bool _checkingManually = false;
  Future<AndroidRelease?>? _pendingCheck;
  AndroidRelease? _release;
  DownloadUpdate? _download;
  _Phase _phase = _Phase.idle;
  String? _message;
  int _percent = 0;

  @override
  void initState() {
    super.initState();
    widget.router.routerDelegate.addListener(_afterFrame);
    widget.observer.top.addListener(_afterFrame);
    _lifecycle = AppLifecycleListener(onResume: _afterFrame);
    _afterFrame();
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_afterFrame);
    widget.observer.top.removeListener(_afterFrame);
    _lifecycle.dispose();
    _download?.cancel();
    super.dispose();
  }

  void _afterFrame() {
    if (_frameScheduled) return;
    _frameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _frameScheduled = false;
      if (!mounted) return;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      final navigator = widget.observer.navigator;
      if (navigator == null ||
          navigator.canPop() ||
          widget.router.routerDelegate.currentConfiguration.uri.path != '/' ||
          (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
        return;
      }
      if (!_checked) {
        _checked = true;
        unawaited(_check());
      }
      final release = _release;
      if (release != null && !_prompted) {
        _prompted = true;
        unawaited(_prompt(navigator.context, release));
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _check() async {
    try {
      final release = await _findUpdate();
      if (release == null || !mounted || _prompted) return;
      final deferred = await _platform.invokeMethod<bool>(
        'isDeferred',
        release.versionCode,
      );
      if (!mounted || _prompted || deferred == true) return;
      _release = release;
      _afterFrame();
    } on Exception {
      // An unavailable update feed must never interrupt access to local data.
    }
  }

  Future<AndroidRelease?> _findUpdate() =>
      _pendingCheck ??= _readUpdate().whenComplete(() {
        _pendingCheck = null;
      });

  Future<AndroidRelease?> _readUpdate() async {
    final installed = await widget.installedVersionCode();
    if (installed == null) {
      throw const UpdateFailure('Couldn’t read the installed version.');
    }
    if (!mounted) return null;
    _directory = Directory(
      p.join((await getTemporaryDirectory()).path, 'fitness-updates'),
    );
    AndroidRelease? release;
    try {
      release = await widget.releases.check(installed);
      return release;
    } finally {
      if (await _directory.exists()) {
        await for (final entity in _directory.list(followLinks: false)) {
          if (entity is! File) continue;
          final name = p.basename(entity.path);
          final code = int.tryParse(name.split('-').first);
          if (name.endsWith('.part') ||
              (code != null && code <= installed) ||
              (release != null && name != release.fileName)) {
            await removeUpdateFile(entity);
          }
        }
      }
    }
  }

  Future<void> _checkFromProfile(BuildContext context) async {
    if (_checkingManually) return;
    final reopen = switch (_phase) {
      _Phase.idle ||
      _Phase.downloadFailed ||
      _Phase.downloadCancelled ||
      _Phase.cannotInstall => false,
      _ => true,
    };
    if (reopen) {
      await _openDetails();
      return;
    }
    _checked = true;
    _prompted = true;
    setState(() {
      _checkingManually = true;
      _phase = _Phase.idle;
      _message = null;
    });

    AndroidRelease? release;
    String? notice;
    try {
      release = await _findUpdate();
      if (release == null) notice = 'No update available.';
    } on Exception {
      notice = 'Couldn’t check for updates. Try again.';
    } finally {
      if (mounted) setState(() => _checkingManually = false);
    }

    if (!context.mounted || ModalRoute.of(context)?.isCurrent != true) return;
    if (release != null) {
      await _prompt(context, release);
    } else if (notice != null) {
      announce(context, notice);
    }
  }

  Future<void> _prompt(BuildContext context, AndroidRelease release) async {
    _release = release;
    final update = await showDialog<bool>(
      context: context,
      builder: (context) => _UpdatePrompt(release),
    );
    if (!mounted) return;
    if (update == true) {
      unawaited(_startDownload());
      unawaited(_openDetails());
    } else if (update == false) {
      try {
        await _platform.invokeMethod<void>('defer', release.versionCode);
      } on Exception {
        // The prompt is already dismissed for this launch.
      }
    }
  }

  Future<void> _startDownload() async {
    if (_download != null) return;
    final release = _release!;
    _show(_Phase.downloading);
    _percent = 0;
    final download = _download = widget.releases.download(
      release,
      _directory,
      availableBytes: () async =>
          (await _platform.invokeMethod<int>('availableBytes')) ?? 0,
      onProgress: (progress) {
        final percent = (progress * 100).floor();
        if (mounted && percent != _percent) setState(() => _percent = percent);
      },
    );
    try {
      await download.done;
      _show(_Phase.ready);
    } on UpdateCancelled {
      _show(_Phase.downloadCancelled);
    } on UpdateFailure catch (error) {
      _show(_Phase.downloadFailed, error.message);
    } on Exception {
      _show(
        _Phase.downloadFailed,
        'Check your connection and try downloading again.',
      );
    } finally {
      _download = null;
    }
  }

  Future<void> _install() async {
    if (_phase != _Phase.ready) return;
    final release = _release!;
    _show(_Phase.installing);
    try {
      final permission = await _platform.invokeMethod<String>(
        'installPermission',
      );
      if (!mounted) return;
      if (permission != 'allowed') {
        _legacyInstallSettings = permission == 'legacy';
        _show(_Phase.permission);
        return;
      }
      final status = await _platform.invokeMethod<String>('install', {
        'versionCode': release.versionCode,
        'versionName': release.versionName,
        'sha256': release.sha256,
      });
      switch (status) {
        case 'success':
          _show(_Phase.installed);
        case 'cancelled':
          _show(
            _Phase.ready,
            'Installation cancelled. Your download is ready.',
          );
        case 'missing':
        case 'invalid':
          await removeUpdateFile(
            File(p.join(_directory.path, release.fileName)),
          );
          _show(
            _Phase.downloadFailed,
            'Download the verified update file again.',
          );
        case 'mismatch':
        case 'unreadable':
        case 'conflict':
        case 'incompatible':
          await removeUpdateFile(
            File(p.join(_directory.path, release.fileName)),
          );
          _show(_Phase.cannotInstall, switch (status) {
            'mismatch' =>
              'The APK does not match Fitness Tracker or the expected version.',
            'unreadable' => 'Android couldn’t read this APK. It may require a newer version of Android.',
            'conflict' => 'The update conflicts with an installed app. Android kept your current version.',
            _ => 'This version does not support your Android device.',
          });
        case 'storage':
          _show(_Phase.ready, 'Free some storage to install the update.');
        case 'blocked':
          _show(
            _Phase.ready,
            'Android blocked the installation. Check your device’s install settings.',
          );
        default:
          _show(_Phase.ready, 'Couldn’t install the update.');
      }
    } on Exception {
      _show(_Phase.ready, 'Couldn’t open the installer.');
    }
  }

  void _show(_Phase phase, [String? message]) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _message = message;
    });
  }

  void _dismiss() {
    unawaited(
      removeUpdateFile(File(p.join(_directory.path, _release!.fileName))),
    );
    _show(_Phase.idle);
  }

  Future<void> _openSettings() async {
    if (_openingSettings) return;
    setState(() => _openingSettings = true);
    try {
      final granted = await _platform.invokeMethod<bool>('openInstallSettings');
      if (granted == true) {
        _show(
          _Phase.ready,
          'Permission granted. Android will ask you to confirm the install.',
        );
      } else {
        _show(_Phase.permission, 'Installation permission is still off.');
      }
    } on Exception {
      _show(_Phase.permission, 'Couldn’t open Android settings.');
    } finally {
      if (mounted) setState(() => _openingSettings = false);
    }
  }

  Future<void> _openDetails() async {
    final navigator = widget.observer.navigator;
    if (_detailsOpen || navigator == null || _phase == _Phase.idle) return;
    _detailsOpen = true;
    try {
      await navigator.push<void>(
        MaterialPageRoute(builder: (_) => const _UpdatePage()),
      );
    } finally {
      _detailsOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) => _UpdateScope(
    view: (
      release: _release,
      phase: _phase,
      message: _message,
      percent: _percent,
      openingSettings: _openingSettings,
      legacyInstallSettings: _legacyInstallSettings,
      checkingManually: _checkingManually,
    ),
    host: this,
    child: widget.child,
  );
}

typedef _UpdateView = ({
  AndroidRelease? release,
  _Phase phase,
  String? message,
  int percent,
  bool openingSettings,
  bool legacyInstallSettings,
  bool checkingManually,
});

class _UpdateScope extends InheritedWidget {
  const _UpdateScope({
    required this.view,
    required this.host,
    required super.child,
  });

  final _UpdateView view;
  final _AndroidUpdateHostState host;

  static _UpdateScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_UpdateScope>();

  @override
  bool updateShouldNotify(_UpdateScope oldWidget) => view != oldWidget.view;
}

/// The updater is provided only on Android.
class AndroidUpdateCheck extends StatelessWidget {
  const AndroidUpdateCheck({super.key});

  @override
  Widget build(BuildContext context) {
    final update = _UpdateScope.maybeOf(context);
    if (update == null) return const SizedBox.shrink();
    final checking = update.view.checkingManually;
    return Semantics(
      liveRegion: checking,
      child: QuietButton(
        checking ? 'Checking for updates…' : 'Check for updates',
        checking ? null : () => update.host._checkFromProfile(context),
      ),
    );
  }
}

/// Reopen an update that is already underway without taking over navigation.
class AndroidUpdateRow extends StatelessWidget {
  const AndroidUpdateRow({super.key});

  @override
  Widget build(BuildContext context) {
    final update = _UpdateScope.maybeOf(context);
    if (update == null || update.view.phase == _Phase.idle) {
      return const SizedBox.shrink();
    }
    final view = update.view;
    final downloading = view.phase == _Phase.downloading;
    final label = switch (view.phase) {
      _Phase.downloading =>
        view.percent == 100 ? 'Verifying update' : 'Downloading update',
      _Phase.ready => 'Update ready',
      _Phase.downloadFailed => 'Download stopped',
      _Phase.downloadCancelled => 'Download cancelled',
      _Phase.permission => 'Allow installation',
      _Phase.installing => 'Waiting for Android',
      _Phase.cannotInstall => 'Can’t install this update',
      _Phase.installed => 'Update installed',
      _Phase.idle => 'App update',
    };
    final colors = context.colors;
    final trailing = switch (view.phase) {
      _Phase.downloading => '${view.percent}%',
      _Phase.ready => 'Review',
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Material(
        type: MaterialType.transparency,
        child: Semantics(
          button: true,
          child: InkWell(
            onTap: update.host._openDetails,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: Space.target),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(label, style: context.type.titleSmall),
                        ),
                        if (trailing case final text?) ...[
                          const SizedBox(width: Space.md),
                          Text(
                            text,
                            style: context.type.labelLarge?.copyWith(
                              color: colors.green,
                            ),
                          ),
                        ],
                        const SizedBox(width: Space.xs),
                        Icon(
                          LucideIcons.chevronRight,
                          size: 16,
                          color: colors.muted,
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  height: 2,
                  child: downloading
                      ? ExcludeSemantics(
                          child: LinearProgressIndicator(
                            value: view.percent / 100,
                            borderRadius: BorderRadius.zero,
                            trackGap: 0,
                            stopIndicatorRadius: 0,
                            color: colors.green,
                            backgroundColor: colors.border,
                          ),
                        )
                      : const Divider(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdatePrompt extends StatelessWidget {
  const _UpdatePrompt(this.release);
  final AndroidRelease release;

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    constraints: const BoxConstraints(maxWidth: 400),
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Image.asset(
            'assets/brand/update-handoff.webp',
            height: 102,
            excludeFromSemantics: true,
          ),
        ),
        const SizedBox(height: Space.md),
        Text('Update available', style: context.type.headlineSmall),
      ],
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_releaseLabel(release), style: context.type.labelLarge),
        if (release.notes case final note?) ...[
          const SizedBox(height: Space.sm),
          Text(note, style: context.type.bodyMedium),
        ],
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Later'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Update'),
      ),
    ],
  );
}

class _UpdatePage extends StatelessWidget {
  const _UpdatePage();

  @override
  Widget build(BuildContext context) {
    final update = _UpdateScope.maybeOf(context)!;
    final host = update.host;
    final view = update.view;
    final release = view.release!;
    final downloading = view.phase == _Phase.downloading;
    void exit() => Navigator.pop(context);
    void dismiss() {
      host._dismiss();
      exit();
    }

    final (
      title,
      detail,
      label,
      action,
      secondary,
      alternative,
    ) = switch (view.phase) {
      _Phase.downloading => (
        view.percent == 100 ? 'Verifying the download' : 'Downloading update',
        null,
        'Keep using the app',
        exit,
        'Cancel download',
        host._download?.cancel,
      ),
      _Phase.downloadFailed => (
        'Download stopped',
        view.message,
        'Retry download',
        host._startDownload,
        'Dismiss update',
        dismiss,
      ),
      _Phase.downloadCancelled => (
        'Download cancelled',
        null,
        'Restart download',
        host._startDownload,
        'Dismiss update',
        dismiss,
      ),
      _Phase.ready => (
        'Ready to install',
        view.message ?? 'The download passed verification. Your workouts and preferences stay on this device.',
        'Install',
        host._install,
        'Keep using the app',
        exit,
      ),
      _Phase.permission => (
        'Allow app installation',
        view.legacyInstallSettings
            ? 'Turn on “Unknown sources” in Android security settings. Your download is already saved.'
            : 'Turn on “Allow from this source” for Fitness Tracker in Android settings. Your download is already saved.',
        'Open settings',
        view.openingSettings ? null : host._openSettings,
        'Keep using the app',
        exit,
      ),
      _Phase.installing => (
        'Waiting for Android',
        'Confirm the installation when Android asks.',
        null,
        null,
        null,
        null,
      ),
      _Phase.cannotInstall => (
        'Can’t install this update',
        view.message,
        'Dismiss update',
        dismiss,
        null,
        null,
      ),
      _Phase.installed => (
        'Update installed',
        'Open Fitness Tracker to continue.',
        'Done',
        dismiss,
        null,
        null,
      ),
      _Phase.idle => ('App update', null, null, null, null, null),
    };

    return Scaffold(
      appBar: AppBar(title: const Text('App update')),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _releaseLabel(release),
                          style: context.type.labelLarge?.copyWith(
                            color: context.colors.muted,
                          ),
                        ),
                        const SizedBox(height: Space.sm),
                        Semantics(
                          header: true,
                          liveRegion: !downloading,
                          child: Text(title, style: context.type.headlineLarge),
                        ),
                        if (detail case final detail?) ...[
                          const SizedBox(height: Space.md),
                          Text(
                            detail,
                            style: context.type.bodyLarge?.copyWith(
                              color: context.colors.muted,
                            ),
                          ),
                        ],
                        if (view.phase == _Phase.permission &&
                            view.message != null) ...[
                          const SizedBox(height: Space.sm),
                          Text(view.message!, style: context.type.bodyMedium),
                        ],
                        if (downloading) ...[
                          const SizedBox(height: Space.xl),
                          ExcludeSemantics(
                            child: Text(
                              '${view.percent}%',
                              style: context.type.headlineMedium?.copyWith(
                                color: context.colors.green,
                              ),
                            ),
                          ),
                          const SizedBox(height: Space.sm),
                          LinearProgressIndicator(
                            value: view.percent / 100,
                            minHeight: 5,
                            borderRadius: BorderRadius.circular(3),
                            backgroundColor: context.colors.border,
                            semanticsLabel: 'Update download',
                            semanticsValue: '${view.percent}%',
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (label case final label?)
                          FilledButton(onPressed: action, child: Text(label)),
                        if (secondary case final secondary?)
                          TextButton(
                            onPressed: alternative,
                            child: Text(secondary),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _releaseLabel(AndroidRelease release) =>
    'Version ${release.versionName} · ${_apkSize(release.size)}';

String _apkSize(int bytes) =>
    bytes < 1000000 ? '<1 MB' : '${(bytes / 1000000).round()} MB';
