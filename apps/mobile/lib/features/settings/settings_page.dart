import "package:flutter/material.dart";

import "../../core/i18n/app_i18n.dart";
import "../../core/theme/app_theme_controller.dart";
import "home_tile_settings_page.dart";

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.themeController,
    required this.isGoogleLoggedIn,
    required this.accountName,
    required this.accountEmail,
    required this.onGoogleLogin,
    required this.onGoogleLogout,
    required this.onManageChildProfile,
  });

  final AppThemeController themeController;
  final bool isGoogleLoggedIn;
  final String accountName;
  final String accountEmail;
  final Future<void> Function() onGoogleLogin;
  final VoidCallback onGoogleLogout;
  final Future<void> Function() onManageChildProfile;

  Future<void> _selectTheme(AppThemeMode mode) async {
    await themeController.setMode(mode);
  }

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

  Widget _settingsDropdown<T>({
    required BuildContext context,
    required T initialValue,
    required String label,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return _boundedControl(
      DropdownButtonFormField<T>(
        initialValue: initialValue,
        isExpanded: true,
        menuMaxHeight: 320,
        borderRadius: BorderRadius.circular(14),
        icon: const Icon(Icons.expand_more_rounded, size: 20),
        decoration: _dropdownDecoration(context, label),
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  String _mainFontLabel(BuildContext context, AppMainFont font) {
    switch (font) {
      case AppMainFont.notoSans:
        return "Noto Sans";
      case AppMainFont.systemSans:
        return tr(
          context,
          ko: "시스템 산세리프",
          en: "System Sans",
          es: "Sans del sistema",
        );
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
          title: Text(
            tr(context,
                ko: "고객센터", en: "Customer Center", es: "Centro de ayuda"),
          ),
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

  String _privacyTermsBody(BuildContext context) {
    return tr(
      context,
      ko: """
BabyAI 개인정보 수집 및 이용 안내

1. 수집 항목
- 계정 정보: 로그인 식별자, 이름, 이메일
- 아이 프로필: 이름, 성별, 생년월일, 체중, 수유 방식, 분유 정보
- 기록 데이터: 수면, 수유, 기저귀, 투약, 메모, 통계
- 미디어: 사진 업로드 파일/메타데이터, 음성 입력(텍스트 변환 포함)
- 서비스 설정: 테마, 폰트, 색상, 하단 메뉴 표시, 언어

2. 이용 목적
- 기록 저장/조회 및 통계 시각화
- AI 답변에 프로필/기록 반영(사용자가 허용한 범위)
- 사진 공유/앨범 구성, 커뮤니티/장터 기능 제공(사용 시)
- 고객센터 문의 대응 및 서비스 품질 개선

3. 보관 및 삭제
- 데이터는 서비스 제공 기간 동안 보관됩니다.
- 계정 삭제 또는 이용자 요청 시 관련 법령 범위 내에서 삭제/익명화 처리됩니다.
- 데이터 내보내기/삭제 요청은 고객센터로 접수할 수 있습니다.

4. 제3자 제공 및 처리위탁
- 기본적으로 판매하지 않습니다.
- 클라우드 저장, 인증, 분석 등 서비스 운영에 필요한 범위에서 처리위탁될 수 있습니다.

5. 이용자 권리
- 열람, 정정, 삭제, 처리정지 요청 가능
- 동의 철회 가능(철회 시 일부 기능 제한 가능)

6. 동의
- [동의] 버튼을 누르면 본 안내를 읽고 동의한 것으로 처리됩니다.
""",
      en: """
BabyAI Privacy Collection and Use Notice

1. Data collected
- Account: login identifier, name, email
- Baby profile: name, sex, birth date, weight, feeding method, formula data
- Records: sleep, feeding, diaper, medication, notes, statistics
- Media: uploaded photos/metadata, voice input (including transcript)
- Settings: theme, fonts, color tone, bottom menu visibility, language

2. Purposes
- Store/retrieve records and provide analytics views
- Reflect profile/records in AI responses (within user-authorized scope)
- Provide photo sharing/albums and optional community/market features
- Handle support requests and improve service quality

3. Retention and deletion
- Data is retained while the service is in use.
- Upon account deletion or user request, deletion/anonymization is processed within legal requirements.
- Export/deletion requests can be made via support.

4. Third-party processing
- Data is not sold.
- Processing may be delegated to required providers for storage, auth, and operations.

5. User rights
- Access, correction, deletion, and restriction requests are supported.
- Consent can be withdrawn (some features may be limited).

6. Consent
- Pressing [Agree] records your acceptance of this notice.
""",
      es: """
Aviso de recopilacion y uso de privacidad de BabyAI

1. Datos recopilados
- Cuenta: identificador de inicio de sesion, nombre, correo
- Perfil del bebe: nombre, sexo, fecha de nacimiento, peso, metodo de alimentacion, datos de formula
- Registros: sueno, alimentacion, panal, medicacion, notas, estadisticas
- Medios: fotos cargadas/metadatos, entrada de voz (incluida transcripcion)
- Configuracion: tema, fuentes, color, visibilidad del menu inferior, idioma

2. Finalidades
- Guardar/consultar registros y mostrar analitica
- Reflejar perfil/registros en respuestas de IA (segun autorizacion del usuario)
- Proveer funciones de fotos/albums y opciones de comunidad/mercado
- Atender soporte y mejorar la calidad del servicio

3. Conservacion y eliminacion
- Los datos se conservan durante el uso del servicio.
- Tras eliminar la cuenta o por solicitud, se elimina/anonimiza dentro del marco legal.
- Solicitudes de exportacion/eliminacion via soporte.

4. Procesamiento por terceros
- No se venden datos.
- Puede haber encargados para almacenamiento, autenticacion y operacion.

5. Derechos del usuario
- Solicitudes de acceso, correccion, eliminacion y limitacion.
- Puede retirar el consentimiento (algunas funciones pueden limitarse).

6. Consentimiento
- Al pulsar [Aceptar], se registra su consentimiento.
""",
    );
  }

  Future<void> _showPrivacyTerms(BuildContext context) async {
    final bool? agreed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            tr(
              context,
              ko: "개인정보 수집 약관 안내",
              en: "Privacy Terms",
              es: "Terminos de privacidad",
            ),
          ),
          content: SizedBox(
            width: 520,
            height: 360,
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                child: Text(
                  _privacyTermsBody(context),
                  style: const TextStyle(height: 1.45),
                ),
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr(context, ko: "닫기", en: "Close", es: "Cerrar")),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(tr(context, ko: "동의", en: "Agree", es: "Aceptar")),
            ),
          ],
        );
      },
    );

    if (agreed != true || !context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(
            context,
            ko: "약관 동의가 처리되었습니다.",
            en: "Privacy terms agreement was recorded.",
            es: "Se registro la aceptacion de privacidad.",
          ),
        ),
      ),
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
              _settingsDropdown<AppLanguage>(
                context: context,
                initialValue: themeController.language,
                label: tr(
                  context,
                  ko: "앱 언어",
                  en: "App language",
                  es: "Idioma de la app",
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
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
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
              _settingsDropdown<AppMainFont>(
                context: context,
                initialValue: themeController.mainFont,
                label: tr(context,
                    ko: "메인 폰트", en: "Main font", es: "Fuente principal"),
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
              _settingsDropdown<AppHighlightFont>(
                context: context,
                initialValue: themeController.highlightFont,
                label: tr(context,
                    ko: "하이라이트 폰트",
                    en: "Highlight font",
                    es: "Fuente destacada"),
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.dashboard_customize_outlined),
                title: Text(tr(context,
                    ko: "홈 타일 관리", en: "Home Tiles", es: "Tiles de inicio")),
                subtitle: Text(tr(context,
                    ko: "홈 화면 타일을 추가/삭제하고 유형별 기본 세트를 적용합니다.",
                    en: "Add/remove home tiles and apply profile defaults.",
                    es: "Agrega/elimina tiles y aplica valores por perfil.")),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) => HomeTileSettingsPage(
                          themeController: themeController),
                    ),
                  );
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.sticky_note_2_outlined),
                value: themeController.showSpecialMemo,
                title: Text(tr(context,
                    ko: "특별 메모 표시",
                    en: "Show special memo",
                    es: "Mostrar nota especial")),
                subtitle: Text(tr(context,
                    ko: "홈 상단 특별 메모 카드 표시 여부",
                    en: "Show or hide the special memo card on Home.",
                    es: "Mostrar u ocultar la tarjeta de nota especial en Inicio.")),
                onChanged: (bool value) {
                  themeController.setShowSpecialMemo(value);
                },
              ),
              const Divider(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.child_care_outlined),
                title: Text(tr(context,
                    ko: "아이 등록/수정",
                    en: "Child Registration",
                    es: "Registro del bebe")),
                subtitle: Text(tr(context,
                    ko: "아이 프로필, 수유 방식, 분유 정보를 입력합니다.",
                    en: "Manage profile, feeding method, and formula type.",
                    es: "Gestiona perfil, metodo de alimentacion y formula.")),
                onTap: () => onManageChildProfile(),
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
