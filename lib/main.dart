import 'package:flutter/material.dart';

import 'data/machiscore_repository.dart';
import 'screens/search_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const MachiscoreApp());
}

class MachiscoreApp extends StatelessWidget {
  /// テストから差し替えるための注入口。未指定なら既定のリポジトリを使う。
  final MachiscoreRepository? repository;

  const MachiscoreApp({super.key, this.repository});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'マチスコア',
      // 端末のダークモード設定に追従する
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      home: SearchScreen(repository: repository),
    );
  }
}
