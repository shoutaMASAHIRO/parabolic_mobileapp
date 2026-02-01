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

// RSIの結果
class RSIResult {
  final List<double?> values;
  final int period;

  RSIResult({required this.values, required this.period});
}

// MACDの結果
class MACDResult {
  final List<double?> macdLine;     // MACD線
  final List<double?> signalLine;   // シグナル線
  final List<double?> histogram;    // ヒストグラム

  MACDResult({
    required this.macdLine,
    required this.signalLine,
    required this.histogram,
  });
}

// ストキャスティクスの結果
class StochasticResult {
  final List<double?> percentK;   // %K
  final List<double?> percentD;   // %D

  StochasticResult({
    required this.percentK,
    required this.percentD,
  });
}

// CCIの結果
class CCIResult {
  final List<double?> values;
  final int period;

  CCIResult({required this.values, required this.period});
}

// オシレーター計算クラス（TechnicalIndicatorsの拡張）
class OscillatorIndicators {
  // RSI（相対力指数）を計算
  static RSIResult calculateRSI(List<double> prices, {int period = 14}) {
    final result = List<double?>.filled(prices.length, null);

    if (prices.length < period + 1) {
      return RSIResult(values: result, period: period);
    }

    // 価格変動を計算
    final gains = <double>[];
    final losses = <double>[];

    for (int i = 1; i < prices.length; i++) {
      final change = prices[i] - prices[i - 1];
      gains.add(change > 0 ? change : 0);
      losses.add(change < 0 ? -change : 0);
    }

    // 最初のRS計算（SMA）
    double avgGain = 0;
    double avgLoss = 0;
    for (int i = 0; i < period; i++) {
      avgGain += gains[i];
      avgLoss += losses[i];
    }
    avgGain /= period;
    avgLoss /= period;

    // 最初のRSI
    if (avgLoss == 0) {
      result[period] = 100;
    } else {
      final rs = avgGain / avgLoss;
      result[period] = 100 - (100 / (1 + rs));
    }

    // 残りのRSI（Wilder's Smoothing Method）
    for (int i = period; i < gains.length; i++) {
      avgGain = (avgGain * (period - 1) + gains[i]) / period;
      avgLoss = (avgLoss * (period - 1) + losses[i]) / period;

      if (avgLoss == 0) {
        result[i + 1] = 100;
      } else {
        final rs = avgGain / avgLoss;
        result[i + 1] = 100 - (100 / (1 + rs));
      }
    }

    return RSIResult(values: result, period: period);
  }

  // MACD（移動平均収束拡散）を計算
  static MACDResult calculateMACD(
    List<double> prices, {
    int fastPeriod = 12,
    int slowPeriod = 26,
    int signalPeriod = 9,
  }) {
    final length = prices.length;
    final macdLine = List<double?>.filled(length, null);
    final signalLine = List<double?>.filled(length, null);
    final histogram = List<double?>.filled(length, null);

    if (length < slowPeriod) {
      return MACDResult(
        macdLine: macdLine,
        signalLine: signalLine,
        histogram: histogram,
      );
    }

    // Fast EMAとSlow EMAを計算
    final fastEMA = TechnicalIndicators.calculateEMA(prices, fastPeriod);
    final slowEMA = TechnicalIndicators.calculateEMA(prices, slowPeriod);

    // MACDライン = Fast EMA - Slow EMA
    final macdValues = <double>[];
    for (int i = 0; i < length; i++) {
      if (fastEMA[i] != null && slowEMA[i] != null) {
        macdLine[i] = fastEMA[i]! - slowEMA[i]!;
        macdValues.add(macdLine[i]!);
      }
    }

    // シグナルライン = MACDラインのEMA
    if (macdValues.length >= signalPeriod) {
      final signalEMA = TechnicalIndicators.calculateEMA(macdValues, signalPeriod);

      // シグナル値をマッピング
      int signalIdx = 0;
      for (int i = 0; i < length; i++) {
        if (macdLine[i] != null) {
          if (signalIdx < signalEMA.length && signalEMA[signalIdx] != null) {
            signalLine[i] = signalEMA[signalIdx];
            histogram[i] = macdLine[i]! - signalLine[i]!;
          }
          signalIdx++;
        }
      }
    }

    return MACDResult(
      macdLine: macdLine,
      signalLine: signalLine,
      histogram: histogram,
    );
  }

  // ストキャスティクスを計算
  static StochasticResult calculateStochastic(
    List<Candle> candles, {
    int kPeriod = 14,
    int dPeriod = 3,
    int smooth = 3,
  }) {
    final length = candles.length;
    final rawK = List<double?>.filled(length, null);
    final percentK = List<double?>.filled(length, null);
    final percentD = List<double?>.filled(length, null);

    if (length < kPeriod) {
      return StochasticResult(percentK: percentK, percentD: percentD);
    }

    // Raw %K を計算
    for (int i = kPeriod - 1; i < length; i++) {
      double highestHigh = candles[i].high;
      double lowestLow = candles[i].low;

      for (int j = i - kPeriod + 1; j <= i; j++) {
        if (candles[j].high > highestHigh) highestHigh = candles[j].high;
        if (candles[j].low < lowestLow) lowestLow = candles[j].low;
      }

      final range = highestHigh - lowestLow;
      if (range > 0) {
        rawK[i] = ((candles[i].close - lowestLow) / range) * 100;
      } else {
        rawK[i] = 50; // レンジがない場合は中間値
      }
    }

    // %K（Raw %KのSMA）を計算
    for (int i = kPeriod - 1 + smooth - 1; i < length; i++) {
      double sum = 0;
      int count = 0;
      for (int j = i - smooth + 1; j <= i; j++) {
        if (rawK[j] != null) {
          sum += rawK[j]!;
          count++;
        }
      }
      if (count > 0) {
        percentK[i] = sum / count;
      }
    }

    // %D（%KのSMA）を計算
    for (int i = kPeriod - 1 + smooth - 1 + dPeriod - 1; i < length; i++) {
      double sum = 0;
      int count = 0;
      for (int j = i - dPeriod + 1; j <= i; j++) {
        if (percentK[j] != null) {
          sum += percentK[j]!;
          count++;
        }
      }
      if (count > 0) {
        percentD[i] = sum / count;
      }
    }

    return StochasticResult(percentK: percentK, percentD: percentD);
  }

  // CCI（商品チャンネル指数）を計算
  static CCIResult calculateCCI(List<Candle> candles, {int period = 20}) {
    final length = candles.length;
    final result = List<double?>.filled(length, null);

    if (length < period) {
      return CCIResult(values: result, period: period);
    }

    // Typical Price = (High + Low + Close) / 3
    final typicalPrices = candles
        .map((c) => (c.high + c.low + c.close) / 3)
        .toList();

    for (int i = period - 1; i < length; i++) {
      // SMA of Typical Price
      double sum = 0;
      for (int j = i - period + 1; j <= i; j++) {
        sum += typicalPrices[j];
      }
      final sma = sum / period;

      // Mean Deviation
      double meanDev = 0;
      for (int j = i - period + 1; j <= i; j++) {
        meanDev += (typicalPrices[j] - sma).abs();
      }
      meanDev /= period;

      // CCI = (Typical Price - SMA) / (0.015 * Mean Deviation)
      if (meanDev > 0) {
        result[i] = (typicalPrices[i] - sma) / (0.015 * meanDev);
      } else {
        result[i] = 0;
      }
    }

    return CCIResult(values: result, period: period);
  }
}
