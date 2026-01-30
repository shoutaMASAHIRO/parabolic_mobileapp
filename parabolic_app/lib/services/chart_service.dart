import '../models/candle.dart';
import 'api_service.dart';
import 'cross_detection_service.dart';

class ChartService {
  final ApiService _api = ApiService();

  Future<List<Candle>> getChartData(String symbol, {String interval = '1d'}) async {
    final response = await _api.get('/api/data?ticker=$symbol&interval=$interval');

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

  // インジケーター設定をサーバーに保存
  Future<bool> saveIndicatorSettingsToServer({
    required bool bbEnabled,
    required bool emaEnabled,
    required int bbPeriod,
    required double bbStdDev,
    required int emaPeriod1,
    required int emaPeriod2,
    required int emaPeriod3,
    required bool emailAlertsEnabled,
  }) async {
    final response = await _api.post('/api/mobile/indicator-settings', {
      'areBollingerBandsVisible': bbEnabled,
      'areEmaVisible': emaEnabled,
      'bbPeriod': bbPeriod,
      'bbStdDev': bbStdDev,
      'ema1Period': emaPeriod1,
      'ema2Period': emaPeriod2,
      'ema3Period': emaPeriod3,
      'emailAlertsEnabled': emailAlertsEnabled,
    });
    return response.isSuccess;
  }

  // インジケーター設定をサーバーから取得
  Future<Map<String, dynamic>?> getIndicatorSettingsFromServer() async {
    final response = await _api.get('/api/mobile/indicator-settings');
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
  }) async {
    final diff = (currentPrice - crossEvent.price).abs();
    final direction = crossEvent.direction == CrossDirection.up ? '上抜け' : '下抜け';

    final subject = '【$symbol】${crossEvent.displayName}クロス閾値達成';
    final body = '''
$symbolの${crossEvent.displayName}クロスが閾値に達しました。

【クロス情報】
インジケーター: ${crossEvent.displayName}
方向: $direction
時間足: $interval

【価格情報】
クロス時価格: \$${crossEvent.price.toStringAsFixed(2)}
現在価格: \$${currentPrice.toStringAsFixed(2)}
差分: \$${diff.toStringAsFixed(2)}
閾値: \$${threshold.toStringAsFixed(2)}

クロス発生時刻: ${crossEvent.timestamp.toLocal()}
''';

    final response = await _api.post('/api/send-threshold-email', {
      'symbol': symbol,
      'subject': subject,
      'body': body,
    });

    return response.isSuccess;
  }
}
