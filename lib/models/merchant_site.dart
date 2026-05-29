class MerchantSite {
  final int id;
  final String siteName;
  final String domainAddress;
  final String slug;
  final String apiKeyId;
  final String? apiSecretOnce;
  final String gatewayUrl;
  final String? gatewayUsername;
  final bool isActive;

  const MerchantSite({
    required this.id,
    required this.siteName,
    required this.domainAddress,
    required this.slug,
    required this.apiKeyId,
    this.apiSecretOnce,
    required this.gatewayUrl,
    this.gatewayUsername,
    required this.isActive,
  });

  factory MerchantSite.fromJson(Map<String, dynamic> j) => MerchantSite(
        id: (j['id'] as num).toInt(),
        siteName: j['site_name']?.toString() ?? '',
        domainAddress: j['domain_address']?.toString() ?? '',
        slug: j['slug']?.toString() ?? '',
        apiKeyId: j['api_key_id']?.toString() ?? '',
        apiSecretOnce: j['api_secret']?.toString(),
        gatewayUrl: j['gateway_url']?.toString() ?? '',
        gatewayUsername: j['gateway_username']?.toString(),
        isActive: j['is_active'] == true ||
            j['is_active'] == 1 ||
            j['is_active'] == 'true' ||
            j['is_active'] == '1',
      );

  MerchantSite copyWith({
    bool? isActive,
    String? apiKeyId,
    String? apiSecretOnce,
  }) =>
      MerchantSite(
        id: id,
        siteName: siteName,
        domainAddress: domainAddress,
        slug: slug,
        apiKeyId: apiKeyId ?? this.apiKeyId,
        apiSecretOnce: apiSecretOnce ?? this.apiSecretOnce,
        gatewayUrl: gatewayUrl,
        gatewayUsername: gatewayUsername,
        isActive: isActive ?? this.isActive,
      );
}
