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
  bool _isSearchVisible = false;

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
      body: Stack(
        children: [
          _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    AssetListView(category: MarketCategory.crypto, data: _cryptoData, notifiedSymbols: _notifiedSymbols, favoriteSymbols: _favoriteSymbols, onRefresh: _loadData, onAddPressed: () {}, showAddButton: false),
                    AssetListView(category: MarketCategory.forex, data: _forexData, notifiedSymbols: _notifiedSymbols, favoriteSymbols: _favoriteSymbols, onRefresh: _loadData, onAddPressed: () {}, showAddButton: false),
                    AssetListView(category: MarketCategory.stock, data: _stockData, notifiedSymbols: _notifiedSymbols, favoriteSymbols: _favoriteSymbols, onRefresh: _loadData, onAddPressed: () {}, showAddButton: false),
                  ],
                ),
          
          // Slide-out Search Panel (Centered)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutBack,
            left: MediaQuery.of(context).size.width * 0.075,
            // Use a much larger negative value to ensure it's completely off-screen
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
                    category: MarketCategory.values[_tabController.index],
                    currentSymbols: _getCurrentSymbols(MarketCategory.values[_tabController.index]),
                    onAssetAdded: _loadData,
                    onClose: () => setState(() => _isSearchVisible = false),
                  ),
                ),
              ),
            ),
          ),

          // Floating Search Button in Bottom Left
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
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return RotationTransition(
                    turns: Tween<double>(begin: 0.75, end: 1.0).animate(animation),
                    child: ScaleTransition(scale: animation, child: child),
                  );
                },
                child: Icon(
                  _isSearchVisible ? Icons.close : Icons.search,
                  key: ValueKey<bool>(_isSearchVisible),
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Set<String> _getCurrentSymbols(MarketCategory category) {
    switch (category) {
      case MarketCategory.crypto: return _cryptoData.map((e) => e['symbol'] as String).toSet();
      case MarketCategory.forex: return _forexData.map((e) => e['symbol'] as String).toSet();
      case MarketCategory.stock: return _stockData.map((e) => e['symbol'] as String).toSet();
    }
  }

  Future<void> _showAssetSearch(MarketCategory category) async {
    setState(() {
      _isSearchVisible = true;
    });
  }
}
