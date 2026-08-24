import 'pipeline/ecom_ad_handler_response.dart';

// /buy and POST /recommend both now get the exact same EcomHubInput payload
// just posted to /inp (see pipeline_coordinator.dart), so a result from
// either one is a genuine match for the current object - merge both, buy
// first. GET /recommend is never used: it takes no body at all, so it can't
// carry that same-payload guarantee and has been observed returning generic
// content regardless of input.
List<Map<String, String>> extractEcomRecommendations(EcomAdHandlerRaw raw, {int limit = 4}) {
  final buyMatches = extractRecommendations(raw.buy, limit: limit);
  final recommendMatches = extractRecommendations(raw.recommendPost, limit: limit);
  final seenNames = buyMatches.map((item) => item['name']).toSet();
  final merged = [
    ...buyMatches,
    ...recommendMatches.where((item) => !seenNames.contains(item['name'])),
  ];
  return merged.take(limit).toList();
}

// Best-effort extraction only - the ecom hub's real response shape isn't
// documented (see pipeline/ecom_ad_handler_response.dart), so this looks for
// common list/name/price/description/url conventions and leaves a field out
// entirely rather than fabricate one that might not exist. Shared across the
// home, live-session, matched-products and product-detail screens.
List<Map<String, String>> extractRecommendations(dynamic raw, {int limit = 4}) {
  List<dynamic>? items;
  if (raw is List) {
    items = raw;
  } else if (raw is Map) {
    // The real ecom hub /recommend response splits results across
    // organic_feed and sponsored_feed instead of one list - merge both
    // (organic first) rather than only ever picking whichever key matches first.
    final combined = <dynamic>[];
    for (final key in ['organic_feed', 'sponsored_feed', 'items', 'products', 'recommendations', 'results', 'data']) {
      final value = raw[key];
      if (value is List) combined.addAll(value);
    }
    if (combined.isNotEmpty) items = combined;
  }
  if (items == null) return const [];

  const nameKeys = ['name', 'title', 'product', 'product_name', 'label'];
  const priceKeys = ['price', 'cost', 'amount'];
  const descriptionKeys = ['description', 'summary', 'details', 'blurb'];
  const urlKeys = ['url', 'link', 'product_url', 'store_url', 'buy_url'];
  const imageKeys = ['image', 'image_url', 'imageUrl', 'thumbnail', 'thumbnail_url', 'photo', 'photo_url'];
  final out = <Map<String, String>>[];
  // Extraction runs over every item (not capped yet) so a real photo further
  // down the feed isn't cut off before the has-image sort below gets to see it.
  for (final item in items) {
    if (item is! Map) continue;
    final name = _firstNonEmptyString(item, nameKeys);
    if (name == null) continue;
    final price = _firstPrice(item, priceKeys);
    final description = _firstNonEmptyString(item, descriptionKeys);
    final url = _firstNonEmptyString(item, urlKeys);
    final image = _firstNonEmptyString(item, imageKeys);
    out.add({'name': name, 'price': ?price, 'description': ?description, 'url': ?url, 'image': ?image});
  }
  // Cards with a real photo first, placeholder-only cards after - partition
  // rather than List.sort (not stable in Dart) so relevance/feed order within
  // each group is otherwise untouched.
  final withImage = out.where((item) => item['image'] != null);
  final withoutImage = out.where((item) => item['image'] == null);
  return [...withImage, ...withoutImage].take(limit).toList();
}

String? _firstNonEmptyString(Map item, List<String> keys) {
  for (final key in keys) {
    final value = item[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

String? _firstPrice(Map item, List<String> keys) {
  for (final key in keys) {
    final value = item[key];
    if (value != null) return value is num ? '\$${value.toStringAsFixed(2)}' : '$value';
  }
  return null;
}
