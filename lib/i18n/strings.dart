/// Master list of every translatable string in the app. Both [StringsFr]
/// and [StringsEn] implement this contract — adding a new label means
/// adding a getter here and filling it in both subclasses.
abstract class Strings {
  // ---- Generic ----
  String get appName; // typically not translated
  String get yes;
  String get no;

  // ---- Home ----
  String get playSolo;
  String get battleRoyale;
  String get settings;
  String get bestLabel;
  String comingSoon(String mode);
  String get backendNotConfigured;
  String get editName;
  String get save;
  String get pseudoLabel;

  // ---- Settings ----
  String get audioSection;
  String get gameSection;
  String get languageSection;
  String get music;
  String get sfx;
  String get tutorialLabel;
  String get tutorialDesc;

  // ---- Tutorial overlay ----
  String tutorialStep(int n);
  String get tutorialHold;
  String get tutorialHoldDesc;
  String get tutorialAim;
  String get tutorialAimDesc;
  String get tutorialRelease;
  String get tutorialReleaseDesc;
  String get ready;
  String get next;
  String get back;
  String get dontShowAgain;

  // ---- Solo death overlay ----
  String get gameOver;
  String get newRecord;
  String get recordBeaten;
  String distanceFromRecord(int delta);
  String get replay;
  String get menu;
  String get scoreLabel;

  // ---- Lobby ----
  String get matchmakingTitle;
  String get connecting;
  String get searchingPlayers;
  String get launching;
  String get matchStarted;
  String get matchEnded;
  String get matchClosed;
  String get errorTitle;
  String get waitingSlot;
  String get searchingSlot;
  String get you;
  String get bot;
  String get cancel;
  /// Lobby-specific replacement for [cancel]: once matchmaking is past
  /// the cancellation window, the button still exists (greyed) but its
  /// label flips to a more honest "leave" verb.
  String get leaveLobby;
  String get matchReadyPlaceholder;

  // ---- BR result ----
  String get youFell;
  String position(int rank, int total);
  String survivors(int n);
  String get staySpectator;
  String get quit;
  String get victory;
  String get matchOverTitle;
  String get youWin;
  String winnerWins(String name);
  String get backToMenu;
  String get pointsShort;
  String get replayBattleRoyale;
  String get winnerLabel;
  String get ranking;
  String get aliveLabel;
  String get spectatorLabel;
  // ---- BR kill feed ----
  String feedDied(String name);
  String feedKilled(String killer, String victim);
  String feedLead(String name);

  // ---- Recovery code ----
  String get recoveryCodeLabel;
  String get recoveryCodeHelp;
  String get copyCode;
  String get codeCopied;
  String get restoreProfile;
  String get restoreProfileTitle;
  String get restoreProfileDesc;
  String get pasteCodeHint;
  String get restoreCta;
  String get restoreSuccess;
  String get restoreInvalidCode;
  String get restoreNotFound;
}
