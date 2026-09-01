import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snap_mobile/app/snap_theme.dart';
import 'package:snap_mobile/core/contracts/parking_models.dart';
import 'package:snap_mobile/core/networking/pi_gateway_session.dart';
import 'package:snap_mobile/features/parking_lot/parking_views.dart';

void main() {
  testWidgets('parking selection forwards duration and parking actions',
      (tester) async {
    const vehicle = CustomerVehicle(
      id: 'VEH-1',
      vehicleNumber: '12가3456',
      state: VehicleState.readyToPark,
    );
    var selectedMinutes = 0;
    var parkingRequests = 0;

    await _pumpPage(
      tester,
      ParkingSelectionPage(
        connectionState: GatewayConnectionState.connected,
        snapshot: _snapshot(),
        vehicles: const <CustomerVehicle>[vehicle],
        selectedVehicle: vehicle,
        expectedMinutes: 120,
        isSubmitting: false,
        isFull: false,
        onRefresh: _noRefresh,
        onVehicleSelected: (_) {},
        onExpectedMinutesChanged: (minutes) => selectedMinutes = minutes,
        onParking: () => parkingRequests += 1,
        onRegisterVehicle: () {},
      ),
    );

    final parkingButton = tester.widget<FilledButton>(
      find.byKey(const Key('parking-action')),
    );
    expect(parkingButton.onPressed, isNotNull);
    expect(
      Theme.of(tester.element(find.byType(ParkingSelectionPage))).brightness,
      Brightness.light,
    );

    await tester.ensureVisible(find.text('180분'));
    await tester.tap(find.text('180분'));
    await tester.ensureVisible(find.byKey(const Key('parking-action')));
    await tester.tap(find.byKey(const Key('parking-action')));

    expect(selectedMinutes, 180);
    expect(parkingRequests, 1);
  });

  testWidgets('parking action is disabled while full or disconnected',
      (tester) async {
    const vehicle = CustomerVehicle(
      id: 'VEH-1',
      vehicleNumber: '12가3456',
      state: VehicleState.readyToPark,
    );

    Future<void> pump({
      required GatewayConnectionState connectionState,
      required bool isFull,
    }) {
      return _pumpPage(
        tester,
        ParkingSelectionPage(
          connectionState: connectionState,
          snapshot: _snapshot(),
          vehicles: const <CustomerVehicle>[vehicle],
          selectedVehicle: vehicle,
          expectedMinutes: 120,
          isSubmitting: false,
          isFull: isFull,
          onRefresh: _noRefresh,
          onVehicleSelected: (_) {},
          onExpectedMinutesChanged: (_) {},
          onParking: () {},
          onRegisterVehicle: () {},
        ),
      );
    }

    await pump(
      connectionState: GatewayConnectionState.connected,
      isFull: true,
    );
    expect(find.text('현재 만차입니다'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('parking-action')))
          .onPressed,
      isNull,
    );

    await pump(
      connectionState: GatewayConnectionState.disconnected,
      isFull: false,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('parking-action')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('parking completion shows updatedAt and requests retrieval',
      (tester) async {
    final vehicle = CustomerVehicle(
      id: 'VEH-2',
      vehicleNumber: '34나5678',
      state: VehicleState.parked,
      slotId: '2',
      expectedMinutes: 120,
      updatedAt: DateTime(2026, 8, 25, 14, 18),
    );
    var retrievalRequests = 0;

    await _pumpPage(
      tester,
      ParkingCompletePage(
        connectionState: GatewayConnectionState.connected,
        snapshot: _snapshot(),
        vehicle: vehicle,
        isSubmitting: false,
        onRefresh: _noRefresh,
        onRetrieval: () => retrievalRequests += 1,
      ),
      brightness: Brightness.dark,
    );

    expect(find.text('입차 완료 14:18:00'), findsOneWidget);
    expect(find.text('02'), findsWidgets);
    expect(
      Theme.of(tester.element(find.byType(ParkingCompletePage))).brightness,
      Brightness.dark,
    );

    final retrievalAction = find.byKey(const Key('retrieval-action'));
    await tester.ensureVisible(retrievalAction);
    await tester.tap(retrievalAction);

    expect(retrievalRequests, 1);
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  Widget page, {
  Brightness brightness = Brightness.light,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: SnapTheme.light(),
      darkTheme: SnapTheme.dark(),
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(body: page),
    ),
  );
}

Future<void> _noRefresh() async {}

ParkingSnapshot _snapshot() {
  return ParkingSnapshot(
    lotId: 'demo-01',
    updatedAt: DateTime.utc(2026, 8, 25, 12),
    slots: const <ParkingSlot>[
      ParkingSlot(id: '1', state: SlotState.available),
      ParkingSlot(id: '2', state: SlotState.available),
      ParkingSlot(id: '3', state: SlotState.available),
      ParkingSlot(id: '4', state: SlotState.available),
      ParkingSlot(id: '5', state: SlotState.occupied),
      ParkingSlot(id: '6', state: SlotState.reserved),
    ],
    robot: const RobotSnapshot(
      state: 'READY',
      batteryPct: 86,
      positionPct: 18,
    ),
    job: const JobSnapshot(
      state: JobState.idle,
      message: 'ready',
    ),
  );
}
