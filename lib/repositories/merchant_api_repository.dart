import '../models/checkout_layout.dart';
import '../models/merchant_site.dart';
import '../services/api_service.dart';

class MerchantApiRepository {
  MerchantApiRepository._();
  static final MerchantApiRepository instance = MerchantApiRepository._();

  final _api = ApiService.instance;

  Future<List<MerchantSite>> list() => _api.fetchMerchants();

  Future<MerchantSite> create({
    required String siteName,
    required String domainAddress,
  }) =>
      _api.createMerchant(
        siteName: siteName,
        domainAddress: domainAddress,
      );

  Future<({MerchantSite site, CheckoutLayout layout})> detail(int id) async {
    final data = await _api.fetchMerchantDetail(id);
    final m = Map<String, dynamic>.from(data['merchant'] as Map);
    final layout = CheckoutLayout.fromJson(
      m['checkout_layout'] as Map<String, dynamic>?,
    );
    return (site: MerchantSite.fromJson(m), layout: layout);
  }

  Future<void> setActive(int id, bool active) =>
      _api.patchMerchant(id: id, isActive: active);

  Future<void> saveLayout(int id, CheckoutLayout layout) =>
      _api.saveMerchantCheckoutLayout(id, layout);

  Future<({String apiKeyId, String apiSecret})> regenerateKey({
    required int id,
    required String pin,
  }) =>
      _api.regenerateMerchantApiKey(id: id, pin: pin);
}
