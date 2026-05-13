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
  /// Title of the stats dialog opened from the home screen's trophy chip.
  String get statsTitle;
  /// Label of the "best solo score" row in the stats dialog.
  String get statsBestScore;
  /// Subtitle for the best-score row — explains where it comes from.
  String get statsBestScoreDesc;
  /// Label of the "BR wins" row in the stats dialog.
  String get statsBrWins;
  /// Subtitle for the BR-wins row — explains where it comes from.
  String get statsBrWinsDesc;
  /// Placeholder value shown in the stats dialog when the player has no
  /// recorded score yet.
  String get statsNoScore;
  /// Title of the world ranking dialog opened from the home screen's
  /// podium chip.
  String get rankingTitle;
  /// Label of the Battle Royale tab inside the ranking dialog.
  String get rankingTabBr;
  /// Label of the Best Score tab inside the ranking dialog.
  String get rankingTabScore;
  /// Empty-state message shown inside both ranking tabs until the
  /// global leaderboard data is wired up.
  String get rankingComingSoon;
  /// Tooltip / accessibility label for the world ranking button.
  String get rankingTooltip;
  /// Inline error shown in the pseudo edit dialog when the chosen
  /// name is already taken by another player.
  String get nameErrorTaken;
  /// Inline error when the name matches the server-side blacklist.
  String get nameErrorForbidden;
  /// Inline error when the name is too short (<2 chars after trim).
  String get nameErrorTooShort;
  /// Inline error when the name is empty after trim.
  String get nameErrorEmpty;
  /// Inline error for any other failure (network, server side).
  String get nameErrorGeneric;
  /// Inline error shown when the cloud profile for this device has a
  /// recovery code different from the local one — typically after a
  /// reinstall that wiped prefs but kept the IDFV-derived player_id.
  String get nameErrorRecoveryMismatch;
  /// Underlined CTA next to "Restore profile" inside the pseudo edit
  /// dialog. Opens the reset confirmation.
  String get resetProfileLabel;
  /// Title of the reset-profile confirmation dialog.
  String get resetProfileTitle;
  /// Body text of the reset confirmation, explaining what gets wiped.
  String get resetProfileDesc;
  /// Confirm button label inside the reset dialog.
  String get resetProfileCta;
  /// Snackbar shown after the profile has been reset.
  String get resetProfileSuccess;

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
