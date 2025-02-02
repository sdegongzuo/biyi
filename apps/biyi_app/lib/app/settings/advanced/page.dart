import 'package:biyi_app/generated/locale_keys.g.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:rise_ui/rise_ui.dart';

class AdvancedSettingPage extends StatefulWidget {
  const AdvancedSettingPage({super.key});

  @override
  State<AdvancedSettingPage> createState() => _AdvancedSettingPageState();
}

class _AdvancedSettingPageState extends State<AdvancedSettingPage> {
  Widget _buildBody(BuildContext context) {
    return Container();
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: LocaleKeys.app_settings_advanced_title.tr(),
      child: _buildBody(context),
    );
  }
}
