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
  /// Coaching prompt shown after the user dismisses the explanatory
  /// tutorial slides. Should communicate "land [target] platforms to
  /// finish the tutorial — N/[target] done so far".
  String tutorialCoaching(int done, int target);
  /// Snackbar shown when the user taps the Battle Royale button before
  /// completing the tutorial.
  String get tutorialRequiredForBr;
  /// Sequence of speech-bubble lines spoken by Jack during the intro
  /// phase of the tutorial — one per tap. Implementations should keep
  /// the list ordered (greeting → hold → aim → release → goal) and
  /// short enough to fit a single line on a phone in portrait.
  List<String> get tutorialIntroBubbles;
  /// "Tap to continue" hint shown under the speech bubble.
  String get tutorialTapToContinue;
  /// Celebration line shown after the player nails both coaching jumps,
  /// right before the game restarts on the 3-2-1 countdown. Should
  /// feel like a personal hand-off from Jack: praise + "let's do this
  /// for real now".
  String get tutorialOutroBubble;
  /// Hint shown under the outro bubble — tells the player they have
  /// to tap to launch the real run. Mirrors [tutorialTapToContinue]
  /// in vocabulary but reads as a definitive "go" rather than "next".
  String get tutorialTapToStart;
  /// Title of the help dialog opened from the home screen's "?" icon.
  String get helpTitle;
  /// Label of the "replay the tutorial" CTA inside the help dialog.
  String get helpReplayTutorial;
  /// Subtitle / context line under the replay-tutorial CTA.
  String get helpReplayTutorialDesc;

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
