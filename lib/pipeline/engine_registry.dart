import '../env_config.dart';

// Logical engine name -> base URL, for health checks and diagnostics that
// want a URL without holding a reference to the specific client.
class EngineRegistry {
  EngineRegistry._();

  static String getEngineUrl(String key) {
    switch (key) {
      case 'context':
        return EnvConfig.contextEngineUrl;
      case 'behaviour':
        return EnvConfig.behaviourEnginePostUrl;
      case 'ecom':
        return EnvConfig.ecomHubBaseUrl;
      case 'memory':
        return EnvConfig.safetyMemoryUrl;
      case 'interaction':
        return EnvConfig.interactionWsUrl;
      default:
        return '';
    }
  }
}
