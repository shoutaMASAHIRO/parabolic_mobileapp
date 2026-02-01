import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/candle.dart';

// クロスイベントの種類
enum CrossType { bb, ema, rsi, macd, stochastic, cci }

// クロス方向
enum CrossDirection { up, down }

// クロスイベント
class CrossEvent {
  final String symbol;
  final String interval;
  final CrossType type;
  final String indicatorName; // 例: 'upper2', 'lower1', 'ema10'
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
      case CrossType.bb:
        return _bbDisplayName(indicatorName);
      case CrossType.ema:
        return 'EMA(${indicatorName.replaceAll('ema', '')})';
      case CrossType.rsi:
        return _rsiDisplayName(indicatorName);
      case CrossType.macd:
        return _macdDisplayName(indicatorName);
      case CrossType.stochastic:
        return _stochasticDisplayName(indicatorName);
      case CrossType.cci:
        return _cciDisplayName(indicatorName);
    }
  }

  String _bbDisplayName(String name) {
    switch (name) {
      case 'upper2': return 'BB +2σ';
      case 'upper1': return 'BB +1σ';
      case 'middle': return 'BB 0σ';
      case 'lower1': return 'BB -1σ';
      case 'lower2': return 'BB -2σ';
      default: return name;
    }
  }

  String _rsiDisplayName(String name) {
    switch (name) {
      case 'overbought': return 'RSI 買われすぎ(70)';
      case 'oversold': return 'RSI 売られすぎ(30)';
      default: return 'RSI $name';
    }
  }

  String _macdDisplayName(String name) {
    switch (name) {
      case 'signal': return 'MACDシグナル';
      case 'zero': return 'MACDゼロライン';
      default: return 'MACD $name';
    }
  }

  String _stochasticDisplayName(String name) {
    switch (name) {
      case 'kd_cross': return 'Stoch %K/%D';
      case 'overbought': return 'Stoch 買われすぎ(80)';
      case 'oversold': return 'Stoch 売られすぎ(20)';
      default: return 'Stoch $name';
    }
  }

  String _cciDisplayName(String name) {
    switch (name) {
      case 'upper': return 'CCI +100';
      case 'lower': return 'CCI -100';
      default: return 'CCI $name';
    }
  }
}

// クロス検知サービス
class CrossDetectionService {
  static const String _crossHistoryKey = 'cross_history';
  static const String _thresholdKey = 'cross_threshold';

  // クロス判定
  static bool _crossed(double prevPrice, double curPrice, double prevLine, double curLine) {
    // 価格がラインを上から下へ、または下から上へ交差したか
    final prevDiff = prevPrice - prevLine;
    final curDiff = curPrice - curLine;
    return prevDiff * curDiff < 0; // 符号が変わった = クロス
  }

  // クロス方向を判定
  static CrossDirection _getCrossDirection(double prevPrice, double curPrice, double prevLine, double curLine) {
    if (prevPrice < prevLine && curPrice >= curLine) {
      return CrossDirection.up; // 下から上へ
    }
    return CrossDirection.down; // 上から下へ
  }

  // クロス検知を実行
  static List<CrossEvent> detectCrosses({
    required String symbol,
    required String interval,
    required List<Candle> candles,
    required bool checkBB,
    required bool checkEMA,
    required bool checkRSI,
    required bool checkMACD,
    required bool checkStochastic,
    required bool checkCCI,
    required int bbPeriod,
    required double bbStdDev1,
    required double bbStdDev2,
    required int emaPeriod1,
    required int emaPeriod2,
    required int emaPeriod3,
    int rsiPeriod = 14,
    int macdFast = 12,
    int macdSlow = 26,
    int macdSignal = 9,
    int stochKPeriod = 14,
    int stochDPeriod = 3,
    int stochSmooth = 3,
    int cciPeriod = 20,
  }) {
    if (candles.length < 2) return [];

    final events = <CrossEvent>[];
    final closePrices = candles.map((c) => c.close).toList();
    final prevClose = candles[candles.length - 2].close;
    final curClose = candles.last.close;
    final timestamp = candles.last.date;

    // BBクロス検知
    if (checkBB) {
      final bb = TechnicalIndicators.calculateBollingerBands(
        closePrices,
        period: bbPeriod,
        stdDev1: bbStdDev1,
        stdDev2: bbStdDev2,
      );

      final bbLines = {
        'upper2': bb.upper2,
        'upper1': bb.upper1,
        'middle': bb.middle,
        'lower1': bb.lower1,
        'lower2': bb.lower2,
      };

      for (final entry in bbLines.entries) {
        final line = entry.value;
        if (line.length < 2) continue;
        final prevLine = line[line.length - 2];
        final curLine = line.last;
        if (prevLine == null || curLine == null) continue;

        if (_crossed(prevClose, curClose, prevLine, curLine)) {
          events.add(CrossEvent(
            symbol: symbol,
            interval: interval,
            type: CrossType.bb,
            indicatorName: entry.key,
            price: curClose,
            lineValue: curLine,
            direction: _getCrossDirection(prevClose, curClose, prevLine, curLine),
            timestamp: timestamp,
          ));
        }
      }
    }

    // EMAクロス検知
    if (checkEMA) {
      final emaPeriods = [emaPeriod1, emaPeriod2, emaPeriod3];

      for (final period in emaPeriods) {
        final ema = TechnicalIndicators.calculateEMA(closePrices, period);
        if (ema.length < 2) continue;
        final prevLine = ema[ema.length - 2];
        final curLine = ema.last;
        if (prevLine == null || curLine == null) continue;

        if (_crossed(prevClose, curClose, prevLine, curLine)) {
          events.add(CrossEvent(
            symbol: symbol,
            interval: interval,
            type: CrossType.ema,
            indicatorName: 'ema$period',
            price: curClose,
            lineValue: curLine,
            direction: _getCrossDirection(prevClose, curClose, prevLine, curLine),
            timestamp: timestamp,
          ));
        }
      }
    }

    // RSIクロス検知（買われすぎ/売られすぎレベル）
    if (checkRSI) {
      final rsi = OscillatorIndicators.calculateRSI(closePrices, period: rsiPeriod);
      if (rsi.values.length >= 2) {
        final prevRSI = rsi.values[rsi.values.length - 2];
        final curRSI = rsi.values.last;

        if (prevRSI != null && curRSI != null) {
          // RSI 70（買われすぎ）クロス
          if (_crossed(prevRSI, curRSI, 70, 70)) {
            events.add(CrossEvent(
              symbol: symbol,
              interval: interval,
              type: CrossType.rsi,
              indicatorName: 'overbought',
              price: curClose,
              lineValue: curRSI,
              direction: _getCrossDirection(prevRSI, curRSI, 70, 70),
              timestamp: timestamp,
            ));
          }

          // RSI 30（売られすぎ）クロス
          if (_crossed(prevRSI, curRSI, 30, 30)) {
            events.add(CrossEvent(
              symbol: symbol,
              interval: interval,
              type: CrossType.rsi,
              indicatorName: 'oversold',
              price: curClose,
              lineValue: curRSI,
              direction: _getCrossDirection(prevRSI, curRSI, 30, 30),
              timestamp: timestamp,
            ));
          }
        }
      }
    }

    // MACDクロス検知（シグナルラインとゼロライン）
    if (checkMACD) {
      final macd = OscillatorIndicators.calculateMACD(
        closePrices,
        fastPeriod: macdFast,
        slowPeriod: macdSlow,
        signalPeriod: macdSignal,
      );

      if (macd.macdLine.length >= 2 && macd.signalLine.length >= 2) {
        final prevMACD = macd.macdLine[macd.macdLine.length - 2];
        final curMACD = macd.macdLine.last;
        final prevSignal = macd.signalLine[macd.signalLine.length - 2];
        final curSignal = macd.signalLine.last;

        // MACDとシグナルラインのクロス
        if (prevMACD != null && curMACD != null && prevSignal != null && curSignal != null) {
          if (_crossed(prevMACD, curMACD, prevSignal, curSignal)) {
            events.add(CrossEvent(
              symbol: symbol,
              interval: interval,
              type: CrossType.macd,
              indicatorName: 'signal',
              price: curClose,
              lineValue: curMACD,
              direction: _getCrossDirection(prevMACD, curMACD, prevSignal, curSignal),
              timestamp: timestamp,
            ));
          }

          // MACDとゼロラインのクロス
          if (_crossed(prevMACD, curMACD, 0, 0)) {
            events.add(CrossEvent(
              symbol: symbol,
              interval: interval,
              type: CrossType.macd,
              indicatorName: 'zero',
              price: curClose,
              lineValue: curMACD,
              direction: _getCrossDirection(prevMACD, curMACD, 0, 0),
              timestamp: timestamp,
            ));
          }
        }
      }
    }

    // ストキャスティクスクロス検知
    if (checkStochastic) {
      final stoch = OscillatorIndicators.calculateStochastic(
        candles,
        kPeriod: stochKPeriod,
        dPeriod: stochDPeriod,
        smooth: stochSmooth,
      );

      if (stoch.percentK.length >= 2 && stoch.percentD.length >= 2) {
        final prevK = stoch.percentK[stoch.percentK.length - 2];
        final curK = stoch.percentK.last;
        final prevD = stoch.percentD[stoch.percentD.length - 2];
        final curD = stoch.percentD.last;

        if (prevK != null && curK != null && prevD != null && curD != null) {
          // %Kと%Dのクロス
          if (_crossed(prevK, curK, prevD, curD)) {
            events.add(CrossEvent(
              symbol: symbol,
              interval: interval,
              type: CrossType.stochastic,
              indicatorName: 'kd_cross',
              price: curClose,
              lineValue: curK,
              direction: _getCrossDirection(prevK, curK, prevD, curD),
              timestamp: timestamp,
            ));
          }

          // 80（買われすぎ）クロス
          if (_crossed(prevK, curK, 80, 80)) {
            events.add(CrossEvent(
              symbol: symbol,
              interval: interval,
              type: CrossType.stochastic,
              indicatorName: 'overbought',
              price: curClose,
              lineValue: curK,
              direction: _getCrossDirection(prevK, curK, 80, 80),
              timestamp: timestamp,
            ));
          }

          // 20（売られすぎ）クロス
          if (_crossed(prevK, curK, 20, 20)) {
            events.add(CrossEvent(
              symbol: symbol,
              interval: interval,
              type: CrossType.stochastic,
              indicatorName: 'oversold',
              price: curClose,
              lineValue: curK,
              direction: _getCrossDirection(prevK, curK, 20, 20),
              timestamp: timestamp,
            ));
          }
        }
      }
    }

    // CCIクロス検知（±100レベル）
    if (checkCCI) {
      final cci = OscillatorIndicators.calculateCCI(candles, period: cciPeriod);

      if (cci.values.length >= 2) {
        final prevCCI = cci.values[cci.values.length - 2];
        final curCCI = cci.values.last;

        if (prevCCI != null && curCCI != null) {
          // +100クロス
          if (_crossed(prevCCI, curCCI, 100, 100)) {
            events.add(CrossEvent(
              symbol: symbol,
              interval: interval,
              type: CrossType.cci,
              indicatorName: 'upper',
              price: curClose,
              lineValue: curCCI,
              direction: _getCrossDirection(prevCCI, curCCI, 100, 100),
              timestamp: timestamp,
            ));
          }

          // -100クロス
          if (_crossed(prevCCI, curCCI, -100, -100)) {
            events.add(CrossEvent(
              symbol: symbol,
              interval: interval,
              type: CrossType.cci,
              indicatorName: 'lower',
              price: curClose,
              lineValue: curCCI,
              direction: _getCrossDirection(prevCCI, curCCI, -100, -100),
              timestamp: timestamp,
            ));
          }
        }
      }
    }

    return events;
  }

  // クロス履歴を保存（各ラインごとに最新1件のみ保持）
  static Future<void> saveCrossEvent(CrossEvent event) async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString(_crossHistoryKey);
    final history = <Map<String, dynamic>>[];

    if (historyJson != null) {
      final decoded = jsonDecode(historyJson) as List;
      history.addAll(decoded.cast<Map<String, dynamic>>());
    }

    // 同じシンボル、インターバル、インジケーター名の既存イベントを削除（上書き）
    history.removeWhere((json) =>
        json['symbol'] == event.symbol &&
        json['interval'] == event.interval &&
        json['indicatorName'] == event.indicatorName);

    // 新しいイベントを追加
    history.add(event.toJson());

    await prefs.setString(_crossHistoryKey, jsonEncode(history));
  }

  // クロス履歴を取得
  static Future<List<CrossEvent>> getCrossHistory(String symbol) async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getString(_crossHistoryKey);

    if (historyJson == null) return [];

    final decoded = jsonDecode(historyJson) as List;
    return decoded
        .cast<Map<String, dynamic>>()
        .map((json) => CrossEvent.fromJson(json))
        .where((e) => e.symbol == symbol)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
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
    final filtered = decoded
        .cast<Map<String, dynamic>>()
        .where((json) => json['symbol'] != symbol)
        .toList();

    await prefs.setString(_crossHistoryKey, jsonEncode(filtered));
  }
}
