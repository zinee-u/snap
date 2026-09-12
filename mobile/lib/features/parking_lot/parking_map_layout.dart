import 'dart:ui';

/// Visual slot order, viewed from the top of the map toward the entrance.
/// Slot IDs remain the IDs supplied by the Gateway.
abstract final class ParkingMapLayout {
  static const rows = <List<int>>[
    <int>[6, 5],
    <int>[4, 3],
    <int>[2, 1],
  ];

  /// Route destination inside the bay for [slotId], or null for an unknown ID.
  static Offset? slotCenter(String? slotId, Size size) {
    final id = int.tryParse(slotId ?? '');
    for (var row = 0; row < rows.length; row += 1) {
      final column = rows[row].indexOf(id ?? -1);
      if (column != -1) {
        return Offset(
          size.width * (column == 0 ? 0.28 : 0.72),
          size.height * ((row + 0.5) / rows.length),
        );
      }
    }
    return null;
  }
}
