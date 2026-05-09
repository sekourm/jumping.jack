import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const JumpingJackApp());
}

class JumpingJackApp extends StatelessWidget {
  const JumpingJackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jumping Jack',
      debugShowCheckedModeBanner: false,
      home: GameWidget(game: JumpingJackGame()),
    );
  }
}

class JumpingJackGame extends FlameGame with TapCallbacks {
  static const double _gravity = 1800;
  static const double _jumpVelocity = -700;

  late final Player _player;
  late final Ground _ground;

  @override
  Color backgroundColor() => const Color(0xFF1E2A38);

  @override
  Future<void> onLoad() async {
    _ground = Ground()..size = Vector2(size.x, 24);
    _ground.position = Vector2(0, size.y - _ground.size.y);
    add(_ground);

    _player = Player(groundY: _ground.position.y);
    add(_player);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isMounted) {
      _ground.size = Vector2(size.x, 24);
      _ground.position = Vector2(0, size.y - _ground.size.y);
      _player.groundY = _ground.position.y;
    }
  }

  @override
  void onTapDown(TapDownEvent event) {
    _player.jump();
  }
}

class Player extends RectangleComponent {
  Player({required this.groundY})
      : super(
          size: Vector2(48, 48),
          paint: Paint()..color = const Color(0xFFFFC857),
        );

  double groundY;
  double _velocityY = 0;
  bool get _isGrounded => y + size.y >= groundY;

  @override
  Future<void> onLoad() async {
    position = Vector2(80, groundY - size.y);
  }

  void jump() {
    if (_isGrounded) {
      _velocityY = JumpingJackGame._jumpVelocity;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _velocityY += JumpingJackGame._gravity * dt;
    y += _velocityY * dt;

    if (y + size.y >= groundY) {
      y = groundY - size.y;
      _velocityY = 0;
    }
  }
}

class Ground extends RectangleComponent {
  Ground()
      : super(
          paint: Paint()..color = const Color(0xFF3D5A6C),
        );
}
