import "package:flutter/widgets.dart";
import "package:flutter_svg/flutter_svg.dart";

class AppSvgAsset {
  const AppSvgAsset._();

  static const String aiChatSparkles = "icon_ai_chat_sparkles.svg";
  static const String bell = "icon_bell.png";
  static const String clinicStethoscope = "icon_clinic_stethoscope.png";
  static const String diaper = "icon_diaper.png";
  static const String feeding = "icon_feeding.png";
  static const String home = "icon_home.png";
  static const String medicine = "icon_medicine.png";
  static const String memoLucide = "icon_memo_lucide.svg";
  static const String playCar = "icon_play_car.png";
  static const String profile = "icon_profile.svg";
  static const String sleepCrescentPurple = "icon_sleep_crescent_purple.png";
  static const String sleepCrescentYellow = "icon_sleep_crescent_yellow.png";
  static const String stats = "icon_stats.svg";
}

class AppSvgIcon extends StatelessWidget {
  const AppSvgIcon(
    this.assetName, {
    super.key,
    this.size = 24,
    this.color,
    this.fit = BoxFit.contain,
    this.semanticsLabel,
  });

  final String assetName;
  final double size;
  final Color? color;
  final BoxFit fit;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final String assetPath = "assets/icons/$assetName";
    if (assetName.toLowerCase().endsWith(".svg")) {
      return SvgPicture.asset(
        assetPath,
        width: size,
        height: size,
        fit: fit,
        semanticsLabel: semanticsLabel,
        colorFilter:
            color == null ? null : ColorFilter.mode(color!, BlendMode.srcIn),
      );
    }

    return Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: fit,
      semanticLabel: semanticsLabel,
    );
  }
}
