import 'dart:io';

/// Export launcher assets without changing the existing Xcode build settings.
/// Run from mobile/: dart run tool/generate_app_icons.dart
Future<void> main() async {
  final project = File('ios/Runner.xcodeproj/project.pbxproj');
  final originalProject = await project.readAsString();
  final iconSettings = RegExp(
    r'ASSETCATALOG_COMPILER_APPICON_NAME\s*=\s*([^;]+);',
  ).allMatches(originalProject);
  if (iconSettings.isEmpty ||
      iconSettings.any((setting) => setting.group(1)!.trim() != 'AppIcon')) {
    throw StateError('Expected the existing AppIcon catalog in every build.');
  }

  try {
    final generator = await Process.start(
      Platform.resolvedExecutable,
      <String>['run', 'flutter_launcher_icons'],
      mode: ProcessStartMode.inheritStdio,
    );
    exitCode = await generator.exitCode;
  } finally {
    // flutter_launcher_icons 0.14.4 also rewrites unrelated ASSETCATALOG
    // settings (e.g. a YES boolean becomes AppIcon). This project already uses
    // the default AppIcon catalog, so generating images needs no Xcode edits.
    // Preserve all original settings, including each developer's signing team.
    if (await project.readAsString() != originalProject) {
      await project.writeAsString(originalProject);
    }
  }
}
