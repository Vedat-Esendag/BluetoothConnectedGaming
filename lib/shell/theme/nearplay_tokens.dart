import 'package:flutter/widgets.dart';

/// NearPlay's design tokens — the single source of truth for colour, spacing,
/// radius, and type across the shell and every mini-game.
///
/// **The identity is "felt and brass":** the deep green of a pool table, lit by
/// warm brass. NearPlay is played on a phone lying on a table between two
/// people, often in a pub or a living room, so the palette is dark-first by
/// commitment rather than by preference — a bright screen in that setting is
/// glare, and the game's own surface (a green table) is the brightest thing
/// that should be on screen.
///
/// Games read these tokens directly (they are plain values, not a Material
/// theme) so a game's canvas and the shell around it cannot drift apart.
abstract final class NearPlayColors {
  /// The furthest-back surface: the room the table sits in.
  static const Color canvas = Color(0xFF0E1411);

  /// Cards, sheets, and list rows.
  static const Color surface = Color(0xFF17201B);

  /// Raised elements on top of [surface] — dialogs, the connection banner.
  static const Color surfaceRaised = Color(0xFF1F2B24);

  /// Hairlines and dividers.
  static const Color border = Color(0xFF2E3D34);

  /// Primary text on any dark surface.
  static const Color textPrimary = Color(0xFFECF3ED);

  /// Supporting text: subtitles, helper copy.
  static const Color textSecondary = Color(0xFFA3B5A8);

  /// De-emphasised text: timestamps, signal strength, disabled labels.
  static const Color textMuted = Color(0xFF6E8175);

  /// Brass — the primary accent. Actions, focus, the active player.
  static const Color brass = Color(0xFFE0A93B);

  /// A darker brass for pressed states and borders on brass surfaces.
  static const Color brassDeep = Color(0xFFB9832A);

  /// Text and icons placed on top of [brass].
  static const Color onBrass = Color(0xFF19140A);

  /// The playing surface itself.
  static const Color felt = Color(0xFF14552B);

  /// A lighter felt for the table's inner area and highlights.
  static const Color feltLight = Color(0xFF1B7A3E);

  /// Pocket interiors and other cut-outs in the felt.
  static const Color pocket = Color(0xFF06210F);

  /// Connected, ready, "your turn" — the positive state colour.
  static const Color connected = Color(0xFF3DDC97);

  /// Searching, connecting, waiting — the in-progress state colour.
  static const Color pending = Color(0xFF6FA8DC);

  /// Disconnected, failed, foul — the negative state colour.
  static const Color alert = Color(0xFFFF6B6B);

  /// The cue ball.
  static const Color cueBall = Color(0xFFF7F4EC);

  /// Solid-group object balls.
  static const Color ballSolid = Color(0xFFE0A93B);

  /// Striped-group object balls.
  static const Color ballStripe = Color(0xFFE05B4B);

  /// The 8-ball.
  static const Color ballEight = Color(0xFF12100E);
}

/// The 4-point spacing scale. Every gap in the app is one of these.
abstract final class NearPlaySpacing {
  /// 4 — hairline gaps inside a control.
  static const double xs = 4;

  /// 8 — between tightly related elements.
  static const double sm = 8;

  /// 12 — inside compact controls.
  static const double md = 12;

  /// 16 — the default gap, and standard screen padding.
  static const double lg = 16;

  /// 24 — between groups.
  static const double xl = 24;

  /// 32 — between major sections.
  static const double xxl = 32;

  /// 48 — around a screen's single focal element.
  static const double huge = 48;
}

/// Corner radii. NearPlay's surfaces are generously rounded — the app should
/// feel like a physical object on a table, not a form.
abstract final class NearPlayRadius {
  /// 8 — chips and small controls.
  static const Radius sm = Radius.circular(8);

  /// 16 — cards, sheets, buttons.
  static const Radius md = Radius.circular(16);

  /// 24 — full-bleed panels.
  static const Radius lg = Radius.circular(24);

  /// Fully round — pills and avatars.
  static const Radius pill = Radius.circular(999);

  /// [md] as a ready-made [BorderRadius].
  static const BorderRadius cardBorder = BorderRadius.all(md);

  /// [sm] as a ready-made [BorderRadius].
  static const BorderRadius chipBorder = BorderRadius.all(sm);

  /// [pill] as a ready-made [BorderRadius].
  static const BorderRadius pillBorder = BorderRadius.all(pill);
}

/// The type ramp. Sizes are deliberately few: a game shell needs a headline, a
/// body, and a label, and little in between.
abstract final class NearPlayText {
  /// Reserved for the one thing a screen is about (a winner, a score).
  static const TextStyle display = TextStyle(
    fontSize: 40,
    height: 1.1,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: NearPlayColors.textPrimary,
  );

  /// Screen and section titles.
  static const TextStyle title = TextStyle(
    fontSize: 22,
    height: 1.2,
    fontWeight: FontWeight.w600,
    color: NearPlayColors.textPrimary,
  );

  /// The title of a row or card.
  static const TextStyle subtitle = TextStyle(
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: NearPlayColors.textPrimary,
  );

  /// Running text.
  static const TextStyle body = TextStyle(
    fontSize: 15,
    height: 1.45,
    color: NearPlayColors.textSecondary,
  );

  /// Buttons and chips.
  static const TextStyle label = TextStyle(
    fontSize: 14,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
    color: NearPlayColors.textPrimary,
  );

  /// Metadata: signal strength, ids, status lines.
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    height: 1.3,
    letterSpacing: 0.3,
    color: NearPlayColors.textMuted,
  );
}

/// Motion durations. Short enough to feel responsive on a device being passed
/// between two people.
abstract final class NearPlayMotion {
  /// State changes on a control.
  static const Duration quick = Duration(milliseconds: 120);

  /// Panels and banners entering or leaving.
  static const Duration standard = Duration(milliseconds: 240);

  /// The pulse of a "searching" indicator.
  static const Duration pulse = Duration(milliseconds: 1400);
}
