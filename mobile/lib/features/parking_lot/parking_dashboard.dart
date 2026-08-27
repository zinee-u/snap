import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/contracts/parking_models.dart';
import '../../core/networking/pi_gateway_client.dart';
import '../../core/networking/pi_gateway_session.dart';

class ParkingDashboard extends StatefulWidget {
  const ParkingDashboard({
    required this.gatewayBaseUri,
    required this.lotId,
    super.key,
  });

  final Uri gatewayBaseUri;
  final String lotId;

  @override
  State<ParkingDashboard> createState() => _ParkingDashboardState();
}

class _ParkingDashboardState extends State<ParkingDashboard>
    with WidgetsBindingObserver {
  final TextEditingController _vehicleController =
      TextEditingController(text: 'SNAP-01');
  late final PiGatewaySession _session;
  int _expectedMinutes = 120;
  String _preference = 'AUTO';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = PiGatewaySession(
      client: PiGatewayClient(baseUri: widget.gatewayBaseUri),
      lotId: widget.lotId,
    )..addListener(_onSessionChanged);
    unawaited(_session.start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_session.resume());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_onSessionChanged);
    _session.dispose();
    _vehicleController.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _session.snapshot;
    final isConnected =
        _session.connectionState == GatewayConnectionState.connected;
    final canSubmit = isConnected && !_session.isSubmitting;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('S.N.A.P'),
            Text('Smart Navigation for Automated Parking',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400)),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '최신 현황 조회',
            onPressed: _session.isSubmitting ? null : () => unawaited(_refresh()),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Gateway 다시 연결',
            onPressed: () => unawaited(_session.reconnectNow()),
            icon: const Icon(Icons.link),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            if (_session.isSubmitting ||
                _session.connectionState == GatewayConnectionState.connecting)
              const LinearProgressIndicator(),
            const SizedBox(height: 8),
            _ConnectionCard(
              state: _session.connectionState,
              endpoint: widget.gatewayBaseUri,
              eventType: _session.lastEventType,
              error: _session.lastError,
            ),
            const SizedBox(height: 16),
            if (snapshot == null)
              _EmptyState(
                isConnecting: _session.connectionState !=
                    GatewayConnectionState.disconnected,
                onRetry: () => unawaited(_session.reconnectNow()),
              )
            else ...<Widget>[
              _Overview(snapshot: snapshot),
              const SizedBox(height: 16),
              Text('주차장 현황', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              _SlotGrid(slots: snapshot.slots),
              const SizedBox(height: 16),
              _RobotAndJob(snapshot: snapshot),
              const SizedBox(height: 16),
              _RequestPanel(
                vehicleController: _vehicleController,
                expectedMinutes: _expectedMinutes,
                preference: _preference,
                canSubmitParking: canSubmit &&
                    snapshot.job.state == JobState.idle,
                canSubmitRetrieval: canSubmit &&
                    snapshot.job.state == JobState.parked,
                isSubmitting: _session.isSubmitting,
                onExpectedMinutesChanged: (value) {
                  if (value != null) {
                    setState(() => _expectedMinutes = value);
                  }
                },
                onPreferenceChanged: (value) {
                  if (value != null) {
                    setState(() => _preference = value);
                  }
                },
                onParking: () => unawaited(_requestParking()),
                onRetrieval: () => unawaited(_requestRetrieval()),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    try {
      await _session.refresh();
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    }
  }

  Future<void> _requestParking() async {
    final vehicleId = _normalizedVehicleId();
    if (vehicleId == null) {
      return;
    }
    try {
      final result = await _session.requestParking(
        vehicleId: vehicleId,
        expectedMinutes: _expectedMinutes,
        preference: _preference,
      );
      _showMessage('발렛 요청 접수: ${result.requestId}');
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    }
  }

  Future<void> _requestRetrieval() async {
    final vehicleId = _normalizedVehicleId();
    if (vehicleId == null) {
      return;
    }
    try {
      final result = await _session.requestRetrieval(vehicleId: vehicleId);
      _showMessage('출차 요청 접수: ${result.requestId}');
    } catch (error) {
      _showMessage(error.toString(), isError: true);
    }
  }

  String? _normalizedVehicleId() {
    final value = _vehicleController.text.trim().toUpperCase();
    if (value.isEmpty || value.length > 32) {
      _showMessage('차량 ID를 1~32자로 입력해 주세요.', isError: true);
      return null;
    }
    return value;
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.state,
    required this.endpoint,
    required this.eventType,
    required this.error,
  });

  final GatewayConnectionState state;
  final Uri endpoint;
  final String? eventType;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      GatewayConnectionState.connected => Colors.green,
      GatewayConnectionState.connecting || GatewayConnectionState.reconnecting =>
        Colors.orange,
      GatewayConnectionState.disconnected => Colors.red,
    };
    final label = switch (state) {
      GatewayConnectionState.connected => 'Gateway 연결됨',
      GatewayConnectionState.connecting => 'Gateway 연결 중',
      GatewayConnectionState.reconnecting => '재연결 및 현황 동기화 중',
      GatewayConnectionState.disconnected => 'Gateway 연결 끊김',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                if (eventType != null)
                  Text(eventType!, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(endpoint.toString(),
                style: Theme.of(context).textTheme.bodySmall),
            if (error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.snapshot});

  final ParkingSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final available = snapshot.slots
        .where((slot) => slot.state == SlotState.available)
        .length;
    final occupied = snapshot.slots
        .where((slot) => slot.state == SlotState.occupied)
        .length;
    final reserved = snapshot.slots
        .where((slot) => slot.state == SlotState.reserved)
        .length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(snapshot.lotId,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Text(_formatTime(snapshot.updatedAt),
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(child: _Metric(label: '빈자리', value: '$available')),
                Expanded(child: _Metric(label: '주차', value: '$occupied')),
                Expanded(child: _Metric(label: '예약', value: '$reserved')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _SlotGrid extends StatelessWidget {
  const _SlotGrid({required this.slots});

  final List<ParkingSlot> slots;

  @override
  Widget build(BuildContext context) {
    if (slots.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Gateway가 주차면 정보를 보내지 않았습니다.'),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 680 ? 3 : 2;
        const spacing = 10.0;
        final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: slots
              .map((slot) => SizedBox(width: width, child: _SlotCard(slot: slot)))
              .toList(growable: false),
        );
      },
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({required this.slot});

  final ParkingSlot slot;

  @override
  Widget build(BuildContext context) {
    final color = switch (slot.state) {
      SlotState.available => Colors.green,
      SlotState.reserved => Colors.orange,
      SlotState.occupied => Colors.blueGrey,
      SlotState.unavailable || SlotState.unknown => Colors.red,
    };
    final label = switch (slot.state) {
      SlotState.available => '이용 가능',
      SlotState.reserved => '예약',
      SlotState.occupied => '주차 중',
      SlotState.unavailable => '이용 불가',
      SlotState.unknown => '상태 미확인',
    };

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(slot.id,
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                Icon(Icons.local_parking, color: color),
              ],
            ),
            const SizedBox(height: 12),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
            Text(slot.vehicleId ?? '—', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _RobotAndJob extends StatelessWidget {
  const _RobotAndJob({required this.snapshot});

  final ParkingSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('로봇 · 작업 상태', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(snapshot.job.message),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                Chip(label: Text(snapshot.job.state.wireName)),
                Chip(label: Text('배터리 ${snapshot.robot.batteryPct}%')),
                Chip(label: Text('위치 ${snapshot.robot.positionPct}%')),
                if (snapshot.job.targetSlot != null)
                  Chip(label: Text('목표 ${snapshot.job.targetSlot}')),
              ],
            ),
            if (snapshot.job.reasonCode != null) ...<Widget>[
              const SizedBox(height: 8),
              Text('${snapshot.job.reasonCode}: ${snapshot.job.reason ?? ''}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _RequestPanel extends StatelessWidget {
  const _RequestPanel({
    required this.vehicleController,
    required this.expectedMinutes,
    required this.preference,
    required this.canSubmitParking,
    required this.canSubmitRetrieval,
    required this.isSubmitting,
    required this.onExpectedMinutesChanged,
    required this.onPreferenceChanged,
    required this.onParking,
    required this.onRetrieval,
  });

  final TextEditingController vehicleController;
  final int expectedMinutes;
  final String preference;
  final bool canSubmitParking;
  final bool canSubmitRetrieval;
  final bool isSubmitting;
  final ValueChanged<int?> onExpectedMinutesChanged;
  final ValueChanged<String?> onPreferenceChanged;
  final VoidCallback onParking;
  final VoidCallback onRetrieval;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('발렛 요청', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            TextField(
              controller: vehicleController,
              textCapitalization: TextCapitalization.characters,
              maxLength: 32,
              decoration: const InputDecoration(
                labelText: '차량 ID',
                hintText: '예: SNAP-01',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: expectedMinutes,
              decoration: const InputDecoration(labelText: '예상 이용 시간'),
              items: const <int>[30, 60, 120, 240]
                  .map((minutes) => DropdownMenuItem<int>(
                        value: minutes,
                        child: Text('$minutes분'),
                      ))
                  .toList(growable: false),
              onChanged: isSubmitting ? null : onExpectedMinutesChanged,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: preference,
              decoration: const InputDecoration(labelText: '주차면 선호'),
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(value: 'AUTO', child: Text('자동 균형')),
                DropdownMenuItem(value: 'NEAR_EXIT', child: Text('출구 우선')),
                DropdownMenuItem(value: 'SHORTEST_PATH', child: Text('최단 경로')),
              ],
              onChanged: isSubmitting ? null : onPreferenceChanged,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: canSubmitParking ? onParking : null,
              icon: const Icon(Icons.local_parking),
              label: Text(isSubmitting ? '요청 전송 중…' : '발렛 주차 시작'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: canSubmitRetrieval ? onRetrieval : null,
              icon: const Icon(Icons.directions_car),
              label: const Text('차량 호출'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isConnecting, required this.onRetry});

  final bool isConnecting;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: <Widget>[
            Icon(isConnecting ? Icons.sync : Icons.cloud_off, size: 42),
            const SizedBox(height: 12),
            Text(isConnecting ? '주차장 현황을 불러오는 중입니다.' : '현황을 불러오지 못했습니다.'),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('다시 연결')),
          ],
        ),
      ),
    );
  }
}
