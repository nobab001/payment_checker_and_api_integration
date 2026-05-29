import '../constants/checkout_blocks.dart';
import '../models/sim_filter_preferences.dart';

/// Device Settings → available numbers per provider block.
class CheckoutSimSource {
  final int simSlot;
  final String phone;
  final String providerTag;
  final String blockId;

  const CheckoutSimSource({
    required this.simSlot,
    required this.phone,
    required this.providerTag,
    required this.blockId,
  });
}

List<CheckoutSimSource> buildCheckoutSimSources(SimFilterPreferences prefs) {
  final out = <CheckoutSimSource>[];

  void addSlot(int slot, String number, List<String> tags, bool active) {
    final phone = number.trim();
    if (!active || phone.length < 11) return;
    for (final tag in tags) {
      final blockId = CheckoutBlocks.blockIdForProviderTag(tag);
      if (blockId == null) continue;
      out.add(CheckoutSimSource(
        simSlot: slot,
        phone: phone,
        providerTag: tag,
        blockId: blockId,
      ));
    }
  }

  addSlot(1, prefs.sim1Number, prefs.sim1ProviderTags, prefs.sim1Active);
  addSlot(2, prefs.sim2Number, prefs.sim2ProviderTags, prefs.sim2Active);

  return out;
}

List<CheckoutSimSource> sourcesForBlock(
  List<CheckoutSimSource> all,
  String blockId,
) =>
    all.where((s) => s.blockId == blockId).toList();
