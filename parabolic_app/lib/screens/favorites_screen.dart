import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../providers/market_data_provider.dart';
import '../widgets/asset_list_view.dart';
import 'home_screen.dart' show MarketCategory;

class FavoritesScreen extends StatefulWidget {
  final TabController tabController;
  final VoidCallback? onBack;
  const FavoritesScreen({super.key, required this.tabController, this.onBack});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer<MarketDataProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading && provider.favoriteSymbols.isEmpty) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }

        return TabBarView(
          controller: widget.tabController,
          children: MarketCategory.values.map((cat) {
            final filteredData = _getFilteredFavorites(provider, cat);
            return AssetListView(
              category: cat,
              data: filteredData,
              notifiedSymbols: provider.notifiedSymbols,
              favoriteSymbols: provider.favoriteSymbols,
              onRefresh: () => provider.refreshAllData(force: true),
              showAddButton: false,
              onAddPressed: () {
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
            );
          }).toList(),
        );
      },
    );
  }

  List<Map<String, dynamic>> _getFilteredFavorites(MarketDataProvider provider, MarketCategory category) {
    final allData = [...provider.cryptoData, ...provider.forexData, ...provider.stockData];
    
    return allData
        .where((item) => provider.favoriteSymbols.contains(item['symbol']))
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
