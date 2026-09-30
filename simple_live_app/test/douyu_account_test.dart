import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/mine/account/account_controller.dart';
import 'package:simple_live_app/modules/mine/account/account_page.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:simple_live_app/services/douyu_account_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class MemoryDouyuAccount extends DouyuAccountService {
  String savedCookie = '';

  @override
  Future<void> setCookie(String value) async {
    savedCookie = value.trim();
    hasCookie.value = savedCookie.isNotEmpty;
  }
}

void main() {
  late Directory directory;
  late LocalStorageService storage;
  late DouyuSite site;

  setUp(() async {
    Get.testMode = true;
    directory = await Directory.systemTemp.createTemp('douyu-account-test-');
    Hive.init(directory.path);
    storage = LocalStorageService();
    storage.settingsBox = await Hive.openBox('settings');
    Get.put(storage);
    site = Sites.allSites[Constant.kDouyu]!.liveSite as DouyuSite;
  });

  tearDown(() async {
    site.cookie = '';
    Get.reset();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('saved Cookie survives restart and logout clears both storage and site',
      () async {
    var service = Get.put(DouyuAccountService());
    expect(service.hasCookie.value, isFalse);
    expect(site.cookie, isEmpty);

    await service.setCookie('  acf_auth=test-auth; acf_uid=123  ');
    expect(service.hasCookie.value, isTrue);
    expect(site.cookie, 'acf_auth=test-auth; acf_uid=123');

    await Get.delete<DouyuAccountService>(force: true);
    await storage.settingsBox.close();
    storage.settingsBox = await Hive.openBox('settings');
    site.cookie = '';
    service = Get.put(DouyuAccountService());
    expect(service.hasCookie.value, isTrue);
    expect(site.cookie, 'acf_auth=test-auth; acf_uid=123');

    await service.logout();
    expect(service.hasCookie.value, isFalse);
    expect(site.cookie, isEmpty);
    expect(storage.settingsBox.containsKey(LocalStorageService.kDouyuCookie),
        isFalse);

    await Get.delete<DouyuAccountService>(force: true);
    service = Get.put(DouyuAccountService());
    expect(service.hasCookie.value, isFalse);
    expect(site.cookie, isEmpty);
  });

  testWidgets('account page accepts Cookie and confirms logout',
      (tester) async {
    final service = MemoryDouyuAccount();
    Get.put<DouyuAccountService>(service);
    Get.put(BiliBiliAccountService());
    Get.put(DouyinAccountService());
    Get.put(AccountController());
    await tester.pumpWidget(GetMaterialApp(
      home: const AccountPage(),
      navigatorObservers: [FlutterSmartDialog.observer],
      builder: FlutterSmartDialog.init(),
    ));

    await tester.tap(find.text('斗鱼直播'));
    await tester.pumpAndSettle();
    expect(find.text('斗鱼 Cookie 登录'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'acf_auth=test-auth');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(service.savedCookie, 'acf_auth=test-auth');
    expect(find.text('已配置 Cookie，点击退出'), findsOneWidget);
    await SmartDialog.dismiss();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    await tester.tap(find.text('斗鱼直播'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(service.hasCookie.value, isTrue);

    await tester.tap(find.text('斗鱼直播'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(service.savedCookie, isEmpty);
    expect(find.text('输入 Cookie，获取原画直播'), findsOneWidget);
    await SmartDialog.dismiss();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
