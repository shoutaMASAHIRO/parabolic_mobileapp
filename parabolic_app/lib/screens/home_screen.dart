import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/stock_service.dart';
import 'login_screen.dart';
import 'detail_screen.dart';

// カテゴリ定義
enum MarketCategory {
  crypto('暗号通貨', Icons.currency_bitcoin),
  forex('為替', Icons.currency_exchange),
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
  late TabController _tabController;

  // 各カテゴリのデータ
  List<dynamic> _cryptoData = [];
  List<dynamic> _forexData = [];
  List<dynamic> _stockData = [];

  bool _isLoading = true;
  String? _error;

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
        setState(() {
          _cryptoData = cryptoResponse.jsonList ?? [];
          _forexData = forexResponse.jsonList ?? [];
          _stockData = stockResponse.jsonList ?? [];
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load data';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
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
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parabolic'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                _handleLogout();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    const Icon(Icons.person, size: 20),
                    const SizedBox(width: 8),
                    Text(user?.username ?? 'User'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
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
        bottom: TabBar(
          controller: _tabController,
          tabs: MarketCategory.values.map((cat) => Tab(
            icon: Icon(cat.icon),
            text: cat.label,
          )).toList(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
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
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
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
        _buildCryptoList(),
        _buildForexList(),
        _buildStockList(),
      ],
    );
  }

  Widget _buildCryptoList() {
    return Column(
      children: [
        Expanded(
          child: _cryptoData.isEmpty
              ? const Center(child: Text('暗号通貨データがありません'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _cryptoData.length,
                  itemBuilder: (context, index) {
                    final item = _cryptoData[index];
                    final symbol = item is Map ? item['symbol'] as String : item.toString();
                    final displayName = item is Map
                        ? item['displayName'] as String
                        : symbol.replaceAll('-USD', '');
                    final description = item is Map
                        ? item['description'] as String
                        : symbol;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.orange.shade100,
                          child: const Icon(Icons.currency_bitcoin, color: Colors.orange),
                        ),
                        title: Text(
                          displayName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(description),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.delete_outline, color: Colors.grey.shade600),
                              onPressed: () => _deleteCrypto(symbol, displayName),
                              tooltip: '削除',
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => DetailScreen(
                                symbol: symbol,
                                category: MarketCategory.crypto,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showAssetSearch(MarketCategory.crypto),
              icon: const Icon(Icons.add),
              label: const Text('暗号通貨を追加'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForexList() {
    return Column(
      children: [
        Expanded(
          child: _forexData.isEmpty
              ? const Center(child: Text('為替データがありません'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _forexData.length,
                  itemBuilder: (context, index) {
                    final item = _forexData[index];
                    final symbol = item is Map ? item['symbol'] as String : item.toString();
                    final displayName = item is Map ? item['displayName'] as String : item.toString();
                    final description = item is Map ? item['description'] as String : '為替';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.green.shade100,
                          child: const Icon(Icons.currency_exchange, color: Colors.green),
                        ),
                        title: Text(
                          displayName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(description),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.delete_outline, color: Colors.grey.shade600),
                              onPressed: () => _deleteForex(symbol, displayName),
                              tooltip: '削除',
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => DetailScreen(
                                symbol: symbol,
                                category: MarketCategory.forex,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showAssetSearch(MarketCategory.forex),
              icon: const Icon(Icons.add),
              label: const Text('為替ペアを追加'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStockList() {
    return Column(
      children: [
        Expanded(
          child: _stockData.isEmpty
              ? const Center(child: Text('株式データがありません'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _stockData.length,
                  itemBuilder: (context, index) {
                    final item = _stockData[index];
                    // APIからのデータはMapで返ってくる
                    final symbol = item is Map ? item['symbol'] as String : item.toString();
                    final displayName = item is Map ? item['displayName'] as String : item.toString();
                    final description = item is Map ? item['description'] as String : '株式';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.blue.shade100,
                          child: const Icon(Icons.show_chart, color: Colors.blue),
                        ),
                        title: Text(
                          displayName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(description),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.delete_outline, color: Colors.grey.shade600),
                              onPressed: () => _deleteStock(symbol, displayName),
                              tooltip: '削除',
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => DetailScreen(
                                symbol: symbol,
                                category: MarketCategory.stock,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
        // 銘柄を検索ボタン
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showAssetSearch(MarketCategory.stock),
              icon: const Icon(Icons.add),
              label: const Text('銘柄を追加'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 暗号通貨を削除
  Future<void> _deleteCrypto(String symbol, String displayName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('暗号通貨を削除'),
        content: Text('$displayName をリストから削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _assetService.hideCrypto(symbol);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$displayName を削除しました'),
            duration: const Duration(seconds: 1),
          ),
        );
        _loadData();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('削除に失敗しました'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  // 為替を削除
  Future<void> _deleteForex(String symbol, String displayName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('為替ペアを削除'),
        content: Text('$displayName をリストから削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _assetService.hideForex(symbol);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$displayName を削除しました'),
            duration: const Duration(seconds: 1),
          ),
        );
        _loadData();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('削除に失敗しました'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  // 株式を削除
  Future<void> _deleteStock(String symbol, String displayName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('銘柄を削除'),
        content: Text('$displayName をリストから削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _assetService.hideStock(symbol);
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$displayName を削除しました'),
            duration: const Duration(seconds: 1),
          ),
        );
        _loadData();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('削除に失敗しました'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
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
        return '暗号通貨名を入力 (例: BTC, Bitcoin)';
      case MarketCategory.forex:
        return '通貨ペアを入力 (例: USD, JPY, EUR)';
      case MarketCategory.stock:
        return '銘柄コードまたは会社名を入力';
    }
  }

  String get _exampleText {
    switch (widget.category) {
      case MarketCategory.crypto:
        return '例: BTC, ETH, Bitcoin, Ethereum';
      case MarketCategory.forex:
        return '例: USD, JPY, EUR, GBP';
      case MarketCategory.stock:
        return '例: 7203, トヨタ, AAPL, Apple';
    }
  }

  Color get _categoryColor {
    switch (widget.category) {
      case MarketCategory.crypto:
        return Colors.orange;
      case MarketCategory.forex:
        return Colors.green;
      case MarketCategory.stock:
        return Colors.blue;
    }
  }

  IconData get _categoryIcon {
    switch (widget.category) {
      case MarketCategory.crypto:
        return Icons.currency_bitcoin;
      case MarketCategory.forex:
        return Icons.currency_exchange;
      case MarketCategory.stock:
        return Icons.show_chart;
    }
  }

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
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.search, color: _categoryColor),
                const SizedBox(width: 8),
                Text(
                  _title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) {
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (_searchController.text == value) {
                    _performSearch(value);
                  }
                });
                setState(() {});
              },
              onSubmitted: _performSearch,
              textInputAction: TextInputAction.search,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _buildSearchResults(scrollController),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(ScrollController scrollController) {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_searchController.text.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              _hintText,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              _exampleText,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              '検索結果がありません',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final asset = _searchResults[index];
        final symbol = asset['symbol'] as String;
        final displayName = asset['displayName'] as String;
        final description = asset['description'] as String? ?? '';
        final isAdded = widget.currentSymbols.contains(symbol);

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: isAdded
                ? Colors.grey.shade200
                : _categoryColor.withAlpha(30),
            child: Icon(
              _categoryIcon,
              color: isAdded ? Colors.grey : _categoryColor,
            ),
          ),
          title: Text(
            displayName,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isAdded ? Colors.grey : null,
            ),
          ),
          subtitle: Text(
            '$symbol • $description',
            style: TextStyle(color: isAdded ? Colors.grey : null),
          ),
          trailing: isAdded
              ? const Icon(Icons.check, color: Colors.green)
              : Icon(Icons.add, color: _categoryColor),
          onTap: isAdded
              ? null
              : () async {
                  final success = await _addAsset(symbol, displayName, description);
                  if (mounted) {
                    if (success) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('$displayName を追加しました'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                      widget.onAssetAdded();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('追加に失敗しました'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    }
                  }
                },
        );
      },
    );
  }
}
