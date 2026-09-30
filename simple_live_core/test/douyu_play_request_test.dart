import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:test/test.dart';

void main() {
  test(
    'all Douyu CDN requests preserve the player capability parameters',
    () async {
      final originalDio = HttpClient.instance.dio;
      final requests = <RequestOptions>[];
      final dio = Dio();
      HttpClient.instance.dio = dio;
      addTearDown(() {
        HttpClient.instance.dio = originalDio;
        dio.close();
      });
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            final params = Uri.splitQueryString(options.data as String);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'error': 0,
                  'data': {
                    'cdnsWithName': [
                      {'cdn': 'hw-h5'},
                      {'cdn': 'hs-h5'},
                    ],
                    'multirates': [
                      {'name': '蓝光4M', 'rate': 4},
                    ],
                    'rtmp_url': 'https://example.com',
                    'rtmp_live': '${params['cdn']}.flv?first=1&amp;second=2',
                  },
                },
              ),
            );
          },
        ),
      );
      final detail = LiveRoomDetail(
        roomId: '71415',
        title: '',
        cover: '',
        userName: '',
        userAvatar: '',
        online: 0,
        status: true,
        url: '',
        data: 'v=test&did=test-device&tt=123&sign=test-signature',
      );
      final site = DouyuSite();
      final qualities = await site.getPlayQualites(detail: detail);
      final result = await site.getPlayUrls(
        detail: detail,
        quality: qualities.single,
      );

      expect(requests, hasLength(3));
      final params = requests
          .map((request) => Uri.splitQueryString(request.data as String))
          .toList();
      for (var i = 0; i < requests.length; i++) {
        expect(requests[i].path, endsWith('/getH5Play/71415'));
        expect(requests[i].contentType, Headers.formUrlEncodedContentType);
        expect(params[i], containsPair('did', 'test-device'));
        expect(params[i], containsPair('sign', 'test-signature'));
        expect(params[i], containsPair('ive', '1'));
        expect(params[i], containsPair('iar', '1'));
        expect(params[i], containsPair('hevc', '0'));
        expect(params[i], containsPair('fa', '0'));
        expect(params[i], containsPair('ver', params.first['ver']));
      }
      expect(params.map((p) => p['rate']), ['-1', '4', '4']);
      expect(params.map((p) => p['cdn']), ['', 'hw-h5', 'hs-h5']);
      expect(result.urls, [
        'https://example.com/hw-h5.flv?first=1&second=2',
        'https://example.com/hs-h5.flv?first=1&second=2',
      ]);
    },
  );
}
