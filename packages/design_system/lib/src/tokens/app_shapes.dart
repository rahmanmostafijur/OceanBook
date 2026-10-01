import 'package:flutter/material.dart';

/// Material 3 corner scale. Components use the role that fits; there is no universal "big radius".
abstract final class AppShapes {
  static const double none = 0;
  static const double extraSmall = 4; // book covers, small badges
  static const double small = 8; // chips, text fields, snackbars
  static const double medium = 12; // cards, quiz option tiles, menus
  static const double large = 16; // FABs, navigation drawer
  static const double extraLarge = 28; // dialogs, bottom sheets (top corners)

  static const RoundedRectangleBorder chip = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(small)),
  );
  static const RoundedRectangleBorder card = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(medium)),
  );
  static const RoundedRectangleBorder dialog = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(extraLarge)),
  );
  static const RoundedRectangleBorder bottomSheet = RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(extraLarge)),
  );
  static const BorderRadius cover = BorderRadius.all(Radius.circular(extraSmall));
}

/// Material 3 elevation levels. Hierarchy comes from tonal surfaces (`surfaceContainer*`), not shadows.
abstract final class AppElevation {
  static const double level0 = 0;
  static const double level1 = 1;
  static const double level2 = 3;
  static const double level3 = 6;
  static const double level4 = 8;
  static const double level5 = 12;
}
