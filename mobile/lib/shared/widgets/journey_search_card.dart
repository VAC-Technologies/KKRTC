import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../core/storage/app_state_storage.dart';
import 'custom_button.dart';
import 'location_picker_dialog.dart';

/// Consolidated, reusable journey search component used across Passenger Home and Search screens.
/// Guarantees consistent From & To selection, synchronized state persistence,
/// and smooth location swapping without duplicating forms or lifecycle logic.
class JourneySearchCard extends StatefulWidget {
  final TextEditingController fromController;
  final TextEditingController toController;
  final VoidCallback onSearch;
  final VoidCallback? onSwap;
  final bool compact;
  final bool showSearchButton;

  const JourneySearchCard({
    super.key,
    required this.fromController,
    required this.toController,
    required this.onSearch,
    this.onSwap,
    this.compact = false,
    this.showSearchButton = true,
  });

  @override
  State<JourneySearchCard> createState() => _JourneySearchCardState();
}

class _JourneySearchCardState extends State<JourneySearchCard> {
  void _swapStops() {
    final temp = widget.fromController.text;
    widget.fromController.text = widget.toController.text;
    widget.toController.text = temp;

    AppStateStorage.saveSearchQuery(
      source: widget.fromController.text.trim(),
      destination: widget.toController.text.trim(),
    );

    widget.onSwap?.call();
    setState(() {});
  }

  Future<void> _pickLocation({required bool isFrom}) async {
    final title = isFrom ? 'Select Starting Stop' : 'Select Destination Stop';
    final initial = isFrom
        ? widget.fromController.text
        : widget.toController.text;

    final selected = await LocationPickerDialog.show(
      context,
      title: title,
      initialValue: initial,
    );

    if (selected != null && mounted) {
      if (isFrom) {
        widget.fromController.text = selected;
      } else {
        widget.toController.text = selected;
      }
      AppStateStorage.saveSearchQuery(
        source: widget.fromController.text.trim(),
        destination: widget.toController.text.trim(),
      );
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) {
      return _buildCompactSearch();
    }
    return _buildFullSearchCard();
  }

  Widget _buildFullSearchCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.warmLightYellow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.softYellow, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepNavy.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                AppStrings.searchCardTitle,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.midnightNavy,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.deepNavy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.directions_bus_rounded,
                      size: 14,
                      color: AppColors.deepNavy,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'KKRTC Routes',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.deepNavy,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Search Inputs with Swap Button
          Stack(
            alignment: Alignment.centerRight,
            children: [
              Column(
                children: [
                  _buildStopRow(
                    label: AppStrings.fromStop,
                    value: widget.fromController.text,
                    hint: 'Origin bus stand or city',
                    icon: Icons.trip_origin_rounded,
                    iconColor: AppColors.successGreen,
                    onTap: () => _pickLocation(isFrom: true),
                  ),
                  const SizedBox(height: 10),
                  _buildStopRow(
                    label: AppStrings.toStop,
                    value: widget.toController.text,
                    hint: 'Destination bus stand or city',
                    icon: Icons.location_on_rounded,
                    iconColor: AppColors.transportOrange,
                    onTap: () => _pickLocation(isFrom: false),
                  ),
                ],
              ),
              Positioned(
                right: 12,
                child: Material(
                  color: AppColors.white,
                  elevation: 2,
                  shape: const CircleBorder(
                    side: BorderSide(color: AppColors.borderSubtle),
                  ),
                  child: InkWell(
                    onTap: _swapStops,
                    customBorder: const CircleBorder(),
                    child: const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Icon(
                        Icons.swap_vert_rounded,
                        size: 20,
                        color: AppColors.deepNavy,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (widget.showSearchButton) ...[
            const SizedBox(height: 18),
            CustomButton(
              text: AppStrings.searchBuses,
              icon: Icons.search_rounded,
              backgroundColor: AppColors.deepNavy,
              onPressed: () {
                AppStateStorage.saveSearchQuery(
                  source: widget.fromController.text.trim(),
                  destination: widget.toController.text.trim(),
                );
                widget.onSearch();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactSearch() {
    return Container(
      color: AppColors.midnightNavy,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.darkBlue,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.oceanBlue.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.centerRight,
              children: [
                Column(
                  children: [
                    _buildDarkStopField(
                      controller: widget.fromController,
                      label: AppStrings.fromStop,
                      hint: 'Origin bus stand',
                      icon: Icons.trip_origin_rounded,
                      iconColor: AppColors.brightCyan,
                      onTapSearch: () => _pickLocation(isFrom: true),
                    ),
                    const SizedBox(height: 10),
                    _buildDarkStopField(
                      controller: widget.toController,
                      label: AppStrings.toStop,
                      hint: 'Destination bus stand',
                      icon: Icons.location_on_rounded,
                      iconColor: AppColors.transportOrange,
                      onTapSearch: () => _pickLocation(isFrom: false),
                    ),
                  ],
                ),
                Positioned(
                  right: 10,
                  child: Material(
                    color: AppColors.deepNavy,
                    elevation: 2,
                    shape: const CircleBorder(
                      side: BorderSide(color: AppColors.oceanBlue),
                    ),
                    child: InkWell(
                      onTap: _swapStops,
                      customBorder: const CircleBorder(),
                      child: const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Icon(
                          Icons.swap_vert_rounded,
                          size: 18,
                          color: AppColors.brightCyan,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (widget.showSearchButton) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    AppStateStorage.saveSearchQuery(
                      source: widget.fromController.text.trim(),
                      destination: widget.toController.text.trim(),
                    );
                    widget.onSearch();
                  },
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text(
                    AppStrings.searchBuses,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brightCyan,
                    foregroundColor: AppColors.deepNavy,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStopRow({
    required String label,
    required String value,
    required String hint,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.darkBlue,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.softYellow),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.secondaryText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    value.isEmpty ? hint : value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: value.isEmpty
                          ? AppColors.mutedBlueGrey
                          : AppColors.primaryText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.mutedBlueGrey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDarkStopField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTapSearch,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.deepNavy,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.oceanBlue),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.white,
              ),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: const TextStyle(
                  fontSize: 11,
                  color: AppColors.mutedBlueGrey,
                ),
                hintText: hint,
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: AppColors.mutedBlueGrey,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
              ),
              onChanged: (_) {
                AppStateStorage.saveSearchQuery(
                  source: widget.fromController.text.trim(),
                  destination: widget.toController.text.trim(),
                );
              },
              onSubmitted: (_) => widget.onSearch(),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.list_alt_rounded,
              size: 18,
              color: AppColors.brightCyan,
            ),
            tooltip: 'Browse Stops',
            onPressed: onTapSearch,
          ),
        ],
      ),
    );
  }
}
