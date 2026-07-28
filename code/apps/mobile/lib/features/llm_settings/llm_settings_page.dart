import 'package:flutter/material.dart';

import '../../data/llm_config_repository.dart';
import '../../domain/llm/llm_connection_config.dart';
import '../../domain/llm/llm_provider.dart';
import '../../domain/llm/llm_provider_exception.dart';
import '../../domain/llm/llm_provider_type.dart';
import '../../providers/llm/llm_provider_factory.dart';

typedef LlmProviderBuilder = LlmProvider Function(LlmProviderType type);

class LlmSettingsPage extends StatefulWidget {
  const LlmSettingsPage({super.key, this.repository, this.providerBuilder});

  final LlmConfigRepository? repository;
  final LlmProviderBuilder? providerBuilder;

  @override
  State<LlmSettingsPage> createState() => _LlmSettingsPageState();
}

class _LlmSettingsPageState extends State<LlmSettingsPage> {
  late final LlmConfigRepository _repository;
  late final LlmProviderBuilder _providerBuilder;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(text: '我的 LLM');
  final _urlController = TextEditingController();
  final _keyController = TextEditingController();
  final _modelController = TextEditingController();

  LlmProviderType _providerType = LlmProviderType.openAiCompatible;
  LlmConnectionConfig? _savedConfig;
  bool _loading = true;
  bool _busy = false;
  bool _hasStoredKey = false;
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? DeviceLlmConfigRepository();
    final factory = const LlmProviderFactory();
    _providerBuilder = widget.providerBuilder ?? factory.create;
    _urlController.text = _providerType.defaultBaseUrl;
    _load();
  }

  Future<void> _load() async {
    try {
      final config = await _repository.load();
      if (config != null) {
        final apiKey = await _repository.readApiKey(config.secretRef);
        _savedConfig = config;
        _providerType = config.providerType;
        _nameController.text = config.name;
        _urlController.text = config.baseUrl;
        _modelController.text = config.model;
        _hasStoredKey = apiKey.isNotEmpty;
      }
    } catch (_) {
      _setStatus('读取本机配置失败，请重新填写并保存。', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _keyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  void _changeProvider(LlmProviderType? type) {
    if (type == null || type == _providerType) return;
    final previousDefault = _providerType.defaultBaseUrl;
    setState(() {
      _providerType = type;
      if (_urlController.text.trim().isEmpty ||
          _urlController.text.trim() == previousDefault) {
        _urlController.text = type.defaultBaseUrl;
      }
      _statusMessage = null;
    });
  }

  LlmConnectionConfig? _buildConfig() {
    if (!(_formKey.currentState?.validate() ?? false)) return null;
    try {
      final id =
          _savedConfig?.id ??
          DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      return LlmConnectionConfig(
        id: id,
        name: _nameController.text.trim(),
        providerType: _providerType,
        baseUrl: _urlController.text,
        secretRef: _savedConfig?.secretRef ?? 'llm-api-key-$id',
        model: _modelController.text.trim(),
        requestTimeout:
            _savedConfig?.requestTimeout ?? const Duration(seconds: 120),
      );
    } on FormatException catch (error) {
      _setStatus(error.message, isError: true);
      return null;
    }
  }

  Future<String> _resolveApiKey(LlmConnectionConfig config) async {
    final entered = _keyController.text.trim();
    if (entered.isNotEmpty) return entered;
    return _repository.readApiKey(config.secretRef);
  }

  Future<void> _testConnection() async {
    final config = _buildConfig();
    if (config == null) return;
    setState(() {
      _busy = true;
      _statusMessage = '正在发送最小测试请求…';
      _statusIsError = false;
    });
    try {
      final apiKey = await _resolveApiKey(config);
      await _providerBuilder(
        config.providerType,
      ).testConnection(config: config, apiKey: apiKey);
      _setStatus('连接成功，协议、地址、鉴权和模型均可用。');
    } on LlmProviderException catch (error) {
      _setStatus(error.message, isError: true);
    } catch (_) {
      _setStatus('连接测试失败，请检查配置。', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final config = _buildConfig();
    if (config == null) return;
    setState(() => _busy = true);
    try {
      final enteredKey = _keyController.text.trim();
      final isNewConfiguration = _savedConfig == null;
      await _repository.save(
        config,
        apiKey: enteredKey.isNotEmpty || isNewConfiguration ? enteredKey : null,
      );
      _savedConfig = config;
      _hasStoredKey = enteredKey.isNotEmpty || _hasStoredKey;
      _keyController.clear();
      _setStatus('配置已保存。API Key 仅存储在系统安全存储中。');
    } catch (_) {
      _setStatus('保存失败，请检查系统安全存储是否可用。', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearKey() async {
    final config = _savedConfig;
    if (config == null) {
      _keyController.clear();
      return;
    }
    setState(() => _busy = true);
    try {
      await _repository.clearApiKey(config.secretRef);
      _keyController.clear();
      _hasStoredKey = false;
      _setStatus('已清除保存的 API Key。');
    } catch (_) {
      _setStatus('清除 API Key 失败。', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setStatus(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(() {
      _statusMessage = message;
      _statusIsError = isError;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('自定义 LLM API')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: <Widget>[
                    Text(
                      '选择协议后，只需填写 API 地址、Key 和模型。地址可以指向本地、局域网、自建服务或第三方云服务。',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<LlmProviderType>(
                      key: const Key('providerTypeField'),
                      initialValue: _providerType,
                      decoration: const InputDecoration(labelText: '接口协议'),
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
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('configNameField'),
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: '配置名称'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? '请输入配置名称'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('baseUrlField'),
                      controller: _urlController,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'API Base URL',
                        hintText: 'http://192.168.1.10:11434/v1',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? '请输入 API 地址'
                          : null,
                      onChanged: (_) => setState(() {}),
                    ),
                    if (_urlController.text.trim().startsWith(
                      'http://',
                    )) ...<Widget>[
                      const SizedBox(height: 8),
                      const Text(
                        '当前使用明文 HTTP，API Key 和请求内容可能被同一网络中的其他设备读取。仅在可信网络和可信服务中使用。',
                        style: TextStyle(color: Colors.deepOrange),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('apiKeyField'),
                      controller: _keyController,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: 'API Key（无鉴权服务可留空）',
                        helperText: _hasStoredKey
                            ? '已保存 Key；留空将继续使用，不会回填明文。'
                            : 'Key 只保存到系统 Keychain/Keystore。',
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
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('modelField'),
                      controller: _modelController,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: '模型',
                        hintText: '例如 gpt-4.1-mini 或 gemini-2.5-flash',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? '请输入模型名称'
                          : null,
                    ),
                    const SizedBox(height: 20),
                    if (_statusMessage != null)
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _statusMessage!,
                          key: const Key('statusMessage'),
                          style: TextStyle(
                            color: _statusIsError
                                ? Theme.of(context).colorScheme.error
                                : Colors.green.shade700,
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const Key('testConnectionButton'),
                            onPressed: _busy ? null : _testConnection,
                            icon: const Icon(Icons.network_check),
                            label: const Text('测试连接'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            key: const Key('saveConfigButton'),
                            onPressed: _busy ? null : _save,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('保存配置'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '测试连接会向所选模型发送一次最小请求，可能产生少量服务费用。应用不会把 Key、Prompt 或完整响应写入日志。',
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
