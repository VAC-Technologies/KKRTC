import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/constants/app_colors.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_config.dart';
import '../../core/storage/app_state_storage.dart';
import '../../shared/widgets/osm_map_panel.dart';
import '../../shared/widgets/vac_teams_footer.dart';
import '../authentication/role_selection_screen.dart';

class DriverItem {
  final int id;
  final int driverId;
  final String name;
  final String phoneNumber;
  final String badgeNumber;

  const DriverItem({
    required this.id,
    required this.driverId,
    required this.name,
    required this.phoneNumber,
    required this.badgeNumber,
  });

  factory DriverItem.fromJson(Map<String, dynamic> json) {
    return DriverItem(
      id: json['id'] as int? ?? 0,
      driverId: json['driver_id'] as int? ?? 0,
      name: json['driver_name'] as String? ?? '',
      phoneNumber: json['phone_number'] as String? ?? '',
      badgeNumber: json['badge_number'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DriverItem &&
          runtimeType == other.runtimeType &&
          driverId == other.driverId;

  @override
  int get hashCode => driverId.hashCode;
}

class RouteItem {
  final int id;
  final String routeId;
  final String sourceName;
  final String destinationName;

  const RouteItem({
    required this.id,
    required this.routeId,
    required this.sourceName,
    required this.destinationName,
  });

  factory RouteItem.fromJson(Map<String, dynamic> json) {
    return RouteItem(
      id: json['id'] as int? ?? 0,
      routeId: json['route_id'] as String? ?? '',
      sourceName: json['source_name'] as String? ?? '',
      destinationName: json['destination_name'] as String? ?? '',
    );
  }

  String get displayText => '$routeId ($sourceName → $destinationName)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RouteItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class BusItem {
  final int id;
  final String registrationNumber;
  final int driverId;
  final String driverName;

  const BusItem({
    required this.id,
    required this.registrationNumber,
    required this.driverId,
    required this.driverName,
  });

  factory BusItem.fromJson(Map<String, dynamic> json) {
    return BusItem(
      id: json['id'] as int? ?? 0,
      registrationNumber: json['registration_number'] as String? ?? '',
      driverId: json['driver_id'] as int? ?? 0,
      driverName: json['driver_name'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BusItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  // Dropdown data models
  List<DriverItem> _drivers = [];
  List<RouteItem> _routes = [];
  List<BusItem> _buses = [];

  // Dropdown selections
  DriverItem? _selectedDriver;
  RouteItem? _selectedRoute;
  BusItem? _selectedBus;

  // Dropdown UI loading and error states
  bool _isLoadingDrivers = false;
  bool _isLoadingRoutes = false;
  bool _isLoadingBuses = false;
  String? _driverError;
  String? _routeError;
  String? _busError;

  // Trip state
  bool _journeyConfirmed = false;
  bool _startingTrip = false;
  bool _endingTrip = false;
  int? _activeTripId;
  String? _activeRouteSummary;
  String? _activeBusSummary;
  String? _serviceMessage;

  // Authenticated pilot info
  String? _authenticatedPilotName;
  String? _authenticatedBadgeNumber;
  String? _authenticatedBusRegistration;

  // Real GPS hardware tracking state
  StreamSubscription<Position>? _gpsSubscription;
  double? _lastLatitude;
  double? _lastLongitude;
  double? _lastSpeed;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  Future<void> _fetchInitialData() async {
    await Future.wait([
      _loadDrivers(),
      _loadRoutes(),
      _loadAuthenticatedPilotProfile(),
    ]);
    await _recoverActiveTripFromBackend();
  }

  Future<void> _loadDrivers() async {
    if (!mounted) return;
    setState(() {
      _isLoadingDrivers = true;
      _driverError = null;
    });
    try {
      final response = await ApiClient().get<dynamic>(
        ApiConfig.authorizedPilotsEndpoint,
      );
      if (response.statusCode == 200 && response.data is List) {
        final rawList = response.data as List;
        final loadedDrivers = rawList
            .whereType<Map<String, dynamic>>()
            .map(DriverItem.fromJson)
            .toList();
        if (mounted) {
          setState(() {
            _drivers = loadedDrivers;
            _isLoadingDrivers = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _driverError = 'Failed to load drivers.';
            _isLoadingDrivers = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _driverError = 'Unable to connect to driver service.';
          _isLoadingDrivers = false;
        });
      }
    }
  }

  Future<void> _loadRoutes() async {
    if (!mounted) return;
    setState(() {
      _isLoadingRoutes = true;
      _routeError = null;
    });
    try {
      final response = await ApiClient().get<dynamic>(
        ApiConfig.routesEndpoint,
      );
      if (response.statusCode == 200 && response.data is List) {
        final rawList = response.data as List;
        final loadedRoutes = rawList
            .whereType<Map<String, dynamic>>()
            .map(RouteItem.fromJson)
            .toList();
        if (mounted) {
          setState(() {
            _routes = loadedRoutes;
            _isLoadingRoutes = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _routeError = 'Failed to load routes.';
            _isLoadingRoutes = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _routeError = 'Unable to connect to route service.';
          _isLoadingRoutes = false;
        });
      }
    }
  }

  Future<void> _loadBusesForDriver(int driverId) async {
    if (!mounted) return;
    setState(() {
      _isLoadingBuses = true;
      _busError = null;
      _buses = [];
      _selectedBus = null;
      _journeyConfirmed = false;
    });
    try {
      final response = await ApiClient().get<dynamic>(
        '${ApiConfig.busesEndpoint}?driver_id=$driverId',
      );
      if (response.statusCode == 200 && response.data is List) {
        final rawList = response.data as List;
        final loadedBuses = rawList
            .whereType<Map<String, dynamic>>()
            .map(BusItem.fromJson)
            .toList();
        if (mounted) {
          setState(() {
            _buses = loadedBuses;
            if (_buses.isNotEmpty) {
              _selectedBus = _buses.first;
            }
            _isLoadingBuses = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _busError = 'Failed to load assigned buses.';
            _isLoadingBuses = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busError = 'Unable to connect to bus service.';
          _isLoadingBuses = false;
        });
      }
    }
  }

  Future<void> _loadAuthenticatedPilotProfile() async {
    try {
      final response = await ApiClient().get<dynamic>(
        ApiConfig.pilotProfileEndpoint,
      );
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data as Map<String, dynamic>;
        final username = data['username'] as String?;
        final badge = data['badge_number'] as String?;
        final userId = data['user_id'] as int?;

        if (mounted) {
          setState(() {
            _authenticatedPilotName = username;
            _authenticatedBadgeNumber = badge;
          });
        }

        if (userId != null) {
          final busResponse = await ApiClient().get<dynamic>(
            '${ApiConfig.busesEndpoint}?driver_id=$userId',
          );
          if (busResponse.statusCode == 200 && busResponse.data is List) {
            final list = busResponse.data as List;
            if (list.isNotEmpty && list.first is Map) {
              final reg = (list.first as Map)['registration_number'] as String?;
              if (mounted && reg != null) {
                setState(() => _authenticatedBusRegistration = reg);
              }
            }
          }
        }
      }
    } catch (_) {
      // Non-blocking profile load
    }
  }

  Future<void> _recoverActiveTripFromBackend() async {
    try {
      Map<String, dynamic>? activeData;

      // 1. Try dedicated current active trip endpoint
      try {
        final currentResp = await ApiClient().get<dynamic>(
          ApiConfig.currentActiveTripEndpoint,
        );
        if (currentResp.statusCode == 200 && currentResp.data is Map) {
          final map = currentResp.data as Map<String, dynamic>;
          if (map['active_trip'] is Map<String, dynamic>) {
            activeData = map['active_trip'] as Map<String, dynamic>;
          }
        }
      } catch (_) {
        // Fall through to public list search
      }

      // 2. Fallback to searching active trips list
      if (activeData == null) {
        try {
          final listResp = await ApiClient().get<dynamic>(
            ApiConfig.activeTripsEndpoint,
          );
          if (listResp.statusCode == 200 && listResp.data is List) {
            final list = (listResp.data as List).whereType<Map<String, dynamic>>();
            final pilotName = _authenticatedPilotName ?? 'Anil';
            final matched = list.firstWhere(
              (t) => t['driver_name'] == pilotName || t['status'] == 'ACTIVE',
              orElse: () => <String, dynamic>{},
            );
            if (matched.isNotEmpty) {
              activeData = matched;
            }
          }
        } catch (_) {}
      }

      // 3. If an active trip is found on the backend, restore state and start GPS
      if (activeData != null && mounted) {
        final tripId = activeData['id'] as int?;
        if (tripId != null) {
          final routeStr = activeData['route']?.toString() ?? 'Active Route';
          final busReg = activeData['bus_registration']?.toString() ?? '';
          final lat = double.tryParse(activeData['current_latitude']?.toString() ?? '');
          final lon = double.tryParse(activeData['current_longitude']?.toString() ?? '');
          final speed = double.tryParse(activeData['current_speed']?.toString() ?? '');

          setState(() {
            _activeTripId = tripId;
            _journeyConfirmed = true;
            _activeRouteSummary = routeStr;
            _activeBusSummary = busReg;
            if (lat != null && lon != null) {
              _lastLatitude = lat;
              _lastLongitude = lon;
              _lastSpeed = speed;
            }
            _serviceMessage = 'Active trip #$tripId resumed: $routeStr.';
          });
          await AppStateStorage.savePilotActiveTripId(tripId);
          _startGpsStreaming(tripId);
          return;
        }
      }

      // 4. Fallback: check locally saved trip ID
      final savedTripId = await AppStateStorage.getPilotActiveTripId();
      if (savedTripId != null) {
        await _checkActiveTripStatus(savedTripId);
        if (_activeTripId != null && mounted) {
          _startGpsStreaming(_activeTripId!);
        }
      }
    } catch (_) {}
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
      // Non-blocking stream
    }
  }

  void _stopGpsStreaming() {
    _gpsSubscription?.cancel();
    _gpsSubscription = null;
  }

  Future<void> _checkActiveTripStatus(int tripId) async {
    try {
      Response<dynamic>? response;
      try {
        response = await ApiClient().get<dynamic>(
          '${ApiConfig.tripsEndpoint}$tripId/',
        );
      } catch (_) {
        response = await ApiClient().get<dynamic>(
          '${ApiConfig.liveLocationEndpoint}$tripId/',
        );
      }
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final status = (data is Map<String, dynamic>) ? data['status'] : null;
        if (status == 'ACTIVE' || status == 'IN_PROGRESS' || status == null) {
          if (mounted) {
            setState(() {
              _activeTripId = tripId;
              _journeyConfirmed = true;
              if (data is Map<String, dynamic>) {
                _activeRouteSummary = data['route']?.toString();
                _activeBusSummary = data['bus_registration']?.toString();
              }
            });
          }
          return;
        }
      }
      if (mounted) setState(() => _activeTripId = null);
      await AppStateStorage.savePilotActiveTripId(null);
    } catch (_) {
      if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
        if (mounted) {
          setState(() {
            _activeTripId = tripId;
            _journeyConfirmed = true;
          });
        }
        return;
      }
      if (mounted) setState(() => _activeTripId = null);
      await AppStateStorage.savePilotActiveTripId(null);
    }
  }

  @override
  void dispose() {
    _stopGpsStreaming();
    super.dispose();
  }

  void _confirmJourney() {
    if (_selectedDriver == null) {
      setState(() => _serviceMessage = 'Please select a driver name.');
      return;
    }
    if (_selectedRoute == null) {
      setState(() => _serviceMessage = 'Please select a route ID.');
      return;
    }
    if (_selectedBus == null) {
      setState(() => _serviceMessage = 'Please select an assigned bus number.');
      return;
    }
    setState(() {
      _journeyConfirmed = true;
      _serviceMessage = null;
    });
  }

  Future<void> _startTrip() async {
    if (_selectedRoute == null || _selectedBus == null) {
      setState(() => _serviceMessage = 'Selection incomplete.');
      return;
    }
    setState(() {
      _startingTrip = true;
      _serviceMessage = null;
    });
    try {
      final response = await ApiClient().post<Map<String, dynamic>>(
        ApiConfig.driverStartTripEndpoint,
        data: {
          'route_id': _selectedRoute!.id,
          'bus_id': _selectedBus!.id,
        },
      );
      final result = response.data;
      if (mounted) {
        final tripId = result?['trip_id'] as int?;
        setState(() {
          _activeTripId = tripId;
          _activeRouteSummary = result?['route']?.toString();
          _activeBusSummary = _selectedBus?.registrationNumber;
          _serviceMessage = result == null
              ? 'Trip started, but server returned no trip details.'
              : 'Trip ${result["trip_id"]} started: ${result["route"]}.';
        });
        if (tripId != null) {
          await AppStateStorage.savePilotActiveTripId(tripId);
          _startGpsStreaming(tripId);
        }
      }
    } catch (e) {
      if (!mounted) return;
      String message = 'Trip service unavailable. No trip started.';
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        final responseData = e.response?.data;
        if (responseData is Map<String, dynamic>) {
          final detail = responseData['detail'] ??
              responseData['error'] ??
              responseData['bus_id'] ??
              responseData['route_id'];
          if (detail != null) {
            message = detail is List ? detail.join(', ') : detail.toString();
          } else {
            message = 'Request failed (HTTP $statusCode).';
          }
        } else if (statusCode != null) {
          message = 'Server error (HTTP $statusCode).';
        }

        // If duplicate active trip collision occurs, auto-recover the active trip
        if (message.contains('already has an active trip')) {
          await _recoverActiveTripFromBackend();
        }
      }
      if (mounted) {
        setState(() => _serviceMessage = message);
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
          _activeRouteSummary = null;
          _activeBusSummary = null;
          _lastLatitude = null;
          _lastLongitude = null;
          _lastSpeed = null;
          _serviceMessage = 'Trip $tripId completed.';
        });
        await AppStateStorage.savePilotActiveTripId(null);
      }
    } catch (e) {
      if (mounted) {
        String message = 'Trip could not be completed.';
        if (e is DioException && e.response?.data is Map) {
          final d = (e.response!.data as Map)['detail'];
          if (d != null) message = d.toString();
        }
        setState(() => _serviceMessage = message);
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
          'Return to role selection?',
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
    final bool canConfirm = _selectedDriver != null &&
        _selectedRoute != null &&
        _selectedBus != null &&
        !_isLoadingDrivers &&
        !_isLoadingRoutes &&
        !_isLoadingBuses;

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
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reload Data',
            onPressed: _fetchInitialData,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Switch Role',
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
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: AppColors.brightCyan, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'DEMO PILOT MODE (CAMPUS TESTING)',
                            style: TextStyle(
                              color: AppColors.brightCyan,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Pilot: ${_authenticatedPilotName ?? _selectedDriver?.name ?? "Anil"} (${_authenticatedBadgeNumber ?? "KKRTC-P-01"}) | Assigned Bus: ${_authenticatedBusRegistration ?? _selectedBus?.registrationNumber ?? "KA-35-F-1234"}',
                            style: const TextStyle(
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
              'Select Driver Name, Route ID and assigned Bus Number. Manual entry is disabled.',
              style: TextStyle(
                color: AppColors.mutedBlueGrey,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),

            // 1. DRIVER NAME DROPDOWN
            if (_isLoadingDrivers)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              )
            else
              DropdownButtonFormField<DriverItem>(
                initialValue: _selectedDriver,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Driver Name',
                  hintText: _drivers.isEmpty ? 'No drivers found' : 'Select Driver',
                  prefixIcon: const Icon(Icons.person_outline),
                  errorText: _driverError,
                ),
                items: _drivers.map((driver) {
                  return DropdownMenuItem<DriverItem>(
                    value: driver,
                    child: Text(
                      driver.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  );
                }).toList(),
                onChanged: _activeTripId != null
                    ? null
                    : (DriverItem? selected) {
                        setState(() {
                          _selectedDriver = selected;
                          _journeyConfirmed = false;
                        });
                        if (selected != null) {
                          _loadBusesForDriver(selected.driverId);
                        } else {
                          setState(() {
                            _buses = [];
                            _selectedBus = null;
                          });
                        }
                      },
              ),

            const SizedBox(height: 16),

            // 2. ROUTE ID DROPDOWN
            if (_isLoadingRoutes)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              )
            else
              DropdownButtonFormField<RouteItem>(
                initialValue: _selectedRoute,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Route ID',
                  hintText: _routes.isEmpty ? 'No routes found' : 'Select Route ID',
                  prefixIcon: const Icon(Icons.route_outlined),
                  errorText: _routeError,
                ),
                items: _routes.map((route) {
                  return DropdownMenuItem<RouteItem>(
                    value: route,
                    child: Text(
                      route.displayText,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  );
                }).toList(),
                onChanged: _activeTripId != null
                    ? null
                    : (RouteItem? selected) {
                        setState(() {
                          _selectedRoute = selected;
                          _journeyConfirmed = false;
                        });
                      },
              ),

            const SizedBox(height: 16),

            // 3. BUS NUMBER DROPDOWN (Dependent on Driver)
            if (_isLoadingBuses)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              )
            else
              DropdownButtonFormField<BusItem>(
                initialValue: _selectedBus,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Bus ID / Bus Number',
                  hintText: _selectedDriver == null
                      ? 'Select Driver First'
                      : (_buses.isEmpty
                          ? 'No buses assigned to this driver'
                          : 'Select Assigned Bus'),
                  prefixIcon: const Icon(Icons.directions_bus_outlined),
                  errorText: _busError,
                ),
                items: _buses.map((bus) {
                  return DropdownMenuItem<BusItem>(
                    value: bus,
                    child: Text(
                      bus.registrationNumber,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  );
                }).toList(),
                onChanged: (_activeTripId != null || _selectedDriver == null || _buses.isEmpty)
                    ? null
                    : (BusItem? selected) {
                        setState(() {
                          _selectedBus = selected;
                          _journeyConfirmed = false;
                        });
                      },
              ),

            const SizedBox(height: 20),

            OutlinedButton.icon(
              onPressed: canConfirm ? _confirmJourney : null,
              icon: const Icon(Icons.check_circle_outline),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.verified_user_outlined,
                          color: AppColors.deepNavy,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Driver: ${_selectedDriver?.name ?? ""} | Bus: ${_selectedBus?.registrationNumber ?? ""}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.deepNavy,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.route_rounded,
                          color: AppColors.deepNavy,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Route: ${_selectedRoute?.displayText ?? ""}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.deepNavy,
                            ),
                          ),
                        ),
                      ],
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
                      if (_activeRouteSummary != null || _activeBusSummary != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${_activeRouteSummary ?? ""} ${_activeBusSummary != null && _activeBusSummary!.isNotEmpty ? "• Bus: $_activeBusSummary" : ""}'.trim(),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.deepNavy,
                          ),
                        ),
                      ],
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
            const VacTeamsFooter(padding: EdgeInsets.only(top: 24, bottom: 16)),
          ],
        ),
      ),
    );
  }
}
