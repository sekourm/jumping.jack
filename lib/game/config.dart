import 'package:flutter/painting.dart';

class GameConfig {
  // Physics
  static const double gravity = 1800;
  static const double maxChargeMs = 400;
  static const double minJumpPower = 280;
  static const double maxJumpPower = 1100;

  // Sizes
  static const double playerSize = 32;
  static const double platformHeight = 14;
  static const double platformWidth = playerSize * 2; // fixed: 2x player width

  // Variety
  static const int firstSafePlatforms = 6; // first N spawns are always standard
  // Spawn weights post-safe-zone (sum doesn't need to equal 1, it's normalized).
  static const double weightStandard = 55;
  static const double weightMoving = 28;
  static const double weightBouncy = 17;

  // Moving platforms
  static const double movingPlatformRange = 70; // px L-R amplitude
  static const double movingPlatformSpeed = 1.6; // rad/s

  // Bouncy platforms
  static const double bouncyJumpPower = 950; // straight-up auto-launch

  // Combo
  static const double comboWindow = 1.5; // seconds grounded before combo expires
  static const double comboMultiplierStep = 0.15; // each chained jump
  static const double comboMultiplierMax = 2.5;
  static const int comboMinDisplay = 2; // start showing badge from x2

  // Trajectory visibility (skill ramp)
  static const double trajectoryFullScoreMax = 1000; // full visible up to this
  static const double trajectoryHiddenScore = 2000; // invisible at/after this

  // Pickups — paced + balanced. Spawned between consecutive platforms.
  // After spawning a pickup, [pickupMinPlatformsBetween] platforms must pass
  // before another can spawn. This keeps them spread out along the route.
  static const int pickupMinPlatformsBetween = 4;
  static const double pickupSpawnChance = 0.28; // per eligible platform
  // When a pickup spawns, the type is rolled with these ratios (sum to 1):
  static const double pickupRatioStar = 0.62;     // most common
  static const double pickupRatioCrystal = 0.18;  // occasional
  static const double pickupRatioHeart = 0.08;    // rare
  static const double pickupRatioTeleport = 0.06; // very rare (save-up)
  static const double pickupRatioVision = 0.06;   // restores trajectory dots
  static const int visionBoostJumps = 3;          // how many jumps the boost covers
  static const double pickupRadius = 11; // collision radius
  static const double pickupOffsetMax = 55; // horizontal off-path spawn

  // Pickup effects
  static const int starBaseValue = 25;
  static const double slowTimeMultiplier = 0.45;
  static const double slowTimeDuration = 3.0;
  static const double comboFreezeDuration = 3.0;

  // Procedural spacing — fewer platforms = more punitive
  // Phase 1: first [platformEasyCount] platforms have a fixed [platformBaseSpacingY].
  // Phase 2: variation ramps up linearly over [platformVariationRamp] more platforms.
  // Phase 3: full variation, spacing in [base, base + maxExtra].
  static const double platformBaseSpacingY = 90;
  static const double platformMaxExtraSpacingY = 60;
  static const int platformEasyCount = 8;
  static const int platformVariationRamp = 20;

  // Game feel
  static const double shakeOnLandDuration = 0.18; // seconds
  static const double shakeOnLandAmplitude = 6; // px at full intensity
  static const double shakePowerScale = 0.012; // shake amplitude ∝ landing speed
  static const double squashLerpRate = 16; // higher = snappier squash transitions

  // Cracks are purely visual feedback — they grow from impact (landing) and
  // proximity (how close the platform is to the screen bottom). Platforms
  // never explode from cracks alone; they only explode on release or when
  // the camera catches them at the screen bottom.

  // Reachability safety factor for procedural placement.
  // 1.0 = use full max-jump envelope (some platforms require near-perfect aim),
  // 0.7 = 70% of the envelope (always reachable with some margin),
  // 0.5 = very forgiving.
  static const double platformReachabilitySafety = 0.7;

  // Camera — the player appears at this fraction of the screen height from the top.
  // 0.75 = lower-third, Doodle Jump style: the player stays near the bottom of
  // the screen so most of the visible space shows what's coming above.
  static const double cameraPlayerScreenRatio = 0.75;

  // The camera rises continuously and never follows the player.
  // The comfort line is at [cameraPlayerScreenRatio] of the screen height.
  // - At the comfort line: base speed (sweet spot, the player should aim here).
  // - Above the comfort line (player too high): speed ramps up toward base +
  //   bonus as they approach the top — punishes overshooting.
  // - Below the comfort line (player too low): speed ramps up toward base +
  //   bonus as they approach the bottom — panic / snowball death.
  static const double cameraRiseSpeed = 130; // base pixels per second (calm zone)
  static const double cameraRiseSpeedBonus = 150; // extra px/s when player is high

  // Difficulty ramp at game start: the camera speed is multiplied by
  // [cameraRiseStartMultiplier] before the first platform is reached and ramps
  // linearly back to 1.0 over the next [cameraRiseRampPlatforms] platforms.
  static const double cameraRiseStartMultiplier = 0.5;
  static const int cameraRiseRampPlatforms = 5;

  // Timer pressure (disabled for now — flip to true to re-enable)
  static const bool timerEnabled = false;
  static const double timerInitialSeconds = 5.0;
  static const int timerStartsAfterJumps = 3;
  static const double timerWarnThreshold = 1.5;

  // Colors
  static const Color bgColor = Color(0xFF101820);
  static const Color platformColor = Color(0xFF3D5A6C);
  static const Color platformEdgeColor = Color(0xFF6B8FA8);
  static const Color playerColor = Color(0xFFFFC857);
  static const Color trajectoryColor = Color(0xCCFFFFFF);
  static const Color gaugeBgColor = Color(0x33FFFFFF);
  static const Color gaugeFgColor = Color(0xFFFF5E5B);
  static const Color timerColor = Color(0xFFFFC857);
  static const Color timerWarnColor = Color(0xFFFF5E5B);
  static const Color textColor = Color(0xFFFFFFFF);
  static const Color textMuted = Color(0xB3FFFFFF);
}
