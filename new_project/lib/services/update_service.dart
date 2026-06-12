import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Queries the GitHub Releases API to detect and surface new versions.
///
/// No manual version.json editing required — just push a new tag like
/// `v1.0.1` and this service will pick it up automatically.
class UpdateService {
  static const String _repoOwner = 'Naitik2103';
  static const String _repoName = 'CampusNav';

  static const String _releasesApiUrl =
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';

  static const String _releasesPageUrl =
      'https://github.com/$_repoOwner/$_repoName/releases/latest';

  // Cached after first check so the dialog can use them without a second call.
  static String? latestApkUrl;
  static String? latestVersion;
  static String? latestReleaseNotes;

  /// Fetches the latest release info from GitHub Releases API.
  ///
  /// Returns a map with keys: version, apk_url, release_notes.
  /// Returns null on network error or if no release exists yet.
  Future<Map<String, dynamic>?> getLatest() async {
    try {
      final response = await http
          .get(
            Uri.parse(_releasesApiUrl),
            headers: {
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // Tag is like "v1.0.1" — strip the leading "v" for comparison.
        final tagName = data['tag_name']?.toString() ?? '';
        final version = tagName.replaceAll(RegExp(r'^v'), '');

        // Find the APK asset download URL.
        String apkUrl = _releasesPageUrl; // fallback to releases page
        final assets = data['assets'] as List<dynamic>? ?? [];
        for (final asset in assets) {
          final name = asset['name']?.toString() ?? '';
          if (name.endsWith('.apk')) {
            apkUrl = asset['browser_download_url']?.toString() ?? apkUrl;
            break;
          }
        }

        // Release body / changelog written in the GitHub Release.
        final releaseNotes = (data['body']?.toString() ?? '').trim();

        return {
          'version': version,
          'apk_url': apkUrl,
          'release_notes': releaseNotes.isNotEmpty
              ? releaseNotes
              : 'A new version of CampusNav is available.',
        };
      } else {
        debugPrint(
          'GitHub API returned status ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('UpdateService.getLatest error: $e');
    }
    return null;
  }

  /// Returns true when the latest GitHub Release version differs from the
  /// version currently installed on the device.
  ///
  /// Also populates [latestApkUrl], [latestVersion], [latestReleaseNotes]
  /// so callers don't need a second network round-trip.
  Future<bool> checkForUpdate() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      final String currentVersion = info.version; // e.g. "1.0.0"

      final latest = await getLatest();
      if (latest == null || (latest['version'] as String).isEmpty) {
        return false;
      }

      latestVersion = latest['version'] as String;
      latestApkUrl = latest['apk_url'] as String;
      latestReleaseNotes = latest['release_notes'] as String;

      debugPrint(
        'UpdateService: current=$currentVersion, latest=$latestVersion',
      );

      return currentVersion != latestVersion;
    } catch (e) {
      debugPrint('UpdateService.checkForUpdate error: $e');
      return false;
    }
  }
}
