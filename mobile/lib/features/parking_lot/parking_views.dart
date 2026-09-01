import 'package:flutter/material.dart';

import '../../app/snap_theme.dart';
import '../../core/contracts/parking_models.dart';
import '../../core/networking/pi_gateway_session.dart';

enum ParkingTab { home, vehicles, activity, settings }

class ParkingSelectionPage extends StatelessWidget {
  const ParkingSelectionPage({
    required this.connectionState,
    required this.snapshot,
    required this.vehicles,
    required this.selectedVehicle,
    required this.expectedMinutes,
    required this.isSubmitting,
    required this.isFull,
    required this.onRefresh,
    required this.onVehicleSelected,
    required this.onExpectedMinutesChanged,
    required this.onParking,
    required this.onRegisterVehicle,
    super.key,
  });

  final GatewayConnectionState connectionState;
  final ParkingSnapshot snapshot;
  final List<CustomerVehicle> vehicles;
  final CustomerVehicle? selectedVehicle;
  final int expectedMinutes;
  final bool isSubmitting;
  final bool isFull;
  final Future<void> Function() onRefresh;
  final ValueChanged<String> onVehicleSelected;
  final ValueChanged<int> onExpectedMinutesChanged;
  final VoidCallback onParking;
  final VoidCallback onRegisterVehicle;

  @override
  Widget build(BuildContext context) {
    final available = snapshot.slots
        .where((slot) => slot.state == SlotState.available)
        .length;
    final canRequest = connectionState == GatewayConnectionState.connected &&
        !isSubmitting &&
        !isFull &&
        selectedVehicle?.state.canRequestParking == true;

    return _PageScroll(
      onRefresh: onRefresh,
      children: <Widget>[
        SnapPageHeader(
          title: '주차하기',
          subtitle: 'S.N.A.P  ·  ${snapshot.lotId}',
          connectionState: connectionState,
        ),
        const SizedBox(height: 24),
        if (vehicles.isEmpty)
          _EmptyVehiclePanel(onRegisterVehicle: onRegisterVehicle)
        else ...<Widget>[
          _VehiclePicker(
            vehicles: vehicles,
            selectedVehicle: selectedVehicle,
            onChanged: onVehicleSelected,
          ),
          const SizedBox(height: 18),
          SnapSurface(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: '$available자리',
                        style: const TextStyle(
                          color: SnapColors.electricBlue,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const TextSpan(text: ' 이용 가능'),
                    ],
                  ),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  '주차면 현황',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 18),
                ParkingLotDiagram(
                  slots: snapshot.slots,
                  targetSlot: _isActiveJobState(snapshot.job.state)
                      ? snapshot.job.targetSlot
                      : null,
                  robotProgress: snapshot.robot.positionPct,
                  compact: true,
                ),
                const SizedBox(height: 22),
                Text(
                  '예상 주차 시간',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                DurationSelector(
                  value: expectedMinutes,
                  enabled: !isSubmitting,
                  onChanged: onExpectedMinutesChanged,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('parking-action'),
                  onPressed: canRequest ? onParking : null,
                  child: Text(
                    isSubmitting
                        ? '요청 처리 중…'
                        : isFull
                            ? '현재 만차입니다'
                            : selectedVehicle?.state.canRequestParking == false
                                ? '차량 상태를 확인해 주세요'
                                : '주차 요청',
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    '예상 시간에 맞춰 Gateway가 최적의 주차면을 자동 배정합니다.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class ParkingProgressPage extends StatelessWidget {
  const ParkingProgressPage({
    required this.connectionState,
    required this.snapshot,
    required this.vehicle,
    required this.onRefresh,
    super.key,
  });

  final GatewayConnectionState connectionState;
  final ParkingSnapshot snapshot;
  final CustomerVehicle? vehicle;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final isRetrieval = _isRetrievalProgress(snapshot, vehicle);
    final stage = _jobStage(snapshot.job.state, snapshot.robot.state);
    final position = snapshot.robot.positionPct.clamp(0, 100).toInt();
    final jobMessage = snapshot.job.message.trim();

    return _PageScroll(
      onRefresh: onRefresh,
      children: <Widget>[
        SnapPageHeader(
          title: vehicle == null
              ? '로봇 작업 중'
              : isRetrieval
                  ? '출차 진행 중'
                  : '주차 진행 중',
          subtitle: vehicle?.vehicleNumber ?? 'S.N.A.P AUTOMATED PARKING',
          connectionState: connectionState,
        ),
        const SizedBox(height: 22),
        ParkingLotDiagram(
          slots: snapshot.slots,
          targetSlot: snapshot.job.targetSlot,
          robotProgress: position,
          compact: false,
          carryingVehicle: true,
        ),
        const SizedBox(height: 18),
        SnapSurface(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
          child: Column(
            children: <Widget>[
              Text(
                vehicle == null
                    ? '현재 로봇이 다른 차량의 작업을 진행하고 있어요'
                    : jobMessage.isNotEmpty
                        ? jobMessage
                        : _jobHeadline(snapshot.job.state, isRetrieval),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                '경로 위치 $position%',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: SnapColors.electricBlue,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if (snapshot.job.targetSlot != null)
                Text(
                  '배정 주차면 ${slotLabel(snapshot.job.targetSlot!)}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              const SizedBox(height: 24),
              JobStepper(activeStage: stage, isRetrieval: isRetrieval),
              const SizedBox(height: 22),
              const Divider(),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const Icon(
                    Icons.circle,
                    size: 10,
                    color: SnapColors.electricBlue,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    connectionState == GatewayConnectionState.connected
                        ? '실시간 연결됨'
                        : '연결 복구 중',
                    style: const TextStyle(
                      color: SnapColors.electricBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '앱을 닫아도 로봇 작업은 Gateway에서 계속됩니다.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ParkingCompletePage extends StatelessWidget {
  const ParkingCompletePage({
    required this.connectionState,
    required this.snapshot,
    required this.vehicle,
    required this.isSubmitting,
    required this.onRefresh,
    required this.onRetrieval,
    super.key,
  });

  final GatewayConnectionState connectionState;
  final ParkingSnapshot snapshot;
  final CustomerVehicle vehicle;
  final bool isSubmitting;
  final Future<void> Function() onRefresh;
  final VoidCallback onRetrieval;

  @override
  Widget build(BuildContext context) {
    final slot = vehicle.slotId ?? '-';

    return _PageScroll(
      onRefresh: onRefresh,
      children: <Widget>[
        SnapPageHeader(
          title: '주차 완료',
          subtitle: vehicle.vehicleNumber,
          connectionState: connectionState,
        ),
        const SizedBox(height: 20),
        Center(
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: SnapColors.success),
              color: SnapColors.success.withOpacity(0.08),
            ),
            child: const Icon(
              Icons.check_rounded,
              color: SnapColors.success,
              size: 42,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            '안전하게 주차했어요',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const SizedBox(height: 20),
        SnapSurface(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: <Widget>[
              Container(
                height: 260,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    Positioned.fill(
                      child: CustomPaint(painter: ParkingBayPainter()),
                    ),
                    Icon(
                      Icons.directions_car_filled_rounded,
                      size: 122,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFFE7EAEE)
                          : const Color(0xFFBCC2C9),
                    ),
                    Positioned(
                      bottom: 14,
                      child: Text(
                        slotLabel(slot),
                        style: const TextStyle(
                          color: SnapColors.electricBlue,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _SummaryMetric(
                      label: '차량 정보',
                      value: vehicle.vehicleNumber,
                    ),
                  ),
                  Expanded(
                    child: _SummaryMetric(
                      label: '주차면',
                      value: slotLabel(slot),
                      highlighted: true,
                    ),
                  ),
                  Expanded(
                    child: _SummaryMetric(
                      label: '주차 시간',
                      value: durationLabel(vehicle.expectedMinutes),
                    ),
                  ),
                ],
              ),
              if (vehicle.updatedAt != null) ...<Widget>[
                const SizedBox(height: 18),
                Text(
                  '입차 완료 ${formatClock(vehicle.updatedAt!)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
              const SizedBox(height: 22),
              FilledButton(
                key: const Key('retrieval-action'),
                onPressed: connectionState == GatewayConnectionState.connected &&
                        !isSubmitting &&
                        vehicle.state.canRequestRetrieval
                    ? onRetrieval
                    : null,
                child: Text(isSubmitting ? '요청 처리 중…' : '출차 요청'),
              ),
              const SizedBox(height: 10),
              Text(
                '출차 요청 후 로봇이 차량을 입구로 이동합니다.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class VehicleManagementPage extends StatelessWidget {
  const VehicleManagementPage({
    required this.connectionState,
    required this.vehicles,
    required this.selectedVehicleId,
    required this.registrationController,
    required this.isSubmitting,
    required this.onRefresh,
    required this.onVehicleSelected,
    required this.onRegister,
    super.key,
  });

  final GatewayConnectionState connectionState;
  final List<CustomerVehicle> vehicles;
  final String? selectedVehicleId;
  final TextEditingController registrationController;
  final bool isSubmitting;
  final Future<void> Function() onRefresh;
  final ValueChanged<String> onVehicleSelected;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    final canRegister =
        connectionState == GatewayConnectionState.connected && !isSubmitting;

    return _PageScroll(
      onRefresh: onRefresh,
      children: <Widget>[
        SnapPageHeader(
          title: '내 차량',
          subtitle: '주차와 출차에 사용할 차량을 관리합니다.',
          connectionState: connectionState,
        ),
        const SizedBox(height: 18),
        SnapSurface(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                height: 150,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: Theme.of(context).brightness == Brightness.dark
                        ? const <Color>[Color(0xFF181B1F), Color(0xFF090A0C)]
                        : const <Color>[Color(0xFFFFFFFF), Color(0xFFE9EDF2)],
                  ),
                ),
                child: const Icon(
                  Icons.electric_car_rounded,
                  size: 112,
                  color: SnapColors.electricBlue,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                vehicles.isEmpty ? '차량을 등록하세요' : '새 차량 등록',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 14),
              TextField(
                key: const Key('registration-field'),
                controller: registrationController,
                maxLength: 32,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: '차량번호',
                  hintText: '예: 12가 3456',
                  counterText: '',
                  prefixIcon: Icon(Icons.pin_outlined),
                ),
                onSubmitted: canRegister ? (_) => onRegister() : null,
              ),
              const SizedBox(height: 10),
              FilledButton(
                key: const Key('registration-action'),
                onPressed: canRegister ? onRegister : null,
                child: Text(isSubmitting ? '등록 중…' : '차량 등록'),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.verified_user_outlined,
                    size: 18,
                    color: SnapColors.electricBlue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '등록한 차량으로 주차와 출차를 요청할 수 있어요.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (vehicles.isNotEmpty) ...<Widget>[
          const SizedBox(height: 24),
          Text(
            '등록 차량',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          ...vehicles.map(
            (vehicle) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: VehicleTile(
                key: Key('vehicle-${vehicle.id}'),
                vehicle: vehicle,
                selected: vehicle.id == selectedVehicleId,
                onTap: () => onVehicleSelected(vehicle.id),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class ActivityPage extends StatelessWidget {
  const ActivityPage({
    required this.connectionState,
    required this.vehicles,
    required this.snapshot,
    required this.onRefresh,
    super.key,
  });

  final GatewayConnectionState connectionState;
  final List<CustomerVehicle> vehicles;
  final ParkingSnapshot? snapshot;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return _PageScroll(
      onRefresh: onRefresh,
      children: <Widget>[
        SnapPageHeader(
          title: '이용 기록',
          subtitle: 'Gateway가 제공하는 현재 차량 상태',
          connectionState: connectionState,
        ),
        const SizedBox(height: 20),
        if (vehicles.isEmpty)
          const SnapSurface(
            padding: EdgeInsets.all(24),
            child: _CenteredMessage(
              icon: Icons.history_rounded,
              title: '표시할 차량 상태가 없습니다.',
              message: '차량을 등록하면 현재 주차 상태를 여기에서 확인할 수 있어요.',
            ),
          )
        else
          ...vehicles.map(
            (vehicle) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ActivityTile(vehicle: vehicle),
            ),
          ),
        const SizedBox(height: 8),
        SnapSurface(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(
                Icons.info_outline_rounded,
                color: SnapColors.electricBlue,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '현재 Gateway 계약은 장기 이용 이력을 제공하지 않습니다. '
                  '이 화면은 실시간 차량 상태와 마지막 상태 변경 시각을 표시합니다.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                ),
              ),
            ],
          ),
        ),
        if (snapshot != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            '마지막 동기화 ${formatClock(snapshot!.updatedAt)}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.connectionState,
    required this.endpoint,
    required this.snapshot,
    required this.lastError,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onReconnect,
    required this.onRefresh,
    super.key,
  });

  final GatewayConnectionState connectionState;
  final Uri endpoint;
  final ParkingSnapshot? snapshot;
  final String? lastError;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VoidCallback onReconnect;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final connected = connectionState == GatewayConnectionState.connected;
    final robotHealthy = connected &&
        snapshot != null &&
        _isHealthyRobotState(snapshot!.robot.state);

    return _PageScroll(
      onRefresh: onRefresh,
      children: <Widget>[
        SnapPageHeader(
          title: '설정',
          subtitle: 'S.N.A.P AUTOMATED PARKING',
          connectionState: connectionState,
        ),
        const SizedBox(height: 18),
        SnapSurface(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (connected
                              ? SnapColors.success
                              : SnapColors.warning)
                          .withOpacity(0.12),
                    ),
                    child: Icon(
                      connected ? Icons.link_rounded : Icons.sync_rounded,
                      color:
                          connected ? SnapColors.success : SnapColors.warning,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          connectionLabel(connectionState),
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          endpoint.toString(),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              ConnectionStatusRow(
                label: 'Gateway',
                value: connected ? '정상' : '연결 확인 중',
                healthy: connected,
              ),
              ConnectionStatusRow(
                label: '실시간 이벤트',
                value: connected ? '연결됨' : '재연결 대기',
                healthy: connected,
              ),
              ConnectionStatusRow(
                label: '주차 로봇',
                value: snapshot == null
                    ? '상태 미확인'
                    : robotLabel(snapshot!.robot.state),
                healthy: robotHealthy,
              ),
              if (lastError != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  lastError!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SnapColors.warning,
                      ),
                ),
              ],
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onReconnect,
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Gateway 다시 연결'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SnapSurface(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '화면 모드',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Light와 Dark는 같은 정보 구조와 S.N.A.P 블루를 사용합니다.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 14),
              ThemeModeSelector(
                value: themeMode,
                onChanged: onThemeModeChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class LoadingPage extends StatelessWidget {
  const LoadingPage({
    required this.connectionState,
    required this.endpoint,
    required this.error,
    required this.onReconnect,
    required this.onRefresh,
    super.key,
  });

  final GatewayConnectionState connectionState;
  final Uri endpoint;
  final String? error;
  final VoidCallback onReconnect;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final connecting = connectionState != GatewayConnectionState.disconnected;
    return _PageScroll(
      onRefresh: onRefresh,
      children: <Widget>[
        SnapPageHeader(
          title: 'S.N.A.P',
          subtitle: 'AUTOMATED PARKING',
          connectionState: connectionState,
        ),
        const SizedBox(height: 28),
        SnapSurface(
          padding: const EdgeInsets.fromLTRB(24, 34, 24, 26),
          child: Column(
            children: <Widget>[
              const Icon(
                Icons.precision_manufacturing_outlined,
                size: 100,
                color: SnapColors.electricBlue,
              ),
              const SizedBox(height: 24),
              if (connecting)
                const SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              else
                const Icon(
                  Icons.cloud_off_outlined,
                  size: 34,
                  color: SnapColors.warning,
                ),
              const SizedBox(height: 16),
              Text(
                connecting ? '주차장 연결 중' : '주차장에 연결할 수 없습니다',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                endpoint.toString(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: SnapColors.warning,
                      ),
                ),
              ],
              const SizedBox(height: 22),
              OutlinedButton(
                onPressed: onReconnect,
                child: const Text('다시 연결'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SnapPageHeader extends StatelessWidget {
  const SnapPageHeader({
    required this.title,
    required this.subtitle,
    required this.connectionState,
    super.key,
  });

  final String title;
  final String subtitle;
  final GatewayConnectionState connectionState;

  @override
  Widget build(BuildContext context) {
    final connected = connectionState == GatewayConnectionState.connected;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      letterSpacing: 0.4,
                    ),
              ),
            ],
          ),
        ),
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              const Center(
                child: Icon(
                  Icons.directions_car_outlined,
                  color: SnapColors.electricBlue,
                ),
              ),
              Positioned(
                top: 1,
                right: 1,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        connected ? SnapColors.success : SnapColors.warning,
                    border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SnapSurface extends StatelessWidget {
  const SnapSurface({
    required this.child,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.62),
        ),
      ),
      child: child,
    );
  }
}

class DurationSelector extends StatelessWidget {
  const DurationSelector({
    required this.value,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const values = <int>[60, 120, 180, 240];
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: values.map((minutes) {
          final selected = value == minutes;
          return Expanded(
            child: InkWell(
              onTap: enabled ? () => onChanged(minutes) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: selected
                      ? SnapColors.electricBlue.withOpacity(0.12)
                      : Colors.transparent,
                  border: selected
                      ? Border.all(color: SnapColors.electricBlue, width: 1.5)
                      : null,
                ),
                child: Text(
                  '$minutes분',
                  style: TextStyle(
                    color: selected
                        ? SnapColors.electricBlue
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight:
                        selected ? FontWeight.w800 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

class ParkingLotDiagram extends StatelessWidget {
  const ParkingLotDiagram({
    required this.slots,
    required this.robotProgress,
    this.targetSlot,
    this.compact = false,
    this.carryingVehicle = false,
    super.key,
  });

  final List<ParkingSlot> slots;
  final String? targetSlot;
  final int robotProgress;
  final bool compact;
  final bool carryingVehicle;

  @override
  Widget build(BuildContext context) {
    final normalized = List<ParkingSlot>.generate(6, (index) {
      final id = '${index + 1}';
      for (final slot in slots) {
        if (slot.id == id || slot.id == id.padLeft(2, '0')) {
          return slot;
        }
      }
      return ParkingSlot(id: id, state: SlotState.unknown);
    });
    final left = <ParkingSlot>[normalized[0], normalized[2], normalized[4]];
    final right = <ParkingSlot>[normalized[1], normalized[3], normalized[5]];
    final progress = robotProgress.clamp(0, 100) / 100;

    return SizedBox(
      height: compact ? 410 : 500,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Row(
              children: <Widget>[
                Expanded(child: _BayColumn(slots: left, targetSlot: targetSlot)),
                SizedBox(width: compact ? 50 : 64),
                Expanded(child: _BayColumn(slots: right, targetSlot: targetSlot)),
              ],
            ),
          ),
          Positioned.fill(
            child: Align(
              alignment: Alignment.center,
              child: Container(
                width: 2,
                margin: const EdgeInsets.symmetric(vertical: 12),
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withOpacity(0.6),
              ),
            ),
          ),
          AnimatedAlign(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            alignment: Alignment(0, -0.72 + progress * 1.44),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (carryingVehicle)
                  Icon(
                    Icons.directions_car_filled_rounded,
                    color: Theme.of(context).colorScheme.onSurface,
                    size: compact ? 28 : 34,
                  ),
                Container(
                  width: compact ? 38 : 46,
                  height: compact ? 54 : 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFF20252B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF59616A)),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: SnapColors.electricBlue.withOpacity(0.26),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 4,
                      height: 22,
                      child: DecoratedBox(
                        decoration:
                            BoxDecoration(color: SnapColors.electricBlue),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BayColumn extends StatelessWidget {
  const _BayColumn({required this.slots, required this.targetSlot});

  final List<ParkingSlot> slots;
  final String? targetSlot;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: slots
          .map(
            (slot) => Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ParkingBay(
                  key: Key('slot-${slot.id}'),
                  slot: slot,
                  highlighted: slot.state == SlotState.reserved ||
                      (targetSlot != null &&
                          slot.id.padLeft(2, '0') ==
                              targetSlot!.padLeft(2, '0')),
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class ParkingBay extends StatelessWidget {
  const ParkingBay({
    required this.slot,
    required this.highlighted,
    super.key,
  });

  final ParkingSlot slot;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final stateColor = switch (slot.state) {
      SlotState.available => SnapColors.success,
      SlotState.reserved => SnapColors.electricBlue,
      SlotState.occupied => Theme.of(context).colorScheme.onSurfaceVariant,
      SlotState.unavailable || SlotState.unknown => SnapColors.warning,
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      width: double.infinity,
      decoration: BoxDecoration(
        color: highlighted
            ? SnapColors.electricBlue.withOpacity(0.09)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlighted
              ? SnapColors.electricBlue
              : Theme.of(context).colorScheme.outlineVariant,
          width: highlighted ? 1.8 : 1,
        ),
      ),
      child: Stack(
        children: <Widget>[
          Center(
            child: Text(
              slotLabel(slot.id),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: highlighted
                        ? SnapColors.electricBlue
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w400,
                  ),
            ),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(shape: BoxShape.circle, color: stateColor),
            ),
          ),
          if (slot.state == SlotState.unavailable ||
              slot.state == SlotState.unknown)
            Positioned(
              right: 10,
              bottom: 10,
              child: Icon(Icons.lock_outline, size: 16, color: stateColor),
            ),
        ],
      ),
    );
  }
}

class JobStepper extends StatelessWidget {
  const JobStepper({
    required this.activeStage,
    this.isRetrieval = false,
    super.key,
  });

  final int activeStage;
  final bool isRetrieval;

  @override
  Widget build(BuildContext context) {
    final labels = isRetrieval
        ? const <String>['요청 접수', '차량 이동', '출차 중', '완료']
        : const <String>['요청 접수', '차량 이동', '주차 중', '완료'];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List<Widget>.generate(labels.length, (index) {
        final done = index < activeStage;
        final active = index == activeStage;
        return Expanded(
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  if (index > 0)
                    Expanded(
                      child: Container(
                        height: 1,
                        color: index <= activeStage
                            ? SnapColors.electricBlue
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active
                          ? SnapColors.electricBlue.withOpacity(0.16)
                          : Colors.transparent,
                      border: Border.all(
                        color: done || active
                            ? SnapColors.electricBlue
                            : Theme.of(context).colorScheme.outlineVariant,
                        width: active ? 2 : 1,
                      ),
                    ),
                    child: done
                        ? const Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: SnapColors.electricBlue,
                          )
                        : active
                            ? const Center(
                                child: CircleAvatar(
                                  radius: 5,
                                  backgroundColor: SnapColors.electricBlue,
                                ),
                              )
                            : null,
                  ),
                  if (index < labels.length - 1)
                    Expanded(
                      child: Container(
                        height: 1,
                        color: index < activeStage
                            ? SnapColors.electricBlue
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                labels[index],
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: done || active
                          ? SnapColors.electricBlue
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                    ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class VehicleTile extends StatelessWidget {
  const VehicleTile({
    required this.vehicle,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final CustomerVehicle vehicle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SnapSurface(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: SnapColors.electricBlue.withOpacity(0.1),
                ),
                child: const Icon(
                  Icons.directions_car_filled_outlined,
                  color: SnapColors.electricBlue,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      vehicle.vehicleNumber,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      vehicleStateLabel(vehicle.state),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (vehicle.slotId != null)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Text(
                    '주차면 ${slotLabel(vehicle.slotId!)}',
                    style: const TextStyle(
                      color: SnapColors.electricBlue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected
                    ? SnapColors.electricBlue
                    : Theme.of(context).colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ActivityTile extends StatelessWidget {
  const ActivityTile({required this.vehicle, super.key});

  final CustomerVehicle vehicle;

  @override
  Widget build(BuildContext context) {
    return SnapSurface(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.route_outlined,
            color: SnapColors.electricBlue,
            size: 30,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  vehicle.vehicleNumber,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(vehicleStateLabel(vehicle.state)),
                if (vehicle.updatedAt != null) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    formatClock(vehicle.updatedAt!),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (vehicle.slotId != null)
            Text(
              slotLabel(vehicle.slotId!),
              style: const TextStyle(
                color: SnapColors.electricBlue,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

class ConnectionStatusRow extends StatelessWidget {
  const ConnectionStatusRow({
    required this.label,
    required this.value,
    required this.healthy,
    super.key,
  });

  final String label;
  final String value;
  final bool healthy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: healthy ? SnapColors.success : SnapColors.warning,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class ThemeModeSelector extends StatelessWidget {
  const ThemeModeSelector({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = <(ThemeMode, IconData, String)>[
      (ThemeMode.system, Icons.settings_brightness_outlined, '시스템'),
      (ThemeMode.light, Icons.light_mode_outlined, 'Light'),
      (ThemeMode.dark, Icons.dark_mode_outlined, 'Dark'),
    ];
    return Row(
      children: options.map((option) {
        final selected = value == option.$1;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: option == options.last ? 0 : 8),
            child: InkWell(
              key: Key('theme-mode-${option.$1.name}'),
              onTap: () => onChanged(option.$1),
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: selected
                      ? SnapColors.electricBlue.withOpacity(0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected
                        ? SnapColors.electricBlue
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Column(
                  children: <Widget>[
                    Icon(
                      option.$2,
                      color: selected
                          ? SnapColors.electricBlue
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      option.$3,
                      style: TextStyle(
                        color: selected
                            ? SnapColors.electricBlue
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}

class ParkingBayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.grey.withOpacity(0.35);
    final path = Path()
      ..moveTo(size.width * 0.18, size.height)
      ..lineTo(size.width * 0.18, 0)
      ..moveTo(size.width * 0.82, 0)
      ..lineTo(size.width * 0.82, size.height)
      ..moveTo(0, size.height - 1)
      ..lineTo(size.width, size.height - 1);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PageScroll extends StatelessWidget {
  const _PageScroll({required this.children, required this.onRefresh});

  final List<Widget> children;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
        children: children,
      ),
    );
  }
}

class _VehiclePicker extends StatelessWidget {
  const _VehiclePicker({
    required this.vehicles,
    required this.selectedVehicle,
    required this.onChanged,
  });

  final List<CustomerVehicle> vehicles;
  final CustomerVehicle? selectedVehicle;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: selectedVehicle?.id,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.directions_car_outlined),
        labelText: '주차할 차량',
      ),
      items: vehicles
          .map(
            (vehicle) => DropdownMenuItem<String>(
              value: vehicle.id,
              child: Text(vehicle.vehicleNumber),
            ),
          )
          .toList(growable: false),
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
    );
  }
}

class _EmptyVehiclePanel extends StatelessWidget {
  const _EmptyVehiclePanel({required this.onRegisterVehicle});

  final VoidCallback onRegisterVehicle;

  @override
  Widget build(BuildContext context) {
    return SnapSurface(
      padding: const EdgeInsets.all(26),
      child: Column(
        children: <Widget>[
          const Icon(
            Icons.electric_car_outlined,
            size: 72,
            color: SnapColors.electricBlue,
          ),
          const SizedBox(height: 16),
          Text(
            '먼저 차량을 등록해 주세요',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '등록한 차량으로 주차와 출차를 요청할 수 있습니다.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: onRegisterVehicle,
            child: const Text('차량 등록하기'),
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: highlighted ? SnapColors.electricBlue : null,
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Icon(icon, size: 48, color: SnapColors.electricBlue),
        const SizedBox(height: 12),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

int _jobStage(JobState state, String rawRobotState) {
  final robotState = rawRobotState.trim().toUpperCase();
  return switch (state) {
    JobState.requested || JobState.vehicleDetected => 0,
    JobState.running => switch (robotState) {
        'ACQUIRING_VEHICLE' ||
        'CARRYING_TO_SLOT' ||
        'MOVING_TO_SLOT' ||
        'LIFTING' ||
        'CARRYING_TO_EXIT' ||
        'APPROACHING' ||
        'GRIPPING' ||
        'REVERSING' => 2,
        _ => 1,
      },
    JobState.movingToVehicle => 1,
    JobState.lifting || JobState.movingToSlot || JobState.retrieving => 2,
    JobState.parked || JobState.returning => 3,
    _ => 0,
  };
}

String _jobHeadline(JobState state, bool isRetrieval) {
  return switch (state) {
    JobState.requested || JobState.vehicleDetected =>
      isRetrieval ? '출차 요청을 확인하고 있어요' : '주차 요청을 확인하고 있어요',
    JobState.movingToVehicle => '로봇이 차량으로 이동 중',
    JobState.lifting => '차량을 안전하게 싣는 중',
    JobState.movingToSlot || JobState.running =>
      isRetrieval ? '차량을 입구로 이동 중' : '차량 이동 중',
    JobState.retrieving => '차량을 입구로 이동 중',
    JobState.returning => '로봇이 대기 위치로 복귀 중',
    _ => '작업 상태 확인 중',
  };
}

bool _isRetrievalProgress(
  ParkingSnapshot snapshot,
  CustomerVehicle? vehicle,
) {
  if (vehicle != null) {
    final isRetrievalState = switch (vehicle.state) {
      VehicleState.retrievalRequested ||
      VehicleState.retrieving ||
      VehicleState.retrieved => true,
      _ => false,
    };
    if (isRetrievalState) {
      return true;
    }
  }

  final robotState = snapshot.robot.state.trim().toUpperCase();
  return robotState == 'MOVING_TO_PARKED_VEHICLE' ||
      robotState == 'CARRYING_TO_EXIT' ||
      snapshot.job.state == JobState.retrieving ||
      snapshot.job.message.contains('출차');
}

bool _isHealthyRobotState(String rawState) {
  final state = rawState.trim().toUpperCase();
  return state.isNotEmpty &&
      !const <String>{
        'UNKNOWN',
        'OFFLINE',
        'FAULT',
        'ERROR',
        'EMERGENCY_STOP',
        '상태 미확인',
      }.contains(state);
}

bool _isActiveJobState(JobState state) {
  return switch (state) {
    JobState.requested ||
    JobState.running ||
    JobState.vehicleDetected ||
    JobState.movingToVehicle ||
    JobState.lifting ||
    JobState.movingToSlot ||
    JobState.retrieving ||
    JobState.returning => true,
    _ => false,
  };
}

String vehicleStateLabel(VehicleState state) {
  return switch (state) {
    VehicleState.readyToPark => '주차 준비',
    VehicleState.parkingRequested => '주차 요청 접수',
    VehicleState.parkingInProgress => '주차 진행 중',
    VehicleState.parked => '주차 완료',
    VehicleState.retrievalRequested => '출차 요청 접수',
    VehicleState.retrieving => '출차 진행 중',
    VehicleState.retrieved => '출차 완료',
    VehicleState.error => '확인 필요',
    VehicleState.unknown => '상태 확인 중',
  };
}

String connectionLabel(GatewayConnectionState state) {
  return switch (state) {
    GatewayConnectionState.connected => '주차장 연결됨',
    GatewayConnectionState.connecting => '주차장 연결 중',
    GatewayConnectionState.reconnecting => '주차장 재연결 중',
    GatewayConnectionState.disconnected => '주차장 연결 끊김',
  };
}

String robotLabel(String rawState) {
  return switch (rawState.trim().toUpperCase()) {
    'READY' || 'IDLE' || 'DONE' || 'IDLE_AT_STANDBY' => '준비됨',
    'OFFLINE' => '연결 확인 필요',
    'FAULT' => '안전 확인 필요',
    _ => rawState,
  };
}

String durationLabel(int? minutes) {
  if (minutes == null) {
    return '-';
  }
  return switch (minutes) {
    60 => '60분',
    120 => '120분',
    180 => '180분',
    240 => '240분+',
    _ => '$minutes분',
  };
}

String slotLabel(String value) => value == '-' ? value : value.padLeft(2, '0');

String formatClock(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
