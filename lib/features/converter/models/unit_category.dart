import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class UnitDefinition {
  final String id;
  final String name;
  final String symbol;
  final double toBaseFactor; // Multiply by this to get base unit
  final double fromBaseFactor; // Or custom converter for non-linear units like temperature
  final double Function(double)? toBaseCustom;
  final double Function(double)? fromBaseCustom;

  const UnitDefinition({
    required this.id,
    required this.name,
    required this.symbol,
    this.toBaseFactor = 1.0,
    this.fromBaseFactor = 1.0,
    this.toBaseCustom,
    this.fromBaseCustom,
  });

  double convertTo(double value, UnitDefinition targetUnit) {
    double baseVal;
    if (toBaseCustom != null) {
      baseVal = toBaseCustom!(value);
    } else {
      baseVal = value * toBaseFactor;
    }

    if (targetUnit.fromBaseCustom != null) {
      return targetUnit.fromBaseCustom!(baseVal);
    } else {
      return baseVal / targetUnit.toBaseFactor;
    }
  }
}

class UnitCategory {
  final String id;
  final String name;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color badgeColor;
  final List<UnitDefinition> units;
  final String defaultFromUnitId;
  final String defaultToUnitId;

  const UnitCategory({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.badgeColor,
    required this.units,
    required this.defaultFromUnitId,
    required this.defaultToUnitId,
  });

  UnitDefinition get defaultFrom =>
      units.firstWhere((u) => u.id == defaultFromUnitId, orElse: () => units[0]);

  UnitDefinition get defaultTo =>
      units.firstWhere((u) => u.id == defaultToUnitId, orElse: () => units[1]);
}

class UnitCatalog {
  static final List<UnitCategory> categories = [
    // 1. Length
    UnitCategory(
      id: 'length',
      name: 'Length',
      subtitle: 'm, km, cm, mm, ft, in',
      icon: Icons.straighten_rounded,
      iconColor: AppColors.blueIcon,
      badgeColor: AppColors.blueBadge,
      defaultFromUnitId: 'm',
      defaultToUnitId: 'ft',
      units: const [
        UnitDefinition(id: 'm', name: 'Meter', symbol: 'm', toBaseFactor: 1.0),
        UnitDefinition(id: 'km', name: 'Kilometer', symbol: 'km', toBaseFactor: 1000.0),
        UnitDefinition(id: 'cm', name: 'Centimeter', symbol: 'cm', toBaseFactor: 0.01),
        UnitDefinition(id: 'mm', name: 'Millimeter', symbol: 'mm', toBaseFactor: 0.001),
        UnitDefinition(id: 'mi', name: 'Mile', symbol: 'mi', toBaseFactor: 1609.344),
        UnitDefinition(id: 'yd', name: 'Yard', symbol: 'yd', toBaseFactor: 0.9144),
        UnitDefinition(id: 'ft', name: 'Foot', symbol: 'ft', toBaseFactor: 0.3048),
        UnitDefinition(id: 'in', name: 'Inch', symbol: 'in', toBaseFactor: 0.0254),
        UnitDefinition(id: 'nmi', name: 'Nautical Mile', symbol: 'nmi', toBaseFactor: 1852.0),
      ],
    ),

    // 2. Weight
    UnitCategory(
      id: 'weight',
      name: 'Weight',
      subtitle: 'kg, g, lb, oz, ton',
      icon: Icons.fitness_center_rounded,
      iconColor: AppColors.greenIcon,
      badgeColor: AppColors.greenBadge,
      defaultFromUnitId: 'kg',
      defaultToUnitId: 'lb',
      units: const [
        UnitDefinition(id: 'kg', name: 'Kilogram', symbol: 'kg', toBaseFactor: 1.0),
        UnitDefinition(id: 'g', name: 'Gram', symbol: 'g', toBaseFactor: 0.001),
        UnitDefinition(id: 'mg', name: 'Milligram', symbol: 'mg', toBaseFactor: 0.000001),
        UnitDefinition(id: 'lb', name: 'Pound', symbol: 'lb', toBaseFactor: 0.45359237),
        UnitDefinition(id: 'oz', name: 'Ounce', symbol: 'oz', toBaseFactor: 0.02834952),
        UnitDefinition(id: 'ton', name: 'Metric Ton', symbol: 't', toBaseFactor: 1000.0),
        UnitDefinition(id: 'st', name: 'Stone', symbol: 'st', toBaseFactor: 6.35029),
      ],
    ),

    // 3. Temperature
    UnitCategory(
      id: 'temperature',
      name: 'Temperature',
      subtitle: '°C, °F, K, °R',
      icon: Icons.thermostat_rounded,
      iconColor: AppColors.redIcon,
      badgeColor: AppColors.redBadge,
      defaultFromUnitId: 'c',
      defaultToUnitId: 'f',
      units: [
        UnitDefinition(
          id: 'c',
          name: 'Celsius',
          symbol: '°C',
          toBaseCustom: (val) => val,
          fromBaseCustom: (base) => base,
        ),
        UnitDefinition(
          id: 'f',
          name: 'Fahrenheit',
          symbol: '°F',
          toBaseCustom: (val) => (val - 32) * 5 / 9,
          fromBaseCustom: (base) => (base * 9 / 5) + 32,
        ),
        UnitDefinition(
          id: 'k',
          name: 'Kelvin',
          symbol: 'K',
          toBaseCustom: (val) => val - 273.15,
          fromBaseCustom: (base) => base + 273.15,
        ),
        UnitDefinition(
          id: 'r',
          name: 'Rankine',
          symbol: '°R',
          toBaseCustom: (val) => (val - 491.67) * 5 / 9,
          fromBaseCustom: (base) => (base + 273.15) * 9 / 5,
        ),
      ],
    ),

    // 4. Area
    UnitCategory(
      id: 'area',
      name: 'Area',
      subtitle: 'm², km², ft², acre',
      icon: Icons.dashboard_customize_rounded,
      iconColor: AppColors.amberIcon,
      badgeColor: AppColors.amberBadge,
      defaultFromUnitId: 'sqm',
      defaultToUnitId: 'sqft',
      units: const [
        UnitDefinition(id: 'sqm', name: 'Square Meter', symbol: 'm²', toBaseFactor: 1.0),
        UnitDefinition(id: 'sqkm', name: 'Square Kilometer', symbol: 'km²', toBaseFactor: 1000000.0),
        UnitDefinition(id: 'sqft', name: 'Square Foot', symbol: 'ft²', toBaseFactor: 0.092903),
        UnitDefinition(id: 'sqin', name: 'Square Inch', symbol: 'in²', toBaseFactor: 0.00064516),
        UnitDefinition(id: 'acre', name: 'Acre', symbol: 'ac', toBaseFactor: 4046.86),
        UnitDefinition(id: 'ha', name: 'Hectare', symbol: 'ha', toBaseFactor: 10000.0),
      ],
    ),

    // 5. Speed
    UnitCategory(
      id: 'speed',
      name: 'Speed',
      subtitle: 'km/h, m/s, mph, knot',
      icon: Icons.speed_rounded,
      iconColor: AppColors.purpleIcon,
      badgeColor: AppColors.purpleBadge,
      defaultFromUnitId: 'kmh',
      defaultToUnitId: 'mph',
      units: const [
        UnitDefinition(id: 'kmh', name: 'Kilometer per Hour', symbol: 'km/h', toBaseFactor: 1.0),
        UnitDefinition(id: 'ms', name: 'Meter per Second', symbol: 'm/s', toBaseFactor: 3.6),
        UnitDefinition(id: 'mph', name: 'Miles per Hour', symbol: 'mph', toBaseFactor: 1.60934),
        UnitDefinition(id: 'knot', name: 'Knot', symbol: 'kn', toBaseFactor: 1.852),
        UnitDefinition(id: 'mach', name: 'Mach (STP)', symbol: 'M', toBaseFactor: 1225.04),
      ],
    ),

    // 6. Time
    UnitCategory(
      id: 'time',
      name: 'Time',
      subtitle: 's, min, hr, day, week',
      icon: Icons.schedule_rounded,
      iconColor: AppColors.tealIcon,
      badgeColor: AppColors.tealBadge,
      defaultFromUnitId: 'hr',
      defaultToUnitId: 'min',
      units: const [
        UnitDefinition(id: 'sec', name: 'Second', symbol: 's', toBaseFactor: 1.0),
        UnitDefinition(id: 'min', name: 'Minute', symbol: 'min', toBaseFactor: 60.0),
        UnitDefinition(id: 'hr', name: 'Hour', symbol: 'hr', toBaseFactor: 3600.0),
        UnitDefinition(id: 'day', name: 'Day', symbol: 'd', toBaseFactor: 86400.0),
        UnitDefinition(id: 'wk', name: 'Week', symbol: 'wk', toBaseFactor: 604800.0),
        UnitDefinition(id: 'yr', name: 'Year', symbol: 'yr', toBaseFactor: 31536000.0),
      ],
    ),

    // 7. Data
    UnitCategory(
      id: 'data',
      name: 'Data',
      subtitle: 'B, KB, MB, GB, TB',
      icon: Icons.storage_rounded,
      iconColor: AppColors.orangeIcon,
      badgeColor: AppColors.orangeBadge,
      defaultFromUnitId: 'gb',
      defaultToUnitId: 'mb',
      units: const [
        UnitDefinition(id: 'byte', name: 'Byte', symbol: 'B', toBaseFactor: 1.0),
        UnitDefinition(id: 'kb', name: 'Kilobyte', symbol: 'KB', toBaseFactor: 1024.0),
        UnitDefinition(id: 'mb', name: 'Megabyte', symbol: 'MB', toBaseFactor: 1048576.0),
        UnitDefinition(id: 'gb', name: 'Gigabyte', symbol: 'GB', toBaseFactor: 1073741824.0),
        UnitDefinition(id: 'tb', name: 'Terabyte', symbol: 'TB', toBaseFactor: 1099511627776.0),
        UnitDefinition(id: 'pb', name: 'Petabyte', symbol: 'PB', toBaseFactor: 1125899906842624.0),
      ],
    ),

    // 8. Volume
    UnitCategory(
      id: 'volume',
      name: 'Volume',
      subtitle: 'L, m³, gal, ml, fl oz',
      icon: Icons.view_in_ar_rounded,
      iconColor: AppColors.cyanIcon,
      badgeColor: AppColors.cyanBadge,
      defaultFromUnitId: 'l',
      defaultToUnitId: 'gal',
      units: const [
        UnitDefinition(id: 'l', name: 'Liter', symbol: 'L', toBaseFactor: 1.0),
        UnitDefinition(id: 'ml', name: 'Milliliter', symbol: 'mL', toBaseFactor: 0.001),
        UnitDefinition(id: 'cum', name: 'Cubic Meter', symbol: 'm³', toBaseFactor: 1000.0),
        UnitDefinition(id: 'gal', name: 'Gallon (US)', symbol: 'gal', toBaseFactor: 3.78541),
        UnitDefinition(id: 'floz', name: 'Fluid Ounce (US)', symbol: 'fl oz', toBaseFactor: 0.0295735),
        UnitDefinition(id: 'pt', name: 'Pint (US)', symbol: 'pt', toBaseFactor: 0.473176),
        UnitDefinition(id: 'qt', name: 'Quart (US)', symbol: 'qt', toBaseFactor: 0.946353),
      ],
    ),

    // 9. Energy
    UnitCategory(
      id: 'energy',
      name: 'Energy',
      subtitle: 'J, kWh, cal, kcal',
      icon: Icons.bolt_rounded,
      iconColor: AppColors.violetIcon,
      badgeColor: AppColors.violetBadge,
      defaultFromUnitId: 'kcal',
      defaultToUnitId: 'j',
      units: const [
        UnitDefinition(id: 'j', name: 'Joule', symbol: 'J', toBaseFactor: 1.0),
        UnitDefinition(id: 'kj', name: 'Kilojoule', symbol: 'kJ', toBaseFactor: 1000.0),
        UnitDefinition(id: 'cal', name: 'Calorie', symbol: 'cal', toBaseFactor: 4.184),
        UnitDefinition(id: 'kcal', name: 'Kilocalorie', symbol: 'kcal', toBaseFactor: 4184.0),
        UnitDefinition(id: 'kwh', name: 'Kilowatt-hour', symbol: 'kWh', toBaseFactor: 3600000.0),
        UnitDefinition(id: 'btu', name: 'BTU', symbol: 'BTU', toBaseFactor: 1055.06),
      ],
    ),

    // 10. Fuel
    UnitCategory(
      id: 'fuel',
      name: 'Fuel',
      subtitle: 'L, gal, mpg, km/L',
      icon: Icons.water_drop_rounded,
      iconColor: AppColors.roseIcon,
      badgeColor: AppColors.roseBadge,
      defaultFromUnitId: 'mpg',
      defaultToUnitId: 'kml',
      units: [
        UnitDefinition(
          id: 'kml',
          name: 'Kilometer per Liter',
          symbol: 'km/L',
          toBaseCustom: (v) => v,
          fromBaseCustom: (b) => b,
        ),
        UnitDefinition(
          id: 'mpg',
          name: 'Miles per Gallon (US)',
          symbol: 'mpg',
          toBaseCustom: (v) => v * 0.425144,
          fromBaseCustom: (b) => b / 0.425144,
        ),
        UnitDefinition(
          id: 'l100km',
          name: 'Liters per 100km',
          symbol: 'L/100km',
          toBaseCustom: (v) => v == 0 ? 0 : 100 / v,
          fromBaseCustom: (b) => b == 0 ? 0 : 100 / b,
        ),
      ],
    ),

    // 11. Angle
    UnitCategory(
      id: 'angle',
      name: 'Angle',
      subtitle: 'deg, rad, grad, arcmin',
      icon: Icons.hub_rounded,
      iconColor: AppColors.emeraldIcon,
      badgeColor: AppColors.emeraldBadge,
      defaultFromUnitId: 'deg',
      defaultToUnitId: 'rad',
      units: const [
        UnitDefinition(id: 'deg', name: 'Degree', symbol: '°', toBaseFactor: 1.0),
        UnitDefinition(id: 'rad', name: 'Radian', symbol: 'rad', toBaseFactor: 57.2958),
        UnitDefinition(id: 'grad', name: 'Gradian', symbol: 'grad', toBaseFactor: 0.9),
        UnitDefinition(id: 'arcmin', name: 'Arcminute', symbol: "'", toBaseFactor: 1 / 60),
        UnitDefinition(id: 'arcsec', name: 'Arcsecond', symbol: '"', toBaseFactor: 1 / 3600),
      ],
    ),

    // 12. Pressure
    UnitCategory(
      id: 'pressure',
      name: 'Pressure',
      subtitle: 'Pa, bar, psi, atm',
      icon: Icons.compress_rounded,
      iconColor: AppColors.indigoIcon,
      badgeColor: AppColors.indigoBadge,
      defaultFromUnitId: 'bar',
      defaultToUnitId: 'psi',
      units: const [
        UnitDefinition(id: 'pa', name: 'Pascal', symbol: 'Pa', toBaseFactor: 1.0),
        UnitDefinition(id: 'kpa', name: 'Kilopascal', symbol: 'kPa', toBaseFactor: 1000.0),
        UnitDefinition(id: 'bar', name: 'Bar', symbol: 'bar', toBaseFactor: 100000.0),
        UnitDefinition(id: 'psi', name: 'Pounds per Sq Inch', symbol: 'psi', toBaseFactor: 6894.76),
        UnitDefinition(id: 'atm', name: 'Standard Atmosphere', symbol: 'atm', toBaseFactor: 101325.0),
        UnitDefinition(id: 'torr', name: 'Torr / mmHg', symbol: 'mmHg', toBaseFactor: 133.322),
      ],
    ),
  ];
}
