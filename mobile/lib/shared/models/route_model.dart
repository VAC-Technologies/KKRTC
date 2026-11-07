import 'stop_model.dart';

class RouteModel {
  final String id;
  final String routeNumber;
  final String sourceName;
  final String destinationName;
  final double distanceKm;
  final int estimatedMinutes;
  final List<StopModel> intermediateStops;
  final double? sourceLatitude;
  final double? sourceLongitude;
  final double? destinationLatitude;
  final double? destinationLongitude;
  final bool isActive;
  final int stopsCount;

  const RouteModel({
    required this.id,
    required this.routeNumber,
    required this.sourceName,
    required this.destinationName,
    required this.distanceKm,
    required this.estimatedMinutes,
    this.intermediateStops = const [],
    this.sourceLatitude,
    this.sourceLongitude,
    this.destinationLatitude,
    this.destinationLongitude,
    this.isActive = true,
    this.stopsCount = 0,
  });

  String get routeName => '$sourceName ↔ $destinationName';

  String get durationFormatted {
    if (estimatedMinutes <= 0) {
      if (distanceKm > 0) {
        final mins = (distanceKm / 45 * 60).round();
        return '${(mins / 60).floor()}h ${mins % 60}m';
      }
      return 'Direct';
    }
    return '${(estimatedMinutes / 60).floor()}h ${estimatedMinutes % 60}m';
  }

  factory RouteModel.fromJson(Map<String, dynamic> json) {
    final rawStops = json['stops'] as List<dynamic>? ?? const [];
    final parsedStops = rawStops
        .map((s) => StopModel.fromJson(s as Map<String, dynamic>))
        .toList();

    final dist = json['distance_km'] != null
        ? double.tryParse(json['distance_km'].toString()) ?? 0.0
        : (double.tryParse((json['distanceKm'] ?? '0').toString()) ?? 0.0);

    final estMins = json['estimated_minutes'] is int
        ? json['estimated_minutes'] as int
        : (int.tryParse((json['estimatedMinutes'] ?? '0').toString()) ?? 0);

    return RouteModel(
      id: (json['id'] ?? '').toString(),
      routeNumber: (json['route_id'] ?? json['routeNumber'] ?? '').toString(),
      sourceName: (json['source_name'] ?? json['sourceName'] ?? '').toString(),
      destinationName:
          (json['destination_name'] ?? json['destinationName'] ?? '')
              .toString(),
      distanceKm: dist,
      estimatedMinutes: estMins,
      intermediateStops: parsedStops,
      sourceLatitude: json['source_latitude'] != null
          ? double.tryParse(json['source_latitude'].toString())
          : null,
      sourceLongitude: json['source_longitude'] != null
          ? double.tryParse(json['source_longitude'].toString())
          : null,
      destinationLatitude: json['destination_latitude'] != null
          ? double.tryParse(json['destination_latitude'].toString())
          : null,
      destinationLongitude: json['destination_longitude'] != null
          ? double.tryParse(json['destination_longitude'].toString())
          : null,
      isActive: json['is_active'] as bool? ?? true,
      stopsCount: (json['stops_count'] as int?) ?? parsedStops.length,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'route_id': routeNumber,
    'source_name': sourceName,
    'destination_name': destinationName,
    'distance_km': distanceKm,
    'estimated_minutes': estimatedMinutes,
    'is_active': isActive,
    'stops_count': stopsCount,
    'stops': intermediateStops.map((s) => s.toJson()).toList(),
  };
}
