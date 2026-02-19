import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/candle.dart';
import '../models/chart_configs.dart';

// クロスイベントの種類（トレンド系に限定）
enum CrossType { 
  bb, ema, sma, wma, ichimoku, parabolic, envelope, keltner, supertrend, gmma
}

// クロス方向
enum CrossDirection { up, down }

// クロスイベント
class CrossEvent {
  final String symbol;
  final String interval;
  final CrossType type;
  final String indicatorName; 
  final double price;
  final double lineValue;
  final CrossDirection direction;
  final DateTime timestamp;

  CrossEvent({
    required this.symbol,
    required this.interval,
    required this.type,
    required this.indicatorName,
    required this.price,
    required this.lineValue,
    required this.direction,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    'interval': interval,
    'type': type.name,
    'indicatorName': indicatorName,
    'price': price,
    'lineValue': lineValue,
    'direction': direction.name,
    'timestamp': timestamp.toIso8601String(),
  };

  factory CrossEvent.fromJson(Map<String, dynamic> json) => CrossEvent(
    symbol: json['symbol'],
    interval: json['interval'],
    type: CrossType.values.byName(json['type']),
    indicatorName: json['indicatorName'],
    price: (json['price'] as num).toDouble(),
    lineValue: (json['lineValue'] as num).toDouble(),
    direction: CrossDirection.values.byName(json['direction']),
    timestamp: DateTime.parse(json['timestamp']),
  );

  String get displayName {
    switch (type) {
      case CrossType.bb: return _bbDisplayName(indicatorName);
      case CrossType.ema: return 'EMA(${indicatorName.replaceAll('ema', '')})';
      case CrossType.sma: return 'SMA';
      case CrossType.wma: return 'WMA';
      case CrossType.ichimoku: return _ichimokuDisplayName(indicatorName);
      case CrossType.parabolic: return 'パラボリック';
      case CrossType.envelope: return 'エンベロープ';
      case CrossType.keltner: return 'ケルトナー';
      case CrossType.supertrend: return 'スーパートレンド';
      case CrossType.gmma: return 'GMMA';
    }
  }

  String _bbDisplayName(String name) {
    switch (name) {
      case 'upper2': return 'BB +2σ';
      case 'upper1': return 'BB +1σ';
      case 'middle': return 'BB 0σ';
      case 'lower1': return 'BB -1σ';
      case 'lower2': return 'BB -2σ';
      default: return 'BB';
    }
  }

  String _ichimokuDisplayName(String name) {
    switch (name) {
      case 'tenkan': return '一目(転換線)';
      case 'kijun': return '一目(基準線)';
      case 'senkouA': return '一目(先行A)';
      case 'senkouB': return '一目(先行B)';
      default: return '一目均衡表';
    }
  }
}

// クロス検知サービス
class CrossDetectionService {
  static const String _crossHistoryKey = 'cross_history';
  static const String _thresholdKey = 'cross_threshold';

  // 基本的なクロス判定
  static bool _crossed(double prevVal, double curVal, double prevLine, double curLine) {
    final prevDiff = prevVal - prevLine;
    final curDiff = curVal - curLine;
    return prevDiff * curDiff < 0;
  }

  static CrossDirection _getDirection(double prevVal, double curVal, double prevLine, double curLine) {
    return (prevVal < prevLine) ? CrossDirection.up : CrossDirection.down;
  }

  // クロス検知を実行
  static List<CrossEvent> detectCrosses({
    required String symbol,
    required String interval,
    required List<Candle> candles,
    required List<String> targetIndicators,
    required Map<String, IndicatorSettings> settings,
  }) {
    if (candles.length < 2) return [];

    final events = <CrossEvent>[];
    final prices = candles.map((c) => c.close).toList();
    final prevPrice = prices[prices.length - 2];
    final curPrice = prices.last;
    final timestamp = candles.last.date;

    for (final target in targetIndicators) {
      final config = settings[target];
      if (config == null) continue;

      switch (target) {
        case 'bb':
          final p = config.params['period'] ?? 20;
          final sd1 = config.params['stdDev1'] ?? 1.0;
          final sd2 = config.params['stdDev2'] ?? 2.0;
          final bb = TechnicalIndicators.calculateBollingerBands(prices, period: p, stdDev1: sd1, stdDev2: sd2);
          final lines = {'upper2': bb.upper2, 'upper1': bb.upper1, 'middle': bb.middle, 'lower1': bb.lower1, 'lower2': bb.lower2};
          for (final entry in lines.entries) {
            final line = entry.value;
            if (line.length < 2 || line.last == null || line[line.length-2] == null) continue;
            if (_crossed(prevPrice, curPrice, line[line.length-2]!, line.last!)) {
              events.add(CrossEvent(symbol: symbol, interval: interval, type: CrossType.bb, indicatorName: entry.key, price: curPrice, lineValue: line.last!, direction: _getDirection(prevPrice, curPrice, line[line.length-2]!, line.last!), timestamp: timestamp));
            }
          }
          break;

        case 'ema':
          for (int i = 1; i <= 3; i++) {
            final p = config.params['period$i'] ?? (i == 1 ? 10 : i == 2 ? 25 : 50);
            final ema = TechnicalIndicators.calculateEMA(prices, p);
            if (ema.length < 2 || ema.last == null || ema[ema.length-2] == null) continue;
            if (_crossed(prevPrice, curPrice, ema[ema.length-2]!, ema.last!)) {
              events.add(CrossEvent(symbol: symbol, interval: interval, type: CrossType.ema, indicatorName: 'ema$p', price: curPrice, lineValue: ema.last!, direction: _getDirection(prevPrice, curPrice, ema[ema.length-2]!, ema.last!), timestamp: timestamp));
            }
          }
          break;

        case 'sma':
          final p = config.params['period'] ?? 20;
          final sma = TechnicalIndicators.calculateSMA(prices, p);
          if (sma.length >= 2 && sma.last != null && sma[sma.length-2] != null) {
            if (_crossed(prevPrice, curPrice, sma[sma.length-2]!, sma.last!)) {
              events.add(CrossEvent(symbol: symbol, interval: interval, type: CrossType.sma, indicatorName: 'sma', price: curPrice, lineValue: sma.last!, direction: _getDirection(prevPrice, curPrice, sma[sma.length-2]!, sma.last!), timestamp: timestamp));
            }
          }
          break;

        case 'wma':
          final p = config.params['period'] ?? 20;
          final wma = TechnicalIndicators.calculateWMA(prices, p);
          if (wma.length >= 2 && wma.last != null && wma[wma.length-2] != null) {
            if (_crossed(prevPrice, curPrice, wma[wma.length-2]!, wma.last!)) {
              events.add(CrossEvent(symbol: symbol, interval: interval, type: CrossType.wma, indicatorName: 'wma', price: curPrice, lineValue: wma.last!, direction: _getDirection(prevPrice, curPrice, wma[wma.length-2]!, wma.last!), timestamp: timestamp));
            }
          }
          break;

        case 'ichimoku':
          final ichi = TechnicalIndicators.calculateIchimoku(candles, tenkanPeriod: config.params['tenkan'] ?? 9, kijunPeriod: config.params['kijun'] ?? 26, senkouBPeriod: config.params['senkouB'] ?? 52, displacement: config.params['displacement'] ?? 26);
          final lines = {'tenkan': ichi.tenkan, 'kijun': ichi.kijun, 'senkouA': ichi.senkouA, 'senkouB': ichi.senkouB};
          for (final entry in lines.entries) {
            final line = entry.value;
            if (line.length < 2 || line.last == null || line[line.length-2] == null) continue;
            if (_crossed(prevPrice, curPrice, line[line.length-2]!, line.last!)) {
              events.add(CrossEvent(symbol: symbol, interval: interval, type: CrossType.ichimoku, indicatorName: entry.key, price: curPrice, lineValue: line.last!, direction: _getDirection(prevPrice, curPrice, line[line.length-2]!, line.last!), timestamp: timestamp));
            }
          }
          break;

        case 'parabolic':
          final sar = TechnicalIndicators.calculateParabolicSAR(candles, acceleration: config.params['acceleration'] ?? 0.02, maxAcceleration: config.params['maxAcceleration'] ?? 0.2);
          if (sar.length >= 2 && sar.last != null && sar[sar.length-2] != null) {
            if (_crossed(prevPrice, curPrice, sar[sar.length-2]!, sar.last!)) {
              events.add(CrossEvent(symbol: symbol, interval: interval, type: CrossType.parabolic, indicatorName: 'sar', price: curPrice, lineValue: sar.last!, direction: _getDirection(prevPrice, curPrice, sar[sar.length-2]!, sar.last!), timestamp: timestamp));
            }
          }
          break;

        case 'envelope':
          final env = TechnicalIndicators.calculateEnvelope(prices, period: config.params['period'] ?? 20, deviation: config.params['deviation'] ?? 2.5);
          for (final line in [env.upper, env.lower]) {
            if (line.length >= 2 && line.last != null && line[line.length-2] != null) {
              if (_crossed(prevPrice, curPrice, line[line.length-2]!, line.last!)) {
                events.add(CrossEvent(symbol: symbol, interval: interval, type: CrossType.envelope, indicatorName: 'env', price: curPrice, lineValue: line.last!, direction: _getDirection(prevPrice, curPrice, line[line.length-2]!, line.last!), timestamp: timestamp));
              }
            }
          }
          break;

        case 'keltner':
          final kc = TechnicalIndicators.calculateKeltnerChannel(candles, period: config.params['period'] ?? 20, multiplier: config.params['multiplier'] ?? 2.0);
          for (final line in [kc.upper, kc.lower]) {
            if (line.length >= 2 && line.last != null && line[line.length-2] != null) {
              if (_crossed(prevPrice, curPrice, line[line.length-2]!, line.last!)) {
                events.add(CrossEvent(symbol: symbol, interval: interval, type: CrossType.keltner, indicatorName: 'kc', price: curPrice, lineValue: line.last!, direction: _getDirection(prevPrice, curPrice, line[line.length-2]!, line.last!), timestamp: timestamp));
              }
            }
          }
          break;

        case 'supertrend':
          final st = TechnicalIndicators.calculateSupertrend(candles, period: config.params['period'] ?? 10, multiplier: config.params['multiplier'] ?? 3.0);
          if (st.values.length >= 2 && st.values.last != null && st.values[st.values.length-2] != null) {
            if (_crossed(prevPrice, curPrice, st.values[st.values.length-2]!, st.values.last!)) {
              events.add(CrossEvent(symbol: symbol, interval: interval, type: CrossType.supertrend, indicatorName: 'st', price: curPrice, lineValue: st.values.last!, direction: _getDirection(prevPrice, curPrice, st.values[st.values.length-2]!, st.values.last!), timestamp: timestamp));
            }
          }
          break;

        case 'gmma':
          final gmma = TechnicalIndicators.calculateGMMA(prices);
          final shortAvg = gmma.shortTerm.last.where((v) => v != null).fold(0.0, (a, b) => a + b!) / 6;
          final longAvg = gmma.longTerm.last.where((v) => v != null).fold(0.0, (a, b) => a + b!) / 6;
          final prevShortAvg = gmma.shortTerm[gmma.shortTerm.length-2].where((v) => v != null).fold(0.0, (a, b) => a + b!) / 6;
          final prevLongAvg = gmma.longTerm[gmma.longTerm.length-2].where((v) => v != null).fold(0.0, (a, b) => a + b!) / 6;
          if (_crossed(prevShortAvg, shortAvg, prevLongAvg, longAvg)) {
            events.add(CrossEvent(symbol: symbol, interval: interval, type: CrossType.gmma, indicatorName: 'gmma', price: curPrice, lineValue: shortAvg, direction: _getDirection(prevShortAvg, shortAvg, prevLongAvg, longAvg), timestamp: timestamp));
          }
          break;
      }
    }

    return events;
  }

  // クロス履歴を保存
  static Future<void> saveCrossEvent(CrossEvent event) async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString(_crossHistoryKey);
    final history = <Map<String, dynamic>>[];
    if (historyJson != null) {
      final decoded = jsonDecode(historyJson) as List;
      history.addAll(decoded.cast<Map<String, dynamic>>());
    }
    history.removeWhere((json) => json['symbol'] == event.symbol && json['interval'] == event.interval && json['indicatorName'] == event.indicatorName);
    history.add(event.toJson());
    await prefs.setString(_crossHistoryKey, jsonEncode(history));
  }

  // クロス履歴を取得
  static Future<List<CrossEvent>> getCrossHistory(String symbol) async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString(_crossHistoryKey);
    if (historyJson == null) return [];
    final decoded = jsonDecode(historyJson) as List;
    return decoded.cast<Map<String, dynamic>>().map((json) => CrossEvent.fromJson(json)).where((e) => e.symbol == symbol).toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  // 閾値を保存
  static Future<void> saveThreshold(String symbol, String interval, double threshold) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_thresholdKey}_${symbol}_$interval';
    await prefs.setDouble(key, threshold);
  }

  // 閾値を取得
  static Future<double?> getThreshold(String symbol, String interval) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '${_thresholdKey}_${symbol}_$interval';
    return prefs.getDouble(key);
  }

  // 閾値達成をチェック
  static bool checkThresholdReached(CrossEvent event, double currentPrice, double threshold) {
    final diff = (currentPrice - event.price).abs();
    return diff >= threshold;
  }

  // クロス履歴をクリア
  static Future<void> clearCrossHistory(String symbol) async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString(_crossHistoryKey);
    if (historyJson == null) return;
    final decoded = jsonDecode(historyJson) as List;
    final filtered = decoded.cast<Map<String, dynamic>>().where((json) => json['symbol'] != symbol).toList();
    await prefs.setString(_crossHistoryKey, jsonEncode(filtered));
  }
}
