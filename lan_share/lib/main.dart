import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'core/args.dart';
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
        theme: appTheme(),
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
  @override
  void initState() {
    super.initState();
    if (widget.initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _send(widget.initial));
    }
    if (Platform.isAndroid) _listenShares();
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

  void _send(List<File> files) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => SendScreen(files: files)));

  Future<void> _pick() async {
    final picked = await FilePicker.pickFiles();
    final files = [
      for (final f in picked) if (f.path != null) File(f.path!)
    ];
    if (files.isNotEmpty && mounted) _send(files);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Expanded(
                  child: _Tile(
                key: const Key('send'),
                icon: Icons.north_rounded,
                colors: const [C.blue, C.violet],
                onTap: _pick,
              )),
              const SizedBox(height: 16),
              Expanded(
                  child: _Tile(
                key: const Key('receive'),
                icon: Icons.south_rounded,
                colors: const [C.green, Color(0xFF14B8A6)],
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const ReceiveScreen())),
              )),
            ]),
          ),
        ),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.icon, required this.colors, required this.onTap});
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        borderRadius: BorderRadius.circular(36),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          ),
          child: InkWell(
            onTap: onTap,
            child: Center(child: Icon(icon, size: 110, color: Colors.white)),
          ),
        ),
      );
}
