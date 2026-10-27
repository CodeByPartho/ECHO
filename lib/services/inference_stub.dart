/// Stub inference engine for platforms that don't support local GGUF models
/// (Web). All methods are no-ops that return appropriate errors.
library;

bool get supportsLocalInference => false;

bool get isRunning32Bit => false;

Future<int> fileLength(String path) async => 0;

class LoadResult {
  final bool success;
  final String message;
  final String gpuName;
  final int gpuLayers;
  final String runtime;
  final String backend;
  LoadResult({
    required this.success,
    required this.message,
    this.gpuName = '',
    this.gpuLayers = 0,
    this.runtime = '',
    this.backend = '',
  });
}

class InferenceEngine {
  bool get ggufVisionLoaded => false;

  Future<LoadResult> loadModel({
    required String modelPath,
    String? modelRuntime,
    required int contextSize,
    required String deviceTier,
    bool isTensorSoC = false,
    String liteRtPerformanceMode = 'cpu_safe',
    bool forceLiteRtCpu = true,
    bool clearLiteRtCache = false,
    bool enableLiteRtVision = false,
    bool allowGgufGpu = false,
    String? mmprojPath,
    void Function(double)? onProgress,
  }) async {
    return LoadResult(
      success: false,
      message: 'Local inference is not available on this platform.',
    );
  }

  Future<String> generate({
    required String prompt,
    List<Map<String, String>>? conversationHistory,
    required String systemPrompt,
    required String modelName,
    required int maxTokens,
    required double temperature,
    double? topP,
    String? imagePath,
    String? audioPath,
    String source = 'chat',
    void Function(String token)? onToken,
  }) async {
    return 'ERROR: Local inference is not available on this platform. Use Cloud mode.';
  }

  Future<void> resetConversation() async {}
  Future<void> stop() async {}
  Future<dynamic> getContextInfo() async => null;
  Future<void> dispose() async {}
}
