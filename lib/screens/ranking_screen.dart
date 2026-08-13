import 'package:flutter/material.dart';

import '../data/machiscore_repository.dart';
import '../models/municipality.dart';
import '../theme/app_theme.dart';

/// 全国ランキングを眺める画面。
///
/// 事業所数が少ない町（喫茶店4軒の曽爾村など）も上位に出るが、
/// 数字自体は正確なので下限では切らない。小規模自治体を一律に外すと
/// 地方がランキングから消えてしまい、町を知るアプリとして本末転倒になる。
/// 代わりに各行へ事業所数を併記し、読み手が判断できるようにしている。
class RankingScreen extends StatefulWidget {
  final MachiscoreRepository repository;
  final ValueChanged<Municipality> onOpenMunicipality;

  const RankingScreen({
    super.key,
    required this.repository,
    required this.onOpenMunicipality,
  });

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  /// null は総合スコアのランキング。
  String? _categoryCode;

  static const _limit = 100;

  /// 並べ替えた結果。1863件のソートをビルドのたびに回さないよう保持する。
  List<Municipality> _ranked = const [];

  @override
  void initState() {
    super.initState();
    _ranked = _rank();
  }

  void _selectCategory(String? code) {
    setState(() {
      _categoryCode = code;
      _ranked = _rank();
    });
  }

  List<Municipality> _rank() {
    final all = widget.repository.municipalities.where((m) => m.ranked).toList();
    final code = _categoryCode;
    if (code == null) {
      all.sort((a, b) {
        final diff = (b.totalScore ?? 0).compareTo(a.totalScore ?? 0);
        return diff != 0 ? diff : a.name.compareTo(b.name);
      });
    } else {
      all.removeWhere((m) => m.categories[code]?.rank == null);
      all.sort((a, b) => a.categories[code]!.rank!.compareTo(b.categories[code]!.rank!));
    }
    return all.take(_limit).toList();
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.repository.categories;
    final ranked = _ranked;

    return Scaffold(
      appBar: AppBar(title: const Text('全国ランキング')),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _CategoryChip(
                  label: '総合',
                  selected: _categoryCode == null,
                  onTap: () => _selectCategory(null),
                ),
                for (final category in categories)
                  _CategoryChip(
                    label: category.name,
                    selected: _categoryCode == category.code,
                    onTap: () => _selectCategory(category.code),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: ranked.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final municipality = ranked[index];
                return _RankingRow(
                  position: index + 1,
                  municipality: municipality,
                  categoryCode: _categoryCode,
                  onTap: widget.onOpenMunicipality,
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                '上位$_limit件を表示しています。'
                '事業所数が少ない町も含むため、件数もあわせてご覧ください',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.palette.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        showCheckmark: false,
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  final int position;
  final Municipality municipality;
  final String? categoryCode;
  final ValueChanged<Municipality> onTap;

  const _RankingRow({
    required this.position,
    required this.municipality,
    required this.categoryCode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final code = categoryCode;
    final entry = code == null ? null : municipality.categories[code];
    final score = entry?.score ?? municipality.totalScore;

    return ListTile(
      leading: SizedBox(
        width: 34,
        child: Text(
          '$position',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: position <= 3 ? palette.brand : palette.textSecondary,
            fontWeight: position <= 3 ? FontWeight.bold : null,
          ),
        ),
      ),
      title: Text(municipality.name),
      subtitle: Text(
        entry == null
            ? municipality.prefecture
            // 数字の当てにしやすさが分かるよう事業所数を必ず添える
            : '${municipality.prefecture} ・ ${entry.count}件',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (score != null) ...[
            SizedBox(
              width: 36,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: score / 100,
                  minHeight: 5,
                  backgroundColor: palette.track,
                  valueColor: AlwaysStoppedAnimation(palette.scoreColor(score)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$score点',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: () => onTap(municipality),
    );
  }
}
