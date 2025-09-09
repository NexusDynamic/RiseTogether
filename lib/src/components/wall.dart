import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:rise_together/src/game/rise_together_game.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:rise_together/src/game/rise_together_world.dart';

class Wall extends BodyComponent<RiseTogetherGame<RiseTogetherWorld>>
    with ContactCallbacks {
  final Vector2 _start;
  final Vector2 _end;
  final bool isFatal;
  final bool usePolygon;
  final Image? image;

  @override
  RiseTogetherWorld get world => _world;
  final RiseTogetherWorld _world;

  Wall(
    this._world,
    this._start,
    this._end, {
    this.isFatal = true,
    super.paint,
    this.usePolygon = false,
    this.image,
  });

  @override
  Body createBody() {
    final Shape shape;
    if (usePolygon) {
      final vertices = [
        _start,
        Vector2(_end.x, _start.y),
        _end,
        Vector2(_start.x, _end.y),
      ];
      shape = PolygonShape()..set(vertices);
    } else {
      shape = EdgeShape()..set(_start, _end);
    }

    final fixtureDef = FixtureDef(shape, friction: 0.3);
    final bodyDef = BodyDef(userData: this, position: Vector2.zero());
    return world.createBody(bodyDef)..createFixture(fixtureDef);
  }

  @override
  void renderTree(Canvas canvas) {
    if (image != null) {
      paintImage(
        canvas: canvas,
        rect: Rect.fromLTRB(_start.x, _start.y, _end.x, _end.y),
        image: image!,
        fit: BoxFit.fitWidth,
        alignment: Alignment.topCenter,
      );
    }
    super.renderTree(canvas);
  }

  @override
  Future<void> onLoad() async {
    renderBody = false;
    await super.onLoad();
  }

  @override
  String toString() {
    return 'Wall(start: $_start, end: $_end, isFatal: $isFatal)';
  }
}
