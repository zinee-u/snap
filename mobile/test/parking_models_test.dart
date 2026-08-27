import 'package:flutter_test/flutter_test.dart';
import 'package:snap_mobile/core/contracts/parking_models.dart';

void main() {
  const snapshotJson = <String, Object?>{
    'lotId': 'demo-01',
    'updatedAt': '2026-08-25T12:00:00Z',
    'slots': <Object?>[
      <String, Object?>{'id': 'A1', 'state': 'AVAILABLE'},
      <String, Object?>{
        'id': 'A2',
        'state': 'OCCUPIED',
        'vehicleId': 'SNAP-88',
      },
    ],
    'robot': <String, Object?>{
      'state': '대기 중',
      'batteryPct': 86,
      'positionPct': 18,
    },
    'job': <String, Object?>{
      'id': 'REQ-1',
      'state': 'MOVING_TO_SLOT',
      'vehicleId': 'SNAP-01',
      'targetSlot': 'A1',
      'reasonCode': 'AUTO_BALANCED',
      'message': '이동 중',
    },
  };

  test('parses a direct REST snapshot', () {
    final snapshot = ParkingSnapshot.fromPayload(snapshotJson);

    expect(snapshot.lotId, 'demo-01');
    expect(snapshot.slots, hasLength(2));
    expect(snapshot.slots[1].vehicleId, 'SNAP-88');
    expect(snapshot.job.state, JobState.movingToSlot);
    expect(snapshot.robot.batteryPct, 86);
  });

  test('parses the snapshot nested in a POST response', () {
    final result = GatewayCommandResult.fromPayload(<String, Object?>{
      'requestId': 'REQ-1234',
      'snapshot': snapshotJson,
    });

    expect(result.requestId, 'REQ-1234');
    expect(result.snapshot?.job.targetSlot, 'A1');
  });

  test('parses a WebSocket event envelope', () {
    final event = GatewayEvent.fromPayload(<String, Object?>{
      'type': 'MOVING_TO_SLOT',
      'message': '실시간 상태',
      'snapshot': snapshotJson,
    });

    expect(event.type, 'MOVING_TO_SLOT');
    expect(event.snapshot.job.vehicleId, 'SNAP-01');
  });

  test('accepts snake_case aliases and preserves unknown safety states', () {
    final snapshot = ParkingSnapshot.fromPayload(<String, Object?>{
      'lot_id': 'demo-01',
      'updated_at': '2026-08-25T12:00:00Z',
      'slots': <Object?>[
        <String, Object?>{'slot_id': 'B1', 'status': 'SENSOR_MISSING'},
      ],
      'robot': <String, Object?>{
        'battery_pct': 90,
        'position_pct': 20,
      },
      'activeJob': <String, Object?>{
        'state': 'EMERGENCY_STOP',
        'target_slot': 'B1',
      },
    });

    expect(snapshot.slots.single.state, SlotState.unknown);
    expect(snapshot.job.state, JobState.emergencyStop);
  });
}
