// ignore_for_file: use_null_aware_elements
import 'pipeline/ecom_ad_handler_response.dart';

List<Map<String, String>> extractEcomRecommendations(
  EcomAdHandlerRaw raw, {
  int limit = 4,
  String? groundedTarget,
  double? relevanceScore,
  String? behavioralState,
  String? vlmDescription,
  String? beOutputJson,
  String? capturedTime,
}) {
  final buyMatches = extractRecommendations(
    raw.buy,
    limit: limit,
    groundedTarget: groundedTarget,
    relevanceScore: relevanceScore,
    behavioralState: behavioralState,
    vlmDescription: vlmDescription,
    beOutputJson: beOutputJson,
    capturedTime: capturedTime,
  );
  final recommendMatches = extractRecommendations(
    raw.recommendPost,
    limit: limit,
    groundedTarget: groundedTarget,
    relevanceScore: relevanceScore,
    behavioralState: behavioralState,
    vlmDescription: vlmDescription,
    beOutputJson: beOutputJson,
    capturedTime: capturedTime,
  );
  final seenNames = buyMatches.map((item) => item['name']).toSet();
  final merged = [
    ...buyMatches,
    ...recommendMatches.where((item) => !seenNames.contains(item['name'])),
  ];
  return merged.take(limit).toList();
}

List<Map<String, String>> extractRecommendations(
  dynamic raw, {
  int limit = 4,
  String? groundedTarget,
  double? relevanceScore,
  String? behavioralState,
  String? vlmDescription,
  String? beOutputJson,
  String? capturedTime,
}) {
  List<dynamic>? items;
  if (raw is List) {
    items = raw;
  } else if (raw is Map) {
    final combined = <dynamic>[];
    for (final key in ['recommendations', 'organic_feed', 'sponsored_feed', 'items', 'products', 'results', 'data']) {
      final value = raw[key];
      if (value is List) combined.addAll(value);
    }
    if (combined.isNotEmpty) items = combined;
  }
  if (items == null) return const [];

  const nameKeys = ['product', 'name', 'title', 'product_name', 'label'];
  const priceKeys = ['price', 'cost', 'amount', 'price_val'];
  const descriptionKeys = ['description', 'summary', 'details', 'blurb', 'message'];
  const urlKeys = ['link', 'url', 'product_url', 'store_url', 'buy_url'];
  const imageKeys = ['image_url', 'image', 'imageUrl', 'thumbnail', 'thumbnail_url', 'photo', 'photo_url', 'img', 'img_url', 'picture', 'pic', 'product_image', 'src', 'preview_url', 'icon', 'images', 'media', 'product_image_url'];
  const platformKeys = ['platform', 'merchant', 'store', 'source', 'vendor'];
  const ratingKeys = ['rating', 'stars', 'score', 'customer_rating'];
  const deliveryKeys = ['delivery', 'shipping', 'eta', 'delivery_time', 'speed'];
  const offerKeys = ['offer', 'deal', 'discount', 'tag', 'promo'];
  const matchScoreKeys = ['match_score', 'organic_score', 'relevance_score', 'score'];

  final out = <Map<String, String>>[];
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    if (item is! Map) continue;
    final name = _firstNonEmptyString(item, nameKeys);
    if (name == null) continue;
    final price = _firstPrice(item, priceKeys);
    final description = _firstNonEmptyString(item, descriptionKeys);
    final url = _firstNonEmptyString(item, urlKeys);
    final image = _firstImageUrl(item, imageKeys, name);
    final platform = _firstNonEmptyString(item, platformKeys) ?? _detectPlatform(url, name);
    final rating = _firstNumericString(item, ratingKeys);
    final delivery = _firstNonEmptyString(item, deliveryKeys);
    final offer = _firstNonEmptyString(item, offerKeys);
    final matchScore = _firstPercentString(item, matchScoreKeys);

    final targetName = groundedTarget ?? _firstNonEmptyString(item, ['query_product', 'category', 'target']) ?? name;
    final scoreStr = relevanceScore != null ? '${(relevanceScore * 100).round()}%' : (matchScore ?? '95%');

    out.add({
      'name': name,
      if (price != null) 'price': price,
      if (description != null) 'description': description,
      if (url != null) 'url': url,
      if (image != null) 'image': image,
      'platform': platform,
      if (rating != null) 'rating': rating,
      if (delivery != null) 'delivery': delivery,
      if (offer != null) 'offer': offer,
      if (matchScore != null) 'match_score': matchScore,
      'trigger_object': targetName,
      'trigger_score': scoreStr,
      'behavioral_state': behavioralState ?? 'Engaged',
      if (vlmDescription != null && vlmDescription.isNotEmpty) 'vlm_description': vlmDescription,
      if (beOutputJson != null && beOutputJson.isNotEmpty) 'be_output_json': beOutputJson,
      if (capturedTime != null) 'captured_time': capturedTime,
      'trigger_reason': 'Visual gaze fixation on $targetName with $scoreStr relevance (${behavioralState ?? 'Engaged'} state)',
      'rank': '${out.length + 1}',
    });
  }

  final withImage = out.where((item) => item['image'] != null && !item['image']!.contains('via.placeholder.com'));
  final withoutImage = out.where((item) => item['image'] == null || item['image']!.contains('via.placeholder.com'));
  return [...withImage, ...withoutImage].take(limit).toList();
}

String _detectPlatform(String? url, String name) {
  if (url != null) {
    final lower = url.toLowerCase();
    if (lower.contains('amazon')) return 'Amazon';
    if (lower.contains('zepto')) return 'Zepto';
    if (lower.contains('blinkit')) return 'Blinkit';
    if (lower.contains('flipkart')) return 'Flipkart';
    if (lower.contains('bigbasket')) return 'BigBasket';
    if (lower.contains('swiggy') || lower.contains('instamart')) return 'Instamart';
    if (lower.contains('google.com/search?tbm=shop')) return 'Google Shopping';
  }
  return 'Verified Store';
}

String? _firstImageUrl(Map item, List<String> keys, String productName) {
  for (final key in keys) {
    final value = item[key];
    final candidate = _extractUrlString(value);
    if (candidate != null && candidate.isNotEmpty) {
      final sanitized = _sanitizeImageUrl(candidate);
      if (sanitized != null) return sanitized;
    }
  }
  return _categoryFallbackImage(productName);
}

String? _extractUrlString(dynamic value) {
  if (value is String && value.trim().isNotEmpty) return value.trim();
  if (value is List && value.isNotEmpty) {
    for (final el in value) {
      final res = _extractUrlString(el);
      if (res != null) return res;
    }
  }
  if (value is Map) {
    for (final subKey in ['url', 'src', 'link', 'image_url', 'image', 'thumbnail', 'photo']) {
      final res = _extractUrlString(value[subKey]);
      if (res != null) return res;
    }
  }
  return null;
}

String? _sanitizeImageUrl(String url) {
  var clean = url.trim();
  if (clean.contains('via.placeholder.com') || clean.isEmpty) return null;
  if (clean.startsWith('//')) {
    clean = 'https:$clean';
  } else if (clean.startsWith('http://')) {
    clean = 'https://${clean.substring(7)}';
  }
  if (clean.startsWith('https://')) return clean;
  return null;
}

String _categoryFallbackImage(String name) {
  final lower = name.toLowerCase();
  
  // ── Snacks & Chips ──────────────────────────────────────────────
  if (lower.contains('chip') || lower.contains('bingo') || lower.contains('lays') || lower.contains('snack') ||
      lower.contains('crisp') || lower.contains('nacho') || lower.contains('dorito') || lower.contains('kurkure') ||
      lower.contains('wafer') || lower.contains('popcorn') || lower.contains('namkeen')) {
    return 'https://images.unsplash.com/photo-1566478989037-eec170784d0b?w=500&auto=format&fit=crop&q=80';
  }

  // ── Beverages & Cold Drinks ─────────────────────────────────────
  if (lower.contains('coca') || lower.contains('coke') || lower.contains('thums')) {
    return 'https://images.unsplash.com/photo-1622483767028-3f66f32aef97?w=500&auto=format&fit=crop&q=80';
  }
  if (lower.contains('pepsi') || lower.contains('soda') || lower.contains('sprite') || lower.contains('fanta') ||
      lower.contains('beverage') || lower.contains('drink') || lower.contains('juice') || lower.contains('energy') ||
      lower.contains('red bull') || lower.contains('can') || lower.contains('cold drink')) {
    return 'https://images.unsplash.com/photo-1581009146145-b5ef050c2e1e?w=500&auto=format&fit=crop&q=80';
  }
  if (lower.contains('bottle') || lower.contains('water') || lower.contains('flask') || lower.contains('sipper') ||
      lower.contains('milton') || lower.contains('aquafina') || lower.contains('bisleri') || lower.contains('kinley')) {
    return 'https://images.unsplash.com/photo-1602143407151-7111542de6e8?w=500&auto=format&fit=crop&q=80';
  }
  if (lower.contains('coffee') || lower.contains('tea') || lower.contains('mug') || lower.contains('cup') ||
      lower.contains('espresso') || lower.contains('nescafe') || lower.contains('starbucks')) {
    return 'https://images.unsplash.com/photo-1514432324607-a09d9b4aefdd?w=500&auto=format&fit=crop&q=80';
  }

  // ── Confectionery & Bakery ──────────────────────────────────────
  if (lower.contains('chocolate') || lower.contains('candy') || lower.contains('dairy milk') || lower.contains('kitkat') ||
      lower.contains('sweet') || lower.contains('cadbury')) {
    return 'https://images.unsplash.com/photo-1549007994-cb92caebd54b?w=500&auto=format&fit=crop&q=80';
  }
  if (lower.contains('biscuit') || lower.contains('cookie') || lower.contains('oreo') || lower.contains('parle') ||
      lower.contains('bakery') || lower.contains('cake')) {
    return 'https://images.unsplash.com/photo-1499636136210-6f4ee915583e?w=500&auto=format&fit=crop&q=80';
  }

  // ── Food & Meals ────────────────────────────────────────────────
  if (lower.contains('pizza') || lower.contains('burger') || lower.contains('sandwich') || lower.contains('meal') ||
      lower.contains('food') || lower.contains('bread') || lower.contains('noodle') || lower.contains('maggi')) {
    return 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=500&auto=format&fit=crop&q=80';
  }

  // ── Audio & Electronics ─────────────────────────────────────────
  if (lower.contains('headphone') || lower.contains('earphone') || lower.contains('audio') || lower.contains('airpod') ||
      lower.contains('buds') || lower.contains('sony wh') || lower.contains('headset') || lower.contains('speaker') ||
      lower.contains('boat') || lower.contains('jbl')) {
    return 'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=500&auto=format&fit=crop&q=80';
  }
  if (lower.contains('phone') || lower.contains('iphone') || lower.contains('mobile') || lower.contains('pixel') ||
      lower.contains('samsung') || lower.contains('oneplus') || lower.contains('charger') || lower.contains('cable') ||
      lower.contains('powerbank')) {
    return 'https://images.unsplash.com/photo-1511707171634-5f897ff02aa9?w=500&auto=format&fit=crop&q=80';
  }
  if (lower.contains('laptop') || lower.contains('macbook') || lower.contains('computer') || lower.contains('pc') ||
      lower.contains('dell') || lower.contains('hp') || lower.contains('lenovo') || lower.contains('asus')) {
    return 'https://images.unsplash.com/photo-1496181133206-80ce9b88a853?w=500&auto=format&fit=crop&q=80';
  }
  if (lower.contains('keyboard') || lower.contains('mouse') || lower.contains('touchpad') || lower.contains('monitor') ||
      lower.contains('screen')) {
    return 'https://images.unsplash.com/photo-1587829741301-dc798b83add3?w=500&auto=format&fit=crop&q=80';
  }
  if (lower.contains('watch') || lower.contains('smartwatch') || lower.contains('band') || lower.contains('fitbit') ||
      lower.contains('apple watch') || lower.contains('titan') || lower.contains('fossil')) {
    return 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?w=500&auto=format&fit=crop&q=80';
  }

  // ── Eyewear & Fashion ───────────────────────────────────────────
  if (lower.contains('glasses') || lower.contains('sunglasses') || lower.contains('spectacles') || lower.contains('rayban') ||
      lower.contains('meta') || lower.contains('eyewear') || lower.contains('lens')) {
    return 'https://images.unsplash.com/photo-1572635196237-14b3f281503f?w=500&auto=format&fit=crop&q=80';
  }
  if (lower.contains('shoe') || lower.contains('sneaker') || lower.contains('footwear') || lower.contains('nike') ||
      lower.contains('adidas') || lower.contains('puma') || lower.contains('boot') || lower.contains('sandal')) {
    return 'https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=500&auto=format&fit=crop&q=80';
  }
  if (lower.contains('bag') || lower.contains('backpack') || lower.contains('purse') || lower.contains('luggage') ||
      lower.contains('wallet') || lower.contains('suitcase')) {
    return 'https://images.unsplash.com/photo-1553062407-98eeb64c6a62?w=500&auto=format&fit=crop&q=80';
  }
  if (lower.contains('shirt') || lower.contains('t-shirt') || lower.contains('hoodie') || lower.contains('jacket') ||
      lower.contains('clothing') || lower.contains('apparel') || lower.contains('dress') || lower.contains('jeans')) {
    return 'https://images.unsplash.com/photo-1521572267360-ee0c2909d518?w=500&auto=format&fit=crop&q=80';
  }

  // ── Personal Care & Groceries ───────────────────────────────────
  if (lower.contains('soap') || lower.contains('shampoo') || lower.contains('lotion') || lower.contains('cream') ||
      lower.contains('perfume') || lower.contains('deodorant') || lower.contains('sanitizer') || lower.contains('skincare')) {
    return 'https://images.unsplash.com/photo-1608248597359-052060139b40?w=500&auto=format&fit=crop&q=80';
  }
  if (lower.contains('grocery') || lower.contains('fruit') || lower.contains('apple') || lower.contains('banana') ||
      lower.contains('milk') || lower.contains('butter') || lower.contains('cheese') || lower.contains('oil') ||
      lower.contains('rice') || lower.contains('dal')) {
    return 'https://images.unsplash.com/photo-1542838132-92c53300491e?w=500&auto=format&fit=crop&q=80';
  }
  if (lower.contains('book') || lower.contains('notebook') || lower.contains('journal') || lower.contains('pen') ||
      lower.contains('pencil') || lower.contains('stationery')) {
    return 'https://images.unsplash.com/photo-1544716278-ca5e3f4abd8c?w=500&auto=format&fit=crop&q=80';
  }
  if (lower.contains('plant') || lower.contains('flower') || lower.contains('pot') || lower.contains('cactus') || lower.contains('succulent')) {
    return 'https://images.unsplash.com/photo-1485955900006-10f4d324d411?w=500&auto=format&fit=crop&q=80';
  }

  // ── Generic E-Commerce Retail Package / Shopping Showcase ───────
  return 'https://images.unsplash.com/photo-1586528116311-ad8dd3c8310d?w=500&auto=format&fit=crop&q=80';
}

String? _firstNonEmptyString(Map item, List<String> keys) {
  for (final key in keys) {
    final value = item[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

String? _firstNumericString(Map item, List<String> keys) {
  for (final key in keys) {
    final value = item[key];
    if (value is num) return value.toStringAsFixed(1);
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

String? _firstPercentString(Map item, List<String> keys) {
  for (final key in keys) {
    final value = item[key];
    if (value is num) {
      return value <= 1.0 ? '${(value * 100).round()}%' : '${value.round()}%';
    }
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

String? _firstPrice(Map item, List<String> keys) {
  for (final key in keys) {
    final value = item[key];
    if (value != null) {
      if (value is String && value.trim().isNotEmpty) {
        final trimmed = value.trim();
        if (trimmed.startsWith('₹') || trimmed.startsWith('\$') || trimmed.toLowerCase().startsWith('rs')) {
          return trimmed;
        }
        final numVal = double.tryParse(trimmed.replaceAll(RegExp(r'[^0-9.]'), ''));
        if (numVal != null) return '₹${numVal.round()}';
        return trimmed;
      }
      if (value is num) return '₹${value.round()}';
    }
  }
  return null;
}
