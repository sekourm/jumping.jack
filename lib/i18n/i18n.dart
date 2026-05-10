import 'package:flutter/foundation.dart';

import '../services/preferences.dart';
import 'strings.dart';
import 'strings_en.dart';
import 'strings_fr.dart';

enum AppLocale { fr, en }

/// Singleton holding the active locale + the matching [Strings] instance.
/// Listeners (typically the root `JumpingJackApp`) rebuild when [setLocale]
/// is called so every `I18n.t.xxx` access resolves to the new language.
class I18n extends ChangeNotifier {
  I18n._();
  static final I18n instance = I18n._();

  AppLocale _locale = AppLocale.fr;
  static const _fr = StringsFr();
  static const _en = StringsEn();

  AppLocale get locale => _locale;
  Strings get strings => _locale == AppLocale.fr ? _fr : _en;

  /// Convenience static accessor: `I18n.t.playSolo`.
  static Strings get t => instance.strings;

  /// Loads the persisted choice (or defaults to French). Should be called
  /// once at boot, after `Preferences.init`.
  void load() {
    _locale = Preferences.locale;
  }

  void setLocale(AppLocale loc) {
    if (_locale == loc) return;
    _locale = loc;
    Preferences.locale = loc;
    notifyListeners();
  }
}
