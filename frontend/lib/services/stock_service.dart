import 'api_service.dart';

class AssetService {
  final ApiService _api = ApiService();

  // =====================
  // 暗号通貨
  // =====================

  Future<List<Map<String, dynamic>>> getCryptoTickers() async {
    final response = await _api.get('/api/crypto/tickers');
    if (response.isSuccess && response.jsonList != null) {
      return response.jsonList!.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> searchCrypto(String query) async {
    if (query.isEmpty) return [];
    final response = await _api.get('/api/crypto/search?q=${Uri.encodeComponent(query)}');
    if (response.isSuccess && response.jsonList != null) {
      return response.jsonList!.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<bool> addCrypto({
    required String symbol,
    required String displayName,
    required String description,
  }) async {
    final response = await _api.post('/api/user/crypto-config/add', {
      'symbol': symbol,
      'displayName': displayName,
      'description': description,
    });
    return response.isSuccess;
  }

  Future<bool> hideCrypto(String symbol) async {
    final response = await _api.post('/api/user/crypto-config/hide', {
      'symbol': symbol,
    });
    return response.isSuccess;
  }

  // =====================
  // 為替
  // =====================

  Future<List<Map<String, dynamic>>> getForexTickers() async {
    final response = await _api.get('/api/forex/tickers');
    if (response.isSuccess && response.jsonList != null) {
      return response.jsonList!.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> searchForex(String query) async {
    if (query.isEmpty) return [];
    final response = await _api.get('/api/forex/search?q=${Uri.encodeComponent(query)}');
    if (response.isSuccess && response.jsonList != null) {
      return response.jsonList!.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<bool> addForex({
    required String symbol,
    required String displayName,
    required String description,
  }) async {
    final response = await _api.post('/api/user/forex-config/add', {
      'symbol': symbol,
      'displayName': displayName,
      'description': description,
    });
    return response.isSuccess;
  }

  Future<bool> hideForex(String symbol) async {
    final response = await _api.post('/api/user/forex-config/hide', {
      'symbol': symbol,
    });
    return response.isSuccess;
  }

  // =====================
  // 株式
  // =====================

  Future<List<Map<String, dynamic>>> getStockTickers() async {
    final response = await _api.get('/api/stock/tickers');
    if (response.isSuccess && response.jsonList != null) {
      return response.jsonList!.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> searchStocks(String query) async {
    if (query.isEmpty) return [];
    final response = await _api.get('/api/stock/search?q=${Uri.encodeComponent(query)}');
    if (response.isSuccess && response.jsonList != null) {
      return response.jsonList!.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<bool> addStock({
    required String symbol,
    required String displayName,
    required String description,
  }) async {
    final response = await _api.post('/api/user/stock-config/add', {
      'symbol': symbol,
      'displayName': displayName,
      'description': description,
    });
    return response.isSuccess;
  }

  Future<bool> hideStock(String symbol) async {
    final response = await _api.post('/api/user/stock-config/hide', {
      'symbol': symbol,
    });
    return response.isSuccess;
  }

  // =====================
  // お気に入り / 保有銘柄 (PostgreSQL連携)
  // =====================

  // =====================
  // お気に入り / 保有銘柄 (既存API流用)
  // =====================

  Future<bool> toggleFavorite(String symbol, bool isFavorite, {String? displayName, String? category}) async {
    print('DEBUG: toggleFavorite via threshold - symbol: $symbol, isFavorite: $isFavorite');
    
    final response = await _api.post('/api/mobile/threshold', {
      'symbol': symbol,
      'interval': 'favorite',
      'threshold': isFavorite ? 1.0 : 0.0,
    });

    await _api.post('/api/mobile/indicator-settings', {
      'symbol': symbol,
      'displayName': displayName,
      'category': category,
      'isFavorite': isFavorite,
    });

    print('DEBUG: toggleFavorite response - status: ${response.statusCode}');
    return response.isSuccess;
  }

  Future<List<Map<String, dynamic>>> getFavorites() async {
    print('DEBUG: getFavorites via threshold lookup');
    
    final results = await Future.wait([
      getCryptoTickers(),
      getForexTickers(),
      getStockTickers(),
    ]);

    final allTickers = [...results[0], ...results[1], ...results[2]];
    final List<Map<String, dynamic>> favorites = [];

    await Future.wait(allTickers.map((ticker) async {
      final symbol = ticker['symbol'] as String;
      final response = await _api.get('/api/mobile/threshold?symbol=$symbol&interval=favorite');
      
      if (response.isSuccess && response.json != null) {
        final threshold = response.json!['threshold'];
        if (threshold == 1.0) {
          final settingsRes = await _api.get('/api/mobile/indicator-settings?symbol=$symbol');
          final settings = settingsRes.json ?? {};
          
          favorites.add({
            'symbol': symbol,
            'displayName': settings['displayName'] ?? ticker['displayName'] ?? symbol,
            'category': settings['category'] ?? _guessCategory(symbol),
          });
        }
      }
    }));

    print('DEBUG: Found ${favorites.length} favorites');
    return favorites;
  }

  String _guessCategory(String symbol) {
    if (symbol.contains('-USD')) return 'crypto';
    if (symbol.contains('=X')) return 'forex';
    return 'stock';
  }
}

// 後方互換性のためのエイリアス
typedef StockService = AssetService;
