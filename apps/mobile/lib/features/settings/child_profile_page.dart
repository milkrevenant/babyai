import "package:flutter/material.dart";

import "../../core/i18n/app_i18n.dart";
import "../../core/network/babyai_api.dart";

enum _OnboardingConsentType {
  terms,
  privacy,
  dataProcessing,
}

class ChildProfileSaveResult {
  const ChildProfileSaveResult({
    required this.babyId,
    required this.householdId,
  });

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
  final TextEditingController _birthDateController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _formulaBrandController = TextEditingController();
  final TextEditingController _formulaProductController =
      TextEditingController();
  final TextEditingController _tokenController = TextEditingController();

  bool _loading = false;
  String? _error;

  String _sex = "unknown";
  String _feedingMethod = "mixed";
  String _formulaType = "standard";
  bool _formulaContainsStarch = false;

  bool _consentTerms = false;
  bool _consentPrivacy = false;
  bool _consentData = false;

  String _sexLabel(String sex) {
    switch (sex) {
      case "female":
        return tr(context, ko: "여아", en: "Female", es: "Nina");
      case "male":
        return tr(context, ko: "남아", en: "Male", es: "Nino");
      case "other":
        return tr(context, ko: "기타", en: "Other", es: "Otro");
      case "unknown":
      default:
        return tr(context, ko: "미지정", en: "Unknown", es: "Desconocido");
    }
  }

  String _feedingMethodLabel(String method) {
    switch (method) {
      case "formula":
        return tr(context, ko: "분유", en: "Formula", es: "Formula");
      case "breastmilk":
        return tr(context, ko: "모유", en: "Breastmilk", es: "Lactancia");
      case "mixed":
      default:
        return tr(context, ko: "혼합", en: "Mixed", es: "Mixto");
    }
  }

  String _formulaTypeLabel(String type) {
    switch (type) {
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
      case "standard":
      default:
        return tr(context, ko: "일반", en: "Standard", es: "Estandar");
    }
  }

  @override
  void initState() {
    super.initState();
    if (!widget.initialOnboarding && BabyAIApi.activeBabyId.isNotEmpty) {
      _loadExistingProfile();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _birthDateController.dispose();
    _weightController.dispose();
    _formulaBrandController.dispose();
    _formulaProductController.dispose();
    _tokenController.dispose();
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
      _birthDateController.text = (profile["birth_date"] ?? "").toString();
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
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  bool _consentValue(_OnboardingConsentType type) {
    switch (type) {
      case _OnboardingConsentType.terms:
        return _consentTerms;
      case _OnboardingConsentType.privacy:
        return _consentPrivacy;
      case _OnboardingConsentType.dataProcessing:
        return _consentData;
    }
  }

  void _setConsentValue(_OnboardingConsentType type, bool value) {
    if (type == _OnboardingConsentType.terms) {
      _consentTerms = value;
      return;
    }
    if (type == _OnboardingConsentType.privacy) {
      _consentPrivacy = value;
      return;
    }
    _consentData = value;
  }

  String _consentDialogTitle(_OnboardingConsentType type) {
    switch (type) {
      case _OnboardingConsentType.terms:
        return tr(
          context,
          ko: "이용약관",
          en: "Terms of Service",
          es: "Terminos de servicio",
        );
      case _OnboardingConsentType.privacy:
        return tr(
          context,
          ko: "개인정보 수집 안내",
          en: "Privacy Terms",
          es: "Terminos de privacidad",
        );
      case _OnboardingConsentType.dataProcessing:
        return tr(
          context,
          ko: "데이터 처리 동의",
          en: "Data Processing Terms",
          es: "Terminos de procesamiento de datos",
        );
    }
  }

  String _consentDialogBody(_OnboardingConsentType type) {
    switch (type) {
      case _OnboardingConsentType.terms:
        return tr(
          context,
          ko: """
1. 서비스 목적
- BabyAI는 육아 기록 관리, 사진 정리, 통계 분석 및 AI 질의응답 기능을 제공합니다.

2. 이용자 의무
- 정확한 정보를 입력해야 하며 타인의 권리를 침해하는 콘텐츠를 등록할 수 없습니다.

3. 서비스 제한
- 비정상적 사용, 약관 위반, 보안 위협이 감지될 경우 일부 기능이 제한될 수 있습니다.

4. 책임 제한
- 회사는 안정적인 운영을 위해 노력하나 네트워크/외부 서비스 장애로 인한 손해를 보장하지 않습니다.

5. 약관 동의
- [동의] 버튼을 누르면 본 약관을 읽고 동의한 것으로 처리됩니다.
""",
          en: """
1. Service purpose
- BabyAI provides parenting records, photo organization, analytics, and AI assistance.

2. User obligations
- You must provide accurate information and avoid content that violates others' rights.

3. Service restrictions
- Features may be limited for abuse, policy violations, or security risks.

4. Limitation of liability
- We strive for stable operation but cannot guarantee losses from network/external outages.

5. Agreement
- Pressing [Agree] records your acceptance of these terms.
""",
          es: """
1. Objetivo del servicio
- BabyAI ofrece registros de crianza, fotos, analitica y asistencia de IA.

2. Obligaciones del usuario
- Debe ingresar informacion precisa y no infringir derechos de terceros.

3. Restricciones del servicio
- Algunas funciones pueden limitarse por uso indebido o riesgos de seguridad.

4. Limitacion de responsabilidad
- Nos esforzamos por operar de forma estable, pero no garantizamos danos por fallas externas.

5. Aceptacion
- Al pulsar [Aceptar], se registra su aceptacion de estos terminos.
""",
        );
      case _OnboardingConsentType.privacy:
        return tr(
          context,
          ko: """
1. 수집 항목
- 계정 정보(이름, 이메일), 아이 프로필(이름, 생년월일, 성별, 체중), 수유/수면/기저귀/투약 기록, 업로드한 사진 메타데이터

2. 이용 목적
- 기록 저장 및 조회, 통계 제공, AI 답변 품질 향상, 서비스 운영 및 장애 대응

3. 보관/삭제
- 서비스 이용 기간 동안 보관하며, 삭제 요청 시 관련 법령 범위 내에서 삭제 또는 익명화합니다.

4. 제3자 처리
- 인증/저장/운영에 필요한 범위에서만 위탁 처리할 수 있습니다.

5. 동의
- [동의] 버튼을 누르면 개인정보 수집 및 이용에 동의한 것으로 처리됩니다.
""",
          en: """
1. Collected data
- Account data, baby profile, feeding/sleep/diaper/medication records, uploaded photo metadata

2. Purpose
- Record storage/retrieval, analytics, AI quality improvement, operation and incident response

3. Retention/deletion
- Data is retained during service use and deleted/anonymized on request within legal limits.

4. Third-party processing
- Processing can be delegated only as required for auth, storage, and operation.

5. Agreement
- Pressing [Agree] records your privacy consent.
""",
          es: """
1. Datos recopilados
- Cuenta, perfil del bebe, registros de alimentacion/sueno/panal/medicacion y metadatos de fotos

2. Finalidad
- Guardar/consultar registros, analitica, mejora de IA y operacion del servicio

3. Conservacion/eliminacion
- Se conservan durante el uso del servicio y se eliminan/anonimizan segun la ley.

4. Procesamiento por terceros
- Solo para autenticacion, almacenamiento y operacion del servicio.

5. Aceptacion
- Al pulsar [Aceptar], se registra su consentimiento de privacidad.
""",
        );
      case _OnboardingConsentType.dataProcessing:
        return tr(
          context,
          ko: """
1. 처리 범위
- 수유 방식, 분유 종류, 성장 정보, 최근 기록을 분석해 개인화 추천을 생성합니다.

2. 자동화 처리
- 일부 추천은 자동화된 규칙/모델에 의해 생성되며, 의학적 진단을 대체하지 않습니다.

3. 처리 목적
- 다음 수유 시점/권장량 제안, 기록 요약, 통계 시각화, AI 대화 맥락 유지

4. 보안 조치
- 최소 권한 접근, 전송 구간 암호화, 운영 로그 모니터링을 적용합니다.

5. 동의
- [동의] 버튼을 누르면 데이터 처리에 동의한 것으로 처리됩니다.
""",
          en: """
1. Processing scope
- Feeding method, formula type, growth data, and recent records are analyzed for recommendations.

2. Automated processing
- Some recommendations are generated by rules/models and do not replace medical diagnosis.

3. Purpose
- Suggest next feeding time/amount, summarize records, render stats, and maintain AI context.

4. Security
- Least-privilege access, encrypted transport, and operational log monitoring are applied.

5. Agreement
- Pressing [Agree] records your data-processing consent.
""",
          es: """
1. Alcance del procesamiento
- Metodo de alimentacion, tipo de formula, crecimiento y registros recientes para recomendaciones.

2. Procesamiento automatizado
- Algunas recomendaciones se generan por reglas/modelos y no sustituyen diagnostico medico.

3. Finalidad
- Sugerir horario/cantidad de alimentacion, resumir registros y mostrar estadisticas.

4. Seguridad
- Acceso de minimo privilegio, cifrado en transito y monitoreo de logs operativos.

5. Aceptacion
- Al pulsar [Aceptar], se registra su consentimiento de procesamiento de datos.
""",
        );
    }
  }

  Future<void> _openConsentDialog(_OnboardingConsentType type) async {
    final bool? agreed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(_consentDialogTitle(type)),
          content: SizedBox(
            width: 520,
            height: 360,
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                child: Text(
                  _consentDialogBody(type),
                  style: const TextStyle(height: 1.45),
                ),
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(tr(context, ko: "닫기", en: "Close", es: "Cerrar")),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(tr(context, ko: "동의", en: "Agree", es: "Aceptar")),
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

  Future<void> _onConsentChanged(
    _OnboardingConsentType type,
    bool nextValue,
  ) async {
    if (!nextValue) {
      setState(() => _setConsentValue(type, false));
      return;
    }
    await _openConsentDialog(type);
  }

  String _consentLabel(_OnboardingConsentType type) {
    switch (type) {
      case _OnboardingConsentType.terms:
        return tr(
          context,
          ko: "이용약관 동의 (필수)",
          en: "Terms consent (required)",
          es: "Terminos (obligatorio)",
        );
      case _OnboardingConsentType.privacy:
        return tr(
          context,
          ko: "개인정보 수집 동의 (필수)",
          en: "Privacy consent (required)",
          es: "Privacidad (obligatorio)",
        );
      case _OnboardingConsentType.dataProcessing:
        return tr(
          context,
          ko: "데이터 처리 동의 (필수)",
          en: "Data processing consent (required)",
          es: "Procesamiento de datos (obligatorio)",
        );
    }
  }

  Widget _buildConsentTile(_OnboardingConsentType type) {
    final bool selected = _consentValue(type);
    final TextTheme text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openConsentDialog(type),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: <Widget>[
              Checkbox(
                value: selected,
                onChanged: (bool? value) async {
                  await _onConsentChanged(type, value ?? false);
                },
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _consentLabel(type),
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tr(
                          context,
                          ko: "탭하여 약관 전문 보기",
                          en: "Tap to open full terms",
                          es: "Toque para ver el texto completo",
                        ),
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const Icon(Icons.open_in_new_rounded, size: 18),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
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

  String _tokenRequiredMessage() {
    return tr(
      context,
      ko: "로그인 토큰이 필요합니다. Google JWT 토큰을 입력하거나 --dart-define=API_BEARER_TOKEN으로 실행해 주세요.",
      en: "Login token is required. Enter Google JWT token or run with --dart-define=API_BEARER_TOKEN.",
      es: "Se requiere token. Ingrese JWT de Google o ejecute con --dart-define=API_BEARER_TOKEN.",
    );
  }

  Future<void> _submit() async {
    if (_loading) {
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final String typedToken = _tokenController.text.trim();
      final bool hasBearerToken = typedToken.isNotEmpty ||
          BabyAIApi.currentBearerToken.trim().isNotEmpty;

      if (widget.initialOnboarding && !hasBearerToken) {
        throw ApiFailure(_tokenRequiredMessage());
      }

      if (typedToken.isNotEmpty) {
        BabyAIApi.setBearerToken(typedToken);
      }

      final double? weightKg =
          double.tryParse(_weightController.text.trim().replaceAll(",", "."));

      if (widget.initialOnboarding || BabyAIApi.activeBabyId.isEmpty) {
        final List<String> requiredConsents = _consents();
        if (requiredConsents.length < 3) {
          throw ApiFailure(
            tr(
              context,
              ko: "필수 약관 동의가 필요합니다.",
              en: "All required consents must be accepted.",
              es: "Debe aceptar todos los consentimientos requeridos.",
            ),
          );
        }

        final Map<String, dynamic> created =
            await BabyAIApi.instance.onboardingParent(
          provider: "google",
          babyName: _nameController.text.trim(),
          babyBirthDate: _birthDateController.text.trim(),
          babySex: _sex,
          babyWeightKg: weightKg,
          feedingMethod: _feedingMethod,
          formulaBrand: _formulaBrandController.text.trim(),
          formulaProduct: _formulaProductController.text.trim(),
          formulaType: _formulaType,
          formulaContainsStarch: _formulaContainsStarch,
          requiredConsents: requiredConsents,
        );

        final String babyId = (created["baby_id"] ?? "").toString();
        final String householdId = (created["household_id"] ?? "").toString();
        if (babyId.isEmpty || householdId.isEmpty) {
          throw ApiFailure("Failed to create baby profile.");
        }

        BabyAIApi.setRuntimeIds(babyId: babyId, householdId: householdId);

        await BabyAIApi.instance.upsertBabyProfile(
          babyName: _nameController.text.trim(),
          babyBirthDate: _birthDateController.text.trim(),
          babySex: _sex,
          babyWeightKg: weightKg,
          feedingMethod: _feedingMethod,
          formulaBrand: _formulaBrandController.text.trim(),
          formulaProduct: _formulaProductController.text.trim(),
          formulaType: _formulaType,
          formulaContainsStarch: _formulaContainsStarch,
        );

        await widget.onCompleted(
          ChildProfileSaveResult(babyId: babyId, householdId: householdId),
        );

        if (!mounted) {
          return;
        }
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        }
      } else {
        await BabyAIApi.instance.upsertBabyProfile(
          babyName: _nameController.text.trim(),
          babyBirthDate: _birthDateController.text.trim(),
          babySex: _sex,
          babyWeightKg: weightKg,
          feedingMethod: _feedingMethod,
          formulaBrand: _formulaBrandController.text.trim(),
          formulaProduct: _formulaProductController.text.trim(),
          formulaType: _formulaType,
          formulaContainsStarch: _formulaContainsStarch,
        );

        await widget.onCompleted(
          ChildProfileSaveResult(
            babyId: BabyAIApi.activeBabyId,
            householdId: BabyAIApi.activeHouseholdId,
          ),
        );

        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                ko: "아이 프로필이 저장되었습니다.",
                en: "Child profile saved.",
                es: "Perfil del bebe guardado.",
              ),
            ),
          ),
        );
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.initialOnboarding,
        title: Text(
          tr(
            context,
            ko: "아이 등록",
            en: "Child Registration",
            es: "Registro del bebe",
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: <Widget>[
            if (widget.initialOnboarding) ...<Widget>[
              Text(
                tr(
                  context,
                  ko: "처음 사용을 위해 아이 정보를 등록해 주세요.",
                  en: "Register your baby profile to start.",
                  es: "Registre el perfil del bebe para comenzar.",
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tokenController,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: tr(
                    context,
                    ko: "Google JWT 토큰 (선택)",
                    en: "Google JWT token (optional)",
                    es: "Token JWT de Google (opcional)",
                  ),
                  helperText: BabyAIApi.currentBearerToken.trim().isNotEmpty
                      ? tr(
                          context,
                          ko: "Bearer 토큰이 이미 설정되어 있습니다.",
                          en: "Bearer token is already configured.",
                          es: "El token ya esta configurado.",
                        )
                      : tr(
                          context,
                          ko: "토큰을 입력하거나 --dart-define=API_BEARER_TOKEN으로 실행하세요.",
                          en: "Provide token here or use --dart-define=API_BEARER_TOKEN.",
                          es: "Ingrese token aqui o use --dart-define=API_BEARER_TOKEN.",
                        ),
                  border: const OutlineInputBorder(),
                ),
                validator: (String? value) {
                  if (!widget.initialOnboarding ||
                      BabyAIApi.currentBearerToken.trim().isNotEmpty) {
                    return null;
                  }
                  if ((value ?? "").trim().isEmpty) {
                    return _tokenRequiredMessage();
                  }
                  return null;
                },
              ),
              const SizedBox(height: 10),
            ],
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText:
                    tr(context, ko: "아이 이름", en: "Baby name", es: "Nombre"),
                border: const OutlineInputBorder(),
              ),
              validator: (String? value) {
                if (value == null || value.trim().isEmpty) {
                  return tr(
                    context,
                    ko: "아이 이름을 입력하세요.",
                    en: "Enter baby name.",
                    es: "Ingrese el nombre.",
                  );
                }
                return null;
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _birthDateController,
              decoration: InputDecoration(
                labelText: tr(
                  context,
                  ko: "생년월일 (YYYY-MM-DD)",
                  en: "Birth date (YYYY-MM-DD)",
                  es: "Fecha de nacimiento (YYYY-MM-DD)",
                ),
                border: const OutlineInputBorder(),
              ),
              validator: (String? value) {
                final String raw = (value ?? "").trim();
                if (raw.isEmpty) {
                  return tr(
                    context,
                    ko: "생년월일을 입력하세요.",
                    en: "Enter birth date.",
                    es: "Ingrese fecha de nacimiento.",
                  );
                }
                if (!RegExp(r"^\d{4}-\d{2}-\d{2}$").hasMatch(raw)) {
                  return tr(
                    context,
                    ko: "YYYY-MM-DD 형식으로 입력하세요.",
                    en: "Use YYYY-MM-DD format.",
                    es: "Use formato YYYY-MM-DD.",
                  );
                }
                return null;
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _sex,
              decoration: InputDecoration(
                labelText: tr(context, ko: "성별", en: "Sex", es: "Sexo"),
                border: const OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<String>>[
                DropdownMenuItem(
                    value: "unknown", child: Text(_sexLabel("unknown"))),
                DropdownMenuItem(
                    value: "female", child: Text(_sexLabel("female"))),
                DropdownMenuItem(value: "male", child: Text(_sexLabel("male"))),
                DropdownMenuItem(
                    value: "other", child: Text(_sexLabel("other"))),
              ],
              onChanged: (String? value) {
                if (value != null) {
                  setState(() => _sex = value);
                }
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _weightController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: tr(
                  context,
                  ko: "체중 (kg)",
                  en: "Weight (kg)",
                  es: "Peso (kg)",
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _feedingMethod,
              decoration: InputDecoration(
                labelText: tr(
                  context,
                  ko: "수유 방식",
                  en: "Feeding method",
                  es: "Metodo de alimentacion",
                ),
                border: const OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<String>>[
                DropdownMenuItem(
                    value: "mixed", child: Text(_feedingMethodLabel("mixed"))),
                DropdownMenuItem(
                    value: "formula",
                    child: Text(_feedingMethodLabel("formula"))),
                DropdownMenuItem(
                    value: "breastmilk",
                    child: Text(_feedingMethodLabel("breastmilk"))),
              ],
              onChanged: (String? value) {
                if (value != null) {
                  setState(() => _feedingMethod = value);
                }
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _formulaType,
              decoration: InputDecoration(
                labelText: tr(
                  context,
                  ko: "분유 타입",
                  en: "Formula type",
                  es: "Tipo de formula",
                ),
                border: const OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<String>>[
                DropdownMenuItem(
                    value: "standard",
                    child: Text(_formulaTypeLabel("standard"))),
                DropdownMenuItem(
                    value: "hydrolyzed",
                    child: Text(_formulaTypeLabel("hydrolyzed"))),
                DropdownMenuItem(
                    value: "thickened",
                    child: Text(_formulaTypeLabel("thickened"))),
                DropdownMenuItem(
                    value: "soy", child: Text(_formulaTypeLabel("soy"))),
                DropdownMenuItem(
                    value: "goat", child: Text(_formulaTypeLabel("goat"))),
                DropdownMenuItem(
                    value: "specialty",
                    child: Text(_formulaTypeLabel("specialty"))),
              ],
              onChanged: (String? value) {
                if (value != null) {
                  setState(() => _formulaType = value);
                }
              },
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _formulaBrandController,
              decoration: InputDecoration(
                labelText: tr(
                  context,
                  ko: "분유 브랜드",
                  en: "Formula brand",
                  es: "Marca de formula",
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _formulaProductController,
              decoration: InputDecoration(
                labelText: tr(
                  context,
                  ko: "분유 제품명",
                  en: "Formula product",
                  es: "Producto de formula",
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _formulaContainsStarch,
              title: Text(
                tr(
                  context,
                  ko: "전분(점도) 함유",
                  en: "Contains starch/thickener",
                  es: "Contiene almidon/espesante",
                ),
              ),
              onChanged: (bool value) {
                setState(() => _formulaContainsStarch = value);
              },
            ),
            if (widget.initialOnboarding) ...<Widget>[
              const Divider(height: 22),
              _buildConsentTile(_OnboardingConsentType.terms),
              _buildConsentTile(_OnboardingConsentType.privacy),
              _buildConsentTile(_OnboardingConsentType.dataProcessing),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _submit,
              icon: const Icon(Icons.save_outlined),
              label: Text(
                widget.initialOnboarding
                    ? tr(context,
                        ko: "등록 후 시작",
                        en: "Save & Start",
                        es: "Guardar y empezar")
                    : tr(context, ko: "저장", en: "Save", es: "Guardar"),
              ),
            ),
            if (_loading) ...<Widget>[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}
