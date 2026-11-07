class StopModel {
  final String id;
  final String nameEn;
  final String nameKn;
  final int sequence;
  final double latitude;
  final double longitude;
  final String? landmark;

  const StopModel({
    required this.id,
    required this.nameEn,
    required this.nameKn,
    required this.sequence,
    required this.latitude,
    required this.longitude,
    this.landmark,
  });

  String get localizedName => '$nameEn ($nameKn)';

  factory StopModel.fromJson(Map<String, dynamic> json) {
    final stopName = (json['stop_name'] ?? json['nameEn'] ?? '').toString();
    final stopNameKn = (json['stop_name_kn'] ?? json['nameKn'] ?? stopName)
        .toString();
    final rawSeq = json['sequence_order'] ?? json['sequence'] ?? 1;
    final seq = rawSeq is int ? rawSeq : (int.tryParse(rawSeq.toString()) ?? 1);

    return StopModel(
      id: (json['id'] ?? '').toString(),
      nameEn: stopName,
      nameKn: stopNameKn,
      sequence: seq,
      latitude: json['latitude'] != null
          ? double.tryParse(json['latitude'].toString()) ?? 0.0
          : 0.0,
      longitude: json['longitude'] != null
          ? double.tryParse(json['longitude'].toString()) ?? 0.0
          : 0.0,
      landmark: json['landmark']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'stop_name': nameEn,
    'stop_name_kn': nameKn,
    'sequence_order': sequence,
    'latitude': latitude,
    'longitude': longitude,
    if (landmark != null) 'landmark': landmark,
  };
}
