import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class UpdateService {
  static String? latestApkUrl;

  Future<Map<String, dynamic>?> getLatestRelease() async {
    try {
      final response = await http.get(
        Uri.parse(
          "https://api.github.com/repos/Naitik2103/CampusNav/releases/latest",
        ),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint("Error fetching latest release: $e");
    }
    return null;
  }

  Future<bool> checkForUpdate() async {
    try {
      PackageInfo info = await PackageInfo.fromPlatform();
      String currentVersion = info.version;

      var latest = await getLatestRelease();
      if (latest == null || latest["tag_name"] == null) {
        return false;
      }

      String latestVersion = latest["tag_name"].toString().replaceAll("v", "");
      
      // Parse the APK download URL if available, otherwise fallback to release page
      String? apkUrl;
      if (latest["assets"] != null && latest["assets"] is List) {
        for (var asset in latest["assets"]) {
          if (asset["name"] != null && asset["name"].toString().endsWith(".apk")) {
            apkUrl = asset["browser_download_url"];
            break;
          }
        }
      }
      apkUrl ??= latest["html_url"];
      latestApkUrl = apkUrl;

      // Simple version check
      return currentVersion != latestVersion;
    } catch (e) {
      debugPrint("Error checking for update: $e");
      return false;
    }
  }
}
