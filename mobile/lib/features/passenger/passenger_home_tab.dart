import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/storage/app_state_storage.dart';
import '../../shared/models/route_model.dart';
import '../../shared/models/trip_model.dart';
import '../../shared/repositories/bus_repository.dart';
import '../../shared/widgets/journey_search_card.dart';
import '../../shared/widgets/kkrtc_logo.dart';
import '../../shared/widgets/osm_map_panel.dart';
import '../../shared/widgets/vac_teams_footer.dart';
import '../live_tracking/live_tracking_screen.dart';

/// Unified Passenger Home screen merging Journey Search, Interactive OpenStreetMap,
/// and live matching routes retrieved from Django APIs into a single user-friendly experience.
class PassengerHomeTab extends StatefulWidget {
  final Function(int)? onNavigateTab;
  final VoidCallback? onNavigateToProfile;

  const PassengerHomeTab({
    super.key,
    this.onNavigateTab,
    this.onNavigateToProfile,
  });

  @override
  State<PassengerHomeTab> createState() => _PassengerHomeTabState();
}

class _PassengerHomeTabState extends State<PassengerHomeTab> {
  final BusRepository _busRepository = BusRepository();
  late final TextEditingController _fromController;
  late final TextEditingController _toController;

  List<RouteModel> _routes = [];
  List<TripModel> _activeTrips = [];
  RouteModel? _selectedRoute;

  bool _isLoading = false;
  bool _isMapExpanded = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fromController = TextEditingController();
    _toController = TextEditingController();
    _initSearchAndRestore();
  }

  Future<void> _initSearchAndRestore() async {
    final saved = await AppStateStorage.getSearchQuery();
    if (mounted) {
      if (saved['source']?.isNotEmpty == true) {
        _fromController.text = saved['source']!;
      }
      if (saved['destination']?.isNotEmpty == true) {
        _toController.text = saved['destination']!;
      }
    }
    await _executeSearch();
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  String _getTimeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return AppStrings.greetingMorning;
    if (hour < 17) return AppStrings.greetingAfternoon;
    return AppStrings.greetingEvening;
  }

  Future<void> _executeSearch() async {
    final from = _fromController.text.trim();
    final to = _toController.text.trim();

    await AppStateStorage.saveSearchQuery(source: from, destination: to);

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final routesFuture = _busRepository.searchRoutes(
        fromStop: from,
        toStop: to,
      );
      final tripsFuture = _busRepository.searchTrips(
        fromStop: from,
        toStop: to,
      );

      final routes = await routesFuture;
      final trips = await tripsFuture;

      if (mounted) {
        setState(() {
          _routes = routes;
          _activeTrips = trips;
          _isLoading = false;
          // If a single route matches, automatically select it for map preview
          if (routes.isNotEmpty && (from.isNotEmpty || to.isNotEmpty)) {
            _selectedRoute = routes.first;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Unable to connect to KKRTC server. Check your connection or server IP in Profile.';
        });
      }
    }
  }

  void _clearSearch() {
    _fromController.clear();
    _toController.clear();
    setState(() => _selectedRoute = null);
    _executeSearch();
  }

  void _selectRouteOnMap(RouteModel route) {
    setState(() {
      _selectedRoute = route;
      _isMapExpanded = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Viewing corridor ${route.routeName} on map'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  List<LatLng> _getRouteCoordinates(RouteModel? route) {
    if (route == null) return const [];
    final coords = <LatLng>[];

    // Origin
    if (route.sourceLatitude != null && route.sourceLongitude != null) {
      coords.add(LatLng(route.sourceLatitude!, route.sourceLongitude!));
    }

    // Intermediate Via stops
    for (final stop in route.intermediateStops) {
      if (stop.latitude != 0.0 && stop.longitude != 0.0) {
        coords.add(LatLng(stop.latitude, stop.longitude));
      }
    }

    // Destination
    if (route.destinationLatitude != null &&
        route.destinationLongitude != null) {
      coords.add(
        LatLng(route.destinationLatitude!, route.destinationLongitude!),
      );
    }

    return coords;
  }

  @override
  Widget build(BuildContext context) {
    final routeCoords = _getRouteCoordinates(_selectedRoute);
    final hasSearchTerms =
        _fromController.text.isNotEmpty || _toController.text.isNotEmpty;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _executeSearch,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Header with greeting, KKRTC logo and profile shortcut
                _buildHeader(),

                const SizedBox(height: 12),

                // 2. Integrated OpenStreetMap Panel
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildMapSection(routeCoords),
                ),

                const SizedBox(height: 16),

                // 3. Journey Search Card (Autocomplete From & To)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: JourneySearchCard(
                    fromController: _fromController,
                    toController: _toController,
                    compact: false,
                    onSearch: _executeSearch,
                    onSwap: () {
                      _executeSearch();
                    },
                  ),
                ),

                const SizedBox(height: 20),

                // 4. Live Tracking Shortcut Banner
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildLiveTrackingBanner(),
                ),

                const SizedBox(height: 24),

                // 5. Matching Routes Section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildRoutesHeader(hasSearchTerms),
                ),

                const SizedBox(height: 10),

                // 6. Routes Content (Loading / Error / Empty / Route Cards)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildRoutesContent(),
                ),

                const VacTeamsFooter(
                  padding: EdgeInsets.only(top: 24, bottom: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const KkrtcLogo(size: 38, showText: false),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getTimeGreeting(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.iceBlue
                          : AppColors.oceanBlue,
                    ),
                  ),
                  Text(
                    AppStrings.appNameShort,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.white
                          : AppColors.deepNavy,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ],
          ),
          IconButton(
            onPressed: () {
              if (widget.onNavigateToProfile != null) {
                widget.onNavigateToProfile!();
              } else if (widget.onNavigateTab != null) {
                widget.onNavigateTab!(1);
              }
            },
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.darkBlue
                    : const Color(0xFFE2E8F0),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person_rounded,
                size: 20,
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.brightCyan
                    : AppColors.deepNavy,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapSection(List<LatLng> routeCoords) {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).brightness == Brightness.dark
              ? AppColors.oceanBlue
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Map Header bar with Toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.darkBlue
                : const Color(0xFFF1F5F9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.map_rounded,
                      size: 16,
                      color: AppColors.brightCyan,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _selectedRoute != null
                          ? 'Corridor: ${_selectedRoute!.routeName}'
                          : 'OpenStreetMap Live Transit Map',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppColors.white
                            : AppColors.deepNavy,
                      ),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () => setState(() => _isMapExpanded = !_isMapExpanded),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Row(
                      children: [
                        Text(
                          _isMapExpanded ? 'Compact' : 'Expand',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brightCyan,
                          ),
                        ),
                        Icon(
                          _isMapExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 16,
                          color: AppColors.brightCyan,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // OSM Map Panel
          SizedBox(
            height: _isMapExpanded ? 320 : 190,
            child: OsmMapPanel(
              routeCoordinates: routeCoords,
              origin: routeCoords.isNotEmpty ? routeCoords.first : null,
              destination: routeCoords.length > 1 ? routeCoords.last : null,
              initialZoom: routeCoords.isNotEmpty ? 11.5 : 8.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveTrackingBanner() {
    return Card(
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const LiveTrackingScreen()),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.oceanBlue, AppColors.deepNavy],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.brightCyan.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.radar_rounded,
                  color: AppColors.brightCyan,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.liveBusTracking,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Follow active buses in real time on OpenStreetMap',
                      style: TextStyle(fontSize: 12, color: AppColors.iceBlue),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.brightCyan,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoutesHeader(bool hasSearchTerms) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasSearchTerms ? 'Matching Routes' : 'Active Corridors',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.white
                    : AppColors.deepNavy,
              ),
            ),
            Text(
              hasSearchTerms
                  ? '${_routes.length} verified corridor(s) found'
                  : 'Official KKRTC routes anywhere in Karnataka',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.brightCyan,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (hasSearchTerms)
          TextButton.icon(
            onPressed: _clearSearch,
            icon: const Icon(Icons.clear_all_rounded, size: 16),
            label: const Text('Show All', style: TextStyle(fontSize: 12)),
          ),
      ],
    );
  }

  Widget _buildRoutesContent() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.errorRed.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.errorRed.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: AppColors.errorRed,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _executeSearch,
              child: const Text('Retry Search'),
            ),
          ],
        ),
      );
    }

    if (_routes.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(
                Icons.directions_bus_outlined,
                size: 48,
                color: AppColors.mutedBlueGrey,
              ),
              const SizedBox(height: 12),
              const Text(
                'No bus routes found matching your criteria',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                'Try selecting from our available stops or clear the filter to see active corridors.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _clearSearch,
                child: const Text('Clear Filter & View Corridors'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _routes.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final route = _routes[index];
        final activeTrip = _activeTrips.cast<TripModel?>().firstWhere(
          (t) =>
              t?.route.id == route.id ||
              t?.route.routeNumber == route.routeNumber,
          orElse: () => null,
        );

        final isSelected = _selectedRoute?.id == route.id;

        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isSelected
                  ? AppColors.brightCyan
                  : (Theme.of(context).brightness == Brightness.dark
                        ? AppColors.oceanBlue
                        : const Color(0xFFE2E8F0)),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.brightCyan.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Route ID: ${route.routeNumber}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brightCyan,
                        ),
                      ),
                    ),
                    Text(
                      route.distanceKm > 0
                          ? '${route.distanceKm.toStringAsFixed(1)} km • ${route.estimatedMinutes} min'
                          : 'Official Corridor',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(
                      Icons.directions_bus_rounded,
                      size: 20,
                      color: AppColors.brightCyan,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        route.routeName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                if (route.intermediateStops.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.deepNavy
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.alt_route_rounded,
                          size: 14,
                          color: AppColors.secondaryText,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Via: ${route.intermediateStops.map((s) => s.nameEn).join(" • ")}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.secondaryText,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // Active bus broadcast notice
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: activeTrip != null
                        ? AppColors.brightCyan.withValues(alpha: 0.15)
                        : AppColors.mutedBlueGrey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        activeTrip != null
                            ? Icons.sensors_rounded
                            : Icons.sensors_off_rounded,
                        size: 16,
                        color: activeTrip != null
                            ? AppColors.brightCyan
                            : AppColors.secondaryText,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          activeTrip != null
                              ? 'Active Bus: ${activeTrip.bus.registrationNumber} • Broadcasting'
                              : 'No active bus currently broadcasting on this corridor.',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: activeTrip != null
                                ? AppColors.brightCyan
                                : AppColors.secondaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.map_rounded, size: 16),
                        label: const Text('View on Map'),
                        onPressed: () => _selectRouteOnMap(route),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.navigation_rounded, size: 16),
                        label: const Text('Track Route'),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  LiveTrackingScreen(trip: activeTrip),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
