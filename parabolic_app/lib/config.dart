import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

// API設定
class AppConfig {
  // 開発環境: ローカルサーバーのURL
  // エミュレータからlocalhostにアクセスする場合:
  // - Android: 10.0.2.2
  // - iOS Simulator: localhost
  // 実機テストの場合は実際のIPアドレスを使用

  // 本番環境: デプロイされたサーバーのURL
  static const String prodBaseUrl = 'https://your-production-server.com';

  // 現在の環境設定
  static const bool isProduction = false;

  // 開発環境のベースURL（プラットフォームごとに自動判定）
  static String get _devBaseUrl {
    if (kIsWeb) {
      // Web: ブラウザから直接アクセス
      return 'http://localhost:3000';
    }

    // モバイル/デスクトップ
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        // Androidエミュレータ: 10.0.2.2はホストマシンのlocalhost
        return 'http://10.0.2.2:3000';
      case TargetPlatform.iOS:
        // iOSシミュレータ: localhostが直接使える
        return 'http://localhost:3000';
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        // デスクトップアプリ
        return 'http://localhost:3000';
    }
  }

  // 使用するベースURL
  static String get baseUrl => isProduction ? prodBaseUrl : _devBaseUrl;

  // APIエンドポイント
  static String get apiUrl => baseUrl;

  // Socket.IO URL
  static String get socketUrl => baseUrl;
}
