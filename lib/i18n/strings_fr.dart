import 'strings.dart';

class StringsFr implements Strings {
  const StringsFr();

  @override
  String get appName => 'JUMPING JACK';
  @override
  String get yes => 'Oui';
  @override
  String get no => 'Non';

  // Home
  @override
  String get playSolo => 'MODE SOLO';
  @override
  String get battleRoyale => 'BATTLE ROYALE';
  @override
  String get settings => 'Paramètres';
  @override
  String get bestLabel => 'MON MEILLEUR SCORE';
  @override
  String comingSoon(String mode) => '$mode — bientôt disponible';
  @override
  String get backendNotConfigured => 'BATTLE ROYALE — backend non configuré';
  @override
  String get editName => 'MODIFIER LE PSEUDO';
  @override
  String get save => 'ENREGISTRER';
  @override
  String get pseudoLabel => 'PSEUDO';

  // Settings
  @override
  String get audioSection => 'AUDIO';
  @override
  String get gameSection => 'JEU';
  @override
  String get languageSection => 'LANGUE';
  @override
  String get music => 'MUSIQUE';
  @override
  String get sfx => 'EFFETS';
  @override
  String get tutorialLabel => 'TUTORIEL';
  @override
  String get tutorialDesc => 'Afficher au début de chaque partie';

  // Tutorial
  @override
  String tutorialStep(int n) => '$n / 3';
  @override
  String get tutorialHold => 'MAINTIENS';
  @override
  String get tutorialHoldDesc => 'Appuie et garde ton doigt enfoncé';
  @override
  String get tutorialAim => 'VISE';
  @override
  String get tutorialAimDesc => 'Glisse ton doigt vers la direction du saut';
  @override
  String get tutorialRelease => 'RELÂCHE';
  @override
  String get tutorialReleaseDesc => 'Le saut part dans la direction visée';
  @override
  String get ready => 'JE SUIS PRÊT';
  @override
  String get next => 'SUIVANT';
  @override
  String get back => 'RETOUR';
  @override
  String get dontShowAgain => "T'inquiète j'ai capté";
  @override
  String tutorialCoaching(int done, int target) =>
      'Saute sur $target plateformes  ·  $done/$target';
  @override
  String get tutorialRequiredForBr =>
      'Termine le tutoriel solo pour débloquer le Battle Royale';
  @override
  List<String> get tutorialIntroBubbles => const [
        "Salut, moi c'est Jack !",
        'Maintiens ton doigt pour charger ton saut.',
        'Vise dans la direction, puis relâche pour t\'envoler.',
        'Atterris sur 3 plateformes pour finir le tuto.',
      ];
  @override
  String get tutorialTapToContinue => 'Touche pour continuer';
  @override
  String get tutorialOutroBubble =>
      "Bien joué ! Place aux choses sérieuses…";
  @override
  String get tutorialTapToStart => 'Touche pour commencer';
  @override
  String get helpTitle => 'AIDE';
  @override
  String get helpReplayTutorial => 'Rejouer le tutoriel';
  @override
  String get helpReplayTutorialDesc =>
      'Relance la séquence d\'apprentissage avec Jack au prochain solo.';
  @override
  String get statsTitle => 'MON JACK';
  @override
  String get statsBestScore => 'Meilleur score';
  @override
  String get statsBestScoreDesc =>
      'Score le plus haut atteint en partie solo.';
  @override
  String get statsBrWins => 'Victoires Battle Royale';
  @override
  String get statsBrWinsDesc =>
      'Nombre de Top 1 obtenus en Battle Royale.';
  @override
  String get statsNoScore => 'Aucun score';
  @override
  String get rankingTitle => 'CLASSEMENT';
  @override
  String get rankingTabBr => 'BATTLE ROYALE';
  @override
  String get rankingTabScore => 'SCORE';
  @override
  String get rankingComingSoon => 'Classement bientôt disponible';
  @override
  String get rankingTooltip => 'Classement mondial';
  @override
  String get nameErrorTaken => 'Ce pseudo est déjà pris';
  @override
  String get nameErrorForbidden => 'Ce pseudo n\'est pas autorisé';
  @override
  String get nameErrorTooShort => 'Pseudo trop court (2 caractères min.)';
  @override
  String get nameErrorEmpty => 'Pseudo requis';
  @override
  String get nameErrorGeneric => 'Erreur, réessaie';
  @override
  String get nameErrorRecoveryMismatch =>
      'Profil verrouillé sur le cloud. Utilise ton code de récupération '
      'pour le restaurer, ou réinitialise pour repartir à zéro.';
  @override
  String get resetProfileLabel => 'Réinitialiser le profil';
  @override
  String get resetProfileTitle => 'RÉINITIALISER LE PROFIL';
  @override
  String get resetProfileDesc =>
      'Crée un nouveau profil sur ce device. Tes scores et victoires '
      'BR seront remis à zéro. L\'ancien profil reste accessible '
      'avec son code de récupération.';
  @override
  String get resetProfileCta => 'Réinitialiser';
  @override
  String get resetProfileSuccess => 'Nouveau profil créé';

  // Death overlay
  @override
  String get gameOver => 'TERMINÉ';
  @override
  String get newRecord => 'NOUVEAU RECORD';
  @override
  String get recordBeaten => 'RECORD BATTU';
  @override
  String distanceFromRecord(int delta) => 'À $delta DU RECORD';
  @override
  String get replay => 'REJOUER';
  @override
  String get menu => 'MENU';
  @override
  String get scoreLabel => 'SCORE';

  // Lobby
  @override
  String get matchmakingTitle => 'BATTLE ROYALE';
  @override
  String get connecting => 'CONNEXION';
  @override
  String get searchingPlayers => 'RECHERCHE DE JOUEURS';
  @override
  String get launching => 'LANCEMENT';
  @override
  String get matchStarted => 'PARTIE LANCÉE';
  @override
  String get matchEnded => 'PARTIE TERMINÉE';
  @override
  String get matchClosed => 'FERMÉ';
  @override
  String get errorTitle => 'ERREUR';
  @override
  String get waitingSlot => 'EN ATTENTE…';
  @override
  String get searchingSlot => 'RECHERCHE…';
  @override
  String get you => 'TOI';
  @override
  String get bot => 'BOT';
  @override
  String get cancel => 'ANNULER';
  @override
  String get leaveLobby => 'QUITTER';
  @override
  String get matchReadyPlaceholder =>
      'Match prêt — gameplay multijoueur en phase 2';

  // BR result
  @override
  String get youFell => 'TU ES TOMBÉ';
  @override
  String position(int rank, int total) => 'POSITION  $rank / $total';
  @override
  String survivors(int n) => '$n survivant${n > 1 ? 's' : ''}';
  @override
  String get staySpectator => 'RESTER SPECTATEUR';
  @override
  String get quit => 'QUITTER';
  @override
  String get victory => 'TOP 1';
  @override
  String get matchOverTitle => 'TERMINÉ';
  @override
  String get youWin => 'TU GAGNES';
  @override
  String winnerWins(String name) => '$name  GAGNE';
  @override
  String get backToMenu => 'RETOUR AU MENU';
  @override
  String get pointsShort => 'pts';
  @override
  String get replayBattleRoyale => 'NOUVELLE PARTIE';
  @override
  String get winnerLabel => 'TOP 1';
  @override
  String get ranking => 'CLASSEMENT';
  @override
  String get aliveLabel => 'VIVANTS';
  @override
  String get spectatorLabel => 'SPECTATEUR';
  @override
  String feedDied(String name) => '$name est mort';
  @override
  String feedKilled(String killer, String victim) =>
      '$killer a tué $victim';
  @override
  String feedLead(String name) => '$name prend la tête';

  @override
  String get recoveryCodeLabel => 'CODE DE SAUVEGARDE';
  @override
  String get recoveryCodeHelp =>
      'Note ce code. Il te permet de retrouver ton profil sur un autre navigateur ou après une réinstallation.';
  @override
  String get copyCode => 'COPIER';
  @override
  String get codeCopied => 'CODE COPIÉ';
  @override
  String get restoreProfile => 'RESTAURER UN PROFIL';
  @override
  String get restoreProfileTitle => 'RESTAURER UN PROFIL';
  @override
  String get restoreProfileDesc =>
      'Colle ton code de sauvegarde pour récupérer ton pseudo, ton meilleur score et tes victoires BR.';
  @override
  String get pasteCodeHint => 'JJ-XXXX-XXXX';
  @override
  String get restoreCta => 'RESTAURER';
  @override
  String get restoreSuccess => 'PROFIL RESTAURÉ';
  @override
  String get restoreInvalidCode => 'CODE INVALIDE';
  @override
  String get restoreNotFound => 'AUCUN PROFIL POUR CE CODE';
}
