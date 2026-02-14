import '../models/candle.dart';
import 'api_service.dart';
import 'cross_detection_service.dart';

class ChartService {
  final ApiService _api = ApiService();

  Future<List<Candle>> getChartData(String symbol, {String interval = '1d', String? to, int limit = 1500}) async {
    String url = '/api/data?ticker=$symbol&interval=$interval&limit=$limit';
    if (to != null) {
      url += '&to=$to';
    }
    final response = await _api.get(url);

    if (response.isSuccess && response.jsonList != null) {
      return response.jsonList!
          .map((json) => Candle.fromJson(json as Map<String, dynamic>))
          .toList();
    }

    return [];
  }

  // 登録済みメールアドレス一覧を取得（銘柄別）
  Future<List<String>> getEmails({String symbol = 'GLOBAL'}) async {
    final response = await _api.get('/api/emails?symbol=$symbol');

    if (response.isSuccess && response.json != null) {
      final emails = response.json!['emails'] as List<dynamic>?;
      if (emails != null) {
        return emails
            .map((item) => (item as Map<String, dynamic>)['email'] as String)
            .toList();
      }
    }

    return [];
  }

  // メールアドレスを登録（銘柄別）
  Future<bool> registerEmail({required String email, String symbol = 'GLOBAL'}) async {
    final response = await _api.post('/api/subscribe', {
      'email': email,
      'symbol': symbol,
    });
    return response.isSuccess;
  }

  // メールアドレスを削除（銘柄別）
  Future<bool> deleteEmail({required String email, String symbol = 'GLOBAL'}) async {
    final encodedEmail = Uri.encodeComponent(email);
    final response = await _api.delete('/api/emails/$encodedEmail?symbol=$symbol');
    return response.isSuccess;
  }

  // =====================
  // サーバー同期用API（閾値・インジケーター設定）
  // =====================

  // 閾値をサーバーに保存
  Future<bool> saveThresholdToServer({
    required String symbol,
    required String interval,
    required double? threshold,
  }) async {
    final response = await _api.post('/api/mobile/threshold', {
      'symbol': symbol,
      'interval': interval,
      'threshold': threshold,
    });
    return response.isSuccess;
  }

  // 閾値をサーバーから取得
  Future<double?> getThresholdFromServer({
    required String symbol,
    required String interval,
  }) async {
    final response = await _api.get('/api/mobile/threshold?symbol=$symbol&interval=$interval');
    if (response.isSuccess && response.json != null) {
      final threshold = response.json!['threshold'];
      if (threshold != null) {
        return (threshold as num).toDouble();
      }
    }
    return null;
  }

  // 銘柄のすべての閾値を取得
  Future<Map<String, double>> getAllThresholdsFromServer(String symbol) async {
    final response = await _api.get('/api/mobile/threshold?symbol=$symbol');
    if (response.isSuccess && response.json != null) {
      final thresholds = response.json!['thresholds'] as Map<String, dynamic>?;
      if (thresholds != null) {
        return thresholds.map((k, v) => MapEntry(k, (v as num).toDouble()));
      }
    }
    return {};
  }

  // インジケーター設定をサーバーに保存（銘柄ごと）
  Future<bool> saveIndicatorSettingsToServer({
    required String symbol,
    required bool bbEnabled,
    required bool emaEnabled,
    required int bbPeriod,
    required double bbStdDev,
    required int emaPeriod1,
    required int emaPeriod2,
    required int emaPeriod3,
    required bool emailAlertsEnabled,
    List<String> alertTargetIndicators = const ['ema'],
    Map<String, dynamic>? allParams, // 全てのパラメータを渡せるように追加
    // 互換性のための既存引数
    bool rsiEnabled = false,
    int rsiPeriod = 14,
    bool macdEnabled = false,
    int macdFast = 12,
    int macdSlow = 26,
    int macdSignal = 9,
    bool stochasticEnabled = false,
    int stochKPeriod = 14,
    int stochDPeriod = 3,
    int stochSmooth = 3,
    bool cciEnabled = false,
    int cciPeriod = 20,
  }) async {
    final response = await _api.post('/api/mobile/indicator-settings', {
      'symbol': symbol,
      'areBollingerBandsVisible': bbEnabled,
      'areEmaVisible': emaEnabled,
      'bbPeriod': bbPeriod,
      'bbStdDev': bbStdDev,
      'ema1Period': emaPeriod1,
      'ema2Period': emaPeriod2,
      'ema3Period': emaPeriod3,
      'emailAlertsEnabled': emailAlertsEnabled,
      'alertTargetIndicators': alertTargetIndicators,
      'params': allParams, // 詳細なパラメータをまとめて送信
      // 既存の個別フィールドも送信
      'rsiEnabled': rsiEnabled,
      'rsiPeriod': rsiPeriod,
      'macdEnabled': macdEnabled,
      'macdFast': macdFast,
      'macdSlow': macdSlow,
      'macdSignal': macdSignal,
      'stochasticEnabled': stochasticEnabled,
      'stochKPeriod': stochKPeriod,
      'stochDPeriod': stochDPeriod,
      'stochSmooth': stochSmooth,
      'cciEnabled': cciEnabled,
      'cciPeriod': cciPeriod,
    });
    return response.isSuccess;
  }

  // インジケーター設定をサーバーから取得（銘柄ごと）
  Future<Map<String, dynamic>?> getIndicatorSettingsFromServer(String symbol) async {
    final response = await _api.get('/api/mobile/indicator-settings?symbol=$symbol');
    if (response.isSuccess && response.json != null) {
      return response.json;
    }
    return null;
  }

  // クロス履歴をサーバーから取得
  Future<Map<String, dynamic>> getCrossHistoryFromServer(String symbol) async {
    final response = await _api.get('/api/mobile/cross-history?symbol=$symbol');
    if (response.isSuccess && response.json != null) {
      return response.json!['history'] as Map<String, dynamic>? ?? {};
    }
    return {};
  }

  // クロス履歴をサーバーからクリア
  Future<bool> clearCrossHistoryOnServer(String symbol) async {
    final response = await _api.delete('/api/mobile/cross-history?symbol=$symbol');
    return response.isSuccess;
  }

  // 閾値達成メールを送信（レガシー：サーバーが自動送信するので不要になる予定）
  Future<bool> sendThresholdEmail({
    required String symbol,
    required String interval,
    required CrossEvent crossEvent,
    required double currentPrice,
    required double threshold,
    String? currencySymbol,
  }) async {
    final diff = (currentPrice - crossEvent.price).abs();
    final direction = crossEvent.direction == CrossDirection.up ? '上抜け' : '下抜け';

    // 通貨シンボルを決定（為替の場合はクォート通貨に応じて変更）
    final currency = currencySymbol ?? _getCurrencySymbolForSymbol(symbol);

    // 表示用の銘柄名
    final displaySymbol = _formatDisplaySymbol(symbol);

    final subject = '【$displaySymbol】${crossEvent.displayName}クロス閾値達成';
    final body = '''
$displaySymbolの${crossEvent.displayName}クロスが閾値に達しました。

【クロス情報】
インジケーター: ${crossEvent.displayName}
方向: $direction
時間足: $interval

【価格情報】
クロス時価格: $currency${crossEvent.price.toStringAsFixed(2)}
現在価格: $currency${currentPrice.toStringAsFixed(2)}
差分: $currency${diff.toStringAsFixed(2)}
閾値: $currency${threshold.toStringAsFixed(2)}

クロス発生時刻: ${crossEvent.timestamp.toLocal()}
''';

    final response = await _api.post('/api/send-threshold-email', {
      'symbol': symbol,
      'subject': subject,
      'body': body,
    });

    return response.isSuccess;
  }

  // テストメール送信
  Future<bool> sendTestEmail({required String symbol}) async {
    final response = await _api.post('/api/test-email', {
      'symbol': symbol,
    });
    return response.isSuccess;
  }

  // USD/JPY為替レートを取得
  Future<double?> getUsdJpyRate() async {
    final response = await _api.get('/api/forex/usdjpy');
    if (response.isSuccess && response.json != null) {
      final rate = response.json!['rate'];
      if (rate != null) {
        return (rate as num).toDouble();
      }
    }
    return null;
  }

  // シンボルに応じた通貨シンボルを取得
  String _getCurrencySymbolForSymbol(String symbol) {
    // 為替ペアの場合（=Xで終わる）
    if (symbol.endsWith('=X')) {
      final pair = symbol.replaceAll('=X', '');
      if (pair.endsWith('JPY')) return '¥';
      if (pair.endsWith('USD')) return '\$';
      if (pair.endsWith('EUR')) return '€';
      if (pair.endsWith('GBP')) return '£';
    }
    // 日本株の場合（.Tで終わる）
    if (symbol.endsWith('.T')) {
      return '¥';
    }
    // 暗号通貨・米国株の場合はデフォルトでUSD
    return '\$';
  }

  // 表示用の銘柄名をフォーマット
  String _formatDisplaySymbol(String symbol) {
    // 為替ペアの場合: USDJPY=X → USD/JPY
    if (symbol.endsWith('=X')) {
      final pair = symbol.replaceAll('=X', '');
      if (pair.length == 6) {
        return '${pair.substring(0, 3)}/${pair.substring(3)}';
      }
    }
    // 暗号通貨の場合: BTC-USD → BTC
    if (symbol.endsWith('-USD')) {
      return symbol.replaceAll('-USD', '');
    }
    return symbol;
  }
}
