enum DeathReason {
  offscreenLeft,
  offscreenRight,
  offscreenBottom,
  timeout,
  crushed,
}

extension DeathReasonLabel on DeathReason {
  String get label {
    switch (this) {
      case DeathReason.offscreenLeft:
        return 'Hors écran (gauche)';
      case DeathReason.offscreenRight:
        return 'Hors écran (droite)';
      case DeathReason.offscreenBottom:
        return 'Chute';
      case DeathReason.timeout:
        return 'Trop lent';
      case DeathReason.crushed:
        return 'Écrasé';
    }
  }
}
