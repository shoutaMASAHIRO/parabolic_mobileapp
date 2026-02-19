import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_colors.dart';
import '../providers/market_data_provider.dart';
import '../widgets/asset_list_view.dart';
import '../widgets/asset_search_sheet.dart';
import '../services/stock_service.dart';
import 'home_screen.dart' show MarketCategory;

class MarketListScreen extends StatefulWidget {
  final MarketCategory initialCategory;
  final TabController tabController;
  final VoidCallback? onBack; 
  const MarketListScreen({super.key, required this.initialCategory, required this.tabController, this.onBack});

  @override
  State<MarketListScreen> createState() => _MarketListScreenState();
}

class _MarketListScreenState extends State<MarketListScreen> {
  final AssetService _assetService = AssetService();
  bool _isSearchVisible = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<MarketDataProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading && provider.cryptoData.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        return Stack(
          children: [
            TabBarView(
              controller: widget.tabController,
              children: [
                AssetListView(
                  category: MarketCategory.crypto,
                  data: provider.cryptoData,
                  notifiedSymbols: provider.notifiedSymbols,
                  favoriteSymbols: provider.favoriteSymbols,
                  onRefresh: () => provider.refreshAllData(force: true),
                  showAddButton: false,
                  onAddPressed: () {},
                ),
                AssetListView(
                  category: MarketCategory.forex,
                  data: provider.forexData,
                  notifiedSymbols: provider.notifiedSymbols,
                  favoriteSymbols: provider.favoriteSymbols,
                  onRefresh: () => provider.refreshAllData(force: true),
                  showAddButton: false,
                  onAddPressed: () {},
                ),
                AssetListView(
                  category: MarketCategory.stock,
                  data: provider.stockData,
                  notifiedSymbols: provider.notifiedSymbols,
                  favoriteSymbols: provider.favoriteSymbols,
                  onRefresh: () => provider.refreshAllData(force: true),
                  showAddButton: false,
                  onAddPressed: () {},
                ),
              ],
            ),
            
            AnimatedPositioned(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutBack,
              left: MediaQuery.of(context).size.width * 0.075,
              bottom: _isSearchVisible 
                  ? (MediaQuery.of(context).viewInsets.bottom > 0 ? MediaQuery.of(context).viewInsets.bottom + 10 : 80) 
                  : -1000,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isSearchVisible ? 1.0 : 0.0,
                child: IgnorePointer(
                  ignoring: !_isSearchVisible,
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width * 0.85,
                    child: AssetSearchSheet(
                      assetService: _assetService,
                      category: MarketCategory.values[widget.tabController.index],
                      currentSymbols: _getCurrentSymbols(provider, MarketCategory.values[widget.tabController.index]),
                      onAssetAdded: () => provider.refreshAllData(force: true),
                      onClose: () => setState(() => _isSearchVisible = false),
                    ),
                  ),
                ),
              ),
            ),

            Positioned(
              left: 16,
              bottom: 16,
              child: FloatingActionButton(
                heroTag: 'search_fab',
                backgroundColor: _isSearchVisible ? AppColors.error : AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_isSearchVisible ? 12 : 28),
                ),
                onPressed: () {
                  setState(() {
                    _isSearchVisible = !_isSearchVisible;
                  });
                },
                child: Icon(
                  _isSearchVisible ? Icons.close : Icons.search,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Set<String> _getCurrentSymbols(MarketDataProvider provider, MarketCategory category) {
    return provider.getDataByCategory(category).map((e) => e['symbol'] as String).toSet();
  }
}
