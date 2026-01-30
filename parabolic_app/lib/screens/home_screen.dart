import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
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
      final response = await _api.get('/api/crypto/tickers');
      if (response.isSuccess) {
        final data = response.jsonList;
        if (data != null) {
          setState(() {
            _cryptoData = data;
            // 将来的にAPIから取得するが、今はダミーデータ
            _forexData = ['USD/JPY', 'EUR/USD', 'GBP/USD', 'EUR/JPY', 'AUD/USD'];
            _stockData = ['AAPL', 'GOOGL', 'MSFT', 'AMZN', 'TSLA', 'NVDA'];
            _isLoading = false;
          });
        }
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
    if (_cryptoData.isEmpty) {
      return const Center(child: Text('暗号通貨データがありません'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _cryptoData.length,
      itemBuilder: (context, index) {
        final symbol = _cryptoData[index].toString();
        final displayName = symbol.replaceAll('-USD', '');

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
            subtitle: Text(symbol),
            trailing: const Icon(Icons.chevron_right),
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
    );
  }

  Widget _buildForexList() {
    if (_forexData.isEmpty) {
      return const Center(child: Text('為替データがありません'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _forexData.length,
      itemBuilder: (context, index) {
        final symbol = _forexData[index].toString();

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.green.shade100,
              child: const Icon(Icons.currency_exchange, color: Colors.green),
            ),
            title: Text(
              symbol,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('為替'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // 将来的に実装
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('為替チャートは近日実装予定です')),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildStockList() {
    if (_stockData.isEmpty) {
      return const Center(child: Text('株式データがありません'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _stockData.length,
      itemBuilder: (context, index) {
        final symbol = _stockData[index].toString();

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              child: const Icon(Icons.show_chart, color: Colors.blue),
            ),
            title: Text(
              symbol,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('株式'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // 将来的に実装
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('株式チャートは近日実装予定です')),
              );
            },
          ),
        );
      },
    );
  }
}
