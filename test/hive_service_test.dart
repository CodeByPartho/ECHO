import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:echo/core/constants.dart';
import 'package:echo/services/hive_service.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hive_service_test');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  test('startup cleanup keeps current server settings', () async {
    final box = await Hive.openBox(AppConstants.settingsBox);
    await box.put(AppConstants.keyServerAllowNetwork, true);
    await box.put(AppConstants.keyServerUseApiKey, true);
    await box.put(AppConstants.keyServerApiKey, 'aichat_abc');
    await box.put('server_obsolete_provider', 'x');
    await box.close();

    final hive = await HiveService().init();

    expect(hive.getSetting<bool>(AppConstants.keyServerAllowNetwork), isTrue);
    expect(hive.getSetting<bool>(AppConstants.keyServerUseApiKey), isTrue);
    expect(hive.getSetting<String>(AppConstants.keyServerApiKey), 'aichat_abc');
    expect(hive.settingsBox.containsKey('server_obsolete_provider'), isFalse);
  });
}
