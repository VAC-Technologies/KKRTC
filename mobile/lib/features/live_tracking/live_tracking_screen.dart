import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/constants/app_colors.dart';
import '../../core/network/api_config.dart';
import '../../shared/models/trip_model.dart';
import '../../shared/widgets/osm_map_panel.dart';
import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/vac_teams_footer.dart';
import 'passenger_assisted_tracking_sheet.dart';

class LiveTrackingScreen extends StatefulWidget {
  const LiveTrackingScreen({super.key, this.trip});

  final TripModel? trip;

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  TripModel? _currentTrip;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  bool _connected = false;
  DateTime? _lastUpdatedTime;

  @override
  void initState() {
    super.initState();
    _currentTrip = widget.trip;
    if (_currentTrip != null) {
      _lastUpdatedTime = _currentTrip!.lastUpdated;
    }
    _connectWebSocket();
  }

  void _connectWebSocket() {
    try {
      final channel = WebSocketChannel.connect(ApiConfig.activeTripsWebSocketUri);
      _channel = channel;
      channel.ready.then((_) {
        if (mounted) setState(() => _connected = true);
      }).catchError((Object _) {
        if (mounted) setState(() => _connected = false);
      });

      _subscription = channel.stream.listen(
        _handleWebSocketMessage,
        onError: (Object _) => _handleDisconnect(),
        onDone: _handleDisconnect,
      );
    } catch (_) {
      _connected = false;
    }
  }

  void _handleWebSocketMessage(dynamic message) {
    try {
      final payload = jsonDecode(message as String) as Map<String, dynamic>;
      final event = payload['event'];
      final tripIdStr = _currentTrip?.id;

      if (event == 'location_updated') {
        final updateTripId = (payload['trip_id'] ?? payload['id'])?.toString();
        if (tripIdStr != null && updateTripId == tripIdStr) {
          final lat = double.tryParse(payload['latitude']?.toString() ?? '');
          final lon = double.tryParse(payload['longitude']?.toString() ?? '');
          final speed = double.tryParse(payload['speed']?.toString() ?? '');
          final now = DateTime.now();

          if (lat != null && lon != null && mounted) {
            setState(() {
              _lastUpdatedTime = now;
              _currentTrip = _currentTrip?.copyWith(
                currentLatitude: lat,
                currentLongitude: lon,
                speedKmh: speed,
                lastUpdated: now,
                source: TrackingSource.officialDriverGps,
              );
            });
          }
        }
      } else if (event == 'trip_ended') {
        final endTripId = payload['trip_id']?.toString();
        if (tripIdStr != null && endTripId == tripIdStr && mounted) {
          setState(() {
            _currentTrip = _currentTrip?.copyWith(
              status: TripStatus.completed,
              lastUpdated: DateTime.now(),
            );
          });
        }
      }
    } catch (_) {
      // Ignore malformed payloads
    }
  }

  void _handleDisconnect() {
    if (mounted) {
      setState(() => _connected = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trip = _currentTrip;
    final hasBusPosition =
        trip?.currentLatitude != null && trip?.currentLongitude != null;
    final routeStops = trip?.route.intermediateStops ?? const [];
    final routeCoordinates = routeStops
        .map((stop) => LatLng(stop.latitude, stop.longitude))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(trip?.bus.registrationNumber ?? 'Live tracking'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.circle,
                  size: 10,
                  color: _connected ? AppColors.successGreen : AppColors.mutedBlueGrey,
                ),
                const SizedBox(width: 6),
                Text(
                  _connected ? 'LIVE' : 'OFFLINE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _connected ? AppColors.successGreen : AppColors.mutedBlueGrey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            height: 420,
            child: OsmMapPanel(
              busLocation: hasBusPosition
                  ? LatLng(
                      trip!.currentLatitude!,
                      trip.currentLongitude!,
                    )
                  : null,
              origin: routeCoordinates.isEmpty ? null : routeCoordinates.first,
              destination: routeCoordinates.length < 2
                  ? null
                  : routeCoordinates.last,
              routeCoordinates: routeCoordinates,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (trip == null)
                    const Text(
                      'Live tracking unavailable',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else ...[
                    Text(
                      '${trip.route.sourceName} → ${trip.route.destinationName}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        TrackingSourceBadge(source: trip.source),
                        const Spacer(),
                        if (trip.status == TripStatus.completed)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.mutedBlueGrey.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'TRIP COMPLETED',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  _MetricLine(
                    label: 'Status',
                    value: trip?.status == TripStatus.completed ? 'Completed' : 'In Transit (Live)',
                  ),
                  const SizedBox(height: 8),
                  _MetricLine(
                    label: 'Speed',
                    value: trip?.currentSpeedKmph == null
                        ? 'Speed unavailable'
                        : '${trip!.currentSpeedKmph!.toStringAsFixed(0)} km/h',
                  ),
                  const SizedBox(height: 8),
                  _MetricLine(
                    label: 'Last GPS Update',
                    value: _lastUpdatedTime != null
                        ? '${_lastUpdatedTime!.hour.toString().padLeft(2, "0")}:${_lastUpdatedTime!.minute.toString().padLeft(2, "0")}:${_lastUpdatedTime!.second.toString().padLeft(2, "0")}'
                        : 'Awaiting fix…',
                  ),
                  if (trip == null) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'No live trip data is available from the KKRTC service.',
                      style: TextStyle(color: AppColors.mutedBlueGrey),
                    ),
                  ] else ...[
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () => _showAssistedTracking(context, trip),
                      icon: const Icon(Icons.share_location_outlined),
                      label: const Text('Passenger-assisted GPS'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const VacTeamsFooter(padding: EdgeInsets.only(top: 16, bottom: 16)),
        ],
      ),
    );
  }

  void _showAssistedTracking(BuildContext context, TripModel trip) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          PassengerAssistedTrackingSheet(trip: trip, onToggleSharing: (_) {}),
    );
  }
}

class _MetricLine extends StatelessWidget {
  const _MetricLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: const TextStyle(color: AppColors.mutedBlueGrey)),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
    ],
  );
}
