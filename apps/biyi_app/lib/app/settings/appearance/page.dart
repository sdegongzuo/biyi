import 'package:biyi_app/generated/locale_keys.g.dart';
import 'package:biyi_app/providers/providers.dart';
import 'package:biyi_app/services/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart' hide Icons;
import 'package:provider/provider.dart';
import 'package:rise_ui/rise_ui.dart';

const List<double> _kMaxWindowHeightOptions = [700, 800, 900, 1000];

class AppearanceSettingPage extends StatefulWidget {
  const AppearanceSettingPage({super.key});

  @override
  State<AppearanceSettingPage> createState() => _AppearanceSettingPageState();
}

class _AppearanceSettingPageState extends State<AppearanceSettingPage> {
  Configuration get _configuration => localDb.configuration;

  @override
  void initState() {
    localDb.preferences.addListener(_handleChanged);
    super.initState();
  }

  @override
  void dispose() {
    localDb.preferences.removeListener(_handleChanged);
    super.dispose();
  }

  void _handleChanged() {
    if (mounted) setState(() {});
  }

  void _handleThemeModeChanged(newValue) {
    _configuration.themeMode = newValue;
    context.read<AppSettings>().themeMode = newValue;
  }

  Widget _buildBody(BuildContext context) {
    return Column(
      children: [
        PreferenceListSection.insetGrouped(
          children: [
            PreferenceListTile(
              title: Text(
                LocaleKeys.theme_mode_light.tr(),
              ),
              additionalInfo: _configuration.themeMode == ThemeMode.light
                  ? Icon(
                      FluentIcons.checkmark_circle_20_filled,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () => _handleThemeModeChanged(ThemeMode.light),
            ),
            PreferenceListTile(
              title: Text(
                LocaleKeys.theme_mode_dark.tr(),
              ),
              additionalInfo: _configuration.themeMode == ThemeMode.dark
                  ? Icon(
                      FluentIcons.checkmark_circle_20_filled,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () => _handleThemeModeChanged(ThemeMode.dark),
            ),
            PreferenceListTile(
              title: Text(
                LocaleKeys.theme_mode_system.tr(),
              ),
              additionalInfo: _configuration.themeMode == ThemeMode.system
                  ? Icon(
                      FluentIcons.checkmark_circle_20_filled,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () => _handleThemeModeChanged(ThemeMode.system),
            ),
          ],
        ),
        PreferenceListSection.insetGrouped(
          header: Text(
            LocaleKeys.app_settings_appearance_tray_icon_title.tr(),
          ),
          children: [
            PreferenceListTile(
              title: Text(
                LocaleKeys.app_settings_appearance_tray_icon_show_title.tr(),
              ),
              additionalInfo: _configuration.showTrayIcon
                  ? Icon(
                      FluentIcons.checkmark_circle_20_filled,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              onTap: () {
                _configuration.showTrayIcon = !_configuration.showTrayIcon;
              },
            ),
          ],
        ),
        PreferenceListSection.insetGrouped(
          header: Text(
            LocaleKeys.app_settings_appearance_max_window_height_title.tr(),
          ),
          children: [
            for (var option in _kMaxWindowHeightOptions)
              PreferenceListTile(
                title: Text('${option.toInt()}'),
                additionalInfo: _configuration.maxWindowHeight == option
                    ? Icon(
                        FluentIcons.checkmark_circle_20_filled,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : null,
                onTap: () {
                  _configuration.maxWindowHeight = option;
                },
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: LocaleKeys.app_settings_appearance_title.tr(),
      subtitle: LocaleKeys.app_settings_appearance_subtitle.tr(),
      child: _buildBody(context),
    );
  }
}
