import 'package:flutter/services.dart';

import 'receive_flow.dart';

/// Android-only helpers implemented in Kotlin (MainActivity): joining the laptop's hotspot,
/// saving into the public Downloads folder, opening Downloads.
class NativeBridge implements WifiJoiner {
  static const _channel = MethodChannel('lanshare/native');

  @override
  Future<bool> join(String ssid, String pass) async {
    try {
      return await _channel.invokeMethod<bool>('joinWifi', {'ssid': ssid, 'pass': pass}) ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> leave() async {
    try {
      await _channel.invokeMethod<void>('leaveWifi');
    } on PlatformException {
      // nothing left to release
    }
  }

  Future<void> saveToDownloads(DownloadedFile file) =>
      _channel.invokeMethod<void>('saveToDownloads', {'path': file.path, 'name': file.name});

  Future<void> openDownloads() async {
    try {
      await _channel.invokeMethod<void>('openDownloads');
    } on PlatformException {
      // no Downloads app
    }
  }
}
