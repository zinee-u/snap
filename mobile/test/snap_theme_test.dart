// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snap_mobile/app/snap_theme.dart';
import 'package:snap_mobile/features/parking_lot/parking_views.dart';

void main() {
  group('SnapTheme', () {
    test('uses the same electric blue accent in light and dark modes', () {
      final themes = <ThemeData>[SnapTheme.light(), SnapTheme.dark()];

      expect(SnapColors.electricBlue, const Color(0xFF087CFA));
      for (final theme in themes) {
        expect(theme.colorScheme.primary, SnapColors.electricBlue);
        expect(theme.colorScheme.secondary, SnapColors.electricBlue);
        expect(
          theme.filledButtonTheme.style?.backgroundColor
              ?.resolve(<MaterialState>{}),
          SnapColors.electricBlue,
        );
        expect(
          theme.navigationBarTheme.iconTheme
              ?.resolve(<MaterialState>{MaterialState.selected})
              ?.color,
          SnapColors.electricBlue,
        );
        expect(
          theme.navigationBarTheme.labelTextStyle
              ?.resolve(<MaterialState>{MaterialState.selected})
              ?.color,
          SnapColors.electricBlue,
        );
      }
    });

    test('keeps mode-specific surfaces and a non-red warning palette', () {
      final light = SnapTheme.light();
      final dark = SnapTheme.dark();

      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.scaffoldBackgroundColor, SnapColors.lightBackground);
      expect(dark.scaffoldBackgroundColor, SnapColors.darkBackground);
      expect(light.colorScheme.surface, Colors.white);
      expect(dark.colorScheme.surface, SnapColors.darkSurface);
      expect(light.inputDecorationTheme.fillColor, Colors.white);
      expect(dark.inputDecorationTheme.fillColor, const Color(0xFF0B0D0F));

      expect(light.colorScheme.error, SnapColors.warning);
      expect(dark.colorScheme.error, SnapColors.warning);
      expect(light.colorScheme.errorContainer, const Color(0xFFFFE8B0));
      expect(dark.colorScheme.errorContainer, const Color(0xFF382A06));
      expect(light.colorScheme.onError, const Color(0xFF17130A));
      expect(dark.colorScheme.onError, const Color(0xFF17130A));
      expect(light.colorScheme.onErrorContainer, const Color(0xFF4A3400));
      expect(dark.colorScheme.onErrorContainer, const Color(0xFFFFD56A));
    });
  });

  testWidgets('theme mode selector reports the selected mode', (tester) async {
    var selectedMode = ThemeMode.system;

    await tester.pumpWidget(
      MaterialApp(
        theme: SnapTheme.light(),
        home: Scaffold(
          body: ThemeModeSelectorHarness(
            value: selectedMode,
            onChanged: (mode) => selectedMode = mode,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('theme-mode-dark')));

    expect(selectedMode, ThemeMode.dark);
  });
}

class ThemeModeSelectorHarness extends StatelessWidget {
  const ThemeModeSelectorHarness({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return ThemeModeSelector(value: value, onChanged: onChanged);
  }
}
