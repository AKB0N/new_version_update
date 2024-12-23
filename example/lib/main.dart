import 'package:flutter/material.dart';
import 'package:new_version_update/new_version_update.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'New Version Update Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final newVersionUpdate = NewVersionUpdate(
    androidId:
        'com.orange.mobinilandme', // Replace with your Android package name (optional if using default)
    iOSId:
        'com.orange.mobinilandme', // Replace with your iOS bundle identifier (optional if using default)
    isShowChangelog: true, // Set to false if you don't want to show change log
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkVersion();
    });
  }

  void _checkVersion() async {
    final status = await newVersionUpdate.getVersionStatus();
    if (status != null) {
      debugPrint('Local Version: ${status.localVersion}');
      debugPrint('Store Version: ${status.storeVersion}');
      debugPrint('Can Update: ${status.canUpdate}');
      debugPrint('App Store Link: ${status.appStoreLink}');
      debugPrint('Release Notes: ${status.releaseNotes}');

      // Show update dialog only if can update
      if (status.canUpdate) {
        if (context.mounted) {
          newVersionUpdate.showUpdateDialog(
            context: context,
            versionStatus: status,
            dialogText:
                "You can update this App\nform ${status.localVersion} to ${status.storeVersion}\n\nWhat's New:\n${status.releaseNotes}",
            allowDismissal: true,
            updateButtonText: 'sdd',
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Version Update Example'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'Checking for updates...',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _checkVersion,
              child: const Text('Check for Update'),
            ),
          ],
        ),
      ),
    );
  }
}
