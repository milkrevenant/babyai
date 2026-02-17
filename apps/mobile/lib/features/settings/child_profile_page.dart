import "package:flutter/material.dart";

import "../../core/i18n/app_i18n.dart";
import "../../core/network/babyai_api.dart";

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

  bool _consentTerms = true;
  bool _consentPrivacy = true;
  bool _consentData = true;

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
                  border: const OutlineInputBorder(),
                ),
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
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(value: "unknown", child: Text("Unknown")),
                DropdownMenuItem(value: "female", child: Text("Female")),
                DropdownMenuItem(value: "male", child: Text("Male")),
                DropdownMenuItem(value: "other", child: Text("Other")),
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
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(value: "mixed", child: Text("Mixed")),
                DropdownMenuItem(value: "formula", child: Text("Formula")),
                DropdownMenuItem(
                    value: "breastmilk", child: Text("Breastmilk")),
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
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(value: "standard", child: Text("Standard")),
                DropdownMenuItem(
                    value: "hydrolyzed", child: Text("Hydrolyzed")),
                DropdownMenuItem(
                    value: "thickened", child: Text("Thickened (AR)")),
                DropdownMenuItem(value: "soy", child: Text("Soy")),
                DropdownMenuItem(value: "goat", child: Text("Goat")),
                DropdownMenuItem(value: "specialty", child: Text("Specialty")),
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
              CheckboxListTile(
                value: _consentTerms,
                onChanged: (bool? value) =>
                    setState(() => _consentTerms = value ?? false),
                title: Text(tr(
                  context,
                  ko: "이용약관 동의 (필수)",
                  en: "Terms consent (required)",
                  es: "Terminos (obligatorio)",
                )),
              ),
              CheckboxListTile(
                value: _consentPrivacy,
                onChanged: (bool? value) =>
                    setState(() => _consentPrivacy = value ?? false),
                title: Text(tr(
                  context,
                  ko: "개인정보 수집 동의 (필수)",
                  en: "Privacy consent (required)",
                  es: "Privacidad (obligatorio)",
                )),
              ),
              CheckboxListTile(
                value: _consentData,
                onChanged: (bool? value) =>
                    setState(() => _consentData = value ?? false),
                title: Text(tr(
                  context,
                  ko: "데이터 처리 동의 (필수)",
                  en: "Data processing consent (required)",
                  es: "Procesamiento de datos (obligatorio)",
                )),
              ),
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
