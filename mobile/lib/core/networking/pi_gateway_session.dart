import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../contracts/parking_models.dart';
import 'pi_gateway_client.dart';

enum GatewayConnectionState { disconnected, connecting, connected, reconnecting }

class PiGatewaySession extends ChangeNotifier {
  PiGatewaySession({
    required this.client,
    this.lotId = 'demo-01',
    this.pingInterval = const Duration(seconds: 15),
    List<Duration>? reconnectDelays,
  }) : reconnectDelays = reconnectDelays == null || reconnectDelays.isEmpty
            ? const <Duration>[
              Duration(seconds: 1),
              Duration(seconds: 2),
              Duration(seconds: 4),
              Duration(seconds: 8),
              Duration(seconds: 15),
            ]
            : reconnectDelays;

  final PiGatewayClient client;
  final String lotId;
  final Duration pingInterval;
  final List<Duration> reconnectDelays;

  GatewayConnectionState _connectionState = GatewayConnectionState.disconnected;
  ParkingSnapshot? _snapshot;
  String? _lastError;
  String? _lastEventType;
  bool _isSubmitting = false;
  bool _disposed = false;
  bool _started = false;
  int _generation = 0;
  int _reconnectAttempt = 0;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _retryTimer;

  GatewayConnectionState get connectionState => _connectionState;
  ParkingSnapshot? get snapshot => _snapshot;
  String? get lastError => _lastError;
  String? get lastEventType => _lastEventType;
  bool get isSubmitting => _isSubmitting;

  Future<void> start() async {
    if (_disposed || _started) {
      return;
    }
    _started = true;
    final generation = ++_generation;
    await _connect(generation);
  }

  Future<void> reconnectNow() async {
    if (_disposed) {
      return;
    }
    _started = true;
    _retryTimer?.cancel();
    final generation = ++_generation;
    await _closeActiveSocket();
    _reconnectAttempt = 0;
    await _connect(generation);
  }

  Future<void> refresh() async {
    if (_disposed) {
      return;
    }
    final generation = _generation;
    try {
      final latest = await client.fetchSnapshot(lotId: lotId);
      if (_disposed || generation != _generation) {
        return;
      }
      _acceptSnapshot(latest);
      _lastError = null;
      _notify();
    } catch (error) {
      if (_disposed || generation != _generation) {
        return;
      }
      _lastError = error.toString();
      _notify();
      rethrow;
    }
  }

  Future<void> resume() async {
    if (_connectionState == GatewayConnectionState.connected) {
      try {
        await refresh();
        return;
      } catch (_) {
        // Refresh failures are handed to the same bounded reconnect loop as WS failures.
      }
    }
    await reconnectNow();
  }

  Future<GatewayCommandResult> requestParking({
    required String vehicleId,
    required int expectedMinutes,
    required String preference,
  }) {
    return _runExclusive(() async {
      final result = await client.requestParking(
        vehicleId: vehicleId,
        expectedMinutes: expectedMinutes,
        preference: preference,
        lotId: lotId,
        fallback: _snapshot,
      );
      _applyCommandSnapshot(result);
      return result;
    });
  }

  Future<GatewayCommandResult> requestRetrieval({required String vehicleId}) {
    return _runExclusive(() async {
      final result = await client.requestRetrieval(
        vehicleId: vehicleId,
        lotId: lotId,
        fallback: _snapshot,
      );
      _applyCommandSnapshot(result);
      return result;
    });
  }

  Future<void> stop() async {
    if (_disposed) {
      return;
    }
    _started = false;
    ++_generation;
    _retryTimer?.cancel();
    await _closeActiveSocket();
    _connectionState = GatewayConnectionState.disconnected;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _started = false;
    ++_generation;
    _retryTimer?.cancel();
    unawaited(_socketSubscription?.cancel());
    unawaited(_socket?.close());
    client.close();
    super.dispose();
  }

  Future<void> _connect(int generation) async {
    if (!_isCurrent(generation)) {
      return;
    }
    _retryTimer = null;
    _connectionState = _reconnectAttempt == 0
        ? GatewayConnectionState.connecting
        : GatewayConnectionState.reconnecting;
    _notify();

    try {
      // Every initial connection and reconnect resynchronizes from REST first.
      final latest = await client.fetchSnapshot(lotId: lotId);
      if (!_isCurrent(generation)) {
        return;
      }
      _acceptSnapshot(latest);
      _lastError = null;
      _notify();

      final socket = await WebSocket.connect(client.eventsUri.toString())
          .timeout(client.requestTimeout);
      if (!_isCurrent(generation)) {
        await socket.close();
        return;
      }

      await _closeActiveSocket();
      _socket = socket;
      socket.pingInterval = pingInterval;
      _reconnectAttempt = 0;
      _connectionState = GatewayConnectionState.connected;
      _lastError = null;
      _socketSubscription = socket.listen(
        (message) => _handleSocketMessage(message, generation, socket),
        onError: (Object error) => _handleSocketEnd(error, generation, socket),
        onDone: () => _handleSocketEnd(null, generation, socket),
        cancelOnError: true,
      );
      _notify();
    } catch (error) {
      if (!_isCurrent(generation)) {
        return;
      }
      _lastError = error.toString();
      _scheduleReconnect(generation);
    }
  }

  void _handleSocketMessage(Object? message, int generation, WebSocket socket) {
    if (!_isCurrent(generation) || !identical(_socket, socket)) {
      return;
    }
    try {
      final text = switch (message) {
        String value => value,
        List<int> value => utf8.decode(value),
        _ => throw const FormatException('지원하지 않는 WebSocket 메시지입니다.'),
      };
      final event = GatewayEvent.fromPayload(
        jsonDecode(text),
        fallback: _snapshot,
        strict: true,
        expectedLotId: lotId,
      );
      _acceptSnapshot(event.snapshot);
      _lastEventType = event.type;
      _lastError = null;
      _notify();
    } catch (error) {
      _lastError = '실시간 이벤트 해석 실패: $error';
      _notify();
    }
  }

  void _handleSocketEnd(Object? error, int generation, WebSocket socket) {
    if (!_isCurrent(generation) || !identical(_socket, socket)) {
      return;
    }
    _socket = null;
    _socketSubscription = null;
    if (error != null) {
      _lastError = '실시간 연결 종료: $error';
    }
    _scheduleReconnect(generation);
  }

  void _scheduleReconnect(int generation) {
    if (!_isCurrent(generation) || _retryTimer?.isActive == true) {
      return;
    }
    _connectionState = GatewayConnectionState.reconnecting;
    final delay = reconnectDelays[
        _reconnectAttempt.clamp(0, reconnectDelays.length - 1).toInt()];
    _reconnectAttempt += 1;
    _retryTimer = Timer(delay, () => unawaited(_connect(generation)));
    _notify();
  }

  Future<T> _runExclusive<T>(Future<T> Function() operation) async {
    if (_isSubmitting) {
      throw const DuplicateSubmissionException();
    }
    _isSubmitting = true;
    _lastError = null;
    _notify();
    try {
      return await operation();
    } catch (error) {
      _lastError = error.toString();
      rethrow;
    } finally {
      _isSubmitting = false;
      _notify();
    }
  }

  void _applyCommandSnapshot(GatewayCommandResult result) {
    if (result.snapshot != null) {
      _acceptSnapshot(result.snapshot!);
    }
    _lastError = null;
    _notify();
  }

  bool _acceptSnapshot(ParkingSnapshot incoming) {
    if (incoming.lotId != lotId) {
      throw GatewayException(
        'Snapshot lotId가 다릅니다: expected=$lotId actual=${incoming.lotId}',
      );
    }
    final current = _snapshot;
    if (current != null && incoming.updatedAt.isBefore(current.updatedAt)) {
      return false;
    }
    _snapshot = incoming;
    return true;
  }

  Future<void> _closeActiveSocket() async {
    final subscription = _socketSubscription;
    final socket = _socket;
    _socketSubscription = null;
    _socket = null;
    await subscription?.cancel();
    await socket?.close();
  }

  bool _isCurrent(int generation) =>
      !_disposed && _started && generation == _generation;

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }
}
