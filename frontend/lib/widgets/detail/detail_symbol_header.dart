import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../screens/home_screen.dart' show MarketCategory;

class DetailSymbolHeader extends StatelessWidget {
  final String symbol;
  final MarketCategory category;
  final String interval;
  final String intervalLabel;
  final bool hasCrossHistory;
  final VoidCallback onIntervalTap;
  final VoidCallback onCrossSettingsTap;

  const DetailSymbolHeader({
    super.key,
    required this.symbol,
    required this.category,
    required this.interval,
    required this.intervalLabel,
    this.hasCrossHistory = false,
    required this.onIntervalTap,
    required this.onCrossSettingsTap,
  });

  Color _getCategoryColor() {
    switch (category) {
      case MarketCategory.crypto: return AppColors.crypto;
      case MarketCategory.forex: return AppColors.forex;
      case MarketCategory.stock: return AppColors.stock;
    }
  }

  String _getDisplayName() {
    switch (category) {
      case MarketCategory.crypto: 
        return symbol.replaceAll('-USD', '');
      case MarketCategory.forex: 
        return symbol.replaceAll('=X', '').replaceAllMapped(
          RegExp(r'([A-Z]{3})([A-Z]{3})'), (m) => '${m[1]}/${m[2]}');
      case MarketCategory.stock: 
        return symbol;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(color: AppColors.chartBackground),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _getCategoryColor().withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(category.icon, size: 22, color: _getCategoryColor()),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_getDisplayName(), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text('${category.label} • $symbol', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: onIntervalTap,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2C38),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF4D88FF), width: 1.2),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 4, offset: const Offset(0, 1))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(intervalLabel, style: const TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down, color: Color(0xFFFFD54F), size: 20),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 60, height: 48,
            child: Center(
              child: GestureDetector(
                onTap: onCrossSettingsTap,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter, 
                          end: Alignment.bottomCenter, 
                          colors: [Color(0xFFF57C00), Color(0xFFE65100)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFFD54F), width: 1.5),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 6, offset: const Offset(0, 2))],
                      ),
                      child: const Icon(Icons.notifications_active, size: 24, color: Color(0xFFFFE082)),
                    ),
                    if (hasCrossHistory)
                      Positioned(
                        right: -4, top: -4,
                        child: Container(
                          width: 14, height: 14,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF3B30), 
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.0),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 2)],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
