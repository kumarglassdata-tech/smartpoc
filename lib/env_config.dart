import 'package:flutter_dotenv/flutter_dotenv.dart';

// Reads .env. Getter name matches the .env key.
class EnvConfig {
  static String get contextEngineUrl => dotenv.env['CONTEXT_ENGINE_URL'] ?? '';
  static String get behaviourEnginePostUrl => dotenv.env['BEHAVIOUR_ENGINE_POST_URL'] ?? '';
  static String get behaviourGetEpisodesUrl => dotenv.env['BEHAVIOUR_GET_EPISODES_URL'] ?? '';
  static String get behaviourGetGraphUrl => dotenv.env['BEHAVIOUR_GET_GRAPH_URL'] ?? '';
  static String get ecomHubBaseUrl => dotenv.env['ECOM_HUB_BASE_URL'] ?? '';
  static String get ecomHubBuyUrl => dotenv.env['ECOM_HUB_BUY_URL'] ?? '';
  static String get ecomHubRecommendUrl => dotenv.env['ECOM_HUB_RECOMMEND_URL'] ?? '';
  static String get ecomHubLifebalanceUrl => dotenv.env['ECOM_HUB_LIFEBALANCE_URL'] ?? '';
  static String get ecomHubAnalyzeUrl => dotenv.env['ECOM_HUB_ANALYZE_URL'] ?? '';
  static String get safetyMemoryUrl => dotenv.env['SAFETY_MEMORY_URL'] ?? '';
  static String get interactionWsUrl => dotenv.env['INTERACTION_WS_URL'] ?? '';
  static String get dbHost => dotenv.env['DB_HOST'] ?? '';
  static int get dbPort => int.tryParse(dotenv.env['DB_PORT'] ?? '') ?? 5432;
  static String get dbName => dotenv.env['DB_NAME'] ?? '';
  static String get dbUsername => dotenv.env['DB_USERNAME'] ?? '';
  static String get dbPassword => dotenv.env['DB_PASSWORD'] ?? '';
  static String get googleWebClientId => dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '';
}
