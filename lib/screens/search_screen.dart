import 'package:flutter/material.dart';

import '../data/current_location_finder.dart';
import '../data/home_town_store.dart';
import '../data/machiscore_repository.dart';
import '../models/municipality.dart';
import '../theme/app_theme.dart';
import '../widgets/machiscore_logo.dart';
import '../widgets/score_bar.dart';
import 'about_score_screen.dart';
import 'compare_screen.dart';
import 'ranking_screen.dart';
import 'result_screen.dart';

class SearchScreen extends StatefulWidget {
  /// テストから差し替えるための注入口。未指定なら既定のリポジトリを使う。
  final MachiscoreRepository? repository;

  /// マイタウンの保存先。テストではメモリ実装に差し替える。
  final HomeTownStore? homeTownStore;

  /// 現在地の解決。テストでは座標と住所を差し替える。
  final CurrentLocationFinder? locationFinder;

  const SearchScreen({
    super.key,
    this.repository,
    this.homeTownStore,
    this.locationFinder,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final MachiscoreRepository _repository = widget.repository ?? MachiscoreRepository();
  late final HomeTownStore _homeTownStore =
      widget.homeTownStore ?? SharedPreferencesHomeTownStore();

  late final CurrentLocationFinder _locationFinder =
      widget.locationFinder ?? const CurrentLocationFinder();

  /// 登録したマイタウン。未登録なら null。
  Municipality? _homeTown;

  /// 現在地を調べている最中か。
  bool _locating = false;
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
      final homeCode = await _homeTownStore.load();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _homeTown = homeCode == null
            ? null
            : _repository.municipalities
                .where((m) => m.code == homeCode)
                .firstOrNull;
      });
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

  void _openResult(Municipality municipality) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          municipality: municipality,
          categories: _repository.categories,
          isSelectedForCompare: _selected.any((m) => m.code == municipality.code),
          // 結果を見た流れでそのまま比較に積めるようにする
          onCompare: (target) {
            _toggleSelection(target);
            Navigator.of(context).pop();
          },
          similar: _repository.similarTo(municipality),
          // 似ている町から次の町へ。積み重ねて回遊できる
          onOpenMunicipality: _openResult,
          isHomeTown: _homeTown?.code == municipality.code,
          onToggleHomeTown: _toggleHomeTown,
        ),
      ),
    );
  }

  Future<void> _toggleHomeTown(Municipality municipality) async {
    final isHome = _homeTown?.code == municipality.code;
    if (isHome) {
      await _homeTownStore.clear();
    } else {
      await _homeTownStore.save(municipality.code);
    }
    if (!mounted) return;
    setState(() => _homeTown = isHome ? null : municipality);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isHome ? 'マイタウンを解除しました' : '${municipality.name}をマイタウンにしました'),
      ),
    );
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    final result = await _locationFinder.find(_repository.municipalities);
    if (!mounted) return;
    setState(() => _locating = false);

    switch (result) {
      case LocationFound(:final municipality):
        _openResult(municipality);
      case LocationError(:final failure):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_locationMessage(failure))),
        );
    }
  }

  String _locationMessage(LocationFailure failure) => switch (failure) {
        LocationFailure.serviceDisabled => '位置情報サービスがオフになっています',
        LocationFailure.permissionDenied => '位置情報の利用が許可されていません',
        LocationFailure.permissionDeniedForever =>
          '設定アプリから位置情報の利用を許可してください',
        LocationFailure.notFound => '現在地の市区町村を特定できませんでした',
        LocationFailure.failed => '現在地を取得できませんでした',
      };

  void _openRanking() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RankingScreen(
          repository: _repository,
          onOpenMunicipality: _openResult,
        ),
      ),
    );
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
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AboutScoreScreen(repository: _repository),
              ),
            ),
            tooltip: 'スコアの見かた',
            icon: const Icon(Icons.help_outline),
          ),
          IconButton(
            onPressed: _openRanking,
            tooltip: '全国ランキング',
            icon: const Icon(Icons.leaderboard_outlined),
          ),
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
              labelText: '町の名前で検索（かな・ローマ字可）',
              hintText: '渋谷区 / しぶや / shibuya',
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
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _locating ? null : _useCurrentLocation,
              icon: _locating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location, size: 18),
              label: Text(_locating ? '現在地を調べています' : '現在地の町を見る'),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_controller.text.trim().isEmpty) {
      return _EmptyState(
        categories: _repository.categories,
        homeTown: _homeTown,
        onOpenHomeTown: _openResult,
        sourceNote: _repository.sourceNote,
      );
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
                        child: ScoreBar(score: score, height: 5),
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
                onTap: () => _openResult(municipality),
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

  /// 登録済みのマイタウン。あれば一番上に出す。
  final Municipality? homeTown;
  final ValueChanged<Municipality> onOpenHomeTown;

  /// 出典表記。データ側が持つ文言をそのまま出す。
  final String sourceNote;

  const _EmptyState({
    required this.categories,
    required this.homeTown,
    required this.onOpenHomeTown,
    required this.sourceNote,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(top: 28),
        // 中央揃えの説明文は「テンプレート感」が出て読みにくいので左揃えにする。
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (homeTown != null) ...[
              _HomeTownCard(municipality: homeTown!, onTap: onOpenHomeTown),
              const SizedBox(height: 28),
            ],
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
              '検索するとこの5つに点数がつきます',
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
                          // 「—点」だと「データなし」に読めるので、
                          // 検索後にここが埋まることが分かる表現にする
                          Icon(
                            Icons.more_horiz,
                            size: 18,
                            color: context.palette.textMuted,
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
              '出典: 総務省統計局\n$sourceNote',
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


/// 登録したマイタウンを検索前に見せるカード。
/// 毎回検索し直さずに済み、アプリを再び開く理由にもなる。
class _HomeTownCard extends StatelessWidget {
  final Municipality municipality;
  final ValueChanged<Municipality> onTap;

  const _HomeTownCard({required this.municipality, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final score = municipality.totalScore;
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onTap(municipality),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.star, size: 16, color: context.palette.brand),
                  const SizedBox(width: 4),
                  Text(
                    'マイタウン',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.palette.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                children: [
                  Text(
                    municipality.name,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (score != null)
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$score',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextSpan(
                            text: '点',
                            style: TextStyle(
                              color: context.palette.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (score != null) ...[
                const SizedBox(height: 8),
                ScoreBar(score: score),
              ],
              if (municipality.prefectureRank != null) ...[
                const SizedBox(height: 6),
                Text(
                  '${municipality.prefecture}で${municipality.prefectureRank}位',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.palette.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
