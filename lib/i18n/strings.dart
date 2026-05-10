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
  String get you;
  String get bot;
  String get cancel;
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
}
