import 'package:flutter/material.dart';

import '../data/machiscore_repository.dart';
import '../models/municipality.dart';
import '../theme/app_theme.dart';
import '../widgets/machiscore_logo.dart';
import 'compare_screen.dart';
import 'result_screen.dart';

class SearchScreen extends StatefulWidget {
  /// テストから差し替えるための注入口。未指定なら既定のリポジトリを使う。
  final MachiscoreRepository? repository;

  const SearchScreen({super.key, this.repository});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final MachiscoreRepository _repository = widget.repository ?? MachiscoreRepository();
  final _controller = TextEditingController();
  bool _loading = true;
  Object? _loadError;
  List<Municipality> _results = const [];

  /// 比較に選んだ町。横並びで見せるので3件までに制限する。
  final List<Municipality> _selected = [];
  static const _maxCompare = 3;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await _repository.load();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  void _onQueryChanged(String query) {
    setState(() => _results = _repository.search(query));
  }

  void _toggleSelection(Municipality municipality) {
    setState(() {
      final index = _selected.indexWhere((m) => m.code == municipality.code);
      if (index >= 0) {
        _selected.removeAt(index);
      } else if (_selected.length < _maxCompare) {
        _selected.add(municipality);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('くらべられるのは$_maxCompare件までです')),
        );
      }
    });
  }

  void _openCompare() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CompareScreen(
          municipalities: List.of(_selected),
          categories: _repository.categories,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const MachiscoreLogotype(),
        actions: [
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: () => setState(_selected.clear),
              child: const Text('選択解除'),
            ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: _selected.length >= 2
          ? FloatingActionButton.extended(
              onPressed: _openCompare,
              icon: const Icon(Icons.compare_arrows),
              label: Text('${_selected.length}件をくらべる'),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return _LoadErrorView(onRetry: _load);
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            onChanged: _onQueryChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: '町の名前で検索',
              hintText: '例: 渋谷区、札幌市中央区',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: '検索条件をクリア',
                      onPressed: () {
                        _controller.clear();
                        _onQueryChanged('');
                      },
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_controller.text.trim().isEmpty) {
      return _EmptyState(categories: _repository.categories);
    }
    if (_results.isEmpty) {
      return const Center(child: Text('該当する市区町村が見つかりません'));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text(
            '${_results.length}件',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textSecondary),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final municipality = _results[index];
              final score = municipality.totalScore;
              final isSelected = _selected.any((m) => m.code == municipality.code);
              return ListTile(
                selected: isSelected,
                leading: IconButton(
                  icon: Icon(
                    isSelected ? Icons.check_circle : Icons.add_circle_outline,
                    color: isSelected ? context.palette.brand : context.palette.textMuted,
                  ),
                  tooltip: isSelected ? 'くらべる対象から外す' : 'くらべる対象に追加',
                  onPressed: () => _toggleSelection(municipality),
                ),
                title: Text(municipality.name),
                subtitle: Text(municipality.prefecture),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (score != null) ...[
                      // 一覧の段階でも点数の高さが色でわかるよう小さなバーを添える
                      SizedBox(
                        width: 36,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: score / 100,
                            minHeight: 5,
                            backgroundColor: context.palette.track,
                            valueColor: AlwaysStoppedAnimation(context.palette.scoreColor(score)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Text(
                      score != null ? '$score点' : '対象外',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: score != null ? context.palette.textPrimary : context.palette.textMuted,
                        fontWeight: score != null ? FontWeight.bold : null,
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ResultScreen(
                        municipality: municipality,
                        categories: _repository.categories,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LoadErrorView extends StatelessWidget {
  final VoidCallback onRetry;

  const _LoadErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: context.palette.textMuted),
            const SizedBox(height: 16),
            const Text('データを読み込めませんでした', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('再試行')),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final List<CategoryInfo> categories;

  const _EmptyState({required this.categories});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(top: 28),
        // 中央揃えの説明文は「テンプレート感」が出て読みにくいので左揃えにする。
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ヘッダーにマークがあるので、ここは文字だけで見出しを立てる
            Text(
              '町の実力を、数字で。',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: context.palette.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '町の名前を検索すると、暮らしに関わる${categories.length}つのジャンルについて、'
              '昼間人口あたりの事業所数が全国で何位かを100点満点のスコアで表示します。',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.palette.textSecondary,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '見られるジャンル',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.palette.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            // 結果画面と同じカードの見た目にして、何が返ってくるかを予告する
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (index, category) in categories.indexed) ...[
                    if (index > 0) const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              category.name,
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                          Text(
                            '— 点',
                            style: TextStyle(color: context.palette.textMuted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '出典: 総務省統計局 経済センサス・国勢調査',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.palette.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
