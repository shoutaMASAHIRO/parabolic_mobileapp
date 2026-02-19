import 'api_service.dart';
import 'package:flutter/material.dart';

class AnalysisService {
  final ApiService _api = ApiService();

  Future<Map<String, dynamic>?> getStockAnalysis(String symbol) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final path = '/api/stock/analysis?symbol=$symbol&t=$timestamp';
    debugPrint('ANALYSIS_SERVICE: Requesting $path');
    
    try {
      final response = await _api.get(path);
      debugPrint('ANALYSIS_SERVICE: Response status: ${response.statusCode}');
      debugPrint('ANALYSIS_SERVICE: Response body: ${response.json}');
      
      if (response.isSuccess && response.json != null) {
        return response.json;
      }
    } catch (e) {
      debugPrint('ANALYSIS_SERVICE: Error during API call: $e');
    }
    
    debugPrint('ANALYSIS_SERVICE: Falling back to mock for $symbol');
    return _generateMockAnalysis(symbol);
  }

  Map<String, dynamic> _generateMockAnalysis(String symbol) {
    final isCrypto = symbol.contains('-USD');
    final isForex = symbol.contains('=X');
    
    if (isCrypto || isForex) {
      return {
        'morningstarRating': 'N/A (対象外)',
        'analystRating': 'センチメント: 取得中...',
        'earnings': 'N/A',
        'performance': 'データ取得失敗',
        'valuation': '--',
        'revenueComposition': 'シンボル: $symbol',
      };
    }

    return {
      'morningstarRating': '取得失敗 (モック表示)',
      'analystRating': '''銘柄: $symbol
APIとの接続を確認してください。''',
      'earnings': '''データ取得エラー
サーバーログを確認してください。''',
      'performance': '接続先: ${_api.toString()}',
      'valuation': '時刻: ${DateTime.now().toIso8601String()}',
      'revenueComposition': 'Symbol: $symbol',
    };
  }
}
