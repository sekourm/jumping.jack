import 'strings.dart';

class StringsEn implements Strings {
  const StringsEn();

  @override
  String get appName => 'JUMPING JACK';
  @override
  String get yes => 'Yes';
  @override
  String get no => 'No';

  // Home
  @override
  String get playSolo => 'SOLO MODE';
  @override
  String get battleRoyale => 'BATTLE ROYALE';
  @override
  String get settings => 'Settings';
  @override
  String get bestLabel => 'MY BEST SCORE';
  @override
  String comingSoon(String mode) => '$mode — coming soon';
  @override
  String get backendNotConfigured => 'BATTLE ROYALE — backend not configured';
  @override
  String get editName => 'EDIT NICKNAME';
  @override
  String get save => 'SAVE';
  @override
  String get pseudoLabel => 'NICKNAME';

  // Settings
  @override
  String get audioSection => 'AUDIO';
  @override
  String get gameSection => 'GAME';
  @override
  String get languageSection => 'LANGUAGE';
  @override
  String get music => 'MUSIC';
  @override
  String get sfx => 'SFX';
  @override
  String get tutorialLabel => 'TUTORIAL';
  @override
  String get tutorialDesc => 'Show at the start of every game';

  // Tutorial
  @override
  String tutorialStep(int n) => '$n / 3';
  @override
  String get tutorialHold => 'HOLD';
  @override
  String get tutorialHoldDesc => 'Press and keep your finger down';
  @override
  String get tutorialAim => 'AIM';
  @override
  String get tutorialAimDesc => 'Drag your finger toward the jump direction';
  @override
  String get tutorialRelease => 'RELEASE';
  @override
  String get tutorialReleaseDesc => 'The jump fires in the aimed direction';
  @override
  String get ready => "I'M READY";
  @override
  String get next => 'NEXT';
  @override
  String get back => 'BACK';
  @override
  String get dontShowAgain => "No worries, I got it";
  @override
  String tutorialCoaching(int done, int target) =>
      'Land on $target platforms  ·  $done/$target';
  @override
  String get tutorialRequiredForBr =>
      'Finish the solo tutorial to unlock Battle Royale';
  @override
  List<String> get tutorialIntroBubbles => const [
        "Hey there, I'm Jack!",
        'Hold your finger to charge your jump.',
        'Aim in any direction, then release to fly.',
        'Land on 3 platforms to finish the tutorial.',
      ];
  @override
  String get tutorialTapToContinue => 'Tap to continue';
  @override
  String get tutorialOutroBubble =>
      'Nicely done! Now for the real thing…';
  @override
  String get tutorialTapToStart => 'Tap to start';
  @override
  String get helpTitle => 'HELP';
  @override
  String get helpReplayTutorial => 'Replay the tutorial';
  @override
  String get helpReplayTutorialDesc =>
      'Re-runs the learning sequence with Jack on your next solo run.';

  // Death overlay
  @override
  String get gameOver => 'GAME OVER';
  @override
  String get newRecord => 'NEW RECORD';
  @override
  String get recordBeaten => 'RECORD BEATEN';
  @override
  String distanceFromRecord(int delta) => '$delta TO BEAT THE RECORD';
  @override
  String get replay => 'REPLAY';
  @override
  String get menu => 'MENU';
  @override
  String get scoreLabel => 'SCORE';

  // Lobby
  @override
  String get matchmakingTitle => 'BATTLE ROYALE';
  @override
  String get connecting => 'CONNECTING';
  @override
  String get searchingPlayers => 'FINDING PLAYERS';
  @override
  String get launching => 'LAUNCHING';
  @override
  String get matchStarted => 'MATCH STARTED';
  @override
  String get matchEnded => 'MATCH ENDED';
  @override
  String get matchClosed => 'CLOSED';
  @override
  String get errorTitle => 'ERROR';
  @override
  String get waitingSlot => 'WAITING…';
  @override
  String get searchingSlot => 'SEARCHING…';
  @override
  String get you => 'YOU';
  @override
  String get bot => 'BOT';
  @override
  String get cancel => 'CANCEL';
  @override
  String get leaveLobby => 'LEAVE';
  @override
  String get matchReadyPlaceholder =>
      'Match ready — multiplayer gameplay in phase 2';

  // BR result
  @override
  String get youFell => 'YOU FELL';
  @override
  String position(int rank, int total) => 'POSITION  $rank / $total';
  @override
  String survivors(int n) => '$n survivor${n > 1 ? 's' : ''}';
  @override
  String get staySpectator => 'SPECTATE';
  @override
  String get quit => 'QUIT';
  @override
  String get victory => 'TOP 1';
  @override
  String get matchOverTitle => 'GAME OVER';
  @override
  String get youWin => 'YOU WIN';
  @override
  String winnerWins(String name) => '$name  WINS';
  @override
  String get backToMenu => 'BACK TO MENU';
  @override
  String get pointsShort => 'pts';
  @override
  String get replayBattleRoyale => 'NEW MATCH';
  @override
  String get winnerLabel => 'TOP 1';
  @override
  String get ranking => 'RANKING';
  @override
  String get aliveLabel => 'ALIVE';
  @override
  String get spectatorLabel => 'SPECTATOR';
  @override
  String feedDied(String name) => '$name died';
  @override
  String feedKilled(String killer, String victim) =>
      '$killer killed $victim';
  @override
  String feedLead(String name) => '$name takes the lead';

  @override
  String get recoveryCodeLabel => 'RECOVERY CODE';
  @override
  String get recoveryCodeHelp =>
      'Write this code down. Use it to recover your profile on another browser or after a reinstall.';
  @override
  String get copyCode => 'COPY';
  @override
  String get codeCopied => 'CODE COPIED';
  @override
  String get restoreProfile => 'RESTORE PROFILE';
  @override
  String get restoreProfileTitle => 'RESTORE PROFILE';
  @override
  String get restoreProfileDesc =>
      'Paste your recovery code to bring back your nickname, best score and BR wins.';
  @override
  String get pasteCodeHint => 'JJ-XXXX-XXXX';
  @override
  String get restoreCta => 'RESTORE';
  @override
  String get restoreSuccess => 'PROFILE RESTORED';
  @override
  String get restoreInvalidCode => 'INVALID CODE';
  @override
  String get restoreNotFound => 'NO PROFILE FOR THIS CODE';
}
