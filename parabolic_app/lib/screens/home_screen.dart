import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math'; // For mock data
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/stock_service.dart';
import '../services/chart_service.dart';
import '../theme/app_colors.dart';
import '../widgets/rate_list_item.dart';
import 'login_screen.dart';
import 'detail_screen.dart';

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

  // 各カテゴリのデータ
  List<dynamic> _cryptoData = [];
  List<dynamic> _forexData = [];
  List<dynamic> _stockData = [];

  // 通知設定があるシンボルのセット
  Set<String> _notifiedSymbols = {};

  bool _isLoading = true;
  String? _error;

  int _currentIndex = 0; // BottomNav index

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
      // 暗号通貨、為替、株式のデータを並行取得
      final results = await Future.wait([
        _api.get('/api/crypto/tickers'),
        _api.get('/api/forex/tickers'),
        _api.get('/api/stock/tickers'),
      ]);

      final cryptoResponse = results[0];
      final forexResponse = results[1];
      final stockResponse = results[2];

      if (cryptoResponse.isSuccess && forexResponse.isSuccess && stockResponse.isSuccess) {
        final crypto = cryptoResponse.jsonList ?? [];
        final forex = forexResponse.jsonList ?? [];
        final stock = stockResponse.jsonList ?? [];

        // 全てのシンボルの通知設定をチェック（本来は一括取得APIが望ましいが、既存サービスを利用）
        final allSymbols = [
          ...crypto.map((e) => e is Map ? e['symbol'] as String : e.toString()),
          ...forex.map((e) => e is Map ? e['symbol'] as String : e.toString()),
          ...stock.map((e) => e is Map ? e['symbol'] as String : e.toString()),
        ];

        final notified = <String>{};
        // 並列で各シンボルの閾値設定を確認
        await Future.wait(allSymbols.map((symbol) async {
          final thresholds = await _chartService.getAllThresholdsFromServer(symbol);
          if (thresholds.isNotEmpty) {
            notified.add(symbol);
          }
        }));

        if (mounted) {
          setState(() {
            _cryptoData = crypto;
            _forexData = forex;
            _stockData = stock;
            _notifiedSymbols = notified;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Failed to load data';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleLogout() async {
    await context.read<AuthProvider>().logout();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
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
                tabs: MarketCategory.values
                    .map((cat) => Tab(text: cat.label)) // アイコンなし、テキストのみでスッキリさせる
                    .toList(),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.notifications_none),
                  onPressed: () {},
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'logout') {
                      _handleLogout();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'logout',
                      child: Row(
                        children: [
                          Icon(Icons.logout, size: 20),
                          SizedBox(width: 8),
                          Text('ログアウト'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            )
          : null, // ホーム以外はAppBarを変えるか隠す（今回は簡易実装）
      body: _buildBody(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'ホーム',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.show_chart),
            label: '保有/履歴', // GMO風
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_circle),
            label: 'アカウント',
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_currentIndex != 0) {
      return Center(
        child: Text(
          _currentIndex == 1 ? '保有/履歴画面 (未実装)' : 'アカウント画面 (未実装)',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('再試行'),
            ),
          ],
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [
        _buildAssetList(MarketCategory.crypto, _cryptoData),
        _buildAssetList(MarketCategory.forex, _forexData),
        _buildAssetList(MarketCategory.stock, _stockData),
      ],
    );
  }

  Widget _buildAssetList(MarketCategory category, List<dynamic> data) {
    return Column(
      children: [
        // ヘッダー行 (GMO風)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: AppColors.background,
          child: const Row(
            children: [
              Expanded(flex: 3, child: Text('銘柄', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
              Expanded(flex: 4, child: Text('現在地', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
              Expanded(flex: 3, child: Text('前日比', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
            ],
          ),
        ),
        Expanded(
          child: data.isEmpty
              ? Center(child: Text('${category.label}データがありません'))
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    itemCount: data.length,
                    itemBuilder: (context, index) {
                      final item = data[index];
                      final symbol = item is Map ? item['symbol'] as String : item.toString();
                      final displayName = item is Map
                          ? item['displayName'] as String
                          : symbol.replaceAll('-USD', '');
                      
                      // Mock Data Generation for Visuals
                      // TODO: Replace with real data when API provides it
                      final random = Random(symbol.hashCode);
                      final price = _generateMockPrice(category, random);
                      final change = _generateMockChange(price, random);
                      final changePercent = _generateMockChangePercent(change, price);

                      return RateListItem(
                        symbol: symbol,
                        name: displayName,
                        price: price,
                        change: change,
                        changePercent: changePercent,
                        icon: category.icon,
                        iconColor: CategoryColors.forCategoryName(category.name),
                        hasNotification: _notifiedSymbols.contains(symbol),
                        onTap: () async {
                          final result = await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => DetailScreen(
                                symbol: symbol,
                                category: category,
                              ),
                            ),
                          );
                          
                          if (result is MarketCategory) {
                            _tabController.animateTo(result.index);
                          }
                          _loadData(); // 詳細画面から戻った時に通知設定を再読み込み
                        },
                      );
                    },
                  ),
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showAssetSearch(category),
              icon: const Icon(Icons.add),
              label: Text('${category.label}を追加'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // --- Mock Data Helpers ---
  String _generateMockPrice(MarketCategory category, Random random) {
    switch (category) {
      case MarketCategory.crypto:
        if (random.nextBool()) {
          // BTC like
          return '¥${(4000000 + random.nextInt(5000000)).toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
        } else {
          // Other like
          return '¥${(1000 + random.nextInt(90000)).toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
        }
      case MarketCategory.forex:
        return '${(100 + random.nextInt(50))}.${(random.nextInt(99)).toString().padLeft(2, '0')}';
      case MarketCategory.stock:
        return '¥${(1000 + random.nextInt(9000)).toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
    }
  }

  String _generateMockChange(String priceStr, Random random) {
     double priceVal = double.tryParse(priceStr.replaceAll('¥', '').replaceAll(',', '')) ?? 1000;
     double change = priceVal * (random.nextDouble() * 0.04 - 0.02); // -2% to +2%
     String sign = change >= 0 ? '+' : '';
     return '$sign${change.toStringAsFixed(categoryDecimals(priceStr))}';
  }

   String _generateMockChangePercent(String changeStr, String priceStr) {
     double change = double.tryParse(changeStr) ?? 0;
     double price = double.tryParse(priceStr.replaceAll('¥', '').replaceAll(',', '')) ?? 1000;
     double percent = (change / price) * 100;
     String sign = percent >= 0 ? '+' : '';
     return '$sign${percent.toStringAsFixed(2)}%';
  }
  
  int categoryDecimals(String val) {
    if (val.contains('.')) return 2;
    return 0;
  }

  // 資産検索ダイアログを表示
  Future<void> _showAssetSearch(MarketCategory category) async {
    // 現在登録されている銘柄のシンボル一覧
    Set<String> currentSymbols;
    switch (category) {
      case MarketCategory.crypto:
        currentSymbols = _cryptoData
            .map((item) => item is Map ? item['symbol'] as String : item.toString())
            .toSet();
        break;
      case MarketCategory.forex:
        currentSymbols = _forexData
            .map((item) => item is Map ? item['symbol'] as String : item.toString())
            .toSet();
        break;
      case MarketCategory.stock:
        currentSymbols = _stockData
            .map((item) => item is Map ? item['symbol'] as String : item.toString())
            .toSet();
        break;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, // テーマの丸みを見せるため
      builder: (context) => _AssetSearchSheet(
        assetService: _assetService,
        category: category,
        currentSymbols: currentSymbols,
        onAssetAdded: () {
          _loadData();
        },
      ),
    );
  }
}

// 資産検索ボトムシート（StatefulWidget）
class _AssetSearchSheet extends StatefulWidget {
  final AssetService assetService;
  final MarketCategory category;
  final Set<String> currentSymbols;
  final VoidCallback onAssetAdded;

  const _AssetSearchSheet({
    required this.assetService,
    required this.category,
    required this.currentSymbols,
    required this.onAssetAdded,
  });

  @override
  State<_AssetSearchSheet> createState() => _AssetSearchSheetState();
}

class _AssetSearchSheetState extends State<_AssetSearchSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  String? _lastQuery;

  // ... (Keep existing getter logic)
  String get _title {
    switch (widget.category) {
      case MarketCategory.crypto:
        return '暗号通貨を検索';
      case MarketCategory.forex:
        return '為替ペアを検索';
      case MarketCategory.stock:
        return '銘柄を検索';
    }
  }

  String get _hintText {
    switch (widget.category) {
      case MarketCategory.crypto:
        return 'BTC, Bitcoinなど';
      case MarketCategory.forex:
        return 'USD, JPYなど';
      case MarketCategory.stock:
        return '銘柄コード, 会社名';
    }
  }
  
  // ignore: unused_element
  Color get _categoryColor => CategoryColors.forCategoryName(widget.category.name);


  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    if (query == _lastQuery) return;
    _lastQuery = query;

    setState(() {
      _isSearching = true;
    });

    List<Map<String, dynamic>> results;
    switch (widget.category) {
      case MarketCategory.crypto:
        results = await widget.assetService.searchCrypto(query);
        break;
      case MarketCategory.forex:
        results = await widget.assetService.searchForex(query);
        break;
      case MarketCategory.stock:
        results = await widget.assetService.searchStocks(query);
        break;
    }

    if (_lastQuery != query) return;

    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  Future<bool> _addAsset(String symbol, String displayName, String description) async {
    switch (widget.category) {
      case MarketCategory.crypto:
        return widget.assetService.addCrypto(
          symbol: symbol,
          displayName: displayName,
          description: description,
        );
      case MarketCategory.forex:
        return widget.assetService.addForex(
          symbol: symbol,
          displayName: displayName,
          description: description,
        );
      case MarketCategory.stock:
        return widget.assetService.addStock(
          symbol: symbol,
          displayName: displayName,
          description: description,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
           Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            _title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: _hintText,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _performSearch('');
                      },
                    )
                  : null,
            ),
             onChanged: (value) {
                // Debounce
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (_searchController.text == value) {
                    _performSearch(value);
                  }
                });
                setState(() {});
              },
          ),
          const SizedBox(height: 16),
          if (_isSearching)
            const LinearProgressIndicator()
          else if (_searchResults.isNotEmpty)
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final item = _searchResults[index];
                    final symbol = item['symbol'];
                    final name = item['displayName'];
                    final isAdded = widget.currentSymbols.contains(symbol);

                    return ListTile(
                      title: Text(name),
                      subtitle: Text(symbol),
                      trailing: isAdded
                          ? const Icon(Icons.check_circle, color: AppColors.success)
                          : ElevatedButton(
                              onPressed: () async {
                                final success = await _addAsset(
                                  symbol,
                                  name,
                                  item['description'] ?? '',
                                );
                                if (success && mounted) {
                                  widget.onAssetAdded();
                                  setState(() {});
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                              ),
                              child: const Text('追加'),
                            ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
