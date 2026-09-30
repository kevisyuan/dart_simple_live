import 'package:dio/dio.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:test/test.dart';

void main() {
  late Dio originalDio;
  late Dio dio;
  late List<RequestOptions> requests;
  late DouyuSite site;

  final detail = LiveRoomDetail(
    roomId: '71415',
    title: '',
    cover: '',
    userName: '',
    userAvatar: '',
    online: 0,
    status: true,
    url: '',
    data: 'sign=test-signature',
  );

  setUp(() {
    originalDio = HttpClient.instance.dio;
    dio = Dio();
    HttpClient.instance.dio = dio;
    requests = [];
    site = DouyuSite();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
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
                    {'name': '原画', 'rate': 0},
                  ],
                  'rtmp_url': 'https://cdn.example',
                  'rtmp_live': 'live.flv?expire=0&amp;token=test',
                },
              },
            ),
          );
        },
      ),
    );
  });

  tearDown(() {
    HttpClient.instance.dio = originalDio;
    dio.close();
  });

  test(
    'Cookie is sent to quality and every original-quality CDN lookup',
    () async {
      site.cookie = 'acf_auth=test-auth; acf_uid=123';
      final qualities = await site.getPlayQualites(detail: detail);
      final result = await site.getPlayUrls(
        detail: detail,
        quality: qualities.single,
      );

      expect(requests, hasLength(3));
      for (final request in requests) {
        expect(request.uri.host, 'www.douyu.com');
        expect(request.uri.path, '/lapi/live/getH5Play/71415');
        expect(request.headers['Cookie'], site.cookie);
      }
      final playbackParams = requests
          .skip(1)
          .map((request) => Uri.splitQueryString(request.data as String));
      expect(playbackParams.map((params) => params['rate']), ['0', '0']);
      expect(playbackParams.map((params) => params['cdn']), ['hw-h5', 'hs-h5']);
      expect(result.urls, hasLength(2));
      expect(
        result.urls.first,
        'https://cdn.example/live.flv?expire=0&token=test',
      );
      // Account credentials must not become the media player's CDN headers.
      expect(result.headers, isNull);
    },
  );

  test(
    'clearing Cookie returns all later playback requests to anonymous',
    () async {
      site.cookie = 'acf_auth=test-auth';
      final qualities = await site.getPlayQualites(detail: detail);
      site.cookie = '';
      requests.clear();
      await site.getPlayQualites(detail: detail);
      await site.getPlayUrls(detail: detail, quality: qualities.single);

      expect(requests, hasLength(3));
      for (final request in requests) {
        expect(
          request.headers.keys.map((key) => key.toLowerCase()),
          isNot(contains('cookie')),
        );
      }
    },
  );
}
