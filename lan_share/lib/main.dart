import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'core/args.dart';
import 'core/hotspot.dart';
import 'core/hotspot_runner.dart';
import 'ui/home_view.dart';
import 'ui/receive_screen.dart';
import 'ui/send_screen.dart';
import 'ui/theme.dart';

void main(List<String> args) {
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

  @override
  void initState() {
    super.initState();
    if (widget.initial.isNotEmpty) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _send(widget.initial, closeApp: true));
    }
    if (Platform.isAndroid) _listenShares();
    // a hotspot left on by a crashed run is turned off and the user's settings restored
    if (Platform.isWindows) unawaited(Hotspot(powershellRunner).recover());
  }

  Future<void> _listenShares() async {
    List<File> toFiles(List<SharedMediaFile> m) =>
        [for (final f in m) if (File(f.path).existsSync()) File(f.path)];
    final first = toFiles(await ReceiveSharingIntent.instance.getInitialMedia());
    if (first.isNotEmpty && mounted) _send(first);
    ReceiveSharingIntent.instance.getMediaStream().listen((m) {
      final files = toFiles(m);
      if (files.isNotEmpty && mounted) _send(files);
    });
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
          ),
        ),
      );
}
