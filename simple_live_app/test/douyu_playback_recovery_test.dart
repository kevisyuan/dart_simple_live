import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_core/simple_live_core.dart';

class TestSettings extends AppSettingsController {
  @override
  // Settings persistence is deliberately excluded from playback tests.
  // ignore: must_call_super
  void onInit() {}
}

class FakePlayer extends Fake implements Player {
  final opened = <Playable>[];
  Future<void> Function()? onOpen;
  int jumps = 0;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    opened.add(playable);
    await onOpen?.call();
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> jump(int index) async {
    jumps++;
  }
}

LiveRoomDetail room({
  bool live = true,
  bool record = false,
  String sign = 'fresh',
}) =>
    LiveRoomDetail(
      roomId: '71415',
      title: 'test',
      cover: '',
      userName: 'test',
      userAvatar: '',
      online: 1,
      status: live,
      isRecord: record,
      url: 'https://www.douyu.com/71415',
      data: sign,
    );

class FakeDouyu extends LiveSite {
  int detailRequests = 0;
  final urlSignatures = <Object?>[];
  final requestedQualities = <String>[];
  Future<LiveRoomDetail> Function()? onDetail;
  List<LivePlayQuality> qualities = [
    LivePlayQuality(quality: '原画', data: 0),
    LivePlayQuality(quality: '高清', data: 1),
  ];
  List<String> urls = ['https://cdn.example/fresh.flv'];

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) {
    detailRequests++;
    return onDetail?.call() ??
        Future.value(room(sign: 'fresh-$detailRequests'));
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({
    required LiveRoomDetail detail,
  }) async =>
      qualities;

  @override
  Future<LivePlayUrl> getPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) async {
    urlSignatures.add(detail.data);
    requestedQualities.add(quality.quality);
    return LivePlayUrl(urls: urls, headers: {'Referer': detail.url});
  }
}

class TestController extends LiveRoomController {
  final fakePlayer = FakePlayer();
  TestController(FakeDouyu liveSite)
      : super(
          pSite: Site(id: 'douyu', name: '斗鱼', logo: '', liveSite: liveSite),
          pRoomId: '71415',
        );

  @override
  Player get player => fakePlayer;

  @override
  Future<void> initializePlayer() async {}

  @override
  Future<void> resetSystem() async {}

  // Manual refresh still executes refreshRoom's cancellation, without loading
  // unrelated UI, persistence or danmaku services in these controller tests.
  @override
  void loadData() {}
}

void main() {
  late FakeDouyu site;
  late TestController controller;

  setUp(() async {
    Get.put<AppSettingsController>(TestSettings());
    site = FakeDouyu();
    controller = TestController(site);
    controller.detail.value = room(sign: 'expired');
    controller.liveStatus.value = true;
    controller.qualites.assignAll(site.qualities);
    controller.currentQuality = 1;
    controller.currentQualityInfo.value = '高清';
    controller.playUrls.assignAll([
      'https://cdn.example/expired.flv',
      'https://backup.example/expired.flv',
    ]);
    controller.currentLineIndex = 0;
    await controller.initPlaylist();
  });

  tearDown(() async {
    controller.scrollController.dispose();
    Get.reset();
  });

  testWidgets('refreshes the signature and URL while preserving quality', (
    tester,
  ) async {
    final recovery = controller.recoverDouyuPlayback();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await recovery;

    expect(site.urlSignatures, ['fresh-1']);
    expect(site.requestedQualities, ['高清']);
    expect(controller.liveStatus.value, isTrue);
    expect(controller.fakePlayer.opened, everyElement(isA<Media>()));
    expect((controller.fakePlayer.opened.last as Media).uri, site.urls.single);
    expect(
      (controller.fakePlayer.opened.last as Media).httpHeaders?['Referer'],
      'https://www.douyu.com/71415',
    );
    expect(controller.fakePlayer.jumps, 0);
    expect(controller.errorMsg.value, isEmpty);
  });

  testWidgets('only confirmed offline changes the room to not live', (
    tester,
  ) async {
    site.onDetail = () async => room(live: false);
    final recovery = controller.recoverDouyuPlayback();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await recovery;
    expect(controller.liveStatus.value, isFalse);
    expect(site.urlSignatures, isEmpty);
    expect(controller.fakePlayer.opened, hasLength(1));
  });

  testWidgets('recorded playback is still playable', (tester) async {
    site.onDetail = () async => room(live: false, record: true);
    final recovery = controller.recoverDouyuPlayback();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await recovery;
    expect(controller.liveStatus.value, isTrue);
    expect(controller.fakePlayer.opened, hasLength(2));
  });

  testWidgets('bounds request failures without marking the streamer offline', (
    tester,
  ) async {
    site.onDetail = () async => throw StateError('network unavailable');
    final recovery = controller.recoverDouyuPlayback();
    await tester.pump();
    for (final seconds in [1, 2, 4]) {
      await tester.pump(Duration(seconds: seconds));
    }
    await recovery;
    expect(site.detailRequests, 3);
    expect(controller.liveStatus.value, isTrue);
    expect(controller.errorMsg.value, '直播连接异常，请刷新重试');
    await controller.recoverDouyuPlayback();
    expect(site.detailRequests, 3);
  });

  testWidgets('coalesces repeated EOF callbacks during a pending request', (
    tester,
  ) async {
    final response = Completer<LiveRoomDetail>();
    site.onDetail = () => response.future;
    final recovery = controller.recoverDouyuPlayback();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await controller.recoverDouyuPlayback();
    await controller.recoverDouyuPlayback();
    response.complete(room());
    await tester.pump();
    await recovery;
    expect(site.detailRequests, 1);
    expect(controller.fakePlayer.opened, hasLength(2));
  });

  testWidgets('does not lose a failure emitted while opening the new stream', (
    tester,
  ) async {
    controller.fakePlayer.onOpen = () async {
      await controller.recoverDouyuPlayback();
    };
    final recovery = controller.recoverDouyuPlayback();
    await tester.pump();
    for (final seconds in [1, 2, 4]) {
      await tester.pump(Duration(seconds: seconds));
    }
    await recovery;
    expect(site.detailRequests, 3);
    expect(controller.liveStatus.value, isTrue);
    expect(controller.errorMsg.value, '直播连接异常，请刷新重试');
  });

  testWidgets('ignores a stale offline response after manual refresh', (
    tester,
  ) async {
    final response = Completer<LiveRoomDetail>();
    site.onDetail = () => response.future;
    final recovery = controller.recoverDouyuPlayback();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    controller.refreshRoom();
    response.complete(room(live: false));
    await tester.pump();
    await recovery;
    expect(controller.liveStatus.value, isTrue);
    expect(controller.fakePlayer.opened, hasLength(1));
  });

  testWidgets('falls back safely if the previous quality disappears', (
    tester,
  ) async {
    site.qualities = [LivePlayQuality(quality: '流畅', data: 2)];
    final recovery = controller.recoverDouyuPlayback();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await recovery;
    expect(site.requestedQualities, ['流畅']);
    expect(controller.currentQuality, 0);
  });

  testWidgets('ignores a response from the previous room after switching', (
    tester,
  ) async {
    final response = Completer<LiveRoomDetail>();
    site.onDetail = () => response.future;
    final recovery = controller.recoverDouyuPlayback();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    controller.resetRoom(controller.site, '217331');
    await tester.pump();
    response.complete(room(live: false));
    await tester.pump();
    await recovery;
    expect(controller.roomId, '217331');
    expect(controller.liveStatus.value, isTrue);
    expect(controller.fakePlayer.opened, hasLength(1));
  });

  testWidgets('does not restart playback after the controller is closed', (
    tester,
  ) async {
    final response = Completer<LiveRoomDetail>();
    site.onDetail = () => response.future;
    final recovery = controller.recoverDouyuPlayback();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    controller.onClose();
    response.complete(room());
    await tester.pump();
    await recovery;
    expect(site.urlSignatures, isEmpty);
    expect(controller.fakePlayer.opened, hasLength(1));
  });

  testWidgets('empty URLs exhaust recovery without changing live status', (
    tester,
  ) async {
    site.urls = [];
    final recovery = controller.recoverDouyuPlayback();
    await tester.pump();
    for (final seconds in [1, 2, 4]) {
      await tester.pump(Duration(seconds: seconds));
    }
    await recovery;
    expect(site.detailRequests, 3);
    expect(controller.liveStatus.value, isTrue);
    expect(controller.fakePlayer.opened, hasLength(1));
    expect(controller.errorMsg.value, '直播连接异常，请刷新重试');
  });
}
