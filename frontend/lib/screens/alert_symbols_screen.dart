import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../providers/market_data_provider.dart';
import '../widgets/asset_list_view.dart';
import 'home_screen.dart' show MarketCategory;

class AlertSymbolsScreen extends StatefulWidget {
  final TabController tabController;
  final VoidCallback? onBack;
  const AlertSymbolsScreen({super.key, required this.tabController, this.onBack});

  @override
  State<AlertSymbolsScreen> createState() => _AlertSymbolsScreenState();
}

class _AlertSymbolsScreenState extends State<AlertSymbolsScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer<MarketDataProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading && provider.notifiedSymbols.isEmpty) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }

        return TabBarView(
          controller: widget.tabController,
          children: MarketCategory.values.map((cat) {
            final filteredData = _getFilteredAlerts(provider, cat);
            return AssetListView(
              category: cat,
              data: filteredData,
              notifiedSymbols: provider.notifiedSymbols,
              favoriteSymbols: provider.favoriteSymbols,
              onRefresh: () => provider.refreshAllData(force: true),
              showAddButton: false,
              onAddPressed: () {},
            );
          }).toList(),
        );
      },
    );
  }

  List<Map<String, dynamic>> _getFilteredAlerts(MarketDataProvider provider, MarketCategory category) {
    final allData = [...provider.cryptoData, ...provider.forexData, ...provider.stockData];
    
    return allData
        .where((item) => provider.notifiedSymbols.contains(item['symbol']))
        .where((item) {
          final symbol = item['symbol'] as String;
          if (category == MarketCategory.crypto) return symbol.contains('-USD');
          if (category == MarketCategory.forex) return symbol.contains('=X');
          return !symbol.contains('-USD') && !symbol.contains('=X');
        })
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}
