import 'package:flutter/material.dart';

import '../features/parking_lot/parking_dashboard.dart';
import 'app_config.dart';

class SnapApp extends StatelessWidget {
  const SnapApp({required this.config, super.key});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF155E63),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'S.N.A.P',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F7F6),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
      home: ParkingDashboard(
        gatewayBaseUri: config.gatewayBaseUri,
        lotId: config.lotId,
      ),
    );
  }
}
