# Parabolic Chart & Alert

リアルタイムの株式・為替チャートを表示し、テクニカル指標のクロスと価格閾値の到達をトリガーに通知を行う、バックエンドAPIおよびクライアントアプリケーションです。

## アーキテクチャ概要

このプロジェクトは、独立した2つのコンポーネントで構成されています。

1.  **バックエンドAPI (`/`)**: Node.jsで構築されたAPIサーバーです。データ取得、ユーザー認証、リアルタイム通信（Socket.IO）、アラート通知（メール）などのコアロジックを担当します。
2.  **フロントエンド (`/parabolic_app`)**: Flutterで構築されたクロスプラットフォームアプリケーションです。バックエンドAPIと通信し、チャート表示やユーザー操作などのUI/UXを提供します。

## 主な機能

-   **リアルタイムチャート**: `fl_chart`を利用した軽快なチャート表示。
-   **マルチアセット対応**: 日本株とUSD/JPY為替レートの表示を切り替え可能。
-   **テクニカル指標**: ボリンジャーバンドと指数平滑移動平均（EMA）をチャート上に表示。
-   **クロス判定**: 終値が各指標ラインをまたいだ（クロスした）瞬間を検知し、画面にリアルタイムで通知。
-   **閾値アラート**: クロス発生後、価格がユーザー設定の閾値に到達した場合にバックエンドからメールで通知。
-   **永続的な設定**: ユーザーごとの銘柄、チャート設定、アラート閾値などをデータベースに保存。
-   **ユーザー認証**: ログイン・ログアウト機能、永続セッション管理。

## 技術スタック

#### バックエンド (Node.js)

-   **Node.js**: サーバーサイドJavaScriptランタイム
-   **Express.js**: Webアプリケーションフレームワーク
-   **PostgreSQL**: リレーショナルデータベース
-   **Socket.IO**: リアルタイム双方向通信
-   **pg**: Node.js用PostgreSQLクライアント
-   **nodemailer**: メール送信ライブラリ
-   **bcrypt**: パスワードハッシュ化
-   **express-session**: セッション管理

#### フロントエンド (Flutter)

-   **Flutter / Dart**: クロスプラットフォームUIツールキット
-   **provider**: 状態管理
-   **http**: REST API通信
-   **socket_io_client**: リアルタイム双方向通信
-   **fl_chart**: 高機能なチャート描画
-   **shared_preferences**: ローカルデータ永続化

#### インフラ & その他

-   **Docker / Docker Compose**: コンテナ化およびサービスオーケストレーション
-   **PM2**: Node.jsプロセス管理
-   **Nginx**: リバースプロキシ（構成ファイル同梱）
-   **AWS SSM Parameter Store**: 機密情報（Gmail認証情報）の管理
-   **Yahoo Finance API**: 株価および為替レートのデータソース

## プロジェクト構造

```
.
├── server.js               # バックエンドAPIサーバー (Express, Socket.IO)
├── parabolic_app/          # Flutterフロントエンドアプリケーション
│   ├── lib/                # FlutterアプリのDartソースコード
│   ├── pubspec.yaml        # Flutterアプリの依存関係定義
│   └── (他プラットフォーム別ディレクトリ)
├── Dockerfile              # バックエンドAPIのDockerイメージをビルド
├── docker-compose.yml      # 本番環境用のDocker Compose設定
├── ecosystem.config.js     # PM2のプロセス管理設定
├── package.json            # Node.jsの依存関係とスクリプト
├── init-db.sql             # データベース初期化用のSQLスクリプト
└── nginx.conf              # Nginxリバースプロキシ用の設定ファイル
```

## セットアップと起動

### 前提条件

-   **バックエンド**:
    -   Docker & Docker Compose
    -   Node.js & npm
-   **フロントエンド**:
    -   Flutter SDK

### 1. バックエンドAPIの起動

バックエンドはローカルマシンまたはDockerコンテナで実行できます。

#### 環境変数の設定

プロジェクトのルートに`.env`ファイルを作成し、データベース接続情報などを設定します。

```ini
# PostgreSQL データベース接続URL
# (Dockerで起動する場合、ホスト名は 'db' になります)
DATABASE_URL=postgresql://user:password@host:port/dbname

# Express-session の秘密鍵
SESSION_SECRET=your_very_secret_key_here

# AWS設定（SSMからGmail認証情報を取得するため）
AWS_REGION=ap-northeast-1
# ※ローカルで実行する場合は、別途 ~/.aws/credentials の設定が必要です

# セッションクッキーをセキュアにするか (本番環境では 'true')
COOKIE_SECURE=false
```

#### Dockerでの起動 (推奨)

1.  **環境変数の設定**: `.env`ファイルで`DATABASE_URL`のホスト名を`db`に設定します。
2.  **コンテナのビルドと起動**:
    ```bash
    # 本番環境(EC2等)の場合
    docker-compose up -d --build

    # ローカル開発でAWS認証情報が必要な場合
    docker-compose -f docker-compose.yml -f docker-compose.local.yml up -d --build
    ```
    APIサーバーは`http://localhost:3000`で利用可能になります。

#### ローカルでの起動

1.  `npm install`で依存関係をインストールします。
2.  別途PostgreSQLを起動し、`init-db.sql`でテーブルを作成します。
3.  `node server.js`でサーバーを起動します。

### 2. フロントエンドアプリの起動

1.  **APIサーバーの接続先設定**:
    `parabolic_app/lib/config.dart`などの設定ファイルを開き、バックエンドAPIのURL（例: `http://localhost:3000`）が正しく設定されていることを確認してください。

2.  **ディレクトリの移動**:
    ```bash
    cd parabolic_app
    ```

3.  **依存関係のインストール**:
    ```bash
    flutter pub get
    ```

4.  **アプリケーションの実行**:
    （接続したいデバイスを選択した上で）以下のコマンドを実行します。
    ```bash
    flutter run
    ```

## アーキテクチャのポイント

-   **関心の分離**: バックエンドAPIとフロントエンドUIが明確に分離されているため、それぞれ独立して開発・デプロイが可能です。将来的にWebフロントエンドや他のクライアントを追加することも容易です。
-   **柔軟なユーザー設定**: PostgreSQLの`JSONB`型を積極的に活用し、ユーザーごとの多様な設定（UI、アラート条件など）をスキーマ変更なしで柔軟に管理しています。
-   **堅牢なプロセス管理**: 本番環境では、Dockerコンテナ内でPM2がNode.jsプロセスを管理します。これにより、プロセスの自動復旧やクラスタリングが可能になります。
-   **安全なシークレット管理**: メール送信用のパスワードなどの機密情報はコードに直接記述せず、AWS SSM Parameter Storeで一元管理しています。