// Raw responses from the 6 ecom hub calls the pipeline fires per run. Real
// response shapes for these deployed endpoints aren't documented yet, so
// nothing is parsed into typed fields here - just kept for display/logging.
// If any call fails (e.g. CORS-blocked from a browser origin other than
// https://myna.glassdata.ai), `error` is set instead so the ce/be results
// this engine doesn't affect still get returned.
class EcomAdHandlerRaw {
  final dynamic input;
  final dynamic buy;
  final dynamic recommendGet;
  final dynamic recommendPost;
  final dynamic analyze;
  final dynamic lifebalance;
  final String? error;

  const EcomAdHandlerRaw({
    this.input,
    this.buy,
    this.recommendGet,
    this.recommendPost,
    this.analyze,
    this.lifebalance,
    this.error,
  });

  Map<String, dynamic> toJson() => {
    if (error != null) 'error': error,
    'input': input,
    'buy': buy,
    'recommend_get': recommendGet,
    'recommend_post': recommendPost,
    'analyze': analyze,
    'lifebalance': lifebalance,
  };
}
