import 'package:flutter/material.dart';
import '../services/stock_service.dart';
import '../services/chart_service.dart';
import '../screens/home_screen.dart' show MarketCategory;

class MarketDataProvider with ChangeNotifier {
  final AssetService _assetService = AssetService();
  final ChartService _chartService = ChartService();

  // 銘柄データ
  List<dynamic> _cryptoData = [];
  List<dynamic> _forexData = [];
  List<dynamic> _stockData = [];

  // 通知・お気に入り設定 (Symbol をキーとしたキャッシュ)
  final Map<String, Map<String, double>> _thresholdsCache = {};
  final Set<String> _favoriteSymbols = {};
  final Set<String> _notifiedSymbols = {};

  bool _isLoading = false;
  DateTime? _lastFetchTime;

  // ゲッター
  List<dynamic> get cryptoData => _cryptoData;
  List<dynamic> get forexData => _forexData;
  List<dynamic> get stockData => _stockData;
  bool get isLoading => _isLoading;
  Set<String> get favoriteSymbols => _favoriteSymbols;
  Set<String> get notifiedSymbols => _notifiedSymbols;

  /// 全データの初期読み込み・更新
  Future<void> refreshAllData({bool force = false}) async {
    // 5分以内の再取得はスキップ (強制更新でない場合)
    if (!force && _lastFetchTime != null && 
        DateTime.now().difference(_lastFetchTime!) < const Duration(minutes: 5)) {
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      // 1. 銘柄一覧の取得 (並列)
      final results = await Future.wait([
        _assetService.getCryptoTickers(),
        _assetService.getForexTickers(),
        _assetService.getStockTickers(),
        _assetService.getFavorites(),
      ]);

      _cryptoData = results[0];
      _forexData = results[1];
      _stockData = results[2];
      
      // お気に入りの更新
      _favoriteSymbols.clear();
      for (var item in results[3]) {
        _favoriteSymbols.add(item['symbol'] as String);
      }

      // 2. 通知設定の更新 (重い処理なので、まずは現在表示に必要なものから優先的に、あるいは徐々に取得する)
      // ここでは、お気に入り銘柄の閾値だけをまず一括更新する
      await _updateNotifiedSymbols([..._favoriteSymbols]);

      _lastFetchTime = DateTime.now();
    } catch (e) {
      debugPrint('Error fetching market data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 指定したシンボルリストの通知設定を更新する
  Future<void> _updateNotifiedSymbols(List<String> symbols) async {
    final notified = <String>{};
    
    // N+1問題を軽減するため、Future.wait で並列実行
    // ただし、数が多すぎる場合はチャンク分けが必要
    await Future.wait(symbols.map((symbol) async {
      final thresholds = await _chartService.getAllThresholdsFromServer(symbol);
      _thresholdsCache[symbol] = thresholds;
      
      if (thresholds.keys.any((k) => k != 'favorite')) {
        notified.add(symbol);
      }
    }));

    _notifiedSymbols.addAll(notified);
  }

  /// 特定の銘柄の設定が変更されたときに外部から呼ぶ (DetailScreen など)
  void updateSymbolCache(String symbol, Map<String, double> thresholds) {
    _thresholdsCache[symbol] = thresholds;
    
    if (thresholds['favorite'] == 1.0) {
      _favoriteSymbols.add(symbol);
    } else {
      _favoriteSymbols.remove(symbol);
    }

    if (thresholds.keys.any((k) => k != 'favorite')) {
      _notifiedSymbols.add(symbol);
    } else {
      _notifiedSymbols.remove(symbol);
    }
    
    notifyListeners();
  }

  List<dynamic> getDataByCategory(MarketCategory category) {
    switch (category) {
      case MarketCategory.crypto: return _cryptoData;
      case MarketCategory.forex: return _forexData;
      case MarketCategory.stock: return _stockData;
    }
  }
}
