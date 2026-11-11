import 'dart:math' as math;

/// A named place the owner can pick when GPS is off or denied.
class Zone {
  const Zone(this.name, this.lat, this.lng);
  final String name;
  final double lat;
  final double lng;
}

/// Candidate pilot areas in Nairobi. Edit this list when launch zones are chosen.
const zones = <Zone>[
  Zone('Kasarani – Roysambu', -1.2195, 36.8925),
  Zone('Westlands – Parklands', -1.2640, 36.8140),
  Zone('Kilimani – Ngong Road', -1.2960, 36.7800),
];

/// Straight-line distance in km between two points.
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return r * 2 * math.asin(math.sqrt(a));
}
