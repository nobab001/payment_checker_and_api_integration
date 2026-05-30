class SmsGateway {
  final String id;
  final String name;
  final String apiKey;
  final String username;
  final String endpoint;
  final String senderId;
  final bool isActive;
  final DateTime? createdAt;

  const SmsGateway({
    this.id = '',
    this.name = '',
    this.apiKey = '',
    this.username = '',
    this.endpoint = '',
    this.senderId = '',
    this.isActive = false,
    this.createdAt,
  });

  factory SmsGateway.fromMap(String id, Map<String, dynamic> m) => SmsGateway(
    id: id,
    name: m['name'] as String? ?? '',
    apiKey: m['apiKey'] as String? ?? '',
    username: m['username'] as String? ?? '',
    endpoint: m['endpoint'] as String? ?? '',
    senderId: m['senderId'] as String? ?? '',
    isActive: m['isActive'] as bool? ?? false,
    createdAt: m['createdAt'] != null
        ? (m['createdAt'] is String
              ? DateTime.tryParse(m['createdAt'] as String)
              : (m['createdAt'] as dynamic).toDate())
        : null,
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'apiKey': apiKey,
    'username': username,
    'endpoint': endpoint,
    'senderId': senderId,
    'isActive': isActive,
  };

  SmsGateway copyWith({
    String? id,
    String? name,
    String? apiKey,
    String? username,
    String? endpoint,
    String? senderId,
    bool? isActive,
    DateTime? createdAt,
  }) => SmsGateway(
    id: id ?? this.id,
    name: name ?? this.name,
    apiKey: apiKey ?? this.apiKey,
    username: username ?? this.username,
    endpoint: endpoint ?? this.endpoint,
    senderId: senderId ?? this.senderId,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
  );
}
