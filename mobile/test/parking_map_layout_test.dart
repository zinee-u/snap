import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snap_mobile/app/snap_theme.dart';
import 'package:snap_mobile/core/contracts/parking_models.dart';
import 'package:snap_mobile/features/parking_lot/parking_map_layout.dart';
import 'package:snap_mobile/features/parking_lot/parking_views.dart';

void main() {
  const expectedRows = <List<String>>[
    <String>['6', '5'],
    <String>['4', '3'],
    <String>['2', '1'],
  ];
  const slots = <ParkingSlot>[
    ParkingSlot(id: '3', state: SlotState.occupied),
    ParkingSlot(id: '1', state: SlotState.reserved),
    ParkingSlot(id: '6', state: SlotState.available),
    ParkingSlot(id: '2', state: SlotState.unavailable),
    ParkingSlot(id: '5', state: SlotState.available),
    ParkingSlot(id: '4', state: SlotState.unknown),
  ];

  for (final compact in <bool>[false, true]) {
    testWidgets(
      'map places 6/5, 4/3, 2/1 and routes to the matching bay (compact=$compact)',
      (tester) async {
        tester.view.physicalSize = const Size(430, 932);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        for (final target in slots) {
          await tester.pumpWidget(
            MaterialApp(
              theme: SnapTheme.light(),
              home: Scaffold(
                body: ParkingLotDiagram(
                  slots: slots,
                  targetSlot: target.id.padLeft(2, '0'),
                  robotProgress: 64,
                  compact: compact,
                  carryingVehicle: true,
                ),
              ),
            ),
          );

          final diagram = tester.getRect(find.byType(ParkingLotDiagram));
          double? previousRowY;
          for (final row in expectedRows) {
            final left = tester.getRect(find.byKey(Key('slot-${row[0]}')));
            final right = tester.getRect(find.byKey(Key('slot-${row[1]}')));
            expect(left.center.dx, lessThan(right.center.dx));
            expect(left.center.dy, closeTo(right.center.dy, 0.01));
            if (previousRowY != null) {
              expect(left.center.dy, greaterThan(previousRowY));
            }
            previousRowY = left.center.dy;
          }

          for (final slot in slots) {
            final finder = find.byKey(Key('slot-${slot.id}'));
            final bay = tester.widget<ParkingBay>(finder);
            expect(bay.slot.state, slot.state);
            expect(bay.highlighted, slot.id == target.id);
            final destination = ParkingMapLayout.slotCenter(
              slot.id.padLeft(2, '0'),
              diagram.size,
            );
            expect(destination, isNotNull);
            expect(
              tester.getRect(finder).contains(diagram.topLeft + destination!),
              isTrue,
              reason: 'Route for ${slot.id} must end in its own bay',
            );
          }
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  test('unknown slot IDs do not create a route destination', () {
    for (final id in <String?>[null, '', '-', '0', '7', 'slot-1']) {
      expect(ParkingMapLayout.slotCenter(id, const Size(400, 500)), isNull);
    }
  });
}
