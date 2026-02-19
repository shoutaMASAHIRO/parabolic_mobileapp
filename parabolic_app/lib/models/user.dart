class User {
  final int id;
  final String email;
  final String username;

  User({
    required this.id,
    required this.email,
    required this.username,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      email: json['email'] as String,
      username: json['username'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
    };
  }
}

class Memo {
  final int id;
  final int? userId;
  final String symbol;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  Memo({
    required this.id,
    this.userId,
    required this.symbol,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Memo.fromJson(Map<String, dynamic> json) {
    return Memo(
      id: json['id'] as int,
      userId: json['user_id'] as int?,
      symbol: json['symbol'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
