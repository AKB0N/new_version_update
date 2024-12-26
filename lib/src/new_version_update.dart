import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Information about the app's current version, and the most recent version
/// available in the Apple App Store or Google Play Store.
class VersionStatus {
  /// The current version of the app.
  final String localVersion;

  /// The most recent version of the app in the store.
  final String storeVersion;

  final bool isShowChangelog;

  /// A link to the app store page where the app can be updated.
  final String appStoreLink;

  /// The release notes for the store version of the app.
  final String? releaseNotes;

  /// Returns `true` if the store version of the application is greater than the local version.
  bool get canUpdate {
    final local = localVersion.split('.').map(int.parse).toList();
    final store = storeVersion.split('.').map(int.parse).toList();

    // Each consecutive field in the version notation is less significant than the previous one,
    // therefore only one comparison needs to yield `true` for it to be determined that the store
    // version is greater than the local version.
    for (var i = 0; i < store.length; i++) {
      // The store version field is newer than the local version.
      if (store[i] > local[i]) {
        return true;
      }

      // The local version field is newer than the store version.
      if (local[i] > store[i]) {
        if (isShowChangelog) {
          return true;
        } else {
          return false;
        }
      }

      // The local version field is newer than the store version.
      if (local[i] >= store[i]) {
        if (isShowChangelog) {
          return true;
        } else {
          return false;
        }
      }
    }

    // The local and store versions are the same.
    return false;
  }

  VersionStatus._({
    required this.localVersion,
    required this.storeVersion,
    required this.appStoreLink,
    required this.isShowChangelog,
    this.releaseNotes,
  });
}

class NewVersionUpdate {
  /// An optional value that can override the default packageName when
  /// attempting to reach the Apple App Store. This is useful if your app has
  /// a different package name in the App Store.
  final String? iOSId;

  /// An optional value that can override the default packageName when
  /// attempting to reach the Google Play Store. This is useful if your app has
  /// a different package name in the Play Store.
  final String? androidId;

  /// Only affects iOS App Store lookup: The two-letter country code for the store you want to search.
  /// Provide a value here if your app is only available outside the US.
  /// For example: US. The default is US.
  /// See https://en.wikipedia.org/wiki/ ISO_3166-1_alpha-2 for a list of ISO Country Codes.
  final String? iOSAppStoreCountry;

  /// An optional value that will force the plugin to always return [forceAppVersion]
  /// as the value of [storeVersion]. This can be useful to test the plugin's behavior
  /// before publishng a new version.
  final String? forceAppVersion;
  final bool? isShowChangelog;

  NewVersionUpdate({
    this.androidId,
    this.iOSId,
    this.iOSAppStoreCountry,
    this.forceAppVersion,
    required this.isShowChangelog,
  });

  /// This checks the version status, then displays a platform-specific alert
  /// with buttons to dismiss the update alert, or go to the app store.
  Future<void> showAlertIfNecessary({required BuildContext context}) async {
    final VersionStatus? versionStatus = await getVersionStatus();
    if (versionStatus != null && versionStatus.canUpdate) {
      if (context.mounted) {
        showUpdateDialog(context: context, versionStatus: versionStatus);
      }
    }
  }

  Future<VersionStatus?> _makeHttpGetRequest(Uri uri) async {
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return await _processResponse(response, uri);
      } else {
        debugPrint(
            'Request failed: ${uri.toString()} Status code: ${response.statusCode}');
        return null;
      }
    } on SocketException catch (e) {
      debugPrint('SocketException: $e, uri: $uri');
      return null;
    } on http.ClientException catch (e) {
      debugPrint('ClientException: $e, uri: $uri');
      return null;
    } catch (e) {
      debugPrint('Unexpected exception when doing GET request: $e, uri: $uri');
      return null;
    }
  }

  Future<VersionStatus?> _processResponse(
      http.Response response, Uri uri) async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    if (Platform.isIOS) {
      return await _parseIosVersion(packageInfo, response);
    } else if (Platform.isAndroid) {
      return await _parseAndroidVersion(packageInfo, response, uri);
    }
    return null;
  }

  Future<VersionStatus?> _parseIosVersion(
      PackageInfo packageInfo, http.Response response) async {
    final jsonObj = json.decode(response.body);
    final List results = jsonObj['results'];
    if (results.isEmpty) {
      debugPrint(
          'Can\'t find an app in the App Store with the id: ${packageInfo.packageName}');
      return null;
    }
    return VersionStatus._(
      localVersion: _getCleanVersion(packageInfo.version),
      storeVersion:
          _getCleanVersion(forceAppVersion ?? jsonObj['results'][0]['version']),
      appStoreLink: jsonObj['results'][0]['trackViewUrl'],
      releaseNotes: jsonObj['results'][0]['releaseNotes'],
      isShowChangelog: isShowChangelog!,
    );
  }

  Future<VersionStatus?> _parseAndroidVersion(
      PackageInfo packageInfo, http.Response response, Uri uri) async {
    final document = parse(response.body);

    String storeVersion = '0.0.0';
    String? releaseNotes;

    final additionalInfoElements = document.getElementsByClassName('hAyfc');
    if (additionalInfoElements.isNotEmpty) {
      final versionElement = additionalInfoElements.firstWhere(
        (elm) => elm.querySelector('.BgcNfc')!.text == 'Current Version',
      );
      storeVersion = versionElement.querySelector('.htlgb')!.text;

      final sectionElements = document.getElementsByClassName('W4P4ne');
      final releaseNotesElement = sectionElements.firstWhereOrNull(
        (elm) => elm.querySelector('.wSaTQd')!.text == 'What\'s New',
      );
      releaseNotes = releaseNotesElement
          ?.querySelector('.PHBdkd')
          ?.querySelector('.DWPxHb')
          ?.text
          .replaceAll(RegExp('[a-zA-Z:s]'), '')
          .trim();
    } else {
      final scriptElements = document.getElementsByTagName('script');
      final infoScriptElement = scriptElements
          .firstWhereOrNull((elm) => elm.text.contains('key: \'ds:5\''));

      if (infoScriptElement == null) return null;

      final param = infoScriptElement.text
          .substring(20, infoScriptElement.text.length - 2)
          .replaceAll('key:', '"key":')
          .replaceAll('hash:', '"hash":')
          .replaceAll('data:', '"data":')
          .replaceAll('sideChannel:', '"sideChannel":')
          .replaceAll('d\'', 'd’')
          .replaceAll('s\'', 's’')
          .replaceAll('l\'', 'l’')
          .replaceAll('#39;', '')
          .replaceAll('\'', '"');
      final parsed = json.decode(param);
      final data = parsed['data'];
      if (data.isEmpty) return null;
      storeVersion = data[1][2][140][0][0][0];
      releaseNotes = data[1][2][144][1][1]
          .replaceAll('d&', 'd’')
          .replaceAll('s&', 's’')
          .replaceAll('l&', 'l’')
          .replaceAll('<br>', '\n')
          .replaceAll('& ', '&')
          .replaceAll('&amp;', '&');
    }

    return VersionStatus._(
      localVersion: _getCleanVersion(packageInfo.version),
      storeVersion: _getCleanVersion(forceAppVersion ?? storeVersion),
      appStoreLink: uri.toString(),
      releaseNotes: releaseNotes,
      isShowChangelog: isShowChangelog!,
    );
  }

  final String defaultLocale = Platform.localeName;

  /// This checks the version status and returns the information. This is useful
  /// if you want to display a custom alert, or use the information in a different
  /// way.
  Future<VersionStatus?> getVersionStatus() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    if (Platform.isIOS) {
      final id = iOSId ?? packageInfo.packageName;
      final parameters = {'bundleId': id};
      if (iOSAppStoreCountry != null) {
        parameters.addAll({'country': iOSAppStoreCountry!});
      }
      var uri = Uri.https('itunes.apple.com', '/lookup', parameters);
      return await _makeHttpGetRequest(uri);
    } else if (Platform.isAndroid) {
      final id = androidId ?? packageInfo.packageName;
      final uri = Uri.https('play.google.com', '/store/apps/details',
          {'id': id, 'hl': defaultLocale});
      return await _makeHttpGetRequest(uri);
    } else {
      debugPrint(
          'The target platform "${Platform.operatingSystem}" is not yet supported by this package.');
      return null;
    }
  }

  /// This function attempts to clean local version strings so they match the MAJOR.MINOR.PATCH
  /// versioning pattern, so they can be properly compared with the store version.
  String _getCleanVersion(String version) =>
      RegExp(r'\d+\.\d+\.\d+').stringMatch(version) ?? '0.0.0';

  /// Update action fun
  /// show modal
  void _updateActionFunc({
    required String appStoreLink,
    required bool allowDismissal,
    required BuildContext context,
    LaunchMode launchMode = LaunchMode.platformDefault,
  }) {
    launchAppStore(
      appStoreLink,
      launchMode: launchMode,
    );
    if (allowDismissal) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  /// Shows the user a platform-specific alert about the app update. The user
  /// can dismiss the alert or proceed to the app store.
  ///
  /// To change the appearance and behavior of the update dialog, you can
  /// optionally provide [dialogTitle], [dialogText], [updateButtonText],
  /// [dismissButtonText], and [dismissAction] parameters.
  void showUpdateDialog({
    required BuildContext context,
    required VersionStatus versionStatus,
    String dialogTitle = 'Update Available',
    String? dialogText,
    String updateButtonText = 'Update',
    bool allowDismissal = true,
    String dismissButtonText = 'Maybe Later',
    VoidCallback? dismissAction,
    LaunchMode launchMode = LaunchMode.externalApplication,
  }) async {
    final dialogTitleWidget = Text(dialogTitle);
    final dialogTextWidget = Text(dialogText ??
        'You can now update this app from ${versionStatus.localVersion} to ${versionStatus.storeVersion}');

    final updateButtonTextWidget = Text(updateButtonText);

    List<Widget> actions = [
      // Platform.isAndroid ?
      TextButton(
        onPressed: () => _updateActionFunc(
          allowDismissal: allowDismissal,
          context: context,
          appStoreLink: versionStatus.appStoreLink,
          launchMode: launchMode,
        ),
        child: updateButtonTextWidget,
      )
    ];

    if (allowDismissal) {
      final dismissButtonTextWidget = Text(dismissButtonText);
      dismissAction = dismissAction ??
          () => Navigator.of(context, rootNavigator: true).pop();
      actions.add(
          // Platform.isAndroid ?
          TextButton(
        onPressed: dismissAction,
        child: dismissButtonTextWidget,
      ));
    }

    await showAdaptiveDialog(
      context: context,
      barrierDismissible: allowDismissal,
      builder: (BuildContext context) {
        return PopScope(
            canPop: allowDismissal,
            child:
                // Platform.isAndroid ?
                isShowChangelog!
                    ? AlertDialog(
                        backgroundColor: Theme.of(context).colorScheme.surface,
                        title: dialogTitleWidget,
                        content: dialogTextWidget,
                      )
                    : AlertDialog(
                        title: dialogTitleWidget,
                        content: dialogTextWidget,
                        actions: actions,
                      ));
      },
    );
  }

  /// Launches the Apple App Store or Google Play Store page for the app.
  Future<void> launchAppStore(String appStoreLink,
      {LaunchMode launchMode = LaunchMode.platformDefault}) async {
    debugPrint(appStoreLink);
    if (await canLaunchUrl(Uri.parse(appStoreLink))) {
      await launchUrl(
        Uri.parse(appStoreLink),
        mode: launchMode,
      );
    } else {
      throw 'Could not launch appStoreLink';
    }
  }
}

/// Launches the Apple App Store or Google Play Store page for the app.
Future<void> launchAppStore(String appStoreLink,
    {LaunchMode launchMode = LaunchMode.platformDefault}) async {
  debugPrint(appStoreLink);
  if (await canLaunchUrl(Uri.parse(appStoreLink))) {
    await launchUrl(
      Uri.parse(appStoreLink),
      mode: launchMode,
    );
  } else {
    throw 'Could not launch appStoreLink';
  }
}
