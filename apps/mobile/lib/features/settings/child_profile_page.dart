import "package:flutter/material.dart";

import "../../core/i18n/app_i18n.dart";
import "../../core/network/babyai_api.dart";
import "../../core/theme/app_theme_controller.dart";

enum _ConsentType { terms, privacy, data }

class ChildProfileSaveResult {
  const ChildProfileSaveResult(
      {required this.babyId, required this.householdId});

  final String babyId;
  final String householdId;
}

class ChildProfilePage extends StatefulWidget {
  const ChildProfilePage({
    super.key,
    required this.initialOnboarding,
    required this.onCompleted,
  });

  final bool initialOnboarding;
  final Future<void> Function(ChildProfileSaveResult result) onCompleted;

  @override
  State<ChildProfilePage> createState() => _ChildProfilePageState();
}

class _ChildProfilePageState extends State<ChildProfilePage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _birthController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _formulaBrandController = TextEditingController();
  final TextEditingController _formulaProductController =
      TextEditingController();

  bool _loading = false;
  String? _error;
  int _step = 0;

  String _sex = "unknown";
  String _feedingMethod = "mixed";
  String _formulaType = "standard";
  bool _formulaContainsStarch = false;
  ChildCareProfile _careProfile = ChildCareProfile.formula;

  bool _consentTerms = false;
  bool _consentPrivacy = false;
  bool _consentData = false;

  @override
  void initState() {
    super.initState();
    if (!widget.initialOnboarding && BabyAIApi.activeBabyId.isNotEmpty) {
      _loadExistingProfile();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final AppThemeController? controller = AppSettingsScope.maybeOf(context);
    if (controller != null) {
      _careProfile = controller.childCareProfile;
      _syncFeedingByProfile(fromUserChange: false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _birthController.dispose();
    _weightController.dispose();
    _formulaBrandController.dispose();
    _formulaProductController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final Map<String, dynamic> profile =
          await BabyAIApi.instance.getBabyProfile();
      _nameController.text = (profile["baby_name"] ?? "").toString();
      _birthController.text = (profile["birth_date"] ?? "").toString();
      final Object? weight = profile["weight_kg"];
      if (weight is num) {
        _weightController.text = weight.toString();
      }
      _sex = (profile["sex"] ?? "unknown").toString();
      _feedingMethod = (profile["feeding_method"] ?? "mixed").toString();
      _formulaType = (profile["formula_type"] ?? "standard").toString();
      _formulaBrandController.text =
          (profile["formula_brand"] ?? "").toString();
      _formulaProductController.text =
          (profile["formula_product"] ?? "").toString();
      final Object? starch = profile["formula_contains_starch"];
      if (starch is bool) {
        _formulaContainsStarch = starch;
      }
      if (_feedingMethod == "breastmilk") {
        _careProfile = ChildCareProfile.breastfeeding;
      } else if (_feedingMethod == "formula") {
        _careProfile = ChildCareProfile.formula;
      } else {
        _careProfile = ChildCareProfile.weaning;
      }
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _syncFeedingByProfile({required bool fromUserChange}) {
    if (!fromUserChange) {
      return;
    }
    switch (_careProfile) {
      case ChildCareProfile.breastfeeding:
        _feedingMethod = "breastmilk";
        return;
      case ChildCareProfile.formula:
        _feedingMethod = "formula";
        return;
      case ChildCareProfile.weaning:
        _feedingMethod = "mixed";
        return;
    }
  }

  String _sexLabel(String value) {
    switch (value) {
      case "female":
        return tr(context, ko: "여아", en: "Female", es: "Nina");
      case "male":
        return tr(context, ko: "남아", en: "Male", es: "Nino");
      case "other":
        return tr(context, ko: "기타", en: "Other", es: "Otro");
      default:
        return tr(context, ko: "미지정", en: "Unknown", es: "Desconocido");
    }
  }

  String _profileLabel(ChildCareProfile value) {
    switch (value) {
      case ChildCareProfile.breastfeeding:
        return tr(context,
            ko: "모유수유 산모", en: "Breastfeeding parent", es: "Madre lactante");
      case ChildCareProfile.formula:
        return tr(context,
            ko: "분유 수유 산모", en: "Formula parent", es: "Madre con formula");
      case ChildCareProfile.weaning:
        return tr(context,
            ko: "이유식 부모", en: "Weaning parent", es: "Padre de destete");
    }
  }

  String _feedingLabel(String value) {
    switch (value) {
      case "formula":
        return tr(context, ko: "분유", en: "Formula", es: "Formula");
      case "breastmilk":
        return tr(context, ko: "모유", en: "Breastmilk", es: "Lactancia");
      default:
        return tr(context, ko: "혼합", en: "Mixed", es: "Mixto");
    }
  }

  String _formulaTypeLabel(String value) {
    switch (value) {
      case "hydrolyzed":
        return tr(context, ko: "가수분해", en: "Hydrolyzed", es: "Hidrolizada");
      case "thickened":
        return tr(context,
            ko: "농후/AR", en: "Thickened (AR)", es: "Espesada (AR)");
      case "soy":
        return tr(context, ko: "대두", en: "Soy", es: "Soja");
      case "goat":
        return tr(context, ko: "산양", en: "Goat", es: "Cabra");
      case "specialty":
        return tr(context, ko: "특수", en: "Specialty", es: "Especial");
      default:
        return tr(context, ko: "일반", en: "Standard", es: "Estandar");
    }
  }

  Widget _boundedControl(
    Widget child, {
    double maxWidth = 540,
  }) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }

  InputDecoration _dropdownDecoration(String label) {
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

  Widget _profileDropdown<T>({
    required T initialValue,
    required String label,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    double maxWidth = 540,
    bool isExpanded = true,
  }) {
    return _boundedControl(
      DropdownButtonFormField<T>(
        initialValue: initialValue,
        isExpanded: isExpanded,
        menuMaxHeight: 320,
        borderRadius: BorderRadius.circular(14),
        icon: const Icon(Icons.expand_more_rounded, size: 20),
        decoration: _dropdownDecoration(label),
        items: items,
        onChanged: onChanged,
      ),
      maxWidth: maxWidth,
    );
  }

  bool _consentValue(_ConsentType type) {
    switch (type) {
      case _ConsentType.terms:
        return _consentTerms;
      case _ConsentType.privacy:
        return _consentPrivacy;
      case _ConsentType.data:
        return _consentData;
    }
  }

  void _setConsentValue(_ConsentType type, bool value) {
    switch (type) {
      case _ConsentType.terms:
        _consentTerms = value;
        return;
      case _ConsentType.privacy:
        _consentPrivacy = value;
        return;
      case _ConsentType.data:
        _consentData = value;
        return;
    }
  }

  String _consentTitle(_ConsentType type) {
    switch (type) {
      case _ConsentType.terms:
        return tr(context, ko: "이용약관", en: "Terms of Service", es: "Terminos");
      case _ConsentType.privacy:
        return tr(context,
            ko: "개인정보 수집 동의", en: "Privacy Consent", es: "Privacidad");
      case _ConsentType.data:
        return tr(context, ko: "데이터 처리 동의", en: "Data Consent", es: "Datos");
    }
  }

  String _consentBody(_ConsentType type) {
    switch (type) {
      case _ConsentType.terms:
        return tr(context,
            ko: "서비스 제공 목적, 이용자 책임, 제한 및 면책에 대한 동의입니다.",
            en: "Consent for service purpose, user responsibility, and limitation.",
            es: "Consentimiento sobre objetivo, responsabilidad y limitacion.");
      case _ConsentType.privacy:
        return tr(context,
            ko: "계정/아이 프로필/기록/사진 메타데이터 수집 및 이용 동의입니다.",
            en: "Consent for collecting and using account/profile/record/photo metadata.",
            es: "Consentimiento para recopilar y usar datos de cuenta/perfil/registros/fotos.");
      case _ConsentType.data:
        return tr(context,
            ko: "수유 방식과 기록 분석을 통한 추천 생성 동의입니다.",
            en: "Consent for recommendation generation from feeding profile and records.",
            es: "Consentimiento para recomendaciones con perfil y registros.");
    }
  }

  Future<void> _openConsentDialog(_ConsentType type) async {
    final bool? agreed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(_consentTitle(type)),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(child: Text(_consentBody(type))),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(tr(context, ko: "닫기", en: "Close", es: "Cerrar")),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(tr(context, ko: "동의", en: "Agree", es: "Aceptar")),
            ),
          ],
        );
      },
    );

    if (!mounted) {
      return;
    }
    if (agreed == true) {
      setState(() => _setConsentValue(type, true));
    }
  }

  List<String> _consents() {
    final List<String> values = <String>[];
    if (_consentTerms) {
      values.add("terms");
    }
    if (_consentPrivacy) {
      values.add("privacy");
    }
    if (_consentData) {
      values.add("data_processing");
    }
    return values;
  }

  bool _validateForCurrentStep() {
    if (_step == 0) {
      return _formKey.currentState?.validate() ?? false;
    }
    if (_step == 2) {
      if (_consents().length < 3) {
        _error = tr(context,
            ko: "필수 약관 3개에 모두 동의해야 합니다.",
            en: "All 3 required consents must be accepted.",
            es: "Debe aceptar 3 consentimientos.");
        return false;
      }
    }
    return true;
  }

  Future<void> _submit() async {
    if (_loading || !_validateForCurrentStep()) {
      setState(() {});
      return;
    }
    final AppThemeController? settingsController =
        AppSettingsScope.maybeOf(context);

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final double? weight =
          double.tryParse(_weightController.text.trim().replaceAll(",", "."));
      final bool includeFormulaInputs = _feedingMethod != "breastmilk";
      final String formulaBrand =
          includeFormulaInputs ? _formulaBrandController.text.trim() : "";
      final String formulaProduct =
          includeFormulaInputs ? _formulaProductController.text.trim() : "";
      final String formulaType = includeFormulaInputs ? _formulaType : "";
      final bool formulaContainsStarch =
          includeFormulaInputs ? _formulaContainsStarch : false;

      if (widget.initialOnboarding || BabyAIApi.activeBabyId.isEmpty) {
        final Map<String, dynamic> created =
            await BabyAIApi.instance.createOfflineOnboarding(
          babyName: _nameController.text.trim(),
          babyBirthDate: _birthController.text.trim(),
          babySex: _sex,
          babyWeightKg: weight,
          feedingMethod: _feedingMethod,
          formulaBrand: formulaBrand,
          formulaProduct: formulaProduct,
          formulaType: formulaType,
          formulaContainsStarch: formulaContainsStarch,
        );

        final String babyId = (created["baby_id"] ?? "").toString();
        final String householdId = (created["household_id"] ?? "").toString();
        if (babyId.isEmpty || householdId.isEmpty) {
          throw ApiFailure("Failed to create baby profile.");
        }

        BabyAIApi.setRuntimeIds(babyId: babyId, householdId: householdId);
        await BabyAIApi.instance.upsertBabyProfile(
          babyName: _nameController.text.trim(),
          babyBirthDate: _birthController.text.trim(),
          babySex: _sex,
          babyWeightKg: weight,
          feedingMethod: _feedingMethod,
          formulaBrand: formulaBrand,
          formulaProduct: formulaProduct,
          formulaType: formulaType,
          formulaContainsStarch: formulaContainsStarch,
        );

        bool syncedOnline = false;
        if (BabyAIApi.isGoogleLinked) {
          try {
            final Map<String, dynamic> remote =
                await BabyAIApi.instance.onboardingParent(
              provider: "google",
              babyName: _nameController.text.trim(),
              babyBirthDate: _birthController.text.trim(),
              babySex: _sex,
              babyWeightKg: weight,
              feedingMethod: _feedingMethod,
              formulaBrand: formulaBrand,
              formulaProduct: formulaProduct,
              formulaType: formulaType,
              formulaContainsStarch: formulaContainsStarch,
              requiredConsents: _consents(),
            );
            final String remoteBabyId = (remote["baby_id"] ?? "").toString();
            final String remoteHouseholdId =
                (remote["household_id"] ?? "").toString();
            if (remoteBabyId.isNotEmpty && remoteHouseholdId.isNotEmpty) {
              BabyAIApi.setRuntimeIds(
                babyId: remoteBabyId,
                householdId: remoteHouseholdId,
              );
              await BabyAIApi.instance.upsertBabyProfile(
                babyName: _nameController.text.trim(),
                babyBirthDate: _birthController.text.trim(),
                babySex: _sex,
                babyWeightKg: weight,
                feedingMethod: _feedingMethod,
                formulaBrand: formulaBrand,
                formulaProduct: formulaProduct,
                formulaType: formulaType,
                formulaContainsStarch: formulaContainsStarch,
              );
              syncedOnline = true;
            }
          } catch (_) {
            syncedOnline = false;
          }
        }

        if (settingsController != null) {
          await settingsController.setChildCareProfile(_careProfile,
              applyDefaultTiles: true);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                syncedOnline
                    ? tr(
                        context,
                        ko: "로컬 저장 후 온라인 동기화를 완료했습니다.",
                        en: "Saved locally and synced online.",
                        es: "Guardado local y sincronizado en linea.",
                      )
                    : tr(
                        context,
                        ko: "로컬 저장으로 시작합니다. Google 로그인 시 온라인 동기화가 켜집니다.",
                        en: "Starting with local storage. Online sync starts after Google login.",
                        es: "Inicio con guardado local. La sincronizacion en linea se activa tras Google login.",
                      ),
              ),
            ),
          );
        }

        await widget.onCompleted(
          ChildProfileSaveResult(
            babyId: BabyAIApi.activeBabyId,
            householdId: BabyAIApi.activeHouseholdId,
          ),
        );
      } else {
        await BabyAIApi.instance.upsertBabyProfile(
          babyName: _nameController.text.trim(),
          babyBirthDate: _birthController.text.trim(),
          babySex: _sex,
          babyWeightKg: weight,
          feedingMethod: _feedingMethod,
          formulaBrand: formulaBrand,
          formulaProduct: formulaProduct,
          formulaType: formulaType,
          formulaContainsStarch: formulaContainsStarch,
        );
        if (settingsController != null) {
          await settingsController.setChildCareProfile(_careProfile,
              applyDefaultTiles: false);
        }
        await widget.onCompleted(ChildProfileSaveResult(
          babyId: BabyAIApi.activeBabyId,
          householdId: BabyAIApi.activeHouseholdId,
        ));
      }

      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Widget _consentTile(_ConsentType type) {
    final bool selected = _consentValue(type);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Checkbox(
            value: selected,
            onChanged: (bool? value) async {
              if (value == true) {
                await _openConsentDialog(type);
              } else {
                setState(() => _setConsentValue(type, false));
              }
            },
          ),
          Expanded(
            child: ListTile(
              dense: true,
              title: Text(_consentTitle(type),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(_consentLabel(type)),
              onTap: () => _openConsentDialog(type),
            ),
          ),
        ],
      ),
    );
  }

  String _consentLabel(_ConsentType type) {
    switch (type) {
      case _ConsentType.terms:
        return tr(context,
            ko: "이용약관 동의 (필수)",
            en: "Terms consent (required)",
            es: "Terminos (obligatorio)");
      case _ConsentType.privacy:
        return tr(context,
            ko: "개인정보 수집 동의 (필수)",
            en: "Privacy consent (required)",
            es: "Privacidad (obligatorio)");
      case _ConsentType.data:
        return tr(context,
            ko: "데이터 처리 동의 (필수)",
            en: "Data consent (required)",
            es: "Datos (obligatorio)");
    }
  }

  Widget _stepHeader() {
    final List<String> labels = <String>[
      tr(context, ko: "기본 정보", en: "Basic", es: "Basico"),
      tr(context, ko: "아이 유형", en: "Type", es: "Tipo"),
      tr(context, ko: "약관 동의", en: "Consent", es: "Consent"),
    ];
    return Row(
      children: List<Widget>.generate(labels.length, (int i) {
        final bool selected = i == _step;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == labels.length - 1 ? 0 : 8),
            child: Container(
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(labels[i],
                  style: TextStyle(
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500)),
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool initial = widget.initialOnboarding;
    final bool showFormulaInputs = _feedingMethod != "breastmilk";
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !initial,
        title: Text(
            tr(context, ko: "아이 등록", en: "Child Registration", es: "Registro")),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: <Widget>[
            if (initial) ...<Widget>[
              Text(tr(context,
                  ko: "초기 설문을 완료하면 유형별 홈 타일이 자동 구성됩니다.",
                  en: "Complete onboarding survey to auto-configure home tiles.",
                  es: "Complete la encuesta para configurar tiles.")),
              const SizedBox(height: 10),
              _stepHeader(),
              const SizedBox(height: 12),
            ],
            if (!initial || _step == 0) ...<Widget>[
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                    labelText:
                        tr(context, ko: "아이 이름", en: "Baby name", es: "Nombre"),
                    border: const OutlineInputBorder()),
                validator: (String? value) =>
                    (value == null || value.trim().isEmpty)
                        ? tr(context,
                            ko: "아이 이름을 입력해 주세요.",
                            en: "Enter baby name.",
                            es: "Ingrese nombre.")
                        : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _birthController,
                decoration: InputDecoration(
                    labelText: tr(context,
                        ko: "생년월일 (YYYY-MM-DD)", en: "Birth date", es: "Fecha"),
                    border: const OutlineInputBorder()),
                validator: (String? value) {
                  final String raw = (value ?? "").trim();
                  if (raw.isEmpty) {
                    return tr(context,
                        ko: "생년월일을 입력해 주세요.",
                        en: "Enter birth date.",
                        es: "Ingrese fecha.");
                  }
                  if (!RegExp(r"^\d{4}-\d{2}-\d{2}$").hasMatch(raw)) {
                    return tr(context,
                        ko: "YYYY-MM-DD 형식으로 입력해 주세요.",
                        en: "Use YYYY-MM-DD.",
                        es: "Use YYYY-MM-DD.");
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
              _profileDropdown<String>(
                initialValue: _sex,
                label: tr(context, ko: "성별", en: "Sex", es: "Sexo"),
                items: <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                      value: "unknown", child: Text(_sexLabel("unknown"))),
                  DropdownMenuItem(
                      value: "female", child: Text(_sexLabel("female"))),
                  DropdownMenuItem(
                      value: "male", child: Text(_sexLabel("male"))),
                  DropdownMenuItem(
                      value: "other", child: Text(_sexLabel("other"))),
                ],
                onChanged: (String? value) =>
                    setState(() => _sex = value ?? "unknown"),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _weightController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: tr(context,
                        ko: "체중 (kg)", en: "Weight (kg)", es: "Peso (kg)"),
                    border: const OutlineInputBorder()),
              ),
            ],
            if (!initial || _step == 1) ...<Widget>[
              _profileDropdown<ChildCareProfile>(
                initialValue: _careProfile,
                label: tr(context,
                    ko: "아이 유형 설문",
                    en: "Child type survey",
                    es: "Encuesta de tipo"),
                items: ChildCareProfile.values
                    .map((ChildCareProfile item) =>
                        DropdownMenuItem<ChildCareProfile>(
                            value: item, child: Text(_profileLabel(item))))
                    .toList(),
                onChanged: (ChildCareProfile? value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _careProfile = value;
                    _syncFeedingByProfile(fromUserChange: true);
                  });
                },
              ),
              const SizedBox(height: 10),
              _profileDropdown<String>(
                initialValue: _feedingMethod,
                label: tr(context,
                    ko: "수유 방식", en: "Feeding method", es: "Metodo"),
                items: <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                      value: "mixed", child: Text(_feedingLabel("mixed"))),
                  DropdownMenuItem(
                      value: "formula", child: Text(_feedingLabel("formula"))),
                  DropdownMenuItem(
                      value: "breastmilk",
                      child: Text(_feedingLabel("breastmilk"))),
                ],
                onChanged: (String? value) =>
                    setState(() => _feedingMethod = value ?? "mixed"),
              ),
              if (showFormulaInputs) ...<Widget>[
                const SizedBox(height: 10),
                _profileDropdown<String>(
                  initialValue: _formulaType,
                  label:
                      tr(context, ko: "분유 타입", en: "Formula type", es: "Tipo"),
                  items: <String>[
                    "standard",
                    "hydrolyzed",
                    "thickened",
                    "soy",
                    "goat",
                    "specialty"
                  ]
                      .map((String value) => DropdownMenuItem<String>(
                          value: value, child: Text(_formulaTypeLabel(value))))
                      .toList(),
                  onChanged: (String? value) =>
                      setState(() => _formulaType = value ?? "standard"),
                ),
                const SizedBox(height: 10),
                TextFormField(
                    controller: _formulaBrandController,
                    decoration: InputDecoration(
                        labelText: tr(context,
                            ko: "분유 브랜드", en: "Formula brand", es: "Marca"),
                        border: const OutlineInputBorder())),
                const SizedBox(height: 10),
                TextFormField(
                    controller: _formulaProductController,
                    decoration: InputDecoration(
                        labelText: tr(context,
                            ko: "분유 제품명",
                            en: "Formula product",
                            es: "Producto"),
                        border: const OutlineInputBorder())),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _formulaContainsStarch,
                  title: Text(tr(context,
                      ko: "전분(농후제) 함유",
                      en: "Contains starch",
                      es: "Contiene almidon")),
                  onChanged: (bool value) =>
                      setState(() => _formulaContainsStarch = value),
                ),
              ],
            ],
            if (!initial || _step == 2) ...<Widget>[
              _consentTile(_ConsentType.terms),
              _consentTile(_ConsentType.privacy),
              _consentTile(_ConsentType.data),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600))
            ],
            const SizedBox(height: 12),
            if (initial)
              Row(
                children: <Widget>[
                  Expanded(
                      child: OutlinedButton.icon(
                          onPressed: _loading || _step == 0
                              ? null
                              : () => setState(() => _step -= 1),
                          icon: const Icon(Icons.arrow_back),
                          label: Text(
                              tr(context, ko: "이전", en: "Back", es: "Atras")))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _step < 2
                        ? FilledButton.icon(
                            onPressed: _loading
                                ? null
                                : () {
                                    if (_validateForCurrentStep()) {
                                      setState(() {
                                        _error = null;
                                        _step += 1;
                                      });
                                    } else {
                                      setState(() {});
                                    }
                                  },
                            icon: const Icon(Icons.arrow_forward),
                            label: Text(tr(context,
                                ko: "다음", en: "Next", es: "Siguiente")))
                        : FilledButton.icon(
                            onPressed: _loading ? null : _submit,
                            icon: const Icon(Icons.check_circle_outline),
                            label: Text(tr(context,
                                ko: "등록 후 시작",
                                en: "Save & Start",
                                es: "Guardar"))),
                  ),
                ],
              )
            else
              FilledButton.icon(
                  onPressed: _loading ? null : _submit,
                  icon: const Icon(Icons.save_outlined),
                  label:
                      Text(tr(context, ko: "저장", en: "Save", es: "Guardar"))),
            if (_loading) ...<Widget>[
              const SizedBox(height: 8),
              const LinearProgressIndicator()
            ],
          ],
        ),
      ),
    );
  }
}
