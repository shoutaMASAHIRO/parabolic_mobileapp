import 'package:flutter/material.dart';
import '../services/stock_service.dart';
import '../services/chart_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/asset_list_view.dart';
import 'home_screen.dart' show MarketCategory;

class AlertSymbolsScreen extends StatefulWidget {
  final VoidCallback? onBack;
  const AlertSymbolsScreen({super.key, this.onBack});

  @override
  State<AlertSymbolsScreen> createState() => _AlertSymbolsScreenState();
}

class _AlertSymbolsScreenState extends State<AlertSymbolsScreen> with SingleTickerProviderStateMixin {
  final AssetService _assetService = AssetService();
  final ChartService _chartService = ChartService();
  late TabController _tabController;

  List<Map<String, dynamic>> _alertSymbols = [];
  Set<String> _favoriteSymbols = {};
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
    
    // 全銘柄を取得
    final results = await Future.wait([
      _assetService.getCryptoTickers(),
      _assetService.getForexTickers(),
      _assetService.getStockTickers(),
    ]);
    final allTickers = [...results[0], ...results[1], ...results[2]];

    final alertList = <Map<String, dynamic>>{};
    final favorites = <String>{};

    // 全銘柄の閾値設定を確認
    await Future.wait(allTickers.map((ticker) async {
      final symbol = ticker['symbol'] as String;
      final thresholds = await _chartService.getAllThresholdsFromServer(symbol);
      
      if (thresholds.isNotEmpty) {
        // "favorite" 以外の閾値（＝アラート設定）があるかチェック
        bool hasAlert = thresholds.keys.any((k) => k != 'favorite');
        if (hasAlert) {
          alertList.add({
            'symbol': symbol,
            'displayName': ticker['displayName'] ?? symbol,
            'category': _guessCategory(symbol),
          });
        }
        // お気に入り状態も併せて保持
        if (thresholds['favorite'] == 1.0) {
          favorites.add(symbol);
        }
      }
    }));

    if (mounted) {
      setState(() {
        _alertSymbols = alertList.toList();
        _favoriteSymbols = favorites;
        _isLoading = false;
      });
    }
  }

  String _guessCategory(String symbol) {
    if (symbol.contains('-USD')) return 'crypto';
    if (symbol.contains('=X')) return 'forex';
    return 'stock';
  }

  List<Map<String, dynamic>> _getFilteredAlerts(MarketCategory category) {
    return _alertSymbols.where((item) {
      final symbol = item['symbol'] as String;
      if (category == MarketCategory.crypto) return symbol.contains('-USD');
      if (category == MarketCategory.forex) return symbol.contains('=X');
      return !symbol.contains('-USD') && !symbol.contains('=X');
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        title: const Text('通知設定中', style: AppTextStyles.headline3),
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
          tabs: MarketCategory.values.map((cat) => Tab(text: cat.label)).toList(),
        ),
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : TabBarView(
              controller: _tabController,
              children: MarketCategory.values.map((cat) {
                final filteredData = _getFilteredAlerts(cat);
                return AssetListView(
                  category: cat,
                  data: filteredData,
                  notifiedSymbols: _alertSymbols.map((e) => e['symbol'] as String).toSet(),
                  favoriteSymbols: _favoriteSymbols,
                  onRefresh: _loadData,
                  showAddButton: false,
                  onAddPressed: () {},
                );
              }).toList(),
            ),
    );
  }
}
