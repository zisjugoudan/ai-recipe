import 'package:flutter/material.dart';

// 应用外观与主题
import '../../app/app_theme.dart';
// 后端门面与用例
import '../../application/backend/ai_recipe_backend_facade.dart';
import '../../application/settings/llm_settings_use_cases.dart';
// 领域模型（LLM 诊断 / 多模态 / 服务商类型）
import '../../domain/llm/llm_diagnostic.dart';
import '../../domain/llm/llm_provider_type.dart';
import '../../domain/llm/multimodal_llm_provider.dart';
// 共享组件
import '../../shared/widgets/pixel_ui.dart';
// 图片导入
import '../importing/import_image_picker.dart';

class LlmSettingsPage extends StatefulWidget {
  const LlmSettingsPage({super.key, required this.backend});

  final AiRecipeBackendFacade backend;

  @override
  State<LlmSettingsPage> createState() => _LlmSettingsPageState();
}

class _LlmSettingsPageState extends State<LlmSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(text: '我的 LLM');
  final _urlController = TextEditingController(
    text: LlmProviderType.openAiCompatible.defaultBaseUrl,
  );
  final _keyController = TextEditingController();
  final _modelController = TextEditingController();

  /// 「测试结构化生成」输入文本（BUG-008 诊断辅助）。
  final _structuredGenController = TextEditingController();

  LlmProviderType _providerType = LlmProviderType.openAiCompatible;
  String? _configurationId;
  Duration _requestTimeout = const Duration(seconds: 120);
  bool _loading = true;
  bool _busy = false;
  bool _hasStoredKey = false;
  String? _statusMessage;
  bool _statusIsError = false;

  /// 「测试结构化生成」运行状态与结果（BUG-008 诊断辅助）。
  bool _structuredGenBusy = false;
  LlmStructuredGenerationResult? _structuredGenResult;
  String? _structuredGenError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _keyController.dispose();
    _modelController.dispose();
    _structuredGenController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _statusMessage = null;
    });
    try {
      final snapshot = await widget.backend.loadLlmSettings();
      final configuration = snapshot.configuration;
      if (!mounted) return;
      setState(() {
        _configurationId = configuration?.id;
        _providerType =
            configuration?.providerType ?? LlmProviderType.openAiCompatible;
        _nameController.text = configuration?.name ?? '我的 LLM';
        _urlController.text =
            configuration?.baseUrl ?? _providerType.defaultBaseUrl;
        _modelController.text = configuration?.model ?? '';
        _requestTimeout =
            configuration?.requestTimeout ?? const Duration(seconds: 120);
        _hasStoredKey = snapshot.hasStoredApiKey;
        _keyController.clear();
        _loading = false;
      });
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusMessage = error.message;
        _statusIsError = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusMessage = 'LLM 配置暂时无法读取，请稍后重试。';
        _statusIsError = true;
      });
    }
  }

  void _changeProvider(LlmProviderType? type) {
    if (type == null || type == _providerType) return;
    final previousDefault = _providerType.defaultBaseUrl;
    setState(() {
      _providerType = type;
      final currentUrl = _urlController.text.trim();
      if (currentUrl.isEmpty || currentUrl == previousDefault) {
        _urlController.text = type.defaultBaseUrl;
      }
      _statusMessage = null;
    });
  }

  LlmSettingsInput? _buildInput() {
    if (!(_formKey.currentState?.validate() ?? false)) return null;
    return LlmSettingsInput(
      id: _configurationId,
      name: _nameController.text.trim(),
      providerType: _providerType,
      baseUrl: _urlController.text.trim(),
      model: _modelController.text.trim(),
      apiKey: _keyController.text,
      requestTimeout: _requestTimeout,
    );
  }

  Future<void> _testConnection() async {
    final input = _buildInput();
    if (input == null) return;
    setState(() {
      _busy = true;
      _statusMessage = '正在测试连接…';
      _statusIsError = false;
    });
    try {
      await widget.backend.testLlmConnection(input);
      if (!mounted) return;
      _setStatus('连接成功，可以使用当前模型。');
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      _setStatus(_connectionFailureMessage(error.code), isError: true);
    } catch (_) {
      if (!mounted) return;
      _setStatus('连接失败，请检查地址、模型与网络状态。', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 「测试结构化生成」：输入任意文本，走真实导入链路的结构化生成，
  /// 展示耗时与生成结果，用于判断最终生成超时是否由 LLM 服务本身引起。
  Future<void> _testStructuredGeneration() async {
    final input = _buildInput();
    if (input == null) return;
    final sourceText = _structuredGenController.text;
    if (sourceText.trim().isEmpty) {
      setState(() {
        _structuredGenError = '请先输入要测试结构化的菜谱文本。';
        _structuredGenResult = null;
      });
      return;
    }
    setState(() {
      _structuredGenBusy = true;
      _structuredGenResult = null;
      _structuredGenError = null;
    });
    try {
      final result = await widget.backend.testLlmStructuredGeneration(
        input,
        sourceText: sourceText,
      );
      if (!mounted) return;
      setState(() => _structuredGenResult = result);
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      setState(() => _structuredGenError = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _structuredGenError = '结构化生成测试失败，请检查配置后重试。');
    } finally {
      if (mounted) setState(() => _structuredGenBusy = false);
    }
  }

  Future<void> _save() async {
    final input = _buildInput();
    if (input == null) return;
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final snapshot = await widget.backend.saveLlmSettings(input);
      if (!mounted) return;
      setState(() {
        _configurationId = snapshot.configuration?.id;
        _hasStoredKey = snapshot.hasStoredApiKey;
        _keyController.clear();
      });
      _setStatus('LLM 配置已保存到本机。');
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      _setStatus(error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      _setStatus('LLM 配置暂时无法保存，请稍后重试。', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearKey() async {
    setState(() => _busy = true);
    try {
      final snapshot = await widget.backend.clearLlmApiKey();
      if (!mounted) return;
      setState(() {
        _hasStoredKey = snapshot.hasStoredApiKey;
        _keyController.clear();
      });
      _setStatus('已清除保存的 API Key。');
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      _setStatus(error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      _setStatus('API Key 暂时无法清除，请稍后重试。', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setStatus(String message, {bool isError = false}) {
    setState(() {
      _statusMessage = message;
      _statusIsError = isError;
    });
  }

  static String _connectionFailureMessage(AiRecipeBackendErrorCode code) {
    return switch (code) {
      AiRecipeBackendErrorCode.authenticationFailed =>
        '连接失败：API Key 无效或没有访问权限。',
      AiRecipeBackendErrorCode.rateLimited => '连接失败：服务请求过于频繁，请稍后重试。',
      AiRecipeBackendErrorCode.timeout => '连接超时，请检查地址或调大超时时间。',
      AiRecipeBackendErrorCode.networkUnavailable => '连接失败：当前网络无法访问该 API 地址。',
      AiRecipeBackendErrorCode.providerUnavailable => '连接失败：模型服务暂时不可用。',
      AiRecipeBackendErrorCode.invalidProviderResponse => '连接失败：服务返回了无法识别的响应。',
      _ => '连接失败，请检查地址、模型与网络状态。',
    };
  }

  @override
  Widget build(BuildContext context) {
    final insecureHttp = _urlController.text.trim().startsWith('http://');
    return Scaffold(
      appBar: const PixelPageAppBar(
        title: 'LLM 模型',
      ),
      bottomNavigationBar: _loading
          ? null
          : PixelBottomActionBar(
              child: FilledButton.icon(
                key: const Key('saveConfigButton'),
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? const PixelLoader(size: 6, color: Colors.white)
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(_busy ? '保存中…' : '保存配置'),
              ),
            ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  PixelLoader(),
                  SizedBox(height: 14),
                  PxLabel('正在加载设置'),
                ],
              ),
            )
          : SafeArea(
              bottom: false,
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                  children: <Widget>[
                    // 菜谱生成 LLM：普通文本 LLM，用于把抓取的菜谱整理成结构化菜谱。
                    const PxLabel('菜谱生成 LLM'),
                    const SizedBox(height: 8),
                    const PixelNotice(
                      title: '一个地址 + 一个 Key，即可连接模型',
                      message:
                          '支持 OpenAI-compatible 与 Gemini 原生协议。配置仅保存在本机，可用于游客模式下的本地 AI 服务。',
                      icon: Icons.hub_outlined,
                      tone: PixelNoticeTone.blue,
                    ),
                    const SizedBox(height: 16),
                    PixelSurface(
                      cut: 8,
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const PxLabel('服务商与地址'),
                          const SizedBox(height: 14),
                          const PixelFieldLabel('Provider 类型', required: true),
                          DropdownButtonFormField<LlmProviderType>(
                            key: const Key('providerTypeField'),
                            initialValue: _providerType,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.account_tree_outlined),
                            ),
                            items: LlmProviderType.values
                                .map(
                                  (type) => DropdownMenuItem<LlmProviderType>(
                                    value: type,
                                    child: Text(type.displayName),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: _busy ? null : _changeProvider,
                          ),
                          const SizedBox(height: 14),
                          const PixelFieldLabel('配置名称', required: true),
                          TextFormField(
                            key: const Key('configNameField'),
                            controller: _nameController,
                            decoration: const InputDecoration(
                              hintText: '例如：厨房 Ollama',
                              prefixIcon: Icon(Icons.label_outline_rounded),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? '请输入配置名称'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          const PixelFieldLabel('API Base URL', required: true),
                          TextFormField(
                            key: const Key('baseUrlField'),
                            controller: _urlController,
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              hintText: 'http://192.168.1.10:11434/v1',
                              prefixIcon: Icon(Icons.link_rounded),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? '请输入 API 地址'
                                : null,
                            onChanged: (_) => setState(() {}),
                          ),
                          if (insecureHttp) ...<Widget>[
                            const SizedBox(height: 10),
                            const PixelNotice(
                              title: '当前使用 HTTP',
                              message: 'Key 和请求内容将通过明文 HTTP 传输，请仅在可信局域网内使用。',
                              icon: Icons.warning_amber_rounded,
                              tone: PixelNoticeTone.amber,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    PixelSurface(
                      cut: 8,
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const PxLabel('密钥与模型'),
                          const SizedBox(height: 14),
                          const PixelFieldLabel('API Key'),
                          TextFormField(
                            key: const Key('apiKeyField'),
                            controller: _keyController,
                            obscureText: true,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: InputDecoration(
                              hintText: _hasStoredKey
                                  ? '留空将保留当前密钥'
                                  : '输入服务提供方的 API Key',
                              prefixIcon: const Icon(Icons.key_rounded),
                              helperText: _hasStoredKey
                                  ? '已保存 Key；留空保存时继续使用，如需替换请输入新 Key。'
                                  : 'Key 将安全写入 Keychain / Keystore。',
                              suffixIcon: _hasStoredKey
                                  ? IconButton(
                                      key: const Key('clearApiKeyButton'),
                                      tooltip: '清除已保存的 API Key',
                                      onPressed: _busy ? null : _clearKey,
                                      icon: const Icon(Icons.delete_outline),
                                    )
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 14),
                          const PixelFieldLabel('模型名称', required: true),
                          TextFormField(
                            key: const Key('modelField'),
                            controller: _modelController,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              hintText: '例如 gpt-4.1-mini 或 gemini-2.5-flash',
                              prefixIcon: Icon(Icons.memory_rounded),
                            ),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? '请输入模型名称'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          const PixelFieldLabel('请求超时'),
                          DropdownButtonFormField<Duration>(
                            key: const Key('requestTimeoutField'),
                            initialValue: _requestTimeout,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.timer_outlined),
                            ),
                            // 慢速本地模型（如 Ollama/LM Studio）生成完整菜谱 JSON
                            // 可能远超 120 秒，故提供 180/300/600 秒档位（BUG-008）。
                            items: const <int>[30, 60, 120, 180, 300, 600]
                                .map(
                                  (seconds) => DropdownMenuItem<Duration>(
                                    value: Duration(seconds: seconds),
                                    child: Text('$seconds 秒'),
                                  ),
                                )
                                .toList(growable: false),
                            onChanged: _busy
                                ? null
                                : (value) {
                                    if (value != null) {
                                      setState(() => _requestTimeout = value);
                                    }
                                  },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      key: const Key('testConnectionButton'),
                      onPressed: _busy ? null : _testConnection,
                      icon: _busy
                          ? const PixelLoader(size: 6)
                          : const Icon(Icons.network_check_rounded),
                      label: Text(_busy ? '正在测试…' : '测试连接'),
                    ),
                    const SizedBox(height: 14),
                    PixelSurface(
                      cut: 8,
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const PxLabel('测试结构化生成'),
                          const SizedBox(height: 6),
                          const Text(
                            '输入任意菜谱文本，走与导入完全相同的结构化生成链路，'
                            '测出真实耗时，用于判断「最终生成超时」是否由 LLM 服务本身引起。',
                            style: TextStyle(fontSize: 11.5, height: 1.5),
                          ),
                          const SizedBox(height: 12),
                          const PixelFieldLabel('菜谱文本'),
                          TextFormField(
                            key: const Key('structuredGenInputField'),
                            controller: _structuredGenController,
                            minLines: 4,
                            maxLines: 8,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              hintText:
                                  '例如：红烧肉。五花肉 500 克焯水，锅中放糖炒出糖色…',
                              prefixIcon: Icon(Icons.edit_note_rounded),
                              alignLabelWithHint: true,
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            key: const Key('testStructuredGenButton'),
                            onPressed: _busy || _structuredGenBusy
                                ? null
                                : _testStructuredGeneration,
                            icon: _structuredGenBusy
                                ? const PixelLoader(size: 6)
                                : const Icon(Icons.fact_check_outlined),
                            label: Text(
                              _structuredGenBusy ? '正在生成…' : '测试结构化生成',
                            ),
                          ),
                          if (_structuredGenError != null) ...<Widget>[
                            const SizedBox(height: 12),
                            Semantics(
                              liveRegion: true,
                              child: PixelSurface(
                                cut: 5,
                                elevation: 0,
                                color: AppColors.redSoft,
                                borderColor: AppColors.red.withValues(alpha: .45),
                                padding: const EdgeInsets.all(13),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    const Icon(
                                      Icons.error_outline_rounded,
                                      size: 18,
                                      color: AppColors.red,
                                    ),
                                    const SizedBox(width: 9),
                                    Expanded(
                                      child: Text(
                                        _structuredGenError!,
                                        key: const Key(
                                          'structuredGenErrorText',
                                        ),
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          height: 1.45,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.red,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          if (_structuredGenResult != null) ...<Widget>[
                            const SizedBox(height: 12),
                            Semantics(
                              liveRegion: true,
                              child: PixelSurface(
                                cut: 5,
                                elevation: 0,
                                color: AppColors.greenSofter,
                                borderColor: AppColors.green.withValues(
                                  alpha: .45,
                                ),
                                padding: const EdgeInsets.all(13),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        const Icon(
                                          Icons.check_circle_outline_rounded,
                                          size: 18,
                                          color: AppColors.greenDeep,
                                        ),
                                        const SizedBox(width: 9),
                                        Expanded(
                                          child: Text(
                                            '耗时 ${_structuredGenResult!.elapsedMs} ms'
                                            '（${(_structuredGenResult!.elapsedMs / 1000).toStringAsFixed(1)} 秒）'
                                            '· 模式 ${_structuredGenResult!.reasoningMode?.name ?? 'fast'}',
                                            key: const Key(
                                              'structuredGenElapsedText',
                                            ),
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.greenDeep,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      '耗时与最终导入的「结构化生成」阶段同源，'
                                      '可直接对比排查超时原因；模式为 deep 时会明显变慢。',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        height: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (_statusMessage != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: PixelSurface(
                          cut: 5,
                          elevation: 0,
                          color: _statusIsError
                              ? AppColors.redSoft
                              : AppColors.greenSofter,
                          borderColor: _statusIsError
                              ? AppColors.red.withValues(alpha: .45)
                              : AppColors.green.withValues(alpha: .45),
                          padding: const EdgeInsets.all(13),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Icon(
                                _statusIsError
                                    ? Icons.error_outline_rounded
                                    : Icons.check_circle_outline_rounded,
                                size: 18,
                                color: _statusIsError
                                    ? AppColors.red
                                    : AppColors.greenDeep,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  _statusMessage!,
                                  key: const Key('statusMessage'),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    height: 1.45,
                                    fontWeight: FontWeight.w800,
                                    color: _statusIsError
                                        ? AppColors.red
                                        : AppColors.greenDeep,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    // 多模态 LLM 图片识别配置（与菜谱生成 LLM 独立）：本页集中管理两类 LLM。
                    _MultimodalLlmConfigSection(backend: widget.backend),
                    // const PixelNotice(
                    //   title: '游客也可以使用本地 LLM',
                    //   message:
                    //       '游客不能使用服务器 AI 服务，但可直接连接你配置的本地或第三方 API；Key 不会随菜谱数据导出。',
                    //   icon: Icons.privacy_tip_outlined,
                    //   tone: PixelNoticeTone.green,
                    // ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// 多模态 LLM 图片识别配置区（识图引擎，IMAGE-001）。
///
/// 与菜谱生成 LLM（本地 LLM API 页）完全独立：API 地址 / Key / 模型
/// 单独保存，识别图片时走多模态（视觉）请求。
class _MultimodalLlmConfigSection extends StatefulWidget {
  const _MultimodalLlmConfigSection({required this.backend});

  final AiRecipeBackendFacade backend;

  @override
  State<_MultimodalLlmConfigSection> createState() =>
      _MultimodalLlmConfigSectionState();
}

class _MultimodalLlmConfigSectionState
    extends State<_MultimodalLlmConfigSection> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(text: '图片识别 LLM');
  final _urlController = TextEditingController(
    text: LlmProviderType.openAiCompatible.defaultBaseUrl,
  );
  final _keyController = TextEditingController();
  final _modelController = TextEditingController();

  LlmProviderType _providerType = LlmProviderType.openAiCompatible;
  String? _configurationId;
  Duration _requestTimeout = const Duration(seconds: 120);
  bool _loading = true;

  /// 保存/清除 Key 进行中（保存是本地操作，不应长时间转圈）。
  bool _busy = false;

  /// 检查基础连接进行中（网络请求，与保存状态分离）。
  bool _testingBase = false;

  /// 检查图片能力（标准诊断图）进行中。
  bool _testingProbe = false;

  /// 用我的图片测试进行中（真正发送用户图片给多模态模型）。
  bool _testingImage = false;

  /// 基础连接 / 图片能力的分阶段诊断结果。
  MultimodalDiagnosticOutcome? _diagnosticResult;
  MultimodalRecognitionResult? _testImageResult;
  String? _testImageError;
  final _imagePicker = DeviceImportImagePicker();

  bool _hasStoredKey = false;
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _keyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final snapshot = await widget.backend.loadMultimodalSettings();
      final configuration = snapshot.configuration;
      if (!mounted) return;
      setState(() {
        _configurationId = configuration?.id;
        _providerType =
            configuration?.providerType ?? LlmProviderType.openAiCompatible;
        _nameController.text = configuration?.name ?? '图片识别 LLM';
        _urlController.text =
            configuration?.baseUrl ?? _providerType.defaultBaseUrl;
        _modelController.text = configuration?.model ?? '';
        _requestTimeout =
            configuration?.requestTimeout ?? const Duration(seconds: 120);
        _hasStoredKey = snapshot.hasStoredApiKey;
        _keyController.clear();
        _loading = false;
      });
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusMessage = error.message;
        _statusIsError = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusMessage = '图片识别 LLM 配置暂时无法读取，请稍后重试。';
        _statusIsError = true;
      });
    }
  }

  void _changeProvider(LlmProviderType? type) {
    if (type == null || type == _providerType) return;
    final previousDefault = _providerType.defaultBaseUrl;
    setState(() {
      _providerType = type;
      final currentUrl = _urlController.text.trim();
      if (currentUrl.isEmpty || currentUrl == previousDefault) {
        _urlController.text = type.defaultBaseUrl;
      }
      _statusMessage = null;
    });
  }

  LlmSettingsInput? _buildInput({Duration? requestTimeout}) {
    if (!(_formKey.currentState?.validate() ?? false)) return null;
    return LlmSettingsInput(
      id: _configurationId,
      name: _nameController.text.trim(),
      providerType: _providerType,
      baseUrl: _urlController.text.trim(),
      model: _modelController.text.trim(),
      apiKey: _keyController.text,
      requestTimeout: requestTimeout ?? _requestTimeout,
    );
  }

  /// 检查基础连接：只验证地址、鉴权与模型，不发送图片，也不再等待完整
  /// 响应后统一包装成"链接超时"（BUG-006，ADR-0028）。
  Future<void> _checkBaseConnection() async {
    final input = _buildInput();
    if (input == null) return;
    setState(() {
      _testingBase = true;
      _diagnosticResult = null;
      _statusMessage = '正在检查基础连接…';
      _statusIsError = false;
    });
    try {
      final outcome = await widget.backend.checkMultimodalBaseConnection(input);
      if (!mounted) return;
      setState(() => _diagnosticResult = outcome);
      if (outcome.textCapabilityUnconfirmed) {
        _setStatus('服务与鉴权已通过，文本能力未确认。请继续检查图片能力。');
      } else if (outcome.report.succeeded) {
        _setStatus('基础连接通过：配置、鉴权与模型均正常。');
      } else {
        _setStatus('基础连接未通过，请查看下方阶段结果。', isError: true);
      }
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      _setStatus(error.message.trim().isEmpty
          ? _connectionFailureMessage(error.code)
          : error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      _setStatus('连接检查失败，请稍后重试。', isError: true);
    } finally {
      if (mounted) setState(() => _testingBase = false);
    }
  }

  /// 检查图片能力：发送内置 256×256 标准诊断图，文字与红色方块两个断言
  /// 同时通过才算通过（BUG-006）。
  Future<void> _checkImageCapability() async {
    final input = _buildInput();
    if (input == null) return;
    setState(() {
      _testingProbe = true;
      _diagnosticResult = null;
      _statusMessage = '正在检查图片能力（标准诊断图）…';
      _statusIsError = false;
    });
    try {
      final outcome =
          await widget.backend.checkMultimodalImageCapability(input);
      if (!mounted) return;
      setState(() => _diagnosticResult = outcome);
      if (outcome.imageProbePassed == true) {
        _setStatus('图片能力通过：模型正确识别了文字「AI RECIPE 314」与红色方块。');
      } else {
        _setStatus('图片能力未通过，请查看下方阶段结果。', isError: true);
      }
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      _setStatus(error.message.trim().isEmpty
          ? _connectionFailureMessage(error.code)
          : error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      _setStatus('图片能力检查失败，请稍后重试。', isError: true);
    } finally {
      if (mounted) setState(() => _testingProbe = false);
    }
  }

  /// 测试识图：选择一张真实图片 → 多模态 LLM 识别 → 展示文本与耗时。
  Future<void> _runMultimodalTest() async {
    if (_testingImage || _busy || _testingBase || _testingProbe) return;
    setState(() {
      _testImageError = null;
      _testImageResult = null;
    });
    final PickedImportImage image;
    try {
      final picked = await _imagePicker.pickImage();
      if (picked == null) return;
      image = picked;
    } on ImportImagePickerException catch (error) {
      if (mounted) setState(() => _testImageError = error.message);
      return;
    }
    if (!mounted) return;
    setState(() => _testingImage = true);
    try {
      final result = await widget.backend.testMultimodalImage(
        image.localAssetId,
      );
      if (!mounted) return;
      setState(() {
        _testImageResult = result;
        _testingImage = false;
      });
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      setState(() {
        _testImageError = error.message;
        _testingImage = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _testImageError = '多模态识图暂时失败，请稍后重试。';
        _testingImage = false;
      });
    }
  }

  Future<void> _save() async {
    final input = _buildInput();
    if (input == null) return;
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final snapshot = await widget.backend.saveMultimodalSettings(input);
      if (!mounted) return;
      setState(() {
        _configurationId = snapshot.configuration?.id;
        _hasStoredKey = snapshot.hasStoredApiKey;
        _keyController.clear();
      });
      _setStatus('图片识别 LLM 配置已保存到本机。');
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      _setStatus(error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      _setStatus('图片识别 LLM 配置暂时无法保存，请稍后重试。', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearKey() async {
    setState(() => _busy = true);
    try {
      final snapshot = await widget.backend.clearMultimodalApiKey();
      if (!mounted) return;
      setState(() {
        _hasStoredKey = snapshot.hasStoredApiKey;
        _keyController.clear();
      });
      _setStatus('已清除保存的 API Key。');
    } on AiRecipeBackendException catch (error) {
      if (!mounted) return;
      _setStatus(error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      _setStatus('API Key 暂时无法清除，请稍后重试。', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setStatus(String message, {bool isError = false}) {
    setState(() {
      _statusMessage = message;
      _statusIsError = isError;
    });
  }

  static String _connectionFailureMessage(AiRecipeBackendErrorCode code) {
    return switch (code) {
      AiRecipeBackendErrorCode.authenticationFailed =>
        '连接失败：API Key 无效或没有访问权限。',
      AiRecipeBackendErrorCode.rateLimited => '连接失败：服务请求过于频繁，请稍后重试。',
      AiRecipeBackendErrorCode.timeout => '连接超时，请检查地址或调大超时时间。',
      AiRecipeBackendErrorCode.networkUnavailable => '连接失败：当前网络无法访问该 API 地址。',
      AiRecipeBackendErrorCode.providerUnavailable => '连接失败：模型服务暂时不可用。',
      AiRecipeBackendErrorCode.invalidProviderResponse => '连接失败：服务返回了无法识别的响应。',
      _ => '连接失败，请检查地址、模型与网络状态。',
    };
  }

  @override
  Widget build(BuildContext context) {
    final insecureHttp = _urlController.text.trim().startsWith('http://');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const PxLabel('多模态 LLM 图片识别'),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: PixelLoader()),
          )
        else
          Form(
            key: _formKey,
            child: PixelSurface(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    '图片识别 LLM（独立配置）',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '用于理解图片整体内容，不依赖本地 OCR 模型；'
                    '与菜谱生成 LLM 分开配置。请选择支持图片输入的模型。',
                    style: TextStyle(color: AppColors.ink2, height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  const PixelFieldLabel('Provider 类型', required: true),
                  DropdownButtonFormField<LlmProviderType>(
                    key: const Key('multimodalProviderTypeField'),
                    initialValue: _providerType,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.account_tree_outlined),
                    ),
                    items: LlmProviderType.values
                        .map(
                          (type) => DropdownMenuItem<LlmProviderType>(
                            value: type,
                            child: Text(type.displayName),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _busy ? null : _changeProvider,
                  ),
                  const SizedBox(height: 14),
                  const PixelFieldLabel('API Base URL', required: true),
                  TextFormField(
                    key: const Key('multimodalBaseUrlField'),
                    controller: _urlController,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      hintText: 'http://192.168.1.10:11434/v1',
                      prefixIcon: Icon(Icons.link_rounded),
                    ),
                    validator: (value) =>
                        value == null || value.trim().isEmpty
                        ? '请输入 API 地址'
                        : null,
                    onChanged: (_) => setState(() {}),
                  ),
                  if (insecureHttp) ...<Widget>[
                    const SizedBox(height: 10),
                    const PixelNotice(
                      title: '当前使用 HTTP',
                      message: 'Key 和图片内容将通过明文 HTTP 传输，请仅在可信局域网内使用。',
                      icon: Icons.warning_amber_rounded,
                      tone: PixelNoticeTone.amber,
                    ),
                  ],
                  const SizedBox(height: 14),
                  const PixelFieldLabel('API Key'),
                  TextFormField(
                    key: const Key('multimodalApiKeyField'),
                    controller: _keyController,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      hintText: _hasStoredKey
                          ? '留空将保留当前密钥'
                          : '输入服务提供方的 API Key',
                      prefixIcon: const Icon(Icons.key_rounded),
                      helperText: _hasStoredKey
                          ? '已保存 Key；留空保存时继续使用。'
                          : 'Key 将安全写入 Keychain / Keystore。',
                      suffixIcon: _hasStoredKey
                          ? IconButton(
                              key: const Key('clearMultimodalApiKeyButton'),
                              tooltip: '清除已保存的 API Key',
                              onPressed: _busy ? null : _clearKey,
                              icon: const Icon(Icons.delete_outline),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const PixelFieldLabel('模型名称', required: true),
                  TextFormField(
                    key: const Key('multimodalModelField'),
                    controller: _modelController,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      hintText: '例如 gpt-4o 或 gemini-2.5-flash',
                      prefixIcon: Icon(Icons.memory_rounded),
                    ),
                    validator: (value) =>
                        value == null || value.trim().isEmpty
                        ? '请输入模型名称'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  const PixelFieldLabel('请求超时'),
                  DropdownButtonFormField<Duration>(
                    key: const Key('multimodalRequestTimeoutField'),
                    initialValue: _requestTimeout,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.timer_outlined),
                    ),
                    // 慢速本地模型（如 Ollama/LM Studio）生成完整菜谱 JSON
                    // 可能远超 120 秒，故提供 180/300/600 秒档位（BUG-008）。
                    items: const <int>[30, 60, 120, 180, 300, 600]
                        .map(
                          (seconds) => DropdownMenuItem<Duration>(
                            value: Duration(seconds: seconds),
                            child: Text('$seconds 秒'),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: _busy
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _requestTimeout = value);
                            }
                          },
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          key: const Key('checkBaseConnectionButton'),
                          onPressed: _testingBase || _busy ? null : _checkBaseConnection,
                          icon: _testingBase
                              ? const PixelLoader(size: 6)
                              : const Icon(Icons.network_check_rounded, size: 18),
                          label: Text(_testingBase ? '正在检查…' : '检查基础连接'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        key: const Key('saveMultimodalButton'),
                        onPressed: _busy || _testingBase || _testingProbe
                            ? null
                            : _save,
                        icon: _busy
                            ? const PixelLoader(size: 6, color: Colors.white)
                            : const Icon(Icons.check_rounded, size: 18),
                        label: Text(_busy ? '保存中…' : '保存配置'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 检查图片能力：发送内置 256×256 标准诊断图（BUG-006）。
                  OutlinedButton.icon(
                    key: const Key('checkImageCapabilityButton'),
                    onPressed: _testingProbe || _busy || _testingBase
                        ? null
                        : _checkImageCapability,
                    icon: _testingProbe
                        ? const PixelLoader(size: 6)
                        : const Icon(Icons.visibility_outlined, size: 18),
                    label: Text(
                      _testingProbe
                          ? '正在检查图片能力…'
                          : '检查图片能力（标准诊断图）',
                    ),
                  ),
                  const SizedBox(height: 10),
                  // 用我的图片测试：选一张真实图片发送给多模态模型。
                  OutlinedButton.icon(
                    key: const Key('testMultimodalImageButton'),
                    onPressed: _testingImage || _busy || _testingBase || _testingProbe
                        ? null
                        : _runMultimodalTest,
                    icon: _testingImage
                        ? const PixelLoader(size: 6)
                        : const Icon(Icons.image_search_outlined, size: 18),
                    label: Text(
                      _testingImage ? '正在识别图片…' : '用我的图片测试',
                    ),
                  ),
                  if (_diagnosticResult != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _MultimodalDiagnosticCard(outcome: _diagnosticResult!),
                  ],
                  if (_testImageError != null) ...<Widget>[
                    const SizedBox(height: 12),
                    PixelNotice(
                      key: const Key('multimodalTestImageError'),
                      title: '识图未完成',
                      message: _testImageError,
                      tone: PixelNoticeTone.red,
                      icon: Icons.error_outline_rounded,
                    ),
                  ],
                  if (_testImageResult != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _MultimodalTestResultCard(result: _testImageResult!),
                  ],
                  if (_statusMessage != null) ...<Widget>[
                    const SizedBox(height: 12),
                    PixelSurface(
                      cut: 5,
                      elevation: 0,
                      color: _statusIsError
                          ? AppColors.redSoft
                          : AppColors.greenSofter,
                      borderColor: _statusIsError
                          ? AppColors.red.withValues(alpha: .45)
                          : AppColors.green.withValues(alpha: .45),
                      padding: const EdgeInsets.all(13),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(
                            _statusIsError
                                ? Icons.error_outline_rounded
                                : Icons.check_circle_outline_rounded,
                            size: 18,
                            color: _statusIsError
                                ? AppColors.red
                                : AppColors.greenDeep,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              _statusMessage!,
                              key: const Key('multimodalStatusMessage'),
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.45,
                                fontWeight: FontWeight.w800,
                                color: _statusIsError
                                    ? AppColors.red
                                    : AppColors.greenDeep,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 多模态"测试识图"结果卡片：识别文本 + 耗时 + 模型版本。
class _MultimodalTestResultCard extends StatelessWidget {
  const _MultimodalTestResultCard({required this.result});

  final MultimodalRecognitionResult result;

  @override
  Widget build(BuildContext context) {
    final text = result.text.trim();
    return PixelSurface(
      cut: 6,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.image_search_rounded,
                size: 16,
                color: AppColors.greenDeep,
              ),
              const SizedBox(width: 6),
              const Text(
                '多模态识别结果',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              if (result.durationMs != null)
                Text(
                  '${result.durationMs} ms',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.ink3,
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            text.isEmpty ? '这张图片没有识别出可用内容。' : text,
            key: const Key('multimodalTestImageResultText'),
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.55,
              color: AppColors.ink2,
            ),
          ),
          const SizedBox(height: 8),
          if (result.modelVersion != null)
            Text(
              '模型：${result.modelVersion}',
              style: const TextStyle(fontSize: 11, color: AppColors.ink3),
            ),
        ],
      ),
    );
  }
}

/// 多模态分阶段诊断结果卡（BUG-006，ADR-0028）。
///
/// 逐项展示每个阶段的通过/失败/跳过/警告、耗时、HTTP 状态、稳定 messageKey
/// 中文文案与下一步建议，不再把所有失败统一显示为"链接超时"。
class _MultimodalDiagnosticCard extends StatelessWidget {
  const _MultimodalDiagnosticCard({required this.outcome});

  final MultimodalDiagnosticOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final report = outcome.report;
    final records = report.records;
    return PixelSurface(
      cut: 6,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                report.succeeded
                    ? Icons.check_circle_outline_rounded
                    : Icons.error_outline_rounded,
                size: 16,
                color: report.succeeded ? AppColors.greenDeep : AppColors.red,
              ),
              const SizedBox(width: 6),
              Text(
                report.succeeded ? '诊断通过' : '诊断未通过',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                '${report.totalElapsedMs} ms',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.ink3,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (outcome.modelVersion != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              '模型：${outcome.modelVersion}',
              style: const TextStyle(fontSize: 11, color: AppColors.ink3),
            ),
          ],
          const SizedBox(height: 10),
          for (final record in records) _DiagnosticStageRow(record: record),
          if (outcome.textCapabilityUnconfirmed) ...<Widget>[
            const SizedBox(height: 6),
            const Text(
              '结论：服务与鉴权已通过，但当前模型不支持纯文本请求，'
              '文本能力未确认。请使用"检查图片能力"验证图片输入。',
              key: Key('textCapabilityUnconfirmedMessage'),
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: AppColors.ink2,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 单个诊断阶段的展示行。
class _DiagnosticStageRow extends StatelessWidget {
  const _DiagnosticStageRow({required this.record});

  final LlmDiagnosticStageRecord record;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon, String label) = switch (record.result) {
      LlmDiagnosticStageResult.passed => (
        AppColors.greenDeep,
        Icons.check_circle_outline_rounded,
        '通过',
      ),
      LlmDiagnosticStageResult.failed => (
        AppColors.red,
        Icons.error_outline_rounded,
        '失败',
      ),
      LlmDiagnosticStageResult.skipped => (
        AppColors.ink3,
        Icons.remove_circle_outline_rounded,
        '跳过',
      ),
      LlmDiagnosticStageResult.warning => (
        AppColors.amber,
        Icons.warning_amber_rounded,
        '警告',
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          SizedBox(
            width: 84,
            child: Text(
              _diagnosticStageLabel(record.stage),
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    if (record.elapsedMs > 0) ...<Widget>[
                      const SizedBox(width: 6),
                      Text(
                        '${record.elapsedMs} ms',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.ink3,
                        ),
                      ),
                    ],
                    if (record.httpStatus != null) ...<Widget>[
                      const SizedBox(width: 6),
                      Text(
                        'HTTP ${record.httpStatus}',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.ink3,
                        ),
                      ),
                    ],
                  ],
                ),
                if (record.messageKey != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    _diagnosticMessage(record.messageKey),
                    style: const TextStyle(
                      fontSize: 10.5,
                      height: 1.3,
                      color: AppColors.ink2,
                    ),
                  ),
                ],
                if (record.result == LlmDiagnosticStageResult.failed &&
                    record.nextAction != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    '建议：${record.nextAction}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      height: 1.3,
                      color: AppColors.ink3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _diagnosticStageLabel(LlmDiagnosticStage stage) => switch (stage) {
  LlmDiagnosticStage.configValidation => '配置格式',
  LlmDiagnosticStage.endpointResolution => '地址解析',
  LlmDiagnosticStage.connectionOpen => '连接建立',
  LlmDiagnosticStage.authentication => '鉴权',
  LlmDiagnosticStage.modelValidation => '模型',
  LlmDiagnosticStage.requestAccepted => '请求已接收',
  LlmDiagnosticStage.firstByte => '首字节',
  LlmDiagnosticStage.bodyComplete => '正文完成',
  LlmDiagnosticStage.responseParse => '响应解析',
  LlmDiagnosticStage.imageAssertion => '图片能力',
};

/// 稳定 messageKey → 中文可操作文案（BUG-006）。
///
/// 不直接显示任意服务端正文；未收录的 key 原样返回（不应出现）。
String _diagnosticMessage(String? messageKey) => switch (messageKey) {
  'invalid_config' => '配置格式错误，请修正地址或协议',
  'network_unreachable' => '未建立连接，请检查地址、网络与证书',
  'cancelled' => '测试已取消',
  'request_incompatible' => '请求体、图片字段或模型能力与 Provider 协议不兼容',
  'unauthorized' => '鉴权失败，请检查 API Key 与模型权限',
  'not_found' => '接口或模型不存在，请检查地址、路径与模型名称',
  'method_not_allowed' => '接口类型错误，请检查是否填到了网页或错误路径',
  'provider_gateway_timeout' => '服务端或网关超时，请稍后重试或查询服务状态',
  'model_busy' => '模型加载中或资源被占用，请稍后重试',
  'payload_too_large' => '请求体过大，请压缩图片或减少内容',
  'unsupported_media_type' => '图片类型不支持，请使用 JPG、PNG 或 WebP',
  'rate_limited' => '限流或额度不足，请稍后重试',
  'server_error' => '服务暂时不可用，请稍后重试或切换备用服务',
  'first_byte_deadline' =>
    '服务已接收请求但未开始返回（排队、冷启动或模型能力问题）',
  'body_idle_deadline' => '正文返回后长时间无新数据，响应中断或流未结束',
  'invalid_response' => '响应协议不兼容，服务返回了无法识别的内容',
  'image_not_observed' => '模型未正确读取图片（文字或红色方块断言失败）',
  'text_capability_unconfirmed' =>
    '服务与鉴权已通过，但当前模型不支持纯文本，请直接检查图片能力',
  _ => messageKey ?? '',
};
