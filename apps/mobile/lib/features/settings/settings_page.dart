import "package:flutter/material.dart";

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

  String _mainFontLabel(AppMainFont font) {
    switch (font) {
      case AppMainFont.notoSans:
        return "Noto Sans";
      case AppMainFont.systemSans:
        return "System Sans";
    }
  }

  String _highlightFontLabel(AppHighlightFont font) {
    switch (font) {
      case AppHighlightFont.ibmPlexSans:
        return "IBM Plex Sans";
      case AppHighlightFont.notoSans:
        return "Noto Sans";
    }
  }

  String _toneLabel(AppAccentTone tone) {
    switch (tone) {
      case AppAccentTone.gold:
        return "Gold";
      case AppAccentTone.teal:
        return "Teal";
      case AppAccentTone.coral:
        return "Coral";
      case AppAccentTone.indigo:
        return "Indigo";
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

  String _bottomMenuLabel(AppBottomMenu menu) {
    switch (menu) {
      case AppBottomMenu.chat:
        return "AI Chat";
      case AppBottomMenu.statistics:
        return "Statistics";
      case AppBottomMenu.photos:
        return "Photos";
      case AppBottomMenu.market:
        return "Market";
      case AppBottomMenu.community:
        return "Community";
    }
  }

  Future<void> _showCustomerCenter(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Customer Center"),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text("Support email: support@babyai.app"),
              SizedBox(height: 6),
              Text("Hours: Mon-Fri 09:00-18:00 (KST)"),
              SizedBox(height: 6),
              Text("FAQ: app usage / billing / account / data export"),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Close"),
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
          title: const Text("Data Collection & Privacy Terms"),
          content: const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text("1. Required data: baby event records for core features."),
                SizedBox(height: 6),
                Text(
                  "2. Optional data: photos, assistant phrases, and usage logs for UX improvement.",
                ),
                SizedBox(height: 6),
                Text(
                  "3. Account data: Google profile basics (name/email) for sign-in.",
                ),
                SizedBox(height: 6),
                Text(
                  "4. You can request deletion/export through Customer Center.",
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Close"),
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
      appBar: AppBar(title: const Text("Settings")),
      body: AnimatedBuilder(
        animation: themeController,
        builder: (BuildContext context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            children: <Widget>[
              const Text(
                "Display Mode",
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              RadioGroup<AppThemeMode>(
                groupValue: themeController.mode,
                onChanged: (AppThemeMode? value) {
                  if (value != null) {
                    _selectTheme(value);
                  }
                },
                child: const Column(
                  children: <Widget>[
                    RadioListTile<AppThemeMode>(
                      value: AppThemeMode.system,
                      title: Text("Follow system"),
                    ),
                    RadioListTile<AppThemeMode>(
                      value: AppThemeMode.dark,
                      title: Text("Dark mode"),
                    ),
                    RadioListTile<AppThemeMode>(
                      value: AppThemeMode.light,
                      title: Text("Light mode"),
                    ),
                  ],
                ),
              ),
              const Divider(height: 24),
              const Text(
                "Font Settings",
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<AppMainFont>(
                initialValue: themeController.mainFont,
                decoration: const InputDecoration(
                  labelText: "Main font",
                  border: OutlineInputBorder(),
                ),
                items: AppMainFont.values
                    .map(
                      (AppMainFont item) => DropdownMenuItem<AppMainFont>(
                        value: item,
                        child: Text(_mainFontLabel(item)),
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
                decoration: const InputDecoration(
                  labelText: "Highlight font",
                  border: OutlineInputBorder(),
                ),
                items: AppHighlightFont.values
                    .map(
                      (AppHighlightFont item) =>
                          DropdownMenuItem<AppHighlightFont>(
                        value: item,
                        child: Text(_highlightFontLabel(item)),
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
              const Text(
                "Color Settings",
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
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
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(_toneLabel(tone)),
                          ],
                        ),
                        onSelected: (_) => themeController.setAccentTone(tone),
                      ),
                    )
                    .toList(),
              ),
              const Divider(height: 24),
              const Text(
                "Bottom Menu Visibility",
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                "Home is always visible. Toggle other bottom menus.",
                style: TextStyle(color: color.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              ...AppBottomMenu.values.map(
                (AppBottomMenu menu) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: themeController.isBottomMenuEnabled(menu),
                  title: Text(_bottomMenuLabel(menu)),
                  onChanged: (bool value) {
                    themeController.setBottomMenuEnabled(menu, value);
                  },
                ),
              ),
              const Divider(height: 24),
              const Text(
                "Google Account Login",
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
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
                    Text(
                      accountName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(accountEmail),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: isGoogleLoggedIn ? null : onGoogleLogin,
                            icon: const Icon(Icons.login),
                            label: const Text("Login"),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: isGoogleLoggedIn ? onGoogleLogout : null,
                            icon: const Icon(Icons.logout),
                            label: const Text("Logout"),
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
                title: const Text("Customer Center"),
                subtitle: const Text("Support contact and FAQ"),
                onTap: () => _showCustomerCenter(context),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text("Privacy Terms"),
                subtitle: const Text("Data collection and terms guide"),
                onTap: () => _showPrivacyTerms(context),
              ),
            ],
          );
        },
      ),
    );
  }
}
