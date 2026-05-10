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
  String tutorialStep(int n) => 'TUTORIEL  —  $n / 3';
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
  String get dontShowAgain => 'Ne plus afficher';

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
  String get you => 'TOI';
  @override
  String get bot => 'BOT';
  @override
  String get cancel => 'ANNULER';
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
  String get victory => 'VICTOIRE !';
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
}
