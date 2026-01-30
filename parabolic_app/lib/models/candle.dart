import 'dart:math' as math;

class Candle {
  final DateTime date;
  final double open;
  final double high;
  final double low;
  final double close;

  Candle({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });

  factory Candle.fromJson(Map<String, dynamic> json) {
    return Candle(
      date: DateTime.parse(json['date'] as String),
      open: (json['open'] as num).toDouble(),
      high: (json['high'] as num).toDouble(),
      low: (json['low'] as num).toDouble(),
      close: (json['close'] as num).toDouble(),
    );
  }

  // 変動率を計算
  double get changePercent => ((close - open) / open) * 100;

  bool get isPositive => close >= open;

  // 平均足（Heikin-Ashi）を計算
  static List<Candle> toHeikinAshi(List<Candle> candles) {
    if (candles.isEmpty) return [];

    final result = <Candle>[];

    for (int i = 0; i < candles.length; i++) {
      final current = candles[i];

      // HA Close = (Open + High + Low + Close) / 4
      final haClose = (current.open + current.high + current.low + current.close) / 4;

      // HA Open = (前のHA Open + 前のHA Close) / 2
      final haOpen = i == 0
          ? (current.open + current.close) / 2
          : (result[i - 1].open + result[i - 1].close) / 2;

      // HA High = max(High, HA Open, HA Close)
      final haHigh = [current.high, haOpen, haClose].reduce((a, b) => a > b ? a : b);

      // HA Low = min(Low, HA Open, HA Close)
      final haLow = [current.low, haOpen, haClose].reduce((a, b) => a < b ? a : b);

      result.add(Candle(
        date: current.date,
        open: haOpen,
        high: haHigh,
        low: haLow,
        close: haClose,
      ));
    }

    return result;
  }
}

// テクニカル指標計算クラス
class TechnicalIndicators {
  // EMA（指数移動平均）を計算
  static List<double?> calculateEMA(List<double> prices, int period) {
    if (prices.length < period) {
      return List.filled(prices.length, null);
    }

    final result = List<double?>.filled(prices.length, null);
    final multiplier = 2.0 / (period + 1);

    // 最初のEMAはSMAで初期化
    double sum = 0;
    for (int i = 0; i < period; i++) {
      sum += prices[i];
    }
    result[period - 1] = sum / period;

    // 残りはEMA計算
    for (int i = period; i < prices.length; i++) {
      result[i] = (prices[i] - result[i - 1]!) * multiplier + result[i - 1]!;
    }

    return result;
  }

  // ボリンジャーバンドを計算
  static BollingerBandsResult calculateBollingerBands(
    List<double> prices, {
    int period = 20,
    double stdDev1 = 1.0,
    double stdDev2 = 2.0,
  }) {
    final middle = List<double?>.filled(prices.length, null);
    final upper1 = List<double?>.filled(prices.length, null);
    final lower1 = List<double?>.filled(prices.length, null);
    final upper2 = List<double?>.filled(prices.length, null);
    final lower2 = List<double?>.filled(prices.length, null);

    if (prices.length < period) {
      return BollingerBandsResult(
        middle: middle,
        upper1: upper1,
        lower1: lower1,
        upper2: upper2,
        lower2: lower2,
      );
    }

    for (int i = period - 1; i < prices.length; i++) {
      // SMA計算
      double sum = 0;
      for (int j = i - period + 1; j <= i; j++) {
        sum += prices[j];
      }
      final sma = sum / period;
      middle[i] = sma;

      // 標準偏差計算
      double variance = 0;
      for (int j = i - period + 1; j <= i; j++) {
        variance += math.pow(prices[j] - sma, 2);
      }
      final std = math.sqrt(variance / period);

      upper1[i] = sma + std * stdDev1;
      lower1[i] = sma - std * stdDev1;
      upper2[i] = sma + std * stdDev2;
      lower2[i] = sma - std * stdDev2;
    }

    return BollingerBandsResult(
      middle: middle,
      upper1: upper1,
      lower1: lower1,
      upper2: upper2,
      lower2: lower2,
    );
  }
}

// ボリンジャーバンドの結果
class BollingerBandsResult {
  final List<double?> middle; // 0σ (SMA)
  final List<double?> upper1; // +1σ
  final List<double?> lower1; // -1σ
  final List<double?> upper2; // +2σ
  final List<double?> lower2; // -2σ

  BollingerBandsResult({
    required this.middle,
    required this.upper1,
    required this.lower1,
    required this.upper2,
    required this.lower2,
  });
}
