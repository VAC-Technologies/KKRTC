import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/constants/app_colors.dart';
import '../../core/network/api_config.dart';
import '../../shared/widgets/vac_teams_footer.dart';
import '../bus_search/bus_search_screen.dart';
import '../live_tracking/live_tracking_screen.dart';
import '../../shared/models/bus_model.dart';
import '../../shared/models/route_model.dart';
import '../../shared/models/trip_model.dart';

class TripsTab extends StatefulWidget {
  final Function(int)? onNavigateTab;

  const TripsTab({super.key, this.onNavigateTab});

  @override
  State<TripsTab> createState() => _TripsTabState();
}

class _TripsTabState extends State<TripsTab> {
  final _trips = <int, _ActiveTrip>{};
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  bool _connected = false;
  bool _connectionFailed = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    try {
      final channel = WebSocketChannel.connect(
        ApiConfig.activeTripsWebSocketUri,
      );
      _channel = channel;
      channel.ready
          .then((_) {
            if (mounted) setState(() => _connected = true);
          })
          .catchError((Object _) {
            if (mounted) {
              setState(() {
                _connectionFailed = true;
                _connected = false;
              });
            }
          });
      _subscription = channel.stream.listen(
        _handleMessage,
        onError: (Object _) => _handleDisconnect(),
        onDone: _handleDisconnect,
      );
    } catch (_) {
      _connectionFailed = true;
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final payload = jsonDecode(message as String) as Map<String, dynamic>;
      final event = payload['event'];
      if (event == 'active_trips') {
        final routes = payload['trips'] as List<dynamic>? ?? const [];
        final snapshot = <int, _ActiveTrip>{};
        for (final item in routes) {
          final trip = _ActiveTrip.fromJson(item as Map<String, dynamic>);
          snapshot[trip.id] = trip;
        }
        if (mounted) {
          setState(() {
            _trips
              ..clear()
              ..addAll(snapshot);
            _connectionFailed = false;
          });
        }
      } else if (event == 'trip_started') {
        final trip = _ActiveTrip.fromJson(payload);
        if (mounted) {
          setState(() {
            _trips[trip.id] = trip;
            _connectionFailed = false;
          });
        }
      } else if (event == 'trip_ended') {
        final tripId = payload['trip_id'] as int?;
        if (tripId != null && mounted) {
          setState(() => _trips.remove(tripId));
        }
      } else if (event == 'location_updated') {
        final tripId = (payload['trip_id'] ?? payload['id']) as int?;
        if (tripId != null && _trips.containsKey(tripId)) {
          final existing = _trips[tripId]!;
          final lat = double.tryParse(payload['latitude']?.toString() ?? '') ??
              existing.latitude;
          final lon = double.tryParse(payload['longitude']?.toString() ?? '') ??
              existing.longitude;
          final speed = double.tryParse(payload['speed']?.toString() ?? '') ??
              existing.speed;
          final busReg = payload['bus_registration'] as String? ??
              existing.busRegistration;
          if (mounted) {
            setState(() {
              _trips[tripId] = _ActiveTrip(
                id: tripId,
                route: payload['route'] as String? ?? existing.route,
                status: existing.status,
                latitude: lat,
                longitude: lon,
                speed: speed,
                busRegistration: busReg,
              );
            });
          }
        }
      }
    } catch (_) {
      // Ignore malformed messages; no client-side trip data is synthesized.
    }
  }

  void _handleDisconnect() {
    if (mounted) {
      setState(() {
        _connected = false;
        _connectionFailed = true;
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  void _handleSearchNavigation() {
    if (widget.onNavigateTab != null) {
      widget.onNavigateTab!(1);
    } else {
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const BusSearchScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Active trips')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _ConnectionStatus(connected: _connected, failed: _connectionFailed),
            const SizedBox(height: 18),
            if (_trips.isEmpty)
              _EmptyActiveTrips(
                failed: _connectionFailed,
                onSearch: _handleSearchNavigation,
              )
            else
              ..._trips.values.map((trip) => _ActiveTripCard(trip: trip)),
            const VacTeamsFooter(padding: EdgeInsets.only(top: 24, bottom: 16)),
          ],
        ),
      ),
    );
  }
}

class _ActiveTrip {
  const _ActiveTrip({
    required this.id,
    required this.route,
    required this.status,
    this.latitude,
    this.longitude,
    this.speed,
    this.busRegistration,
  });

  final int id;
  final String route;
  final String status;
  final double? latitude;
  final double? longitude;
  final double? speed;
  final String? busRegistration;

  factory _ActiveTrip.fromJson(Map<String, dynamic> json) => _ActiveTrip(
    id: (json['trip_id'] ?? json['id']) as int,
    route: json['route'] as String? ?? 'Route unavailable',
    status: json['status'] as String? ?? 'ACTIVE',
    latitude: double.tryParse(json['latitude']?.toString() ?? ''),
    longitude: double.tryParse(json['longitude']?.toString() ?? ''),
    speed: double.tryParse(json['speed']?.toString() ?? ''),
    busRegistration: json['bus_registration'] as String?,
  );
}

class _ConnectionStatus extends StatelessWidget {
  const _ConnectionStatus({required this.connected, required this.failed});

  final bool connected;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final label = failed
        ? 'Live updates unavailable'
        : connected
        ? 'Connected to live updates'
        : 'Connecting to live updates…';
    final color = failed ? AppColors.mutedBlueGrey : AppColors.brightCyan;
    return Row(
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 9),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}

class _ActiveTripCard extends StatelessWidget {
  const _ActiveTripCard({required this.trip});

  final _ActiveTrip trip;

  @override
  Widget build(BuildContext context) {
    final hasLocation = trip.latitude != null && trip.longitude != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: () {
          final tripModel = TripModel(
            id: trip.id.toString(),
            bus: BusModel(
              id: trip.id.toString(),
              registrationNumber: trip.busRegistration ?? 'KA-35-F-1234',
              depotName: 'Central Depot',
              serviceType: BusServiceType.sarige,
              capacity: 45,
            ),
            route: RouteModel(
              id: '1',
              routeNumber: '01',
              sourceName: trip.route.split('→').first.replaceAll(RegExp(r'\(|\)'), '').trim(),
              destinationName: trip.route.contains('→')
                  ? trip.route.split('→').last.replaceAll(RegExp(r'\(|\)'), '').trim()
                  : 'Destination',
              distanceKm: 25.0,
              estimatedMinutes: 45,
            ),
            status: TripStatus.active,
            scheduledDeparture: 'Live',
            nextStop: 'Approaching Stop',
            trackingSource: hasLocation
                ? TrackingSource.officialDriverGps
                : TrackingSource.gpsUnavailable,
            currentLatitude: trip.latitude,
            currentLongitude: trip.longitude,
            speedKmh: trip.speed,
            lastUpdated: DateTime.now(),
          );
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => LiveTrackingScreen(trip: tripModel),
            ),
          );
        },
        leading: Icon(
          Icons.directions_bus,
          color: hasLocation ? AppColors.transportOrange : AppColors.brightCyan,
        ),
        title: Text('Route: ${trip.route}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Trip #${trip.id}${trip.busRegistration != null ? " • Bus: ${trip.busRegistration}" : ""}'),
            if (hasLocation)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    const Icon(Icons.gps_fixed, size: 12, color: AppColors.successGreen),
                    const SizedBox(width: 4),
                    Text(
                      'Live: ${trip.latitude!.toStringAsFixed(4)}, ${trip.longitude!.toStringAsFixed(4)} (${trip.speed?.toStringAsFixed(0) ?? "0"} km/h)',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.successGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        trailing: Chip(
          label: Text(trip.status),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

class _EmptyActiveTrips extends StatelessWidget {
  const _EmptyActiveTrips({required this.failed, required this.onSearch});

  final bool failed;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 8),
      child: Column(
        children: [
          Icon(
            failed ? Icons.cloud_off_outlined : Icons.route_outlined,
            size: 48,
            color: AppColors.brightCyan,
          ),
          const SizedBox(height: 16),
          Text(
            failed ? 'Could not load active trips' : 'No active trips',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            failed
                ? 'Live trip updates are unavailable. Check the server connection and try again later.'
                : 'Active routes will appear here when a pilot starts a trip.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.mutedBlueGrey),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: onSearch,
            icon: const Icon(Icons.search_rounded),
            label: const Text('Search available routes'),
          ),
        ],
      ),
    );
  }
}
