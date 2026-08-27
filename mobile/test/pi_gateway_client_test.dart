import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snap_mobile/core/networking/pi_gateway_client.dart';

void main() {
  late HttpServer server;
  late PiGatewayClient client;
  late StreamSubscription<HttpRequest> requests;
  Map<String, Object?>? receivedParkingBody;
  var responseLotId = 'demo-01';
  var malformedSnapshot = false;
  var emptyRequestId = false;

  setUp(() async {
    receivedParkingBody = null;
    responseLotId = 'demo-01';
    malformedSnapshot = false;
    emptyRequestId = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = PiGatewayClient(
      baseUri: Uri.parse('http://${server.address.host}:${server.port}'),
    );
    requests = server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET' &&
          request.uri.path == '/v1/parking-lots/demo-01/snapshot') {
        final snapshot = _snapshot('IDLE', lotId: responseLotId);
        if (malformedSnapshot) {
          snapshot.remove('robot');
        }
        request.response.write(jsonEncode(snapshot));
      } else if (request.method == 'POST' &&
          request.uri.path == '/v1/parking-requests') {
        receivedParkingBody = Map<String, Object?>.from(
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<Object?, Object?>,
        );
        request.response.write(jsonEncode(<String, Object?>{
          'requestId': emptyRequestId ? '' : 'REQ-TEST',
          'snapshot': _snapshot('REQUESTED', lotId: responseLotId),
        }));
      } else if (request.uri.path == '/fail') {
        request.response.statusCode = HttpStatus.conflict;
        request.response.write(jsonEncode(<String, Object?>{'detail': 'busy'}));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('{}');
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    client.close();
    await requests.cancel();
    await server.close(force: true);
  });

  test('fetches the configured parking lot snapshot', () async {
    final snapshot = await client.fetchSnapshot();

    expect(snapshot.lotId, 'demo-01');
    expect(snapshot.slots.single.id, 'A1');
  });

  test('sends the contract body and parses the POST response snapshot', () async {
    final result = await client.requestParking(
      vehicleId: 'SNAP-01',
      expectedMinutes: 120,
      preference: 'AUTO',
    );

    expect(receivedParkingBody, <String, Object?>{
      'vehicleId': 'SNAP-01',
      'expectedMinutes': 120,
      'preference': 'AUTO',
    });
    expect(result.requestId, 'REQ-TEST');
    expect(result.snapshot?.job.state.wireName, 'REQUESTED');
  });

  test('rejects a malformed REST snapshot', () async {
    malformedSnapshot = true;

    await expectLater(
      client.fetchSnapshot(),
      throwsA(
        isA<GatewayException>().having(
          (error) => error.message,
          'message',
          contains('robot'),
        ),
      ),
    );
  });

  test('rejects a snapshot for a different parking lot', () async {
    responseLotId = 'other-lot';

    await expectLater(
      client.fetchSnapshot(),
      throwsA(
        isA<GatewayException>().having(
          (error) => error.message,
          'message',
          contains('lotId'),
        ),
      ),
    );
  });

  test('rejects a command response without a requestId', () async {
    emptyRequestId = true;

    await expectLater(
      client.requestParking(
        vehicleId: 'SNAP-01',
        expectedMinutes: 120,
        preference: 'AUTO',
      ),
      throwsA(
        isA<GatewayException>().having(
          (error) => error.message,
          'message',
          contains('requestId'),
        ),
      ),
    );
  });
}

Map<String, Object?> _snapshot(
  String jobState, {
  String lotId = 'demo-01',
}) =>
    <String, Object?>{
      'lotId': lotId,
      'updatedAt': '2026-08-25T12:00:00Z',
      'slots': <Object?>[
        <String, Object?>{'id': 'A1', 'state': 'AVAILABLE'},
      ],
      'robot': <String, Object?>{
        'state': '대기 중',
        'batteryPct': 86,
        'positionPct': 18,
      },
      'job': <String, Object?>{'state': jobState, 'message': jobState},
    };
