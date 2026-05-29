/// Checkout designer block IDs and fixed Bengali titles.
class CheckoutBlocks {
  CheckoutBlocks._();

  static const defaultOrder = [
    'bkash_personal',
    'nagad_personal',
    'rocket_personal',
    'upay_personal',
    'bkash_agent',
    'nagad_agent',
    'bank_accounts',
  ];

  static const titles = <String, String>{
    'bkash_personal':
        'বিকাশ পার্সোনাল — নিচের নাম্বারগুলোতে সেন্ড মানি অথবা ক্যাশ ইন করুন',
    'nagad_personal':
        'নগদ পার্সোনাল — নিচের নাম্বারগুলোতে সেন্ড মানি অথবা ক্যাশ ইন করুন',
    'rocket_personal':
        'রকেট পার্সোনাল — নিচের নাম্বারগুলোতে সেন্ড মানি অথবা ক্যাশ ইন করুন',
    'upay_personal':
        'উপায় পার্সোনাল — নিচের নাম্বারগুলোতে সেন্ড মানি অথবা ক্যাশ ইন করুন',
    'bkash_agent': 'বিকাশ এজেন্ট — নিচের নাম্বারগুলোতে ক্যাশ আউট করুন',
    'nagad_agent': 'নগদ এজেন্ট — নিচের নাম্বারগুলোতে ক্যাশ আউট করুন',
    'bank_accounts':
        'ব্যাংক — নিচের অ্যাকাউন্ট নাম্বারগুলোতে অবশ্যই NPSB করবেন',
  };

  /// Maps admin template customer_preview / provider tag to block id.
  static String? blockIdForProviderTag(String tag) {
    final t = tag.toLowerCase();
    if (t.contains('bikash') || t.contains('bkash')) {
      return t.contains('agent') ? 'bkash_agent' : 'bkash_personal';
    }
    if (t.contains('nagad')) {
      return t.contains('agent') ? 'nagad_agent' : 'nagad_personal';
    }
    if (t.contains('rocket') || t.contains('16216')) return 'rocket_personal';
    if (t.contains('upay') || t.contains('উপায়')) return 'upay_personal';
    if (t.contains('bank') || t.contains('ব্যাংক')) return 'bank_accounts';
    return null;
  }
}
