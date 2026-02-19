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

  // SMA（単純移動平均）を計算

  static List<double?> calculateSMA(List<double> prices, int period) {

    if (prices.length < period) {

      return List.filled(prices.length, null);

    }



    final result = List<double?>.filled(prices.length, null);

    double sum = 0;

    for (int i = 0; i < period; i++) {

      sum += prices[i];

    }

    result[period - 1] = sum / period;



    for (int i = period; i < prices.length; i++) {

      sum = sum - prices[i - period] + prices[i];

      result[i] = sum / period;

    }



    return result;

  }



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



  // WMA（加重移動平均）を計算

  static List<double?> calculateWMA(List<double> prices, int period) {

    if (prices.length < period) {

      return List.filled(prices.length, null);

    }



    final result = List<double?>.filled(prices.length, null);

    final divisor = period * (period + 1) / 2;



    for (int i = period - 1; i < prices.length; i++) {

      double sum = 0;

      for (int j = 0; j < period; j++) {

        sum += prices[i - j] * (period - j);

      }

      result[i] = sum / divisor;

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



  // 一目均衡表を計算

  static IchimokuResult calculateIchimoku(List<Candle> candles, {

    int tenkanPeriod = 9,

    int kijunPeriod = 26,

    int senkouBPeriod = 52,

    int displacement = 26,

  }) {

    final length = candles.length;

    final tenkan = List<double?>.filled(length, null);

    final kijun = List<double?>.filled(length, null);

    final senkouA = List<double?>.filled(length + displacement, null);

    final senkouB = List<double?>.filled(length + displacement, null);

    final chikou = List<double?>.filled(length, null);



    double? getHighLowMid(int endIdx, int period) {

      if (endIdx < period - 1) return null;

      double h = candles[endIdx].high;

      double l = candles[endIdx].low;

      for (int i = endIdx - period + 1; i <= endIdx; i++) {

        if (candles[i].high > h) h = candles[i].high;

        if (candles[i].low < l) l = candles[i].low;

      }

      return (h + l) / 2;

    }



    for (int i = 0; i < length; i++) {

      tenkan[i] = getHighLowMid(i, tenkanPeriod);

      kijun[i] = getHighLowMid(i, kijunPeriod);

      

      if (tenkan[i] != null && kijun[i] != null) {

        senkouA[i + displacement] = (tenkan[i]! + kijun[i]!) / 2;

      }

      senkouB[i + displacement] = getHighLowMid(i, senkouBPeriod);



      if (i + displacement < length) {

        chikou[i] = candles[i + displacement].close;

      }

    }



    return IchimokuResult(

      tenkan: tenkan,

      kijun: kijun,

      senkouA: senkouA,

      senkouB: senkouB,

      chikou: chikou,

    );

  }



  // パラボリックSARを計算

  static List<double?> calculateParabolicSAR(List<Candle> candles, {

    double acceleration = 0.02,

    double maxAcceleration = 0.2,

  }) {

    if (candles.length < 2) return List.filled(candles.length, null);



    final sar = List<double?>.filled(candles.length, null);

    bool isBull = candles[1].close > candles[0].close;

    double ep = isBull ? candles[1].high : candles[1].low;

    double af = acceleration;

    sar[1] = isBull ? candles[0].low : candles[0].high;



    for (int i = 2; i < candles.length; i++) {

      double prevSar = sar[i - 1]!;

      sar[i] = prevSar + af * (ep - prevSar);



      if (isBull) {

        if (candles[i - 1].low < sar[i]!) sar[i] = candles[i - 1].low;

        if (candles[i - 2].low < sar[i]!) sar[i] = candles[i - 2].low;



        if (candles[i].high > ep) {

          ep = candles[i].high;

          af = math.min(af + acceleration, maxAcceleration);

        }



        if (candles[i].low < sar[i]!) {

          isBull = false;

          sar[i] = ep;

          ep = candles[i].low;

          af = acceleration;

        }

      } else {

        if (candles[i - 1].high > sar[i]!) sar[i] = candles[i - 1].high;

        if (candles[i - 2].high > sar[i]!) sar[i] = candles[i - 2].high;



        if (candles[i].low < ep) {

          ep = candles[i].low;

          af = math.min(af + acceleration, maxAcceleration);

        }



        if (candles[i].high > sar[i]!) {

          isBull = true;

          sar[i] = ep;

          ep = candles[i].high;

          af = acceleration;

        }

      }

    }

    return sar;

  }



  // エンベロープを計算

  static EnvelopeResult calculateEnvelope(List<double> prices, {int period = 20, double deviation = 2.5}) {

    final sma = calculateSMA(prices, period);

    final upper = List<double?>.filled(prices.length, null);

    final lower = List<double?>.filled(prices.length, null);



    for (int i = 0; i < prices.length; i++) {

      if (sma[i] != null) {

        upper[i] = sma[i]! * (1 + deviation / 100);

        lower[i] = sma[i]! * (1 - deviation / 100);

      }

    }



    return EnvelopeResult(middle: sma, upper: upper, lower: lower);

  }



  // ATR（平均真の範囲）を計算

  static List<double?> calculateATR(List<Candle> candles, int period) {

    if (candles.length < 2) return List.filled(candles.length, null);

    

    final tr = List<double>.filled(candles.length, 0);

    tr[0] = candles[0].high - candles[0].low;

    

    for (int i = 1; i < candles.length; i++) {

      double highLow = candles[i].high - candles[i].low;

      double highClose = (candles[i].high - candles[i - 1].close).abs();

      double lowClose = (candles[i].low - candles[i - 1].close).abs();

      tr[i] = math.max(highLow, math.max(highClose, lowClose));

    }



    final atr = List<double?>.filled(candles.length, null);

    double sum = 0;

    for (int i = 0; i < period; i++) sum += tr[i];

    atr[period - 1] = sum / period;



    for (int i = period; i < candles.length; i++) {

      atr[i] = (atr[i - 1]! * (period - 1) + tr[i]) / period;

    }



    return atr;

  }



  // ケルトナーチャネルを計算

  static KeltnerResult calculateKeltnerChannel(List<Candle> candles, {int period = 20, double multiplier = 2.0}) {

    final prices = candles.map((c) => c.close).toList();

    final middle = calculateEMA(prices, period);

    final atr = calculateATR(candles, period);

    final upper = List<double?>.filled(candles.length, null);

    final lower = List<double?>.filled(candles.length, null);



    for (int i = 0; i < candles.length; i++) {

      if (middle[i] != null && atr[i] != null) {

        upper[i] = middle[i]! + (atr[i]! * multiplier);

        lower[i] = middle[i]! - (atr[i]! * multiplier);

      }

    }



    return KeltnerResult(middle: middle, upper: upper, lower: lower);

  }



  // スーパートレンドを計算

  static SupertrendResult calculateSupertrend(List<Candle> candles, {int period = 10, double multiplier = 3.0}) {

    final atr = calculateATR(candles, period);

    final length = candles.length;

    final upperBand = List<double?>.filled(length, null);

    final lowerBand = List<double?>.filled(length, null);

    final trend = List<double?>.filled(length, null);

    final isBull = List<bool>.filled(length, true);



    if (length < period) return SupertrendResult(values: trend, isBull: isBull);



    for (int i = period - 1; i < length; i++) {

      double median = (candles[i].high + candles[i].low) / 2;

      double basicUpper = median + multiplier * atr[i]!;

      double basicLower = median - multiplier * atr[i]!;



      if (i == period - 1) {

        upperBand[i] = basicUpper;

        lowerBand[i] = basicLower;

        trend[i] = candles[i].close > basicUpper ? basicLower : basicUpper;

        isBull[i] = candles[i].close > basicUpper;

      } else {

        upperBand[i] = (basicUpper < upperBand[i - 1]! || candles[i - 1].close > upperBand[i - 1]!) ? basicUpper : upperBand[i - 1];

        lowerBand[i] = (basicLower > lowerBand[i - 1]! || candles[i - 1].close < lowerBand[i - 1]!) ? basicLower : lowerBand[i - 1];



        if (isBull[i - 1]) {

          isBull[i] = candles[i].close >= lowerBand[i]!;

        } else {

          isBull[i] = candles[i].close > upperBand[i]!;

        }

        

        trend[i] = isBull[i] ? lowerBand[i] : upperBand[i];

      }

    }



    return SupertrendResult(values: trend, isBull: isBull);

  }



  // GMMAを計算

  static GMMAResult calculateGMMA(List<double> prices) {

    final shortPeriods = [3, 5, 8, 10, 12, 15];

    final longPeriods = [30, 35, 40, 45, 50, 60];

    

    final shortEma = shortPeriods.map((p) => calculateEMA(prices, p)).toList();

    final longEma = longPeriods.map((p) => calculateEMA(prices, p)).toList();



    return GMMAResult(shortTerm: shortEma, longTerm: longEma);

  }

}



// ボリンジャーバンドの結果

class BollingerBandsResult {

  final List<double?> middle, upper1, lower1, upper2, lower2;

  BollingerBandsResult({required this.middle, required this.upper1, required this.lower1, required this.upper2, required this.lower2});

}



class IchimokuResult {

  final List<double?> tenkan, kijun, senkouA, senkouB, chikou;

  IchimokuResult({required this.tenkan, required this.kijun, required this.senkouA, required this.senkouB, required this.chikou});

}



class EnvelopeResult {

  final List<double?> middle, upper, lower;

  EnvelopeResult({required this.middle, required this.upper, required this.lower});

}



class KeltnerResult {

  final List<double?> middle, upper, lower;

  KeltnerResult({required this.middle, required this.upper, required this.lower});

}



class SupertrendResult {

  final List<double?> values;

  final List<bool> isBull;

  SupertrendResult({required this.values, required this.isBull});

}



class GMMAResult {

  final List<List<double?>> shortTerm, longTerm;

  GMMAResult({required this.shortTerm, required this.longTerm});

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



class DMIResult {

  final List<double?> plusDI, minusDI, adx;

  DMIResult({required this.plusDI, required this.minusDI, required this.adx});

}



// オシレーター計算クラス（TechnicalIndicatorsの拡張）

class OscillatorIndicators {

  // 移動平均乖離率を計算

  static List<double?> calculateMADeviation(List<double> prices, {int period = 25}) {

    final sma = TechnicalIndicators.calculateSMA(prices, period);

    final result = List<double?>.filled(prices.length, null);

    for (int i = 0; i < prices.length; i++) {

      if (sma[i] != null && sma[i] != 0) {

        result[i] = ((prices[i] - sma[i]!) / sma[i]!) * 100;

      }

    }

    return result;

  }



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



  // DMI / ADX を計算

  static DMIResult calculateDMI(List<Candle> candles, {int period = 14}) {

    final length = candles.length;

    final plusDI = List<double?>.filled(length, null);

    final minusDI = List<double?>.filled(length, null);

    final adx = List<double?>.filled(length, null);



    if (length < period + 1) return DMIResult(plusDI: plusDI, minusDI: minusDI, adx: adx);



    final plusDM = List<double>.filled(length, 0);

    final minusDM = List<double>.filled(length, 0);

    final tr = List<double>.filled(length, 0);



    for (int i = 1; i < length; i++) {

      double upMove = candles[i].high - candles[i - 1].high;

      double downMove = candles[i - 1].low - candles[i].low;

      

      if (upMove > downMove && upMove > 0) plusDM[i] = upMove;

      if (downMove > upMove && downMove > 0) minusDM[i] = downMove;

      

      double hl = candles[i].high - candles[i].low;

      double hc = (candles[i].high - candles[i - 1].close).abs();

      double lc = (candles[i].low - candles[i - 1].close).abs();

      tr[i] = math.max(hl, math.max(hc, lc));

    }



    double smoothTR = 0, smoothPlusDM = 0, smoothMinusDM = 0;

    for (int i = 1; i <= period; i++) {

      smoothTR += tr[i]; smoothPlusDM += plusDM[i]; smoothMinusDM += minusDM[i];

    }



    final dx = List<double?>.filled(length, null);



    for (int i = period; i < length; i++) {

      if (i > period) {

        smoothTR = smoothTR - (smoothTR / period) + tr[i];

        smoothPlusDM = smoothPlusDM - (smoothPlusDM / period) + plusDM[i];

        smoothMinusDM = smoothMinusDM - (smoothMinusDM / period) + minusDM[i];

      }



      plusDI[i] = (smoothPlusDM / smoothTR) * 100;

      minusDI[i] = (smoothMinusDM / smoothTR) * 100;

      

      double diSum = plusDI[i]! + minusDI[i]!;

      double diDiff = (plusDI[i]! - minusDI[i]!).abs();

      dx[i] = diSum == 0 ? 0 : (diDiff / diSum) * 100;

    }



    double dxSum = 0;

    for (int i = period; i < period * 2; i++) dxSum += dx[i]!;

    adx[period * 2 - 1] = dxSum / period;



    for (int i = period * 2; i < length; i++) {

      adx[i] = (adx[i - 1]! * (period - 1) + dx[i]!) / period;

    }



    return DMIResult(plusDI: plusDI, minusDI: minusDI, adx: adx);

  }



  // RCI（順位相関指数）を計算

  static List<double?> calculateRCI(List<double> prices, {int period = 9}) {

    final length = prices.length;

    final rci = List<double?>.filled(length, null);

    if (length < period) return rci;



    for (int i = period - 1; i < length; i++) {

      final subset = prices.sublist(i - period + 1, i + 1);

      final sorted = List.from(subset)..sort((a, b) => b.compareTo(a));

      

      double d2 = 0;

      for (int j = 0; j < period; j++) {

        int dateRank = period - j;

        int priceRank = sorted.indexOf(subset[j]) + 1;

        // 同順位がある場合の処理（簡易版）

        d2 += math.pow(dateRank - priceRank, 2);

      }

      rci[i] = (1 - (6 * d2) / (period * (math.pow(period, 2) - 1))) * 100;

    }

    return rci;

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



  // モメンタムを計算

  static List<double?> calculateMomentum(List<double> prices, {int period = 10}) {

    final result = List<double?>.filled(prices.length, null);

    for (int i = period; i < prices.length; i++) {

      result[i] = prices[i] - prices[i - period];

    }

    return result;

  }



  // ROC（変化率）を計算

  static List<double?> calculateROC(List<double> prices, {int period = 12}) {

    final result = List<double?>.filled(prices.length, null);

    for (int i = period; i < prices.length; i++) {

      if (prices[i - period] != 0) {

        result[i] = ((prices[i] - prices[i - period]) / prices[i - period]) * 100;

      }

    }

    return result;

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



  // アルティメット・オシレーターを計算

  static List<double?> calculateUltimateOscillator(List<Candle> candles, {int p1 = 7, int p2 = 14, int p3 = 28}) {

    final length = candles.length;

    final uo = List<double?>.filled(length, null);

    if (length < p3 + 1) return uo;



    final bp = List<double>.filled(length, 0);

    final tr = List<double>.filled(length, 0);



    for (int i = 1; i < length; i++) {

      double lowPrevClose = math.min(candles[i].low, candles[i - 1].close);

      double highPrevClose = math.max(candles[i].high, candles[i - 1].close);

      bp[i] = candles[i].close - lowPrevClose;

      tr[i] = highPrevClose - lowPrevClose;

    }



    for (int i = p3; i < length; i++) {

      double avg7 = bp.sublist(i - 6, i + 1).reduce((a, b) => a + b) / tr.sublist(i - 6, i + 1).reduce((a, b) => a + b);

      double avg14 = bp.sublist(i - 13, i + 1).reduce((a, b) => a + b) / tr.sublist(i - 13, i + 1).reduce((a, b) => a + b);

      double avg28 = bp.sublist(i - 27, i + 1).reduce((a, b) => a + b) / tr.sublist(i - 27, i + 1).reduce((a, b) => a + b);

      uo[i] = 100 * (4 * avg7 + 2 * avg14 + avg28) / 7;

    }

    return uo;

  }



  // TRIXを計算

  static List<double?> calculateTRIX(List<double> prices, {int period = 12}) {

    final ema1 = TechnicalIndicators.calculateEMA(prices, period);

    final ema2Values = <double>[];

    for (var v in ema1) if (v != null) ema2Values.add(v);

    

    if (ema2Values.length < period) return List.filled(prices.length, null);

    final ema2 = TechnicalIndicators.calculateEMA(ema2Values, period);

    

    final ema3Values = <double>[];

    for (var v in ema2) if (v != null) ema3Values.add(v);

    

    if (ema3Values.length < period) return List.filled(prices.length, null);

    final ema3Full = TechnicalIndicators.calculateEMA(ema3Values, period);

    

    // Map back to original length

    final ema3 = List<double?>.filled(prices.length, null);

    int offset = prices.length - ema3Full.length;

    for (int i = 0; i < ema3Full.length; i++) ema3[i + offset] = ema3Full[i];



    final trix = List<double?>.filled(prices.length, null);

    for (int i = 1; i < prices.length; i++) {

      if (ema3[i] != null && ema3[i - 1] != null && ema3[i - 1] != 0) {

        trix[i] = (ema3[i]! - ema3[i - 1]!) / ema3[i - 1]! * 100;

      }

    }

    return trix;

  }

}


