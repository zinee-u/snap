// Render the real app widgets with fixed demo data, without a Gateway connection.
// From mobile/: flutter test tool/readme_preview_test.dart --update-goldens
// On other hosts, pass --dart-define=SNAP_PREVIEW_FONT=/path/to/a/Korean-font.ttf.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snap_mobile/app/snap_theme.dart';
import 'package:snap_mobile/core/contracts/parking_models.dart';
import 'package:snap_mobile/core/networking/pi_gateway_session.dart';
import 'package:snap_mobile/features/parking_lot/parking_application.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    const fontPath = String.fromEnvironment(
      'SNAP_PREVIEW_FONT',
      defaultValue: '/System/Library/Fonts/AppleSDGothicNeo.ttc',
    );
    final font = File(fontPath);
    if (!font.existsSync()) {
      throw StateError('Set SNAP_PREVIEW_FONT to an installed Korean font.');
    }
    final fontData = ByteData.sublistView(await font.readAsBytes());
    final loader = FontLoader('SnapPreview')..addFont(Future.value(fontData));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final dark in <bool>[false, true]) {
    testWidgets('render README home in ${dark ? 'dark' : 'light'}',
        (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = _PreviewSession();
      addTearDown(session.dispose);
      final baseTheme = dark ? SnapTheme.dark() : SnapTheme.light();

      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('readme-preview'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: baseTheme.copyWith(
              textTheme: baseTheme.textTheme.apply(fontFamily: 'SnapPreview'),
              primaryTextTheme:
                  baseTheme.primaryTextTheme.apply(fontFamily: 'SnapPreview'),
              filledButtonTheme: FilledButtonThemeData(
                style: baseTheme.filledButtonTheme.style!.copyWith(
                  textStyle: WidgetStatePropertyAll(
                    baseTheme.filledButtonTheme.style!.textStyle!.resolve(
                        <WidgetState>{})!.copyWith(fontFamily: 'SnapPreview'),
                  ),
                ),
              ),
            ),
            home: ParkingApplication(
              gatewayBaseUri: Uri.parse('http://pi.local:8101'),
              lotId: 'demo-01',
              customerId: 'demo-customer',
              session: session,
            ),
          ),
        ),
      );
      // Load bundled images before capturing; periodic pulse animations do not
      // settle, so advance to a fixed frame instead of pumpAndSettle.
      await tester.runAsync(() async {
        final context = tester.element(find.byType(ParkingApplication));
        await Future.wait(<Future<void>>[
          precacheImage(const AssetImage('assets/images/car-top.png'), context),
          precacheImage(
              const AssetImage('assets/images/robot-top.png'), context),
        ]);
      });
      await tester.pump(const Duration(milliseconds: 800));
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(const Key('readme-preview')),
        matchesGoldenFile(
          '../../assets/readme/snap-mobile-home-${dark ? 'dark' : 'light'}.png',
        ),
      );
    });
  }
}

class _PreviewSession extends ChangeNotifier
    implements ParkingSessionController {
  @override
  GatewayConnectionState get connectionState =>
      GatewayConnectionState.connected;

  @override
  bool get isSubmitting => false;

  @override
  String? get lastError => null;

  @override
  String? get lastEventType => 'SNAPSHOT';

  @override
  ParkingSnapshot get snapshot => ParkingSnapshot(
        lotId: 'demo-01',
        updatedAt: DateTime.utc(2026, 9, 10),
        slots: const <ParkingSlot>[
          ParkingSlot(id: '1', state: SlotState.available),
          ParkingSlot(id: '2', state: SlotState.available),
          ParkingSlot(id: '3', state: SlotState.available),
          ParkingSlot(id: '4', state: SlotState.available),
          ParkingSlot(id: '5', state: SlotState.occupied),
          ParkingSlot(id: '6', state: SlotState.available),
        ],
        robot: const RobotSnapshot(
          state: 'READY',
          batteryPct: 86,
          positionPct: 18,
        ),
        job: const JobSnapshot(state: JobState.idle, message: 'ready'),
      );

  @override
  List<CustomerVehicle> get vehicles => const <CustomerVehicle>[
        CustomerVehicle(
          id: 'VEH-DEMO-1',
          vehicleNumber: 'SNAP-01',
          state: VehicleState.readyToPark,
        ),
      ];

  @override
  Future<void> reconnectNow() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> start() async {}

  @override
  Future<CustomerVehicle> registerVehicle({required String vehicleNumber}) =>
      throw UnsupportedError('README preview is read-only');

  @override
  Future<GatewayCommandResult> requestParking({
    required String vehicleId,
    required int expectedMinutes,
  }) =>
      throw UnsupportedError('README preview is read-only');

  @override
  Future<GatewayCommandResult> requestRetrieval({required String vehicleId}) =>
      throw UnsupportedError('README preview is read-only');
}
