import 'package:flutter/foundation.dart';

import '../game/config.dart';
import 'death_reason.dart';

enum GameStatus { idle, playing, dead }

class GameState extends ChangeNotifier {
  GameStatus _status = GameStatus.idle;
  int _successfulJumps = 0;
  double _bestHeight = 0;
  double _timerRemaining = 0;
  bool _grounded = true;
  double _chargeProgress = 0;
  bool _charging = false;
  double _dangerLevel = 0; // 0 = safe, 1 = about to die from below
  // Combo
  int _comboCount = 0;
  double _comboTimer = 0; // seconds left while grounded
  double _bonusScore = 0; // accumulated score from combo multipliers + pickups
  // Pickup-driven effects
  double _slowTimeRemaining = 0;
  double _comboFreezeRemaining = 0;
  // Consecutive bouncy-platform chain (drives the trail + score reward)
  int _bouncyChainCount = 0;
  // Pickup that re-enables the trajectory dots for N jumps.
  int _trajectoryBoostJumps = 0;
  DeathReason? _deathReason;
  // Set to true on death when the run beats the persisted best score.
  bool _newBest = false;

  GameStatus get status => _status;
  int get successfulJumps => _successfulJumps;
  /// Same as [successfulJumps] — each successful jump = a new platform reached.
  int get platformsReached => _successfulJumps;
  double get bestHeight => _bestHeight;
  double get timerRemaining => _timerRemaining;
  double get chargeProgress => _chargeProgress;
  bool get charging => _charging;
  double get dangerLevel => _dangerLevel;
  int get comboCount => _comboCount;
  double get comboTimerRemaining => _comboTimer;
  double get slowTimeRemaining => _slowTimeRemaining;
  bool get slowTimeActive => _slowTimeRemaining > 0;

  /// Effective slow-time multiplier on world speed. Equals
  /// [GameConfig.slowTimeMultiplier] while well within the bonus, and
  /// linearly ramps back to 1.0 over the last second so the camera doesn't
  /// snap back to full speed when the bonus ends.
  double get slowFactor {
    if (_slowTimeRemaining <= 0) return 1.0;
    const fadeOut = 1.0; // seconds over which we ramp back to normal
    if (_slowTimeRemaining >= fadeOut) {
      return GameConfig.slowTimeMultiplier;
    }
    final progress = (fadeOut - _slowTimeRemaining) / fadeOut;
    return GameConfig.slowTimeMultiplier +
        (1.0 - GameConfig.slowTimeMultiplier) * progress;
  }
  bool get comboFrozen => _comboFreezeRemaining > 0;
  int get bouncyChainCount => _bouncyChainCount;
  int get trajectoryBoostJumps => _trajectoryBoostJumps;
  bool get newBest => _newBest;
  double get comboMultiplier {
    if (_comboCount <= 1) return 1.0;
    final extra = (_comboCount - 1) * GameConfig.comboMultiplierStep;
    return (1.0 + extra).clamp(1.0, GameConfig.comboMultiplierMax);
  }
  DeathReason? get deathReason => _deathReason;

  bool get timerActive =>
      GameConfig.timerEnabled &&
      _status == GameStatus.playing &&
      _grounded &&
      _successfulJumps >= GameConfig.timerStartsAfterJumps;

  int get score => (_bestHeight + _bonusScore).toInt();

  void start() {
    _status = GameStatus.playing;
    _successfulJumps = 0;
    _bestHeight = 0;
    _timerRemaining = 0;
    _grounded = true;
    _chargeProgress = 0;
    _charging = false;
    _dangerLevel = 0;
    _comboCount = 0;
    _comboTimer = 0;
    _bonusScore = 0;
    _slowTimeRemaining = 0;
    _comboFreezeRemaining = 0;
    _bouncyChainCount = 0;
    _trajectoryBoostJumps = 0;
    _deathReason = null;
    _newBest = false;
    notifyListeners();
  }

  void markNewBest() {
    if (_newBest) return;
    _newBest = true;
    notifyListeners();
  }

  void onJumpStart() {
    _grounded = false;
    _charging = false;
    _chargeProgress = 0;
    notifyListeners();
  }

  void onJumpLanded() {
    _successfulJumps++;
    _grounded = true;
    // Combo: chain only if the previous window hadn't expired.
    if (_comboTimer > 0) {
      _comboCount++;
    } else {
      _comboCount = 1;
    }
    _comboTimer = GameConfig.comboWindow;
    if (GameConfig.timerEnabled &&
        _successfulJumps >= GameConfig.timerStartsAfterJumps) {
      _timerRemaining = GameConfig.timerInitialSeconds;
    }
    notifyListeners();
  }

  /// Adds combo bonus when the player gains height. Returns the bonus added.
  double addComboBonus(double heightGained) {
    if (heightGained <= 0) return 0;
    final bonus = heightGained * (comboMultiplier - 1.0);
    if (bonus > 0) {
      _bonusScore += bonus;
      notifyListeners();
    }
    return bonus;
  }

  /// Flat score bonus from a pickup (already multiplied by combo by caller).
  void addBonus(int amount) {
    if (amount <= 0) return;
    _bonusScore += amount.toDouble();
    notifyListeners();
  }

  /// Grant a boost that re-enables the trajectory dots for [jumps] releases.
  void grantTrajectoryBoost(int jumps) {
    if (jumps <= 0) return;
    _trajectoryBoostJumps += jumps;
    notifyListeners();
  }

  /// Consume one trajectory boost release (no-op if already at zero).
  void consumeTrajectoryBoostJump() {
    if (_trajectoryBoostJumps <= 0) return;
    _trajectoryBoostJumps--;
    notifyListeners();
  }

  void updateBouncyChain(int count) {
    if (count != _bouncyChainCount) {
      _bouncyChainCount = count;
      notifyListeners();
    }
  }

  void activateSlowTime(double seconds) {
    if (seconds <= 0) return;
    if (seconds > _slowTimeRemaining) {
      _slowTimeRemaining = seconds;
      notifyListeners();
    }
  }

  void freezeCombo(double seconds) {
    if (seconds <= 0) return;
    if (seconds > _comboFreezeRemaining) {
      _comboFreezeRemaining = seconds;
      notifyListeners();
    }
  }

  void updateBestHeight(double height) {
    if (height > _bestHeight) {
      _bestHeight = height;
      notifyListeners();
    }
  }

  void updateCharge({required bool charging, required double progress}) {
    _charging = charging;
    _chargeProgress = progress;
    notifyListeners();
  }

  void updateDanger(double level) {
    final clamped = level.clamp(0.0, 1.0);
    if ((clamped - _dangerLevel).abs() < 0.01) return;
    _dangerLevel = clamped;
    notifyListeners();
  }

  void tick(double dt) {
    // Pickup-driven effects always tick down (regardless of grounded).
    var dirty = false;
    if (_slowTimeRemaining > 0) {
      _slowTimeRemaining -= dt;
      if (_slowTimeRemaining < 0) _slowTimeRemaining = 0;
      dirty = true;
    }
    if (_comboFreezeRemaining > 0) {
      _comboFreezeRemaining -= dt;
      if (_comboFreezeRemaining < 0) _comboFreezeRemaining = 0;
      dirty = true;
    }

    // Combo window only ticks while grounded AND not frozen.
    if (_grounded && _comboTimer > 0 && _comboFreezeRemaining <= 0) {
      _comboTimer -= dt;
      if (_comboTimer <= 0) {
        _comboTimer = 0;
        _comboCount = 0;
        dirty = true;
      } else {
        dirty = true;
      }
    }

    if (timerActive) {
      _timerRemaining -= dt;
      if (_timerRemaining <= 0) {
        die(DeathReason.timeout);
        return;
      }
      dirty = true;
    }
    if (dirty) notifyListeners();
  }

  void die(DeathReason reason) {
    if (_status == GameStatus.dead) return;
    _status = GameStatus.dead;
    _deathReason = reason;
    _charging = false;
    _chargeProgress = 0;
    notifyListeners();
  }
}
