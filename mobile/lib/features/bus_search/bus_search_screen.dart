import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/network/api_config.dart';
import '../../core/storage/app_state_storage.dart';
import '../../shared/models/bus_model.dart';
import '../../shared/models/route_model.dart';
import '../../shared/models/trip_model.dart';
import '../../shared/repositories/bus_repository.dart';
import '../../shared/widgets/bus_card.dart';
import '../../shared/widgets/journey_search_card.dart';
import '../../shared/widgets/vac_teams_footer.dart';
import '../live_tracking/live_tracking_screen.dart';

class BusSearchScreen extends StatefulWidget {
  final String? initialFrom;
  final String? initialTo;

  const BusSearchScreen({super.key, this.initialFrom, this.initialTo});

  @override
  State<BusSearchScreen> createState() => _BusSearchScreenState();
}

class _BusSearchScreenState extends State<BusSearchScreen> {
  final BusRepository _busRepository = BusRepository();
  late TextEditingController _fromController;
  late TextEditingController _toController;

  BusServiceType? _selectedServiceType;
  List<RouteModel> _matchedRoutes = [];
  List<TripModel> _matchedTrips = [];
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fromController = TextEditingController(text: widget.initialFrom ?? '');
    _toController = TextEditingController(text: widget.initialTo ?? '');
    _initSearchAndRestore();
  }

  Future<void> _initSearchAndRestore() async {
    if (widget.initialFrom == null && widget.initialTo == null) {
      final saved = await AppStateStorage.getSearchQuery();
      if (mounted) {
        if (saved['source']?.isNotEmpty == true) {
          _fromController.text = saved['source']!;
        }
        if (saved['destination']?.isNotEmpty == true) {
          _toController.text = saved['destination']!;
        }
      }
    }
    _executeSearch();
  }

  @override
  void dispose() {
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
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
          _matchedRoutes = routes;
          _matchedTrips = trips;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Could not connect to KKRTC server at ${ApiConfig.activeBaseUrl}. Please ensure the Django backend is running and reachable.';
        });
      }
    }
  }

  void _showServerConfigDialog() {
    final textController = TextEditingController(text: ApiConfig.activeBaseUrl);
    showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Configure API Address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your computer’s LAN IP for physical device testing (e.g., http://192.168.1.100:8000/api):',
              style: TextStyle(fontSize: 13, color: AppColors.secondaryText),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              decoration: const InputDecoration(
                labelText: 'API Base URL',
                hintText: 'http://<HOST_IP>:8000/api',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogCtx).pop(textController.text.trim()),
            child: const Text('Save & Reconnect'),
          ),
        ],
      ),
    ).then((newUrl) async {
      textController.dispose();
      if (newUrl != null && newUrl.isNotEmpty && mounted) {
        ApiConfig.activeBaseUrl = newUrl;
        await AppStateStorage.saveBaseUrl(newUrl);
        _executeSearch();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamBackground,
      appBar: AppBar(
        title: const Text(
          AppStrings.searchBuses,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: AppColors.midnightNavy,
        foregroundColor: AppColors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_ethernet_rounded),
            tooltip: 'Server Connection Settings',
            onPressed: _showServerConfigDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Consolidated Search Box
          JourneySearchCard(
            fromController: _fromController,
            toController: _toController,
            compact: true,
            onSearch: _executeSearch,
            onSwap: _executeSearch,
          ),

          // 2. Service Filter Chips
          _buildFilterChips(),

          // 3. Results Header & List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildResultsList(),
          ),
          const VacTeamsFooter(
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      color: AppColors.darkBlue,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip(
              label: 'All Routes & Trips',
              isSelected: _selectedServiceType == null,
              onSelected: () => setState(() => _selectedServiceType = null),
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              label: BusServiceType.karnatakaSarige.label,
              isSelected:
                  _selectedServiceType == BusServiceType.karnatakaSarige,
              onSelected: () => setState(
                () => _selectedServiceType = BusServiceType.karnatakaSarige,
              ),
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              label: BusServiceType.kalyanaRatha.label,
              isSelected: _selectedServiceType == BusServiceType.kalyanaRatha,
              onSelected: () => setState(
                () => _selectedServiceType = BusServiceType.kalyanaRatha,
              ),
            ),
            const SizedBox(width: 8),
            _buildFilterChip(
              label: BusServiceType.express.label,
              isSelected: _selectedServiceType == BusServiceType.express,
              onSelected: () =>
                  setState(() => _selectedServiceType = BusServiceType.express),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      selectedColor: AppColors.brightCyan,
      backgroundColor: AppColors.deepNavy,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: isSelected ? AppColors.deepNavy : AppColors.white,
      ),
      side: BorderSide(
        color: isSelected ? AppColors.brightCyan : AppColors.oceanBlue,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Widget _buildResultsList() {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                size: 54,
                color: AppColors.errorRed,
              ),
              const SizedBox(height: 14),
              const Text(
                'Connection Error',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.secondaryText,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _showServerConfigDialog,
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text('Change Server IP'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _executeSearch,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (_matchedRoutes.isEmpty && _matchedTrips.isEmpty) {
      final from = _fromController.text.trim();
      final to = _toController.text.trim();
      final queryText = (from.isNotEmpty || to.isNotEmpty)
          ? '${from.isNotEmpty ? from : "Any"} → ${to.isNotEmpty ? to : "Any"}'
          : 'your search criteria';

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: AppColors.softYellow,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.route_outlined,
                  size: 40,
                  color: AppColors.deepNavy,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'No Routes Found',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'No KKRTC routes currently match $queryText. Try searching popular transit hubs like Bengaluru, Ballari, Tumakuru, or Hostel.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.secondaryText,
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () {
                  _fromController.clear();
                  _toController.clear();
                  _executeSearch();
                },
                icon: const Icon(Icons.clear_all_rounded),
                label: const Text('View All Active Routes'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. Live Running Trips (if any exist)
        if (_matchedTrips.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Live Operating Buses',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.deepNavy,
              ),
            ),
          ),
          ..._matchedTrips.map((trip) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: BusCard(
                trip: trip,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => LiveTrackingScreen(trip: trip),
                    ),
                  );
                },
              ),
            );
          }),
          const SizedBox(height: 16),
        ],

        // 2. Official Routes from PostgreSQL Database
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Verified KKRTC Corridors (${_matchedRoutes.length})',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.deepNavy,
                ),
              ),
              const Text(
                'Official Data',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.transportOrange,
                ),
              ),
            ],
          ),
        ),

        ..._matchedRoutes.map((route) => _buildRouteItem(route)),
      ],
    );
  }

  Widget _buildRouteItem(RouteModel route) {
    final viaStops = route.intermediateStops.map((s) => s.nameEn).join(' • ');

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.borderSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Route ID & Distance
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.warmLightYellow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.softYellow),
                  ),
                  child: Text(
                    'Route ID: ${route.routeNumber}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.deepNavy,
                    ),
                  ),
                ),
                Text(
                  route.distanceKm > 0
                      ? '${route.distanceKm.toStringAsFixed(1)} km'
                      : 'Active corridor',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Route Origin & Destination Corridor
            Row(
              children: [
                const Icon(
                  Icons.trip_origin_rounded,
                  size: 16,
                  color: AppColors.successGreen,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    route.sourceName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryText,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: AppColors.mutedBlueGrey,
                  ),
                ),
                const Icon(
                  Icons.location_on_rounded,
                  size: 16,
                  color: AppColors.transportOrange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    route.destinationName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryText,
                    ),
                  ),
                ),
              ],
            ),

            // Intermediate Via Stops
            if (route.intermediateStops.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.creamBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Via: ',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.secondaryText,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        viaStops,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // Trip availability notice (Preserves exact truth: Route is present, but no fake active trip synthesized)
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: AppColors.mutedBlueGrey,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'No active bus is currently operating on this route.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.mutedBlueGrey,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
