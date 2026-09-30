import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class DouyuAccountService extends GetxService {
  static DouyuAccountService get instance => Get.find<DouyuAccountService>();

  final hasCookie = false.obs;

  @override
  void onInit() {
    // Read the box directly: the generic storage helpers log their values.
    final cookie = LocalStorageService.instance.settingsBox
        .get(LocalStorageService.kDouyuCookie, defaultValue: "") as String;
    _setSite(cookie);
    super.onInit();
  }

  Future<void> setCookie(String value) async {
    final cookie = value.trim();
    final box = LocalStorageService.instance.settingsBox;
    if (cookie.isEmpty) {
      await box.delete(LocalStorageService.kDouyuCookie);
    } else {
      await box.put(LocalStorageService.kDouyuCookie, cookie);
    }
    _setSite(cookie);
  }

  Future<void> logout() => setCookie("");

  void _setSite(String cookie) {
    final site = Sites.allSites[Constant.kDouyu]!.liveSite as DouyuSite;
    site.cookie = cookie;
    hasCookie.value = cookie.isNotEmpty;
  }
}
