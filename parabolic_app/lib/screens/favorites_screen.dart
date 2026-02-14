import 'package:flutter/material.dart';
import '../services/stock_service.dart';
import '../services/chart_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/asset_list_view.dart';
import 'home_screen.dart' show MarketCategory;
import 'dart:math';

class FavoritesScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const FavoritesScreen({super.key, this.onBack});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> with SingleTickerProviderStateMixin {
  final AssetService _assetService = AssetService();
  final ChartService _chartService = ChartService();
  late TabController _tabController;

  List<Map<String, dynamic>> _allFavorites = [];
  Set<String> _notifiedSymbols = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: MarketCategory.values.length, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final data = await _assetService.getFavorites();
    
    final notified = <String>{};
    await Future.wait(data.map((item) async {
      final symbol = item['symbol'] as String;
      final thresholds = await _chartService.getAllThresholdsFromServer(symbol);
      if (thresholds.keys.any((k) => k != 'favorite')) {
        notified.add(symbol);
      }
    }));

    if (mounted) {
      setState(() {
        _allFavorites = List<Map<String, dynamic>>.from(data);
        _notifiedSymbols = notified;
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _getFilteredFavorites(MarketCategory category) {
    return _allFavorites.where((item) {
      final symbol = item['symbol'] as String? ?? '';
      final categoryStr = (item['category'] as String? ?? '').toLowerCase();
      
      if (category == MarketCategory.crypto) {
        return categoryStr == 'crypto' || symbol.contains('-USD');
      } else if (category == MarketCategory.forex) {
        return categoryStr == 'forex' || symbol.contains('=X');
      } else {
        return categoryStr == 'stock' || (!symbol.contains('-USD') && !symbol.contains('=X'));
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        title: const Text('保有 / お気に入り', style: AppTextStyles.headline3),
        backgroundColor: AppColors.scaffoldBackground,
        elevation: 0,
        centerTitle: true,
        leading: widget.onBack != null 
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                onPressed: widget.onBack,
              )
            : null,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          tabs: MarketCategory.values.map((cat) {
            Color iconColor;
            switch (cat) {
              case MarketCategory.crypto: iconColor = AppColors.crypto; break;
              case MarketCategory.forex: iconColor = AppColors.forex; break;
              case MarketCategory.stock: iconColor = AppColors.stock; break;
            }
            return Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(cat.icon, size: 18, color: iconColor),
                  const SizedBox(width: 8),
                  Text(cat.label),
                ],
              ),
            );
          }).toList(),
        ),
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : TabBarView(
              controller: _tabController,
              children: MarketCategory.values.map((cat) {
                final filteredData = _getFilteredFavorites(cat);
                return AssetListView(
                  category: cat,
                  data: filteredData,
                  notifiedSymbols: _notifiedSymbols,
                  favoriteSymbols: _allFavorites.map((e) => e['symbol'] as String).toSet(),
                  onRefresh: _loadData,
                  showAddButton: false,
                  onAddPressed: () {
                    // 非表示にするのでこの中身は実行されません
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  },
                );
              }).toList(),
            ),
    );
  }
}
