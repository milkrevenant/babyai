import "package:flutter/material.dart";

import "../../core/i18n/app_i18n.dart";
import "../../core/theme/app_theme_controller.dart";

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.themeController,
    required this.isGoogleLoggedIn,
    required this.accountName,
    required this.accountEmail,
    required this.onGoogleLogin,
    required this.onGoogleLogout,
  });

  final AppThemeController themeController;
  final bool isGoogleLoggedIn;
  final String accountName;
  final String accountEmail;
  final Future<void> Function() onGoogleLogin;
  final VoidCallback onGoogleLogout;

  Future<void> _selectTheme(AppThemeMode mode) async {
    await themeController.setMode(mode);
  }

  String _mainFontLabel(BuildContext context, AppMainFont font) {
    switch (font) {
      case AppMainFont.notoSans:
        return "Noto Sans";
      case AppMainFont.systemSans:
        return tr(context,
            ko: "시스템 산세리프", en: "System Sans", es: "Sans del sistema");
    }
  }

  String _highlightFontLabel(BuildContext context, AppHighlightFont font) {
    switch (font) {
      case AppHighlightFont.ibmPlexSans:
        return "IBM Plex Sans";
      case AppHighlightFont.notoSans:
        return "Noto Sans";
    }
  }

  String _toneLabel(BuildContext context, AppAccentTone tone) {
    switch (tone) {
      case AppAccentTone.gold:
        return tr(context, ko: "골드", en: "Gold", es: "Dorado");
      case AppAccentTone.teal:
        return tr(context, ko: "틸", en: "Teal", es: "Verde azulado");
      case AppAccentTone.coral:
        return tr(context, ko: "코랄", en: "Coral", es: "Coral");
      case AppAccentTone.indigo:
        return tr(context, ko: "인디고", en: "Indigo", es: "Indigo");
    }
  }

  Color _toneColor(AppAccentTone tone) {
    switch (tone) {
      case AppAccentTone.gold:
        return const Color(0xFFB9933F);
      case AppAccentTone.teal:
        return const Color(0xFF0E8F88);
      case AppAccentTone.coral:
        return const Color(0xFFBE5F3D);
      case AppAccentTone.indigo:
        return const Color(0xFF5C66C5);
    }
  }

  String _bottomMenuLabel(BuildContext context, AppBottomMenu menu) {
    switch (menu) {
      case AppBottomMenu.chat:
        return tr(context, ko: "AI 채팅", en: "AI Chat", es: "Chat IA");
      case AppBottomMenu.statistics:
        return tr(context, ko: "통계", en: "Statistics", es: "Estadisticas");
      case AppBottomMenu.photos:
        return tr(context, ko: "사진", en: "Photos", es: "Fotos");
      case AppBottomMenu.market:
        return tr(context, ko: "장터", en: "Market", es: "Mercado");
      case AppBottomMenu.community:
        return tr(context, ko: "커뮤니티", en: "Community", es: "Comunidad");
    }
  }

  String _languageLabel(AppLanguage language) {
    switch (language) {
      case AppLanguage.ko:
        return "한국어";
      case AppLanguage.en:
        return "English";
      case AppLanguage.es:
        return "Espanol";
    }
  }

  Future<void> _showCustomerCenter(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(tr(context,
              ko: "고객센터", en: "Customer Center", es: "Centro de ayuda")),
          content: Text(
            tr(
              context,
              ko: "문의: support@babyai.app\n운영시간: 평일 09:00-18:00 (KST)",
              en: "Contact: support@babyai.app\nHours: Mon-Fri 09:00-18:00 (KST)",
              es: "Contacto: support@babyai.app\nHorario: Lun-Vie 09:00-18:00 (KST)",
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr(context, ko: "닫기", en: "Close", es: "Cerrar")),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showPrivacyTerms(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(tr(context,
              ko: "개인정보 수집 약관 안내",
              en: "Privacy Terms",
              es: "Terminos de privacidad")),
          content: Text(
            tr(
              context,
              ko: "기록, 사진, 계정 정보는 서비스 제공 목적 범위에서만 사용됩니다.\n삭제/내보내기 요청은 고객센터를 통해 처리할 수 있습니다.",
              en: "Event/photo/account data is used only for service operations.\nDeletion/export requests are available via support.",
              es: "Los datos de registros/fotos/cuenta se usan solo para el servicio.\nPuede solicitar eliminacion/exportacion en soporte.",
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr(context, ko: "닫기", en: "Close", es: "Cerrar")),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme color = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, ko: "설정", en: "Settings", es: "Ajustes")),
      ),
      body: AnimatedBuilder(
        animation: themeController,
        builder: (BuildContext context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            children: <Widget>[
              Text(tr(context, ko: "언어", en: "Language", es: "Idioma"),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              DropdownButtonFormField<AppLanguage>(
                initialValue: themeController.language,
                decoration: InputDecoration(
                  labelText: tr(context,
                      ko: "앱 언어", en: "App language", es: "Idioma de la app"),
                  border: const OutlineInputBorder(),
                ),
                items: AppLanguage.values
                    .map(
                      (AppLanguage item) => DropdownMenuItem<AppLanguage>(
                        value: item,
                        child: Text(_languageLabel(item)),
                      ),
                    )
                    .toList(),
                onChanged: (AppLanguage? value) {
                  if (value != null) {
                    themeController.setLanguage(value);
                  }
                },
              ),
              const Divider(height: 24),
              Text(
                  tr(context,
                      ko: "표시 모드", en: "Display Mode", es: "Modo de pantalla"),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              RadioGroup<AppThemeMode>(
                groupValue: themeController.mode,
                onChanged: (AppThemeMode? value) {
                  if (value != null) {
                    _selectTheme(value);
                  }
                },
                child: Column(
                  children: <Widget>[
                    RadioListTile<AppThemeMode>(
                      value: AppThemeMode.system,
                      title: Text(tr(context,
                          ko: "기기 설정 따름",
                          en: "Follow system",
                          es: "Seguir sistema")),
                    ),
                    RadioListTile<AppThemeMode>(
                      value: AppThemeMode.dark,
                      title: Text(tr(context,
                          ko: "다크 모드", en: "Dark mode", es: "Modo oscuro")),
                    ),
                    RadioListTile<AppThemeMode>(
                      value: AppThemeMode.light,
                      title: Text(tr(context,
                          ko: "라이트 모드", en: "Light mode", es: "Modo claro")),
                    ),
                  ],
                ),
              ),
              const Divider(height: 24),
              Text(tr(context, ko: "폰트 설정", en: "Font Settings", es: "Fuentes"),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              DropdownButtonFormField<AppMainFont>(
                initialValue: themeController.mainFont,
                decoration: InputDecoration(
                  labelText: tr(context,
                      ko: "메인 폰트", en: "Main font", es: "Fuente principal"),
                  border: const OutlineInputBorder(),
                ),
                items: AppMainFont.values
                    .map(
                      (AppMainFont item) => DropdownMenuItem<AppMainFont>(
                        value: item,
                        child: Text(_mainFontLabel(context, item)),
                      ),
                    )
                    .toList(),
                onChanged: (AppMainFont? value) {
                  if (value != null) {
                    themeController.setMainFont(value);
                  }
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<AppHighlightFont>(
                initialValue: themeController.highlightFont,
                decoration: InputDecoration(
                  labelText: tr(context,
                      ko: "하이라이트 폰트",
                      en: "Highlight font",
                      es: "Fuente destacada"),
                  border: const OutlineInputBorder(),
                ),
                items: AppHighlightFont.values
                    .map(
                      (AppHighlightFont item) =>
                          DropdownMenuItem<AppHighlightFont>(
                        value: item,
                        child: Text(_highlightFontLabel(context, item)),
                      ),
                    )
                    .toList(),
                onChanged: (AppHighlightFont? value) {
                  if (value != null) {
                    themeController.setHighlightFont(value);
                  }
                },
              ),
              const Divider(height: 24),
              Text(
                  tr(context, ko: "색상 설정", en: "Color Settings", es: "Colores"),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AppAccentTone.values
                    .map(
                      (AppAccentTone tone) => ChoiceChip(
                        selected: themeController.accentTone == tone,
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                  color: _toneColor(tone),
                                  shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 6),
                            Text(_toneLabel(context, tone)),
                          ],
                        ),
                        onSelected: (_) => themeController.setAccentTone(tone),
                      ),
                    )
                    .toList(),
              ),
              const Divider(height: 24),
              Text(
                  tr(context,
                      ko: "하단 메뉴 표시",
                      en: "Bottom Menu Visibility",
                      es: "Menu inferior"),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                tr(context,
                    ko: "홈은 고정입니다. 나머지 메뉴를 켜고 끌 수 있습니다.",
                    en: "Home is fixed. Toggle the other menus.",
                    es: "Inicio es fijo. Active o desactive otros menus."),
                style: TextStyle(color: color.onSurfaceVariant),
              ),
              ...AppBottomMenu.values.map(
                (AppBottomMenu menu) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: themeController.isBottomMenuEnabled(menu),
                  title: Text(_bottomMenuLabel(context, menu)),
                  onChanged: (bool value) {
                    themeController.setBottomMenuEnabled(menu, value);
                  },
                ),
              ),
              const Divider(height: 24),
              Text(
                  tr(context,
                      ko: "구글 계정 로그인",
                      en: "Google Account Login",
                      es: "Cuenta de Google"),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(accountName,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(accountEmail),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: isGoogleLoggedIn ? null : onGoogleLogin,
                            icon: const Icon(Icons.login),
                            label: Text(tr(context,
                                ko: "로그인", en: "Login", es: "Entrar")),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: isGoogleLoggedIn ? onGoogleLogout : null,
                            icon: const Icon(Icons.logout),
                            label: Text(tr(context,
                                ko: "로그아웃", en: "Logout", es: "Salir")),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.support_agent_outlined),
                title: Text(tr(context,
                    ko: "고객센터", en: "Customer Center", es: "Centro de ayuda")),
                subtitle: Text(tr(context,
                    ko: "문의 및 FAQ",
                    en: "Support and FAQ",
                    es: "Soporte y FAQ")),
                onTap: () => _showCustomerCenter(context),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.privacy_tip_outlined),
                title: Text(tr(context,
                    ko: "개인정보 수집 약관 안내",
                    en: "Privacy Terms",
                    es: "Privacidad")),
                subtitle: Text(tr(context,
                    ko: "수집 항목 및 이용 목적",
                    en: "Data collection and terms",
                    es: "Recopilacion de datos y terminos")),
                onTap: () => _showPrivacyTerms(context),
              ),
            ],
          );
        },
      ),
    );
  }
}
