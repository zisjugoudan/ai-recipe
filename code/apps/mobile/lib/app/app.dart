import 'package:flutter/material.dart';

import '../data/llm_config_repository.dart';
import '../features/llm_settings/llm_settings_page.dart';

class AiRecipeApp extends StatelessWidget {
  const AiRecipeApp({super.key, this.repository});

  final LlmConfigRepository? repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI 食谱',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE66A36)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: LlmSettingsPage(repository: repository),
    );
  }
}
