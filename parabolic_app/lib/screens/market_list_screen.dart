import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/asset_list_view.dart';
import '../widgets/asset_search_sheet.dart';
import '../services/stock_service.dart';
import '../services/chart_service.dart';
import 'home_screen.dart' show MarketCategory;

class MarketListScreen extends StatefulWidget {
  final MarketCategory initialCategory;
  final VoidCallback? onBack; 
  const MarketListScreen({super.key, required this.initialCategory, this.onBack});

  @override
  State<MarketListScreen> createState() => _MarketListScreenState();
}

class _MarketListScreenState extends State<MarketListScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AssetService _assetService = AssetService();
  final ChartService _chartService = ChartService();

  List<dynamic> _cryptoData = [];
  List<dynamic> _forexData = [];
  List<dynamic> _stockData = [];
  Set<String> _notifiedSymbols = {};
  Set<String> _favoriteSymbols = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: MarketCategory.values.length, 
      vsync: this,
      initialIndex: widget.initialCategory.index,
    );
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _assetService.getCryptoTickers(),
        _assetService.getForexTickers(),
        _assetService.getStockTickers(),
      ]);

      final crypto = results[0];
      final forex = results[1];
      final stock = results[2];

      final allSymbols = [
        ...crypto.map((e) => e['symbol'] as String),
        ...forex.map((e) => e['symbol'] as String),
        ...stock.map((e) => e['symbol'] as String),
      ];

      final notified = <String>{};
      final favorites = <String>{};
      await Future.wait(allSymbols.map((symbol) async {
        final thresholds = await _chartService.getAllThresholdsFromServer(symbol);
        if (thresholds.isNotEmpty) {
          if (thresholds.keys.any((k) => k != 'favorite')) notified.add(symbol);
          if (thresholds['favorite'] == 1.0) favorites.add(symbol);
        }
      }));

      if (mounted) {
        setState(() {
          _cryptoData = crypto;
          _forexData = forex;
          _stockData = stock;
          _notifiedSymbols = notified;
          _favoriteSymbols = favorites;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        title: const Text('銘柄一覧', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
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
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                AssetListView(category: MarketCategory.crypto, data: _cryptoData, notifiedSymbols: _notifiedSymbols, favoriteSymbols: _favoriteSymbols, onRefresh: _loadData, onAddPressed: () => _showAssetSearch(MarketCategory.crypto)),
                AssetListView(category: MarketCategory.forex, data: _forexData, notifiedSymbols: _notifiedSymbols, favoriteSymbols: _favoriteSymbols, onRefresh: _loadData, onAddPressed: () => _showAssetSearch(MarketCategory.forex)),
                AssetListView(category: MarketCategory.stock, data: _stockData, notifiedSymbols: _notifiedSymbols, favoriteSymbols: _favoriteSymbols, onRefresh: _loadData, onAddPressed: () => _showAssetSearch(MarketCategory.stock)),
              ],
            ),
    );
  }

  Future<void> _showAssetSearch(MarketCategory category) async {
    Set<String> currentSymbols;
    switch (category) {
      case MarketCategory.crypto: currentSymbols = _cryptoData.map((e) => e['symbol'] as String).toSet(); break;
      case MarketCategory.forex: currentSymbols = _forexData.map((e) => e['symbol'] as String).toSet(); break;
      case MarketCategory.stock: currentSymbols = _stockData.map((e) => e['symbol'] as String).toSet(); break;
    }

    await showDialog(
      context: context,
      builder: (context) => AssetSearchSheet(
        assetService: _assetService,
        category: category,
        currentSymbols: currentSymbols,
        onAssetAdded: _loadData,
      ),
    );
  }
}
