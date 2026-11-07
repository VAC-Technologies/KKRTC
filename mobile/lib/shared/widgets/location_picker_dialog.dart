import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../repositories/bus_repository.dart';

/// Modal dialog for searching and selecting bus stands, stops, and stations.
/// Fetches real-time autocomplete suggestions from Django APIs while typing.
/// Implemented as a dedicated StatefulWidget with debounce and safe controller lifecycle.
class LocationPickerDialog extends StatefulWidget {
  final String title;
  final String initialValue;
  final String hint;

  const LocationPickerDialog({
    super.key,
    required this.title,
    this.initialValue = '',
    this.hint = 'Enter bus stand or city name (e.g., Ballari, Bengaluru)',
  });

  static Future<String?> show(
    BuildContext context, {
    required String title,
    String initialValue = '',
    String hint = 'Enter bus stand or city name',
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => LocationPickerDialog(
        title: title,
        initialValue: initialValue,
        hint: hint,
      ),
    );
  }

  @override
  State<LocationPickerDialog> createState() => _LocationPickerDialogState();
}

class _LocationPickerDialogState extends State<LocationPickerDialog> {
  final BusRepository _busRepository = BusRepository();
  late final TextEditingController _controller;
  Timer? _debounceTimer;

  List<Map<String, dynamic>> _suggestions = [];
  bool _isLoading = false;
  bool _hasSearched = false;

  static const List<Map<String, String>> _fallbackStops = [
    {'name': 'Bengaluru (Majestic)', 'type': 'Bus Station / Origin'},
    {'name': 'Ballari (Central Bus Stand)', 'type': 'Bus Station / Origin'},
    {'name': 'Tumakuru', 'type': 'Via Stop'},
    {'name': 'Chitradurga', 'type': 'Via Stop'},
    {'name': 'Vijayanagara (Hosapete)', 'type': 'Bus Station'},
    {'name': 'Kampli', 'type': 'Bus Station / Destination'},
    {'name': 'Hubballi (CBT)', 'type': 'Bus Station'},
    {'name': 'Kalaburagi (Central)', 'type': 'Bus Station / Origin'},
    {'name': 'Raichur', 'type': 'Bus Station'},
    {'name': 'Hostel', 'type': 'Bus Station / Origin'},
    {'name': 'Vinayak temple', 'type': 'Bus Station / Destination'},
    {'name': 'T -Shop', 'type': 'Via Stop'},
    {'name': 'Kuduthini', 'type': 'Via Stop'},
    {'name': 'Hosa Daroji', 'type': 'Via Stop'},
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _fetchSuggestions(widget.initialValue);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        _fetchSuggestions(value.trim());
      }
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    setState(() {
      _isLoading = true;
      _hasSearched = true;
    });

    try {
      final remote = await _busRepository.fetchLocationSuggestions(query);
      if (remote.isNotEmpty && mounted) {
        setState(() {
          _suggestions = remote;
          _isLoading = false;
        });
        return;
      }
    } catch (_) {}

    // Fallback search over verified Karnataka stops
    if (mounted) {
      final queryLower = query.toLowerCase();
      final filtered = _fallbackStops
          .where((s) {
            if (queryLower.isEmpty) return true;
            return s['name']!.toLowerCase().contains(queryLower);
          })
          .map((s) => {'name': s['name']!, 'type': s['type']!})
          .toList();

      setState(() {
        _suggestions = filtered;
        _isLoading = false;
      });
    }
  }

  void _submit([String? selected]) {
    final text = selected ?? _controller.text.trim();
    if (mounted) {
      Navigator.of(context).pop(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: AppColors.white,
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.softYellow,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.place_rounded,
              color: AppColors.deepNavy,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.midnightNavy,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.midnightNavy,
              ),
              decoration: InputDecoration(
                hintText: widget.hint,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _controller.clear();
                          _fetchSuggestions('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppColors.creamBackground,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.borderSubtle),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.deepNavy,
                    width: 1.5,
                  ),
                ),
              ),
              onChanged: _onTextChanged,
              onSubmitted: (_) => _submit(),
            ),

            const SizedBox(height: 12),

            // Autocomplete Results or Loading or No Results
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Searching stops...',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.secondaryText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            else if (_suggestions.isNotEmpty) ...[
              const Text(
                'Suggestions',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.secondaryText,
                ),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _suggestions[index];
                    final name = item['name'] as String? ?? '';
                    final type = item['type'] as String? ?? 'Bus Stop';

                    return InkWell(
                      onTap: () {
                        _controller.text = name;
                        _submit(name);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 4,
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppColors.creamBackground,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.directions_bus_rounded,
                                size: 16,
                                color: AppColors.deepNavy,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryText,
                                    ),
                                  ),
                                  Text(
                                    type,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.secondaryText,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.north_west_rounded,
                              size: 16,
                              color: AppColors.secondaryText,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ] else if (_hasSearched && _controller.text.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    "No bus stops found matching '${_controller.text.trim()}'.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.secondaryText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: AppColors.secondaryText),
          ),
        ),
        FilledButton(
          onPressed: () => _submit(),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.deepNavy,
            foregroundColor: AppColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
