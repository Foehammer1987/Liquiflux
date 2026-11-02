// Generated from the Console design system tokens (tokens.json). Edit the source, not this file.
import 'package:flutter/material.dart';

/// Console colour tokens for one theme.
@immutable
class ConsoleColors extends ThemeExtension<ConsoleColors> {
  const ConsoleColors({
    required this.surface000,
    required this.surface050,
    required this.surface100,
    required this.surface200,
    required this.surface300,
    required this.border100,
    required this.border200,
    required this.border300,
    required this.track,
    required this.text100,
    required this.text200,
    required this.text300,
    required this.textDisabled,
    required this.primary,
    required this.primaryFill,
    required this.primaryFillHover,
    required this.onPrimary,
    required this.primaryTint,
    required this.link,
    required this.chartDownload,
    required this.chartUpload,
    required this.chartClients,
    required this.chartGrid,
    required this.success,
    required this.successText,
    required this.successTint,
    required this.warning,
    required this.warningText,
    required this.warningTint,
    required this.danger,
    required this.dangerText,
    required this.dangerTint,
    required this.dangerFill,
    required this.neutralDot,
    required this.scrim,
  });

  /// Page background behind panels and the left info column. Near-black in dark.
  final Color surface000;

  /// Icon rail on the far left.
  final Color surface050;

  /// Panels and tables. In dark it sits almost flush with surface-000 — the border-200 outline does the separating.
  final Color surface100;

  /// Top app bar, inputs, table row hover, secondary button fill, header chips.
  final Color surface200;

  /// Device/client tiles, pressed states, segmented-control track, toggle track off.
  final Color surface300;

  /// Chart grid lines and the faintest row dividers.
  final Color border100;

  /// Panel outlines, column dividers (rail | info column | content), section rules in the info column.
  final Color border200;

  /// Input border on hover; checkbox outline. 3:1 on surface-100 in dark only.
  final Color border300;

  /// Empty part of progress bars, activity bars and usage rings.
  final Color track;

  /// Primary text: panel titles, values, names, on every surface.
  final Color text100;

  /// Secondary text: info-column labels, inactive tabs and nav icons, table values that aren't the name.
  final Color text200;

  /// Tertiary text: clock, timestamps, OS version, chart axis labels, tile captions. 4.5:1+ on surface-000/100 in both themes; not on surface-300.
  final Color text300;

  /// Disabled labels and icons only — intentionally below 4.5:1.
  final Color textDisabled;

  /// The UniFi blue as a mark: active app tab icon, active rail icon, selected tile ring, usage-ring fill, toggles on, focus ring. 4.4:1 on surface-100 — fine for marks, use `link` for text.
  final Color primary;

  /// Primary button and selected pill fill. `on-primary` on it is 4.45:1 — label at 13px weight 600 minimum.
  final Color primaryFill;

  /// Primary button hover / pressed.
  final Color primaryFillHover;

  /// Labels and icons on primary-fill and danger-fill.
  final Color onPrimary;

  /// Selected nav item, selected table row, the outline of a selected tile.
  final Color primaryTint;

  /// Text actions: "See All", "Run Now", "View Release Notes", the active app tab label. 5:1 on surface-000 in dark.
  final Color link;

  /// Download figures (↓ 148 GB), download series, WiFi activity bars. Also readable as text on surface-000/100.
  final Color chartDownload;

  /// Upload figures (↑ 4.49 GB) and the upload series. Readable as text on surface-000/100.
  final Color chartUpload;

  /// The stepped client-count histogram behind Internet Activity.
  final Color chartClients;

  /// Cell lines cut into the client histogram.
  final Color chartGrid;

  /// Online / healthy dots, the health bar, the controller status dot. A mark only — always beside a word.
  final Color success;

  /// "Excellent", "100%" uptime and other good-state wording on surface-000/100.
  final Color successText;

  /// Background of success badges.
  final Color successTint;

  /// Degraded segments in the health bar, Updating dots. A mark only.
  final Color warning;

  /// Warning wording on surface-000/100 and warning-tint.
  final Color warningText;

  /// Background of warning badges.
  final Color warningTint;

  /// Offline / disconnected / outage dots and health-bar segments. A mark only.
  final Color danger;

  /// Error wording, field errors, destructive text buttons.
  final Color dangerText;

  /// Background of danger badges.
  final Color dangerTint;

  /// Destructive button fill; on-primary on it is 5:1.
  final Color dangerFill;

  /// Unknown / disabled / not-adopted status dot.
  final Color neutralDot;

  /// Overlay behind modals and slide-over panels.
  final Color scrim;

  static const dark = ConsoleColors(
    surface000: Color(0xFF0C0C0C),
    surface050: Color(0xFF0F0F0F),
    surface100: Color(0xFF0E0E0E),
    surface200: Color(0xFF29292C),
    surface300: Color(0xFF2D2D2F),
    border100: Color(0xFF1B1B1B),
    border200: Color(0xFF424242),
    border300: Color(0xFF6A6A70),
    track: Color(0xFF3D3D3D),
    text100: Color(0xFFF9FAFA),
    text200: Color(0xFFB6B9C4),
    text300: Color(0xFF8B919B),
    textDisabled: Color(0xFF50565E),
    primary: Color(0xFF006FFF),
    primaryFill: Color(0xFF006FFF),
    primaryFillHover: Color(0xFF2B84FF),
    onPrimary: Color(0xFFFFFFFF),
    primaryTint: Color(0xFF10264A),
    link: Color(0xFF1A7CFF),
    chartDownload: Color(0xFF43B0F1),
    chartUpload: Color(0xFFA46AE8),
    chartClients: Color(0xFF38373B),
    chartGrid: Color(0xFF1C1C1F),
    success: Color(0xFF38CC65),
    successText: Color(0xFF38CC65),
    successTint: Color(0xFF12301C),
    warning: Color(0xFFF5C518),
    warningText: Color(0xFFF7CF4A),
    warningTint: Color(0xFF33290A),
    danger: Color(0xFFF03A3E),
    dangerText: Color(0xFFFF6B6E),
    dangerTint: Color(0xFF3A1A1C),
    dangerFill: Color(0xFFD32F34),
    neutralDot: Color(0xFF50565E),
    scrim: Color.fromRGBO(0, 0, 0, 0.7),
  );

  static const light = ConsoleColors(
    surface000: Color(0xFFF4F5F6),
    surface050: Color(0xFFFFFFFF),
    surface100: Color(0xFFFFFFFF),
    surface200: Color(0xFFF9FAFA),
    surface300: Color(0xFFEDEEF0),
    border100: Color(0xFFEDEEF0),
    border200: Color(0xFFDEE0E3),
    border300: Color(0xFFB6B9C4),
    track: Color(0xFFE2E4E8),
    text100: Color(0xFF212327),
    text200: Color(0xFF50565E),
    text300: Color(0xFF6B717B),
    textDisabled: Color(0xFFB6B9C4),
    primary: Color(0xFF006FFF),
    primaryFill: Color(0xFF006FFF),
    primaryFillHover: Color(0xFF0059CC),
    onPrimary: Color(0xFFFFFFFF),
    primaryTint: Color(0xFFE5F0FF),
    link: Color(0xFF0062E6),
    chartDownload: Color(0xFF0072C6),
    chartUpload: Color(0xFF7A3FD1),
    chartClients: Color(0xFFDFE1E5),
    chartGrid: Color(0xFFF4F5F6),
    success: Color(0xFF38CC65),
    successText: Color(0xFF17803F),
    successTint: Color(0xFFE8F8ED),
    warning: Color(0xFFF5A623),
    warningText: Color(0xFFA35F00),
    warningTint: Color(0xFFFEF4E4),
    danger: Color(0xFFF03A3E),
    dangerText: Color(0xFFC8292E),
    dangerTint: Color(0xFFFDEAEA),
    dangerFill: Color(0xFFD32F34),
    neutralDot: Color(0xFFB6B9C4),
    scrim: Color.fromRGBO(20, 21, 24, 0.4),
  );

  @override
  ConsoleColors copyWith({
    Color? surface000,
    Color? surface050,
    Color? surface100,
    Color? surface200,
    Color? surface300,
    Color? border100,
    Color? border200,
    Color? border300,
    Color? track,
    Color? text100,
    Color? text200,
    Color? text300,
    Color? textDisabled,
    Color? primary,
    Color? primaryFill,
    Color? primaryFillHover,
    Color? onPrimary,
    Color? primaryTint,
    Color? link,
    Color? chartDownload,
    Color? chartUpload,
    Color? chartClients,
    Color? chartGrid,
    Color? success,
    Color? successText,
    Color? successTint,
    Color? warning,
    Color? warningText,
    Color? warningTint,
    Color? danger,
    Color? dangerText,
    Color? dangerTint,
    Color? dangerFill,
    Color? neutralDot,
    Color? scrim,
  }) => ConsoleColors(
    surface000: surface000 ?? this.surface000,
    surface050: surface050 ?? this.surface050,
    surface100: surface100 ?? this.surface100,
    surface200: surface200 ?? this.surface200,
    surface300: surface300 ?? this.surface300,
    border100: border100 ?? this.border100,
    border200: border200 ?? this.border200,
    border300: border300 ?? this.border300,
    track: track ?? this.track,
    text100: text100 ?? this.text100,
    text200: text200 ?? this.text200,
    text300: text300 ?? this.text300,
    textDisabled: textDisabled ?? this.textDisabled,
    primary: primary ?? this.primary,
    primaryFill: primaryFill ?? this.primaryFill,
    primaryFillHover: primaryFillHover ?? this.primaryFillHover,
    onPrimary: onPrimary ?? this.onPrimary,
    primaryTint: primaryTint ?? this.primaryTint,
    link: link ?? this.link,
    chartDownload: chartDownload ?? this.chartDownload,
    chartUpload: chartUpload ?? this.chartUpload,
    chartClients: chartClients ?? this.chartClients,
    chartGrid: chartGrid ?? this.chartGrid,
    success: success ?? this.success,
    successText: successText ?? this.successText,
    successTint: successTint ?? this.successTint,
    warning: warning ?? this.warning,
    warningText: warningText ?? this.warningText,
    warningTint: warningTint ?? this.warningTint,
    danger: danger ?? this.danger,
    dangerText: dangerText ?? this.dangerText,
    dangerTint: dangerTint ?? this.dangerTint,
    dangerFill: dangerFill ?? this.dangerFill,
    neutralDot: neutralDot ?? this.neutralDot,
    scrim: scrim ?? this.scrim,
  );

  @override
  ConsoleColors lerp(ConsoleColors? other, double t) {
    if (other == null) return this;
    return ConsoleColors(
      surface000: Color.lerp(surface000, other.surface000, t)!,
      surface050: Color.lerp(surface050, other.surface050, t)!,
      surface100: Color.lerp(surface100, other.surface100, t)!,
      surface200: Color.lerp(surface200, other.surface200, t)!,
      surface300: Color.lerp(surface300, other.surface300, t)!,
      border100: Color.lerp(border100, other.border100, t)!,
      border200: Color.lerp(border200, other.border200, t)!,
      border300: Color.lerp(border300, other.border300, t)!,
      track: Color.lerp(track, other.track, t)!,
      text100: Color.lerp(text100, other.text100, t)!,
      text200: Color.lerp(text200, other.text200, t)!,
      text300: Color.lerp(text300, other.text300, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      primaryFill: Color.lerp(primaryFill, other.primaryFill, t)!,
      primaryFillHover: Color.lerp(primaryFillHover, other.primaryFillHover, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      primaryTint: Color.lerp(primaryTint, other.primaryTint, t)!,
      link: Color.lerp(link, other.link, t)!,
      chartDownload: Color.lerp(chartDownload, other.chartDownload, t)!,
      chartUpload: Color.lerp(chartUpload, other.chartUpload, t)!,
      chartClients: Color.lerp(chartClients, other.chartClients, t)!,
      chartGrid: Color.lerp(chartGrid, other.chartGrid, t)!,
      success: Color.lerp(success, other.success, t)!,
      successText: Color.lerp(successText, other.successText, t)!,
      successTint: Color.lerp(successTint, other.successTint, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningText: Color.lerp(warningText, other.warningText, t)!,
      warningTint: Color.lerp(warningTint, other.warningTint, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerText: Color.lerp(dangerText, other.dangerText, t)!,
      dangerTint: Color.lerp(dangerTint, other.dangerTint, t)!,
      dangerFill: Color.lerp(dangerFill, other.dangerFill, t)!,
      neutralDot: Color.lerp(neutralDot, other.neutralDot, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}

abstract final class Space {
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space8 = 32;
  static const double space10 = 40;
}

abstract final class Radii {
  static const double radiusSm = 4;
  static const double radiusMd = 8;
  static const double radiusLg = 12;
  static const double radiusFull = 9999;
}

abstract final class Sizes {
  /// Segmented pills, compact buttons in panel headers and tables.
  static const double controlSm = 24;

  /// Default button, input and select height.
  static const double controlMd = 32;

  /// Setup-flow and modal primary actions.
  static const double controlLg = 40;

  /// Rail and top-bar icons, 1.5px stroke.
  static const double iconMd = 20;

  /// Client / access-point tile square.
  static const double tileSize = 44;

  /// Far-left icon rail.
  static const double railWidth = 44;

  /// Left info column (device, WAN, uptime, health, speed test).
  static const double infoWidth = 252;

  /// Top app bar with app tabs and the device chip.
  static const double topbarHeight = 45;

  /// Rows in dashboard tables (Traffic Identification, WiFi Technology).
  static const double rowHeight = 29;
}
