import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/stock_service.dart';
import '../services/chart_service.dart';
import '../theme/app_colors.dart';
import '../widgets/asset_list_view.dart';
import '../widgets/asset_search_sheet.dart';
import 'login_screen.dart';
import 'favorites_screen.dart';

// カテゴリ定義
enum MarketCategory {
  crypto('暗号資産', Icons.currency_bitcoin),
  forex('外国為替', Icons.currency_exchange),
  stock('株式', Icons.show_chart);

  final String label;
  final IconData icon;
  const MarketCategory(this.label, this.icon);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  final AssetService _assetService = AssetService();
  final ChartService _chartService = ChartService();
  late TabController _tabController;

  List<dynamic> _cryptoData = [];
  List<dynamic> _forexData = [];
  List<dynamic> _stockData = [];
  Set<String> _notifiedSymbols = {};
  Set<String> _favoriteSymbols = {};

  bool _isLoading = true;
  String? _error;
  int _currentIndex = 0;

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
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _api.get('/api/crypto/tickers'),
        _api.get('/api/forex/tickers'),
        _api.get('/api/stock/tickers'),
      ]);

      if (results[0].isSuccess && results[1].isSuccess && results[2].isSuccess) {
        final crypto = results[0].jsonList ?? [];
        final forex = results[1].jsonList ?? [];
        final stock = results[2].jsonList ?? [];

        final allSymbols = [
          ...crypto.map((e) => e is Map ? e['symbol'] as String : e.toString()),
          ...forex.map((e) => e is Map ? e['symbol'] as String : e.toString()),
          ...stock.map((e) => e is Map ? e['symbol'] as String : e.toString()),
        ];

        final notified = <String>{};
        final favorites = <String>{};
        await Future.wait(allSymbols.map((symbol) async {
          final thresholds = await _chartService.getAllThresholdsFromServer(symbol);
          if (thresholds.isNotEmpty) {
            bool hasNotif = thresholds.keys.any((k) => k != 'favorite');
            bool isFav = thresholds['favorite'] == 1.0;
            if (hasNotif) notified.add(symbol);
            if (isFav) favorites.add(symbol);
            print('DEBUG: $symbol - hasNotif: $hasNotif, isFav: $isFav'); // 判定結果を出力
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
      } else {
        if (mounted) setState(() { _error = 'Failed to load data'; _isLoading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _handleLogout() async {
    await context.read<AuthProvider>().logout();
    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: _currentIndex == 0
          ? AppBar(
              title: const Text('Parabolic'),
              elevation: 0,
              bottom: TabBar(
                controller: _tabController,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.primary,
                indicatorWeight: 3,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                tabs: MarketCategory.values.map((cat) => Tab(text: cat.label)).toList(),
              ),
              actions: [
                IconButton(icon: const Icon(Icons.notifications_none), onPressed: () {}),
                PopupMenuButton<String>(
                  onSelected: (value) { if (value == 'logout') _handleLogout(); },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'logout', child: Row(children: [Icon(Icons.logout, size: 20), SizedBox(width: 8), Text('ログアウト')])),
                  ],
                ),
              ],
            )
          : null,
      body: _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'ホーム'),
          BottomNavigationBarItem(icon: Icon(Icons.show_chart), label: '保有/履歴'),
          BottomNavigationBarItem(icon: Icon(Icons.account_circle), label: 'アカウント'),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_currentIndex == 1) {
      return const FavoritesScreen();
    }
    if (_currentIndex != 0) {
      return Center(child: Text(_currentIndex == 1 ? '保有/履歴画面 (未実装)' : 'アカウント画面 (未実装)', style: const TextStyle(color: AppColors.textSecondary)));
    }
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.error_outline, size: 48, color: AppColors.error), const SizedBox(height: 16),
        Text(_error!, textAlign: TextAlign.center), const SizedBox(height: 16),
        ElevatedButton(onPressed: _loadData, child: const Text('再試行')),
      ]));
    }

    return TabBarView(
      controller: _tabController,
      children: [
        AssetListView(category: MarketCategory.crypto, data: _cryptoData, notifiedSymbols: _notifiedSymbols, favoriteSymbols: _favoriteSymbols, onRefresh: _loadData, onAddPressed: () => _showAssetSearch(MarketCategory.crypto)),
        AssetListView(category: MarketCategory.forex, data: _forexData, notifiedSymbols: _notifiedSymbols, favoriteSymbols: _favoriteSymbols, onRefresh: _loadData, onAddPressed: () => _showAssetSearch(MarketCategory.forex)),
        AssetListView(category: MarketCategory.stock, data: _stockData, notifiedSymbols: _notifiedSymbols, favoriteSymbols: _favoriteSymbols, onRefresh: _loadData, onAddPressed: () => _showAssetSearch(MarketCategory.stock)),
      ],
    );
  }

  Future<void> _showAssetSearch(MarketCategory category) async {
    Set<String> currentSymbols;
    switch (category) {
      case MarketCategory.crypto: currentSymbols = _cryptoData.map((e) => e is Map ? e['symbol'] as String : e.toString()).toSet(); break;
      case MarketCategory.forex: currentSymbols = _forexData.map((e) => e is Map ? e['symbol'] as String : e.toString()).toSet(); break;
      case MarketCategory.stock: currentSymbols = _stockData.map((e) => e is Map ? e['symbol'] as String : e.toString()).toSet(); break;
    }

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AssetSearchSheet(
        assetService: _assetService,
        category: category,
        currentSymbols: currentSymbols,
        onAssetAdded: _loadData,
      ),
    );
  }
}
