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
}

// 後方互換性のためのエイリアス
typedef StockService = AssetService;
