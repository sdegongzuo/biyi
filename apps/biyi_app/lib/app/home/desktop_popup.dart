import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:biyi_advanced_features/biyi_advanced_features.dart';
import 'package:biyi_app/app/home/limited_functionality_banner.dart';
import 'package:biyi_app/app/home/new_version_found_banner.dart';
import 'package:biyi_app/app/home/toolbar_item_always_on_top.dart';
import 'package:biyi_app/app/home/toolbar_item_settings.dart';
import 'package:biyi_app/app/home/translation_input_view.dart';
import 'package:biyi_app/app/home/translation_results_view.dart';
import 'package:biyi_app/app/home/translation_target_select_view.dart';
import 'package:biyi_app/generated/locale_keys.g.dart';
import 'package:biyi_app/models/models.dart';
import 'package:biyi_app/networking/networking.dart';
import 'package:biyi_app/services/services.dart';
import 'package:biyi_app/utilities/utilities.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:keypress_simulator/keypress_simulator.dart';
import 'package:protocol_handler/protocol_handler.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:screen_text_extractor/screen_text_extractor.dart';
import 'package:shortid/shortid.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:uni_ocr_client/uni_ocr_client.dart';
import 'package:uni_platform/uni_platform.dart';
import 'package:uni_translate_client/uni_translate_client.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:window_manager/window_manager.dart';

const kMenuItemKeyShow = 'show';
const kMenuItemKeyQuickStartGuide = 'quick-start-guide';
const kMenuItemKeyQuitApp = 'quit-app';

const kMenuSubItemKeyJoinDiscord = 'subitem-join-discord';
const kMenuSubItemKeyJoinQQGroup = 'subitem-join-qq';

class DesktopPopupPage extends StatefulWidget {
  const DesktopPopupPage({super.key});

  @override
  State<StatefulWidget> createState() => _DesktopPopupPageState();
}

class _DesktopPopupPageState extends State<DesktopPopupPage>
    with
        WidgetsBindingObserver,
        ProtocolListener,
        ShortcutListener,
        TrayListener,
        WindowListener {
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _textEditingController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final GlobalKey _bannersViewKey = GlobalKey();
  final GlobalKey _inputViewKey = GlobalKey();
  final GlobalKey _resultsViewKey = GlobalKey();

  Configuration get _configuration => localDb.configuration;

  Brightness _brightness = Brightness.light;

  bool? _lastShowTrayIcon;
  String? _lastAppLanguage;
  Offset _lastShownPosition = Offset.zero;

  Version? _latestVersion;
  bool _isAllowedScreenCaptureAccess = true;
  bool _isAllowedScreenSelectionAccess = true;

  String _sourceLanguage = kLanguageEN;
  String _targetLanguage = kLanguageZH;
  bool _isShowSourceLanguageSelector = false;
  bool _isShowTargetLanguageSelector = false;

  bool _querySubmitted = false;
  String _text = '';
  String? _textDetectedLanguage;
  CapturedData? _capturedData;
  bool _isTextDetecting = false;
  List<TranslationResult> _translationResultList = [];

  List<Future> _futureList = [];

  Timer? _resizeTimer;

  List<TranslationEngineConfig> get _translationEngineList {
    return localDb.engines.list(
      where: (e) => !e.disabled,
    );
  }

  List<TranslationTarget> get _translationTargetList {
    if (_configuration.translationMode == kTranslationModeManual) {
      return [
        TranslationTarget(
          sourceLanguage: _sourceLanguage,
          targetLanguage: _targetLanguage,
        ),
      ];
    }
    return localDb.translationTargets.list();
  }

  @override
  void initState() {
    localDb.preferences.addListener(_handleChanged);
    WidgetsBinding.instance.addObserver(this);
    if (UniPlatform.isLinux || UniPlatform.isMacOS || UniPlatform.isWindows) {
      protocolHandler.addListener(this);
      ShortcutService.instance.setListener(this);
      trayManager.addListener(this);
      windowManager.addListener(this);
      _init();
    }
    _loadData();
    super.initState();
    UniPlatform.call<Future<void>>(
      desktop: () => _initWindow(),
      otherwise: () => Future(() => null),
    );
  }

  @override
  void dispose() {
    localDb.preferences.removeListener(_handleChanged);
    WidgetsBinding.instance.removeObserver(this);
    if (UniPlatform.isLinux || UniPlatform.isMacOS || UniPlatform.isWindows) {
      protocolHandler.removeListener(this);
      ShortcutService.instance.setListener(null);
      trayManager.removeListener(this);
      windowManager.removeListener(this);
      _uninit();
    }
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    Brightness newBrightness =
        // ignore: deprecated_member_use
        WidgetsBinding.instance.window.platformBrightness;

    if (newBrightness != _brightness) {
      _brightness = newBrightness;
      if (UniPlatform.isWindows && _configuration.showTrayIcon) {
        _initTrayIcon();
      }
      setState(() {});
    }
  }

  Future<void> _initWindow() async {
    const size = Size(400, 185);
    const minimunSize = Size(400, 185);
    const maximumSize = Size(400, 600);
    await Future.any([
      windowManager.setSize(size),
      windowManager.setMinimumSize(minimunSize),
      windowManager.setMaximumSize(maximumSize),
      windowManager.setSkipTaskbar(true),
      windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      ),
      windowManager.setPreventClose(true),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await windowManager.show();
  }

  void _handleChanged() {
    bool trayIconUpdated = _lastShowTrayIcon != _configuration.showTrayIcon ||
        _lastAppLanguage != _configuration.appLanguage;

    _lastShowTrayIcon = _configuration.showTrayIcon;
    _lastAppLanguage = _configuration.appLanguage;

    if (trayIconUpdated) {
      _initTrayIcon();
    }

    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    if (UniPlatform.isMacOS) {
      _isAllowedScreenCaptureAccess =
          await ScreenCapturer.instance.isAccessAllowed();
      _isAllowedScreenSelectionAccess =
          await screenTextExtractor.isAccessAllowed();
    }

    ShortcutService.instance.start();

    // 初始化托盘图标
    await _initTrayIcon();
    await Future.delayed(const Duration(milliseconds: 400));

    if (UniPlatform.isLinux || UniPlatform.isWindows) {
      Display primaryDisplay = await screenRetriever.getPrimaryDisplay();
      Size windowSize = await windowManager.getSize();
      _lastShownPosition = Offset(
        primaryDisplay.size.width - windowSize.width - 50,
        50,
      );
      await windowManager.setPosition(_lastShownPosition);
    }
    await _windowShow(
      isShowBelowTray: UniPlatform.isMacOS,
    );
    setState(() {});
  }

  Future<void> _initTrayIcon() async {
    if (UniPlatform.isWeb) return;

    String trayIconName = UniPlatform.select<String>(
      windows: 'tray_icon_black.ico',
      linux: 'tray_icon.ico',
      otherwise: 'tray_icon_black.png',
    );
    if (_brightness == Brightness.dark) {
      trayIconName = UniPlatform.select<String>(
        windows: 'tray_icon.ico',
        otherwise: 'tray_icon.png',
      );
    }

    await trayManager.destroy();
    if (_configuration.showTrayIcon) {
      await trayManager.setIcon(
        R.image(trayIconName),
        isTemplate: UniPlatform.isMacOS ? true : false,
      );
      await Future.delayed(const Duration(milliseconds: 10));
      Menu menu = Menu(
        items: [
          MenuItem(
            label:
                '${LocaleKeys.app_name.tr()} v${sharedEnv.appVersion} (BUILD ${sharedEnv.appBuildNumber})',
            disabled: true,
          ),
          MenuItem.separator(),
          if (UniPlatform.isLinux)
            MenuItem(
              key: kMenuItemKeyShow,
              label: LocaleKeys.tray_context_menu_item_show.tr(),
            ),
          MenuItem(
            key: kMenuItemKeyQuickStartGuide,
            label: LocaleKeys.tray_context_menu_item_quick_start_guide.tr(),
          ),
          MenuItem.submenu(
            label: LocaleKeys.tray_context_menu_item_discussion.tr(),
            submenu: Menu(
              items: [
                MenuItem(
                  key: kMenuSubItemKeyJoinDiscord,
                  label: LocaleKeys
                      .tray_context_menu_item_discussion_subitem_discord_server
                      .tr(),
                ),
                MenuItem(
                  key: kMenuSubItemKeyJoinQQGroup,
                  label: LocaleKeys
                      .tray_context_menu_item_discussion_subitem_qq_group
                      .tr(),
                ),
              ],
            ),
          ),
          MenuItem.separator(),
          MenuItem(
            key: kMenuItemKeyQuitApp,
            label: LocaleKeys.tray_context_menu_item_quit_app.tr(),
          ),
        ],
      );
      await trayManager.setContextMenu(menu);
    }
  }

  void _uninit() {
    ShortcutService.instance.stop();
  }

  Future<void> _windowShow({
    bool isShowBelowTray = false,
  }) async {
    bool isAlwaysOnTop = await windowManager.isAlwaysOnTop();
    Size windowSize = await windowManager.getSize();

    if (UniPlatform.isLinux) {
      await windowManager.setPosition(_lastShownPosition);
    }

    if (UniPlatform.isMacOS && isShowBelowTray) {
      Rect? trayIconBounds = await trayManager.getBounds();
      if (trayIconBounds != null) {
        Size trayIconSize = trayIconBounds.size;
        Offset trayIconPosition = trayIconBounds.topLeft;

        Offset newPosition = Offset(
          trayIconPosition.dx - ((windowSize.width - trayIconSize.width) / 2),
          trayIconPosition.dy,
        );

        if (!isAlwaysOnTop) {
          await windowManager.setPosition(newPosition);
        }
      }
    }

    bool isVisible = await windowManager.isVisible();
    if (!isVisible) {
      await windowManager.show();
    } else {
      await windowManager.focus();
    }

    // Linux 下无法激活窗口临时解决方案
    if (UniPlatform.isLinux && !isAlwaysOnTop) {
      await windowManager.setAlwaysOnTop(true);
      await Future.delayed(const Duration(milliseconds: 10));
      await windowManager.setAlwaysOnTop(false);
      await Future.delayed(const Duration(milliseconds: 10));
      await windowManager.focus();
    }
  }

  Future<void> _windowHide() async {
    await windowManager.hide();
  }

  void _windowResize() {
    if (Navigator.of(context).canPop()) return;

    if (_resizeTimer != null && _resizeTimer!.isActive) {
      _resizeTimer?.cancel();
    }
    _resizeTimer = Timer.periodic(const Duration(milliseconds: 10), (_) async {
      if (!UniPlatform.isMacOS) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      RenderBox? rb1 =
          _bannersViewKey.currentContext?.findRenderObject() as RenderBox?;
      RenderBox? rb2 =
          _inputViewKey.currentContext?.findRenderObject() as RenderBox?;
      RenderBox? rb3 =
          _resultsViewKey.currentContext?.findRenderObject() as RenderBox?;

      double toolbarViewHeight = 36.0;
      double bannersViewHeight = rb1?.size.height ?? 0;
      double inputViewHeight = rb2?.size.height ?? 0;
      double resultsViewHeight = rb3?.size.height ?? 0;

      try {
        double newWindowHeight = toolbarViewHeight +
            bannersViewHeight +
            inputViewHeight +
            resultsViewHeight +
            (UniPlatform.isWindows ? 5 : 0);
        Size oldSize = await windowManager.getSize();
        Size newSize = Size(
          oldSize.width,
          newWindowHeight < _configuration.maxWindowHeight
              ? newWindowHeight
              : _configuration.maxWindowHeight,
        );
        if (oldSize.width != newSize.width ||
            oldSize.height != newSize.height) {
          await windowManager.setSize(newSize, animate: true);
        }
      } catch (error) {
        // print(error);
      }

      if (_resizeTimer != null) {
        _resizeTimer?.cancel();
        _resizeTimer = null;
      }
    });
  }

  Future<void> _loadData() async {
    try {
      await localDb.setCurrentUser(
        localDb.user,
      );
    } catch (error) {
      // skip
    }
    try {
      _latestVersion = await apiClient.version('latest').get();
      setState(() {});
    } catch (error) {
      // skip
    }
    try {
      await localDb.loadFromCloudServer();
    } catch (error) {
      // skip
    }
  }

  Future<void> _queryData() async {
    setState(() {
      _isShowSourceLanguageSelector = false;
      _isShowTargetLanguageSelector = false;
      _querySubmitted = true;
      _textDetectedLanguage = null;
      _translationResultList = [];
      _futureList = [];
    });

    if (_configuration.translationMode == kTranslationModeManual) {
      TranslationResult translationResult = TranslationResult(
        translationTarget: _translationTargetList.first,
        translationResultRecordList: [],
      );
      _translationResultList = [translationResult];
    } else {
      var filteredTranslationTargetList = _translationTargetList;
      try {
        DetectLanguageRequest detectLanguageRequest = DetectLanguageRequest(
          texts: [_text],
        );
        DetectLanguageResponse detectLanguageResponse = await translateClient
            .use(_configuration.defaultEngineId ?? '')
            .detectLanguage(detectLanguageRequest);

        _textDetectedLanguage = detectLanguageResponse
            .detections!.first.detectedLanguage
            .split('-')[0];

        filteredTranslationTargetList = _translationTargetList
            .where((e) => e.sourceLanguage == _textDetectedLanguage)
            .toList();
      } catch (error) {
        // print(error);
      }

      for (var translationTarget in filteredTranslationTargetList) {
        TranslationResult translationResult = TranslationResult(
          translationTarget: translationTarget,
          translationResultRecordList: [],
          unsupportedEngineIdList: [],
        );
        _translationResultList.add(translationResult);
      }

      setState(() {});
    }

    for (int i = 0; i < _translationResultList.length; i++) {
      TranslationTarget? translationTarget =
          _translationResultList[i].translationTarget;

      List<String> engineIdList = [];
      List<String> unsupportedEngineIdList = [];

      for (int j = 0; j < _translationEngineList.length; j++) {
        String identifier = _translationEngineList[j].identifier;

        if (_translationEngineList[j].disabled) continue;

        try {
          List<LanguagePair> supportedLanguagePairList = [];
          supportedLanguagePairList =
              await translateClient.use(identifier).getSupportedLanguagePairs();

          LanguagePair? languagePair =
              supportedLanguagePairList.firstWhereOrNull(
            (e) {
              return e.sourceLanguage == translationTarget?.sourceLanguage &&
                  e.targetLanguage == translationTarget?.targetLanguage;
            },
          );
          if (languagePair == null) {
            unsupportedEngineIdList.add(identifier);
          } else {
            engineIdList.add(identifier);
          }
        } catch (error) {
          engineIdList.add(identifier);
        }
      }

      _translationResultList[i].unsupportedEngineIdList =
          unsupportedEngineIdList;

      for (int j = 0; j < engineIdList.length; j++) {
        String identifier = engineIdList[j];

        TranslationResultRecord translationResultRecord =
            TranslationResultRecord(
          id: shortid.generate(),
          translationEngineId: identifier,
          translationTargetId: translationTarget?.id,
        );
        _translationResultList[i]
            .translationResultRecordList!
            .add(translationResultRecord);

        Future<bool> future = Future<bool>.sync(() async {
          LookUpRequest? lookUpRequest;
          LookUpResponse? lookUpResponse;
          UniTranslateClientError? lookUpError;
          if ((translateClient.use(identifier).supportedScopes)
              .contains(kScopeLookUp)) {
            try {
              lookUpRequest = LookUpRequest(
                sourceLanguage: translationTarget!.sourceLanguage!,
                targetLanguage: translationTarget.targetLanguage!,
                word: _text,
              );
              lookUpResponse = await translateClient //
                  .use(identifier)
                  .lookUp(lookUpRequest);
            } on UniTranslateClientError catch (error) {
              lookUpError = error;
            } catch (error) {
              lookUpError = UniTranslateClientError(message: error.toString());
            }
          }

          TranslateRequest? translateRequest;
          TranslateResponse? translateResponse;
          UniTranslateClientError? translateError;

          if ((translateClient.use(identifier).supportedScopes)
              .contains(kScopeTranslate)) {
            try {
              translateRequest = TranslateRequest(
                sourceLanguage: translationTarget!.sourceLanguage,
                targetLanguage: translationTarget.targetLanguage,
                text: _text,
              );
              translateResponse = await translateClient //
                  .use(identifier)
                  .translate(translateRequest);
              translateResponse.stream.listen(
                (event) {
                  setState(() {});
                },
                onDone: () {},
              );
            } on UniTranslateClientError catch (error) {
              translateError = error;
            } catch (error) {
              translateError =
                  UniTranslateClientError(message: error.toString());
            }
          }

          if (lookUpResponse != null) {
            _translationResultList[i]
                .translationResultRecordList![j]
                .lookUpRequest = lookUpRequest;
            _translationResultList[i]
                .translationResultRecordList![j]
                .lookUpResponse = lookUpResponse;
          }
          if (lookUpError != null) {
            _translationResultList[i]
                .translationResultRecordList![j]
                .lookUpError = lookUpError;
          }

          if (translateResponse != null) {
            _translationResultList[i]
                .translationResultRecordList![j]
                .translateRequest = translateRequest;
            _translationResultList[i]
                .translationResultRecordList![j]
                .translateResponse = translateResponse;
          }
          if (translateError != null) {
            _translationResultList[i]
                .translationResultRecordList![j]
                .translateError = translateError;
          }

          setState(() {});

          return true;
        });
        _futureList.add(future);
      }
    }

    await Future.wait(_futureList);
  }

  void _handleTextChanged(
    String? newValue, {
    bool isRequery = false,
  }) {
    setState(() {
      // 移除前后多余的空格
      _text = (newValue ?? '').trim();
      // 当使用 Enter 键触发翻译时用空格替换换行符
      if (_configuration.inputSetting == kInputSettingSubmitWithEnter) {
        _text = _text.replaceAll('\n', ' ');
      }
    });
    if (isRequery) {
      _textEditingController.text = _text;
      _textEditingController.selection = TextSelection(
        baseOffset: _text.length,
        extentOffset: _text.length,
      );
      _handleButtonTappedTrans();
    }
  }

  Future<void> _handleExtractTextFromScreenSelection() async {
    ExtractedData? extractedData = await screenTextExtractor.extract(
      mode: ExtractMode.screenSelection,
    );

    await _windowShow();
    await Future.delayed(const Duration(milliseconds: 10));

    _handleTextChanged(extractedData?.text, isRequery: true);
  }

  Future<void> _handleExtractTextFromScreenCapture() async {
    setState(() {
      _querySubmitted = false;
      _text = '';
      _textDetectedLanguage = null;
      _capturedData = null;
      _isTextDetecting = false;
      _translationResultList = [];
    });
    _textEditingController.clear();
    _focusNode.unfocus();

    await _windowHide();

    String? imagePath;
    if (!UniPlatform.isWeb) {
      Directory userDataDirectory = await getUserDataDirectory();
      int timestamp = DateTime.now().millisecondsSinceEpoch;
      String fileName = 'Screenshot-$timestamp.png';
      imagePath = '${userDataDirectory.path}/Screenshots/$fileName';
    }
    _capturedData = await ScreenCapturer.instance.capture(
      imagePath: imagePath,
    );

    await _windowShow();

    if (_capturedData == null) {
      BotToast.showText(
        text: LocaleKeys.app_home_msg_capture_screen_area_canceled.tr(),
        align: Alignment.center,
      );
      setState(() {});
      return;
    } else {
      try {
        _isTextDetecting = true;
        setState(() {});
        String base64Image = base64Encode(_capturedData!.imageBytes!);
        await Future.delayed(const Duration(milliseconds: 10));
        RecognizeTextResponse recognizeTextResponse = await sharedOcrClient
            .use(_configuration.defaultOcrEngineId ?? '')
            .recognizeText(
              RecognizeTextRequest(
                imagePath: _capturedData?.imagePath,
                base64Image: base64Image,
              ),
            );
        _isTextDetecting = false;
        setState(() {});
        if (_configuration.autoCopyDetectedText) {
          Clipboard.setData(ClipboardData(text: recognizeTextResponse.text));
        }
        _handleTextChanged(recognizeTextResponse.text, isRequery: true);
      } catch (error) {
        String errorMessage = error.toString();
        if (error is UniOcrClientError) {
          errorMessage = error.message;
        }
        _isTextDetecting = false;
        setState(() {});
        BotToast.showText(
          text: errorMessage,
          align: Alignment.center,
        );
      }
    }
  }

  Future<void> _handleExtractTextFromClipboard() async {
    bool windowIsVisible = await windowManager.isVisible();
    if (!windowIsVisible) {
      await _windowShow();
      await Future.delayed(const Duration(milliseconds: 10));
    }

    ExtractedData? extractedData = await screenTextExtractor.extract(
      mode: ExtractMode.clipboard,
    );
    _handleTextChanged(extractedData?.text, isRequery: true);
  }

  void _handleButtonTappedClear() {
    setState(() {
      _querySubmitted = false;
      _text = '';
      _textDetectedLanguage = null;
      _capturedData = null;
      _isTextDetecting = false;
      _translationResultList = [];
    });
    _textEditingController.clear();
    _focusNode.requestFocus();
  }

  Future<void> _handleButtonTappedTrans() async {
    if (_text.isEmpty) {
      BotToast.showText(
        text: LocaleKeys.app_home_msg_please_enter_word_or_text.tr(),
        align: Alignment.center,
      );
      _focusNode.requestFocus();
      return;
    }
    await _queryData();
  }

  Widget _buildBannersView(BuildContext context) {
    bool isFoundNewVersion = _latestVersion != null &&
        _latestVersion!.buildNumber > sharedEnv.appBuildNumber;

    bool isNoAllowedAllAccess =
        !(_isAllowedScreenCaptureAccess && _isAllowedScreenSelectionAccess);

    return Container(
      key: _bannersViewKey,
      width: double.infinity,
      margin: EdgeInsets.only(
        bottom: (isFoundNewVersion || isNoAllowedAllAccess) ? 12 : 0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isFoundNewVersion)
            NewVersionFoundBanner(
              latestVersion: _latestVersion!,
            ),
          if (isNoAllowedAllAccess)
            LimitedFunctionalityBanner(
              isAllowedScreenCaptureAccess: _isAllowedScreenCaptureAccess,
              isAllowedScreenSelectionAccess: _isAllowedScreenSelectionAccess,
              onTappedRecheckIsAllowedAllAccess: () async {
                _isAllowedScreenCaptureAccess =
                    await ScreenCapturer.instance.isAccessAllowed();
                _isAllowedScreenSelectionAccess =
                    await screenTextExtractor.isAccessAllowed();

                setState(() {});

                if (_isAllowedScreenCaptureAccess &&
                    _isAllowedScreenSelectionAccess) {
                  BotToast.showText(
                    text: LocaleKeys
                        .app_home_limited_banner_msg_all_access_allowed
                        .tr(),
                    align: Alignment.center,
                  );
                } else {
                  BotToast.showText(
                    text: LocaleKeys
                        .app_home_limited_banner_msg_all_access_not_allowed
                        .tr(),
                    align: Alignment.center,
                  );
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _buildInputView(BuildContext context) {
    return SizedBox(
      key: _inputViewKey,
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TranslationInputView(
            focusNode: _focusNode,
            controller: _textEditingController,
            onChanged: (newValue) => _handleTextChanged(newValue),
            capturedData: _capturedData,
            isTextDetecting: _isTextDetecting,
            translationMode: _configuration.translationMode,
            onTranslationModeChanged: (newTranslationMode) {
              _configuration.translationMode = newTranslationMode;
            },
            inputSetting: _configuration.inputSetting,
            onClickExtractTextFromScreenCapture:
                _handleExtractTextFromScreenCapture,
            onClickExtractTextFromClipboard: _handleExtractTextFromClipboard,
            onButtonTappedClear: _handleButtonTappedClear,
            onButtonTappedTrans: _handleButtonTappedTrans,
          ),
          TranslationTargetSelectView(
            translationMode: _configuration.translationMode,
            isShowSourceLanguageSelector: _isShowSourceLanguageSelector,
            isShowTargetLanguageSelector: _isShowTargetLanguageSelector,
            onToggleShowSourceLanguageSelector: (newValue) {
              setState(() {
                _isShowSourceLanguageSelector = newValue;
                _isShowTargetLanguageSelector = false;
              });
            },
            onToggleShowTargetLanguageSelector: (newValue) {
              setState(() {
                _isShowSourceLanguageSelector = false;
                _isShowTargetLanguageSelector = newValue;
              });
            },
            sourceLanguage: _sourceLanguage,
            targetLanguage: _targetLanguage,
            onChanged: (newSourceLanguage, newTargetLanguage) {
              setState(() {
                _isShowSourceLanguageSelector = false;
                _isShowTargetLanguageSelector = false;
                _sourceLanguage = newSourceLanguage;
                _targetLanguage = newTargetLanguage;
              });
              if (_text.isNotEmpty) {
                _handleButtonTappedTrans();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildResultsView(BuildContext context) {
    return TranslationResultsView(
      viewKey: _resultsViewKey,
      controller: _scrollController,
      translationMode: _configuration.translationMode,
      querySubmitted: _querySubmitted,
      text: _text,
      textDetectedLanguage: _textDetectedLanguage,
      translationResultList: _translationResultList,
      onTextTapped: (word) {
        _handleTextChanged(word, isRequery: true);
      },
    );
  }

  Widget _buildBody(BuildContext context) {
    return SizedBox(
      height: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          _buildBannersView(context),
          _buildInputView(context),
          _buildResultsView(context),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(34),
      child: Container(
        padding: const EdgeInsets.only(left: 8, right: 8, top: 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const ToolbarItemAlwaysOnTop(),
            Expanded(child: Container()),
            const ToolbarItemSettings(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _windowResize());
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: _buildAppBar(context),
      body: _buildBody(context),
    );
  }

  @override
  Future<void> onProtocolUrlReceived(String url) async {
    Uri uri = Uri.parse(url);
    if (uri.scheme != 'biyiapp') return;

    if (uri.authority == 'translate') {
      if (_text.isNotEmpty) _handleButtonTappedClear();
      String? text = uri.queryParameters['text'];
      if (text != null && text.isNotEmpty) {
        _handleTextChanged(text, isRequery: true);
      }
    }
    await _windowShow();
  }

  @override
  Future<void> onShortcutKeyDownShowOrHide() async {
    bool isVisible = await windowManager.isVisible();
    if (isVisible) {
      _windowHide();
    } else {
      _windowShow();
    }
  }

  @override
  Future<void> onShortcutKeyDownHide() async {
    _windowHide();
  }

  @override
  void onShortcutKeyDownExtractFromScreenSelection() {
    _handleExtractTextFromScreenSelection();
  }

  @override
  void onShortcutKeyDownExtractFromScreenCapture() {
    _handleExtractTextFromScreenCapture();
  }

  @override
  void onShortcutKeyDownExtractFromClipboard() {
    _handleExtractTextFromClipboard();
  }

  @override
  void onShortcutKeyDownSubmitWithMateEnter() {
    if (_configuration.inputSetting != kInputSettingSubmitWithMetaEnter) {
      return;
    }
    _handleButtonTappedTrans();
  }

  @override
  Future<void> onShortcutKeyDownTranslateInputContent() async {
    await keyPressSimulator.simulateKeyPress(
      key: LogicalKeyboardKey.keyA,
      modifiers: [
        UniPlatform.isMacOS
            ? ModifierKey.metaModifier
            : ModifierKey.controlModifier,
      ],
    );
    await keyPressSimulator.simulateKeyPress(
      key: LogicalKeyboardKey.keyA,
      modifiers: [
        UniPlatform.isMacOS
            ? ModifierKey.metaModifier
            : ModifierKey.controlModifier,
      ],
      keyDown: false,
    );

    try {
      ExtractedData? extractedData = await screenTextExtractor.extract(
        mode: ExtractMode.screenSelection,
      );

      if ((extractedData?.text ?? '').isEmpty) {
        throw Exception('Extracted text is empty');
      }

      TranslateResponse translateResponse = await translateClient
          .use(_configuration.defaultTranslateEngineId!)
          .translate(
            TranslateRequest(
              text: extractedData?.text ?? '',
              sourceLanguage: kLanguageZH,
              targetLanguage: kLanguageEN,
            ),
          );

      TextTranslation? textTranslation =
          (translateResponse.translations ?? []).firstOrNull;

      if (textTranslation != null) {
        Clipboard.setData(ClipboardData(text: textTranslation.text));
      }
    } catch (error) {
      return;
    }

    await keyPressSimulator.simulateKeyPress(
      key: LogicalKeyboardKey.keyA,
      modifiers: [
        UniPlatform.isMacOS
            ? ModifierKey.metaModifier
            : ModifierKey.controlModifier,
      ],
    );
    await keyPressSimulator.simulateKeyPress(
      key: LogicalKeyboardKey.keyA,
      modifiers: [
        UniPlatform.isMacOS
            ? ModifierKey.metaModifier
            : ModifierKey.controlModifier,
      ],
      keyDown: false,
    );
    await keyPressSimulator.simulateKeyPress(
      key: LogicalKeyboardKey.keyV,
      modifiers: [
        UniPlatform.isMacOS
            ? ModifierKey.metaModifier
            : ModifierKey.controlModifier,
      ],
    );
    await keyPressSimulator.simulateKeyPress(
      key: LogicalKeyboardKey.keyV,
      modifiers: [
        UniPlatform.isMacOS
            ? ModifierKey.metaModifier
            : ModifierKey.controlModifier,
      ],
      keyDown: false,
    );
  }

  @override
  Future<void> onTrayIconMouseDown() async {
    _windowShow(isShowBelowTray: true);
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  Future<void> onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case kMenuItemKeyShow:
        await Future.delayed(const Duration(milliseconds: 300));
        await _windowShow();
        break;
      case kMenuItemKeyQuickStartGuide:
        await launchUrlString('${sharedEnv.webUrl}/docs');
        break;
      case kMenuSubItemKeyJoinDiscord:
        await launchUrlString('https://discord.gg/yRF62CKza8');
        break;
      case kMenuSubItemKeyJoinQQGroup:
        await launchUrlString('https://jq.qq.com/?_wv=1027&k=vYQ5jW7y');
        break;
      case kMenuItemKeyQuitApp:
        await trayManager.destroy();
        exit(0);
    }
  }

  @override
  Future<void> onWindowFocus() async {
    _focusNode.requestFocus();
  }

  @override
  Future<void> onWindowBlur() async {
    _focusNode.unfocus();
    bool isAlwaysOnTop = await windowManager.isAlwaysOnTop();
    if (!isAlwaysOnTop) {
      windowManager.hide();
    }
  }

  @override
  Future<void> onWindowMove() async {
    _lastShownPosition = await windowManager.getPosition();
  }
}
