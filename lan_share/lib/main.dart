import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'core/app_file.dart';
import 'core/app_share.dart';
import 'core/args.dart';
import 'core/hotspot.dart';
import 'core/hotspot_runner.dart';
import 'core/identity.dart';
import 'core/lan_address.dart';
import 'core/settings.dart';
import 'mobile/mobile_app.dart';
import 'ui/app_qr_dialog.dart';
import 'ui/home_view.dart';
import 'ui/receive_screen.dart';
import 'ui/send_screen.dart';
import 'ui/theme.dart';

void main(List<String> args) {
  // the phone gets its own receiving app; the laptop keeps the sharing app
  if (Platform.isAndroid) {
    runApp(const MobileApp());
    return;
  }
  runApp(App(initial: parseSharedPaths(args)));
}

class App extends StatelessWidget {
  const App({super.key, this.initial = const []});
  final List<File> initial;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'LAN Share',
        debugShowCheckedModeBanner: false,
        theme: lightTheme(),
        darkTheme: appTheme(),
        themeMode: ThemeMode.system,
        home: Home(initial: initial),
      );
}

class Home extends StatefulWidget {
  const Home({super.key, this.initial = const []});
  final List<File> initial;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  bool _dragging = false;
  Settings _settings = Settings();
  Directory? _dir;
  String? _address;
  Timer? _net;
  final File? _apk = bundledApk();

  @override
  void initState() {
    super.initState();
    if (widget.initial.isNotEmpty) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _send(widget.initial, closeApp: true));
    }
    // a hotspot left on by a crashed run is turned off and the user's settings restored
    // (when sharing right away, the sending screen does this itself, before it starts a hotspot)
    if (Platform.isWindows && widget.initial.isEmpty) unawaited(Hotspot(powershellRunner).recover());
    _loadSettings();
    _refreshAddress();
    _net = Timer.periodic(const Duration(seconds: 5), (_) => _refreshAddress());
  }

  @override
  void dispose() {
    _net?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    _dir = await getApplicationSupportDirectory();
    final s = await Settings.load(_dir!);
    if (mounted) setState(() => _settings = s);
  }

  /// Which network this laptop is on, shown as a chip; null when there is none.
  Future<void> _refreshAddress() async {
    final a = await pickLanAddress();
    final text = a.isLoopback ? null : a.address;
    if (mounted && text != _address) setState(() => _address = text);
  }

  Future<void> _toggleAssist() async {
    setState(() => _settings.hotspotAssist = !_settings.hotspotAssist);
    if (_dir != null) await _settings.save(_dir!);
  }

  /// A QR that sends a phone to the Android app on this laptop; closing it stops the sharing.
  Future<void> _phoneApp() async {
    final apk = _apk;
    if (apk == null) return;
    final share = AppShare(apk, await loadOrCreateIdentity(await getApplicationSupportDirectory()));
    try {
      final url = await share.start();
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (_) => AppQrDialog(url: url));
    } finally {
      await share.stop();
    }
  }

  void _send(List<File> files, {bool closeApp = false}) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SendScreen(files: files, closeApp: closeApp)));

  Future<void> _pick() async {
    final picked = await FilePicker.pickFiles();
    final files = [
      for (final f in picked) if (f.path != null) File(f.path!)
    ];
    if (files.isNotEmpty && mounted) _send(files);
  }

  void _dropped(DropDoneDetails d) {
    setState(() => _dragging = false);
    // folders are skipped: only real files can be served
    final files = [for (final f in d.files) if (File(f.path).existsSync()) File(f.path)];
    if (files.isNotEmpty && mounted) _send(files);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: _dropped,
          child: HomeView(
            dragging: _dragging,
            onPick: _pick,
            onReceive: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ReceiveScreen())),
            showPhoneApp: _apk != null,
            onPhoneApp: _phoneApp,
            assistOn: _settings.hotspotAssist,
            onToggleAssist: Platform.isWindows ? _toggleAssist : null,
            address: _address,
          ),
        ),
      );
}
