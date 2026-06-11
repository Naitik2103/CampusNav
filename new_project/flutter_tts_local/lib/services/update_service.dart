import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class UpdateService {
  static String? latestApkUrl;

  Future<Map<String, dynamic>?> getLatest() async {
    try {
      final response = await http.get(
        Uri.parse(
          "https://naitik2103.github.io/CampusNav/update/version.json",
        ),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint("Error fetching latest version info: $e");
    }
    return null;
  }

  Future<bool> checkForUpdate() async {
    try {
      PackageInfo info = await PackageInfo.fromPlatform();
      String currentVersion = info.version;

      var latest = await getLatest();
      if (latest == null || latest["version"] == null) {
        return false;
      }

      String latestVersion = latest["version"].toString().replaceAll("v", "");
      latestApkUrl = latest["apk_url"];

      // Simple version check
      return currentVersion != latestVersion;
    } catch (e) {
      debugPrint("Error checking for update: $e");
      return false;
    }
  }
}