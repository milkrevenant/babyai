import "package:flutter/widgets.dart";

import "../theme/app_theme_controller.dart";

class AppSettingsScope extends InheritedNotifier<AppThemeController> {
  const AppSettingsScope({
    super.key,
    required AppThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppThemeController of(BuildContext context) {
    final AppSettingsScope? scope =
        context.dependOnInheritedWidgetOfExactType<AppSettingsScope>();
    if (scope == null || scope.notifier == null) {
      throw FlutterError("AppSettingsScope is not available in context.");
    }
    return scope.notifier!;
  }

  static AppThemeController? maybeOf(BuildContext context) {
    final AppSettingsScope? scope =
        context.dependOnInheritedWidgetOfExactType<AppSettingsScope>();
    return scope?.notifier;
  }
}

String tr(
  BuildContext context, {
  required String ko,
  required String en,
  required String es,
}) {
  final AppLanguage language =
      AppSettingsScope.maybeOf(context)?.language ?? AppLanguage.ko;
  switch (language) {
    case AppLanguage.ko:
      return ko;
    case AppLanguage.en:
      return en;
    case AppLanguage.es:
      return es;
  }
}
