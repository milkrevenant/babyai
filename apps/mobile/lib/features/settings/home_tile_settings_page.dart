import "package:flutter/material.dart";

import "../../core/i18n/app_i18n.dart";
import "../../core/theme/app_theme_controller.dart";

class HomeTileSettingsPage extends StatelessWidget {
  const HomeTileSettingsPage({super.key, required this.themeController});

  final AppThemeController themeController;

  Widget _boundedControl(Widget child) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: child,
      ),
    );
  }

  InputDecoration _dropdownDecoration(BuildContext context, String label) {
    final ColorScheme color = Theme.of(context).colorScheme;
    final BorderRadius borderRadius = BorderRadius.circular(14);
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: color.surfaceContainerHighest.withValues(alpha: 0.24),
      border: OutlineInputBorder(borderRadius: borderRadius),
      enabledBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: color.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: color.primary, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _profileDropdown({
    required BuildContext context,
    required ChildCareProfile initialValue,
    required List<DropdownMenuItem<ChildCareProfile>> items,
    required ValueChanged<ChildCareProfile?> onChanged,
  }) {
    return _boundedControl(
      DropdownButtonFormField<ChildCareProfile>(
        initialValue: initialValue,
        isExpanded: true,
        menuMaxHeight: 320,
        borderRadius: BorderRadius.circular(14),
        icon: const Icon(Icons.expand_more_rounded, size: 20),
        decoration: _dropdownDecoration(
          context,
          tr(
            context,
            ko: "설문 기본 유형",
            en: "Default profile",
            es: "Perfil predeterminado",
          ),
        ),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  Widget _columnsDropdown({
    required BuildContext context,
    required int initialValue,
    required ValueChanged<int?> onChanged,
  }) {
    return _boundedControl(
      DropdownButtonFormField<int>(
        initialValue: initialValue,
        isExpanded: true,
        menuMaxHeight: 240,
        borderRadius: BorderRadius.circular(14),
        icon: const Icon(Icons.expand_more_rounded, size: 20),
        decoration: _dropdownDecoration(
          context,
          tr(
            context,
            ko: "홈 타일 열 수",
            en: "Home tile columns",
            es: "Columnas de tiles",
          ),
        ),
        items: const <DropdownMenuItem<int>>[
          DropdownMenuItem<int>(value: 2, child: Text("2")),
          DropdownMenuItem<int>(value: 3, child: Text("3")),
        ],
        onChanged: onChanged,
      ),
    );
  }

  String _profileLabel(BuildContext context, ChildCareProfile profile) {
    switch (profile) {
      case ChildCareProfile.breastfeeding:
        return tr(
          context,
          ko: "모유수유 산모",
          en: "Breastfeeding parent",
          es: "Madre lactante",
        );
      case ChildCareProfile.formula:
        return tr(
          context,
          ko: "분유 수유 산모",
          en: "Formula parent",
          es: "Madre con formula",
        );
      case ChildCareProfile.weaning:
        return tr(
          context,
          ko: "이유식 부모",
          en: "Weaning parent",
          es: "Padre de destete",
        );
    }
  }

  IconData _tileIcon(HomeTileType tile) {
    switch (tile) {
      case HomeTileType.formula:
        return Icons.local_drink_outlined;
      case HomeTileType.breastfeed:
        return Icons.favorite_outline;
      case HomeTileType.weaning:
        return Icons.rice_bowl_outlined;
      case HomeTileType.diaper:
        return Icons.baby_changing_station_outlined;
      case HomeTileType.sleep:
        return Icons.bedtime_outlined;
      case HomeTileType.medication:
        return Icons.medication_outlined;
      case HomeTileType.memo:
        return Icons.sticky_note_2_outlined;
    }
  }

  String _tileLabel(BuildContext context, HomeTileType tile) {
    switch (tile) {
      case HomeTileType.formula:
        return tr(context, ko: "분유", en: "Formula", es: "Formula");
      case HomeTileType.breastfeed:
        return tr(context, ko: "모유", en: "Breastfeed", es: "Lactancia");
      case HomeTileType.weaning:
        return tr(context, ko: "이유식", en: "Weaning", es: "Destete");
      case HomeTileType.diaper:
        return tr(context, ko: "기저귀", en: "Diaper", es: "Panal");
      case HomeTileType.sleep:
        return tr(context, ko: "수면", en: "Sleep", es: "Sueno");
      case HomeTileType.medication:
        return tr(context, ko: "투약", en: "Medication", es: "Medicacion");
      case HomeTileType.memo:
        return tr(context, ko: "메모", en: "Memo", es: "Memo");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr(context, ko: "홈 타일 관리", en: "Home Tiles", es: "Tiles de inicio"),
        ),
      ),
      body: AnimatedBuilder(
        animation: themeController,
        builder: (BuildContext context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            children: <Widget>[
              Text(
                tr(
                  context,
                  ko: "아이 유형",
                  en: "Child type",
                  es: "Tipo de nino",
                ),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              _profileDropdown(
                context: context,
                initialValue: themeController.childCareProfile,
                items: ChildCareProfile.values
                    .map(
                      (ChildCareProfile profile) =>
                          DropdownMenuItem<ChildCareProfile>(
                        value: profile,
                        child: Text(_profileLabel(context, profile)),
                      ),
                    )
                    .toList(),
                onChanged: (ChildCareProfile? value) {
                  if (value != null) {
                    themeController.setChildCareProfile(value);
                  }
                },
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () {
                  themeController.applyDefaultHomeTilesForProfile();
                },
                icon: const Icon(Icons.auto_fix_high_outlined),
                label: Text(
                  tr(
                    context,
                    ko: "유형별 추천 타일 적용",
                    en: "Apply recommended tiles",
                    es: "Aplicar tiles recomendados",
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tr(
                  context,
                  ko: "모유/분유/이유식 유형에 맞는 기본 타일 세트를 다시 적용합니다.",
                  en: "Re-apply tile defaults for breastfeeding/formula/weaning.",
                  es: "Reaplica los tiles segun lactancia/formula/destete.",
                ),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              _columnsDropdown(
                context: context,
                initialValue: themeController.homeTileColumns,
                onChanged: (int? value) {
                  if (value != null) {
                    themeController.setHomeTileColumns(value);
                  }
                },
              ),
              const SizedBox(height: 8),
              Text(
                tr(
                  context,
                  ko: "기본은 2열이며, 필요 시 3열로 더 촘촘하게 배치할 수 있습니다.",
                  en: "Default is 2 columns. Switch to 3 columns for denser tiles.",
                  es: "Por defecto son 2 columnas. Cambie a 3 para mayor densidad.",
                ),
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const Divider(height: 24),
              Text(
                tr(
                  context,
                  ko: "홈 화면 타일 표시",
                  en: "Visible home tiles",
                  es: "Tiles visibles",
                ),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              ...HomeTileType.values.map(
                (HomeTileType tile) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: themeController.isHomeTileEnabled(tile),
                  title: Text(_tileLabel(context, tile)),
                  secondary: Icon(_tileIcon(tile)),
                  onChanged: (bool value) {
                    themeController.setHomeTileEnabled(tile, value);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
