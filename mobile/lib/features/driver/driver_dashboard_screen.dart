import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/constants/app_colors.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_config.dart';
import '../../core/storage/app_state_storage.dart';
import '../../shared/widgets/osm_map_panel.dart';
import '../../shared/widgets/vac_teams_footer.dart';
import '../authentication/role_selection_screen.dart';

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  final _routeIdController = TextEditingController();
  final _busIdController = TextEditingController();
  bool _journeyConfirmed = false;
  bool _startingTrip = false;
  bool _endingTrip = false;
  int? _activeTripId;
  String? _serviceMessage;

  // Real GPS hardware tracking state
  StreamSubscription<Position>? _gpsSubscription;
  double? _lastLatitude;
  double? _lastLongitude;
  double? _lastSpeed;

  @override
  void initState() {
    super.initState();
    _restoreSavedPilotState();
  }

  Future<void> _restoreSavedPilotState() async {
    final form = await AppStateStorage.getPilotForm();
    final routeId = form['routeId'] as String? ?? '';
    final busId = form['busId'] as String? ?? '';
    final isConfirmed = form['isConfirmed'] as bool? ?? false;
    final savedTripId = await AppStateStorage.getPilotActiveTripId();

    if (!mounted) return;
    setState(() {
      if (routeId.isNotEmpty) _routeIdController.text = routeId;
      if (busId.isNotEmpty) _busIdController.text = busId;
      _journeyConfirmed =
          isConfirmed &&
          _routeIdController.text.trim().isNotEmpty &&
          _busIdController.text.trim().isNotEmpty;
    });

    if (savedTripId != null) {
      await _checkActiveTripStatus(savedTripId);
      if (_activeTripId != null) {
        _startGpsStreaming(_activeTripId!);
      }
    }
  }

  Future<void> _startGpsStreaming(int tripId) async {
    _stopGpsStreaming();
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() => _serviceMessage = 'Location services are disabled on device.');
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() => _serviceMessage = 'Location permission denied by user.');
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _serviceMessage = 'Location permission permanently denied.');
        }
        return;
      }

      // Stream real hardware coordinates from phone sensor
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      );

      _gpsSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) => _sendGpsCoordinate(tripId, position),
        onError: (Object err) {
          if (mounted) {
            setState(() => _serviceMessage = 'GPS tracking error: $err');
          }
        },
      );

      // Send initial position fix immediately
      final initialPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await _sendGpsCoordinate(tripId, initialPosition);
    } catch (e) {
      if (mounted) {
        setState(() => _serviceMessage = 'GPS sensor initialization failed: $e');
      }
    }
  }

  Future<void> _sendGpsCoordinate(int tripId, Position position) async {
    try {
      final speedKmph = (position.speed * 3.6).clamp(0.0, 150.0);
      final bearing = position.heading.clamp(0.0, 360.0);
      if (mounted) {
        setState(() {
          _lastLatitude = position.latitude;
          _lastLongitude = position.longitude;
          _lastSpeed = speedKmph;
        });
      }
      await ApiClient().post<Map<String, dynamic>>(
        ApiConfig.driverGpsSubmissionEndpoint,
        data: {
          'trip_id': tripId,
          'latitude': position.latitude.toStringAsFixed(6),
          'longitude': position.longitude.toStringAsFixed(6),
          'speed': speedKmph.toStringAsFixed(2),
          'bearing': bearing.toStringAsFixed(2),
        },
      );
    } catch (_) {
      // Non-blocking: continue stream on next GPS fix
    }
  }

  void _stopGpsStreaming() {
    _gpsSubscription?.cancel();
    _gpsSubscription = null;
  }

  Future<void> _checkActiveTripStatus(int tripId) async {
    try {
      final response = await ApiClient().get<dynamic>(
        '${ApiConfig.liveLocationEndpoint}$tripId/',
      );
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final status = (data is Map<String, dynamic>) ? data['status'] : null;
        if (status == 'ACTIVE' || status == 'IN_PROGRESS' || status == null) {
          if (mounted) {
            setState(() {
              _activeTripId = tripId;
              _journeyConfirmed = true;
            });
          }
          return;
        }
      }
      if (mounted) {
        setState(() => _activeTripId = null);
      }
      await AppStateStorage.savePilotActiveTripId(null);
    } catch (_) {
      // Backend is offline or trip is unverified.
      // Do NOT auto-start or assume trip is active.
      if (mounted) {
        setState(() => _activeTripId = null);
      }
      await AppStateStorage.savePilotActiveTripId(null);
    }
  }

  void _saveDraftForm() {
    AppStateStorage.savePilotForm(
      routeId: _routeIdController.text.trim(),
      busId: _busIdController.text.trim(),
      isConfirmed: _journeyConfirmed,
    );
  }

  @override
  void dispose() {
    _stopGpsStreaming();
    _routeIdController.dispose();
    _busIdController.dispose();
    super.dispose();
  }

  void _confirmJourney() {
    final routeText = _routeIdController.text.trim();
    final busText = _busIdController.text.trim();
    if (routeText.isEmpty || busText.isEmpty) {
      setState(
        () => _serviceMessage = 'Enter a valid route ID and assigned bus ID.',
      );
      return;
    }
    setState(() {
      _journeyConfirmed = true;
      _serviceMessage = null;
    });
    _saveDraftForm();
  }

  Future<void> _startTrip() async {
    setState(() {
      _startingTrip = true;
      _serviceMessage = null;
    });
    try {
      final routeVal =
          int.tryParse(_routeIdController.text.trim()) ??
          _routeIdController.text.trim();
      final busVal =
          int.tryParse(_busIdController.text.trim()) ??
          _busIdController.text.trim();
      final response = await ApiClient().post<Map<String, dynamic>>(
        ApiConfig.driverStartTripEndpoint,
        data: {'route_id': routeVal, 'bus_id': busVal},
      );
      final result = response.data;
      if (mounted) {
        final tripId = result?['trip_id'] as int?;
        setState(() {
          _activeTripId = tripId;
          _serviceMessage = result == null
              ? 'Trip started, but the server returned no trip details.'
              : 'Trip ${result["trip_id"]} started: ${result["route"]}.';
        });
        if (tripId != null) {
          await AppStateStorage.savePilotActiveTripId(tripId);
          _startGpsStreaming(tripId);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _serviceMessage =
              'Trip service unavailable. No trip has been started.',
        );
      }
    } finally {
      if (mounted) setState(() => _startingTrip = false);
    }
  }

  Future<void> _endTrip() async {
    final tripId = _activeTripId;
    if (tripId == null) return;
    setState(() {
      _endingTrip = true;
      _serviceMessage = null;
    });
    try {
      await ApiClient().post<Map<String, dynamic>>(
        ApiConfig.driverStopTripEndpoint,
        data: {'trip_id': tripId},
      );
      if (mounted) {
        _stopGpsStreaming();
        setState(() {
          _activeTripId = null;
          _journeyConfirmed = false;
          _lastLatitude = null;
          _lastLongitude = null;
          _lastSpeed = null;
          _serviceMessage = 'Trip $tripId completed.';
        });
        await AppStateStorage.savePilotActiveTripId(null);
        _saveDraftForm();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _serviceMessage = 'Trip could not be completed.');
      }
    } finally {
      if (mounted) setState(() => _endingTrip = false);
    }
  }

  Future<void> _handleSignOut() async {
    _stopGpsStreaming();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign Out'),
        content: const Text(
          'Sign out of Pilot mode and return to account selection?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.errorRed,
              foregroundColor: AppColors.white,
            ),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await AppStateStorage.clearSession();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const RoleSelectionScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Pilot Journey',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppColors.midnightNavy,
        foregroundColor: AppColors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign Out / Switch Role',
            onPressed: _handleSignOut,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            if (ApiConfig.demoPilotMode) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.deepNavy,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.brightCyan, width: 1.5),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: AppColors.brightCyan, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'DEMO PILOT MODE (CAMPUS TESTING)',
                            style: TextStyle(
                              color: AppColors.brightCyan,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Pilot: Anil (KKRTC-P-4401) | Assigned Bus: KA-34-A-1001',
                            style: TextStyle(
                              color: AppColors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Text(
              'Plan your trip',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.primaryText,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Enter a route and assigned bus ID. A trip starts only when you press Start trip.',
              style: TextStyle(
                color: AppColors.mutedBlueGrey,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _routeIdController,
              textInputAction: TextInputAction.next,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Route ID',
                hintText: 'Route ID from the server',
                prefixIcon: Icon(Icons.route_outlined),
              ),
              onChanged: (_) {
                setState(() => _journeyConfirmed = false);
                _saveDraftForm();
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _busIdController,
              textInputAction: TextInputAction.done,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Assigned bus ID',
                hintText: 'Bus ID assigned to this pilot',
                prefixIcon: Icon(Icons.directions_bus_outlined),
              ),
              onChanged: (_) {
                setState(() => _journeyConfirmed = false);
                _saveDraftForm();
              },
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _confirmJourney,
              icon: const Icon(Icons.route_outlined),
              label: const Text('Confirm journey'),
            ),
            if (_journeyConfirmed && _activeTripId == null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warmLightYellow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.softYellow),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.route_rounded,
                      color: AppColors.deepNavy,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Route ID: ${_routeIdController.text.trim()}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.deepNavy,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const SizedBox(height: 250, child: OsmMapPanel()),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _startingTrip ? null : _startTrip,
                icon: _startingTrip
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: const Text('Start trip'),
              ),
            ],
            if (_activeTripId != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Active trip #$_activeTripId',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.successGreen.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.gps_fixed,
                                  color: AppColors.successGreen,
                                  size: 14,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'GPS BROADCASTING',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.successGreen,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (_lastLatitude != null && _lastLongitude != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Live GPS: ${_lastLatitude!.toStringAsFixed(5)}, ${_lastLongitude!.toStringAsFixed(5)} (${_lastSpeed?.toStringAsFixed(1) ?? "0.0"} km/h)',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.deepNavy,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _endingTrip ? null : _endTrip,
                        icon: _endingTrip
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.stop_circle_outlined),
                        label: const Text('End trip'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_serviceMessage != null) ...[
              const SizedBox(height: 14),
              Text(
                _serviceMessage!,
                style: const TextStyle(color: AppColors.iceBlue),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 20),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.gps_not_fixed, color: AppColors.mutedBlueGrey),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Live tracking unavailable until the trip and GPS APIs are configured.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const VacTeamsFooter(padding: EdgeInsets.only(top: 24, bottom: 16)),
          ],
        ),
      ),
    );
  }
}
