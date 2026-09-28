import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../models/unit_category.dart';
import '../providers/converter_provider.dart';

class UnitDetailScreen extends ConsumerStatefulWidget {
  final UnitCategory category;

  const UnitDetailScreen({super.key, required this.category});

  @override
  ConsumerState<UnitDetailScreen> createState() => _UnitDetailScreenState();
}

class _UnitDetailScreenState extends ConsumerState<UnitDetailScreen> {
  late UnitDefinition _fromUnit;
  late UnitDefinition _toUnit;
  String _inputExpression = '1';

  @override
  void initState() {
    super.initState();
    _fromUnit = widget.category.defaultFrom;
    _toUnit = widget.category.defaultTo;
  }

  void _onKeyPress(String key) {
    HapticFeedback.lightImpact();
    setState(() {
      if (key == 'C') {
        _inputExpression = '0';
      } else if (key == '⌫') {
        if (_inputExpression.length > 1) {
          _inputExpression = _inputExpression.substring(0, _inputExpression.length - 1);
        } else {
          _inputExpression = '0';
        }
      } else if (key == '±') {
        if (_inputExpression.startsWith('-')) {
          _inputExpression = _inputExpression.substring(1);
        } else if (_inputExpression != '0') {
          _inputExpression = '-$_inputExpression';
        }
      } else if (key == '.') {
        if (!_inputExpression.contains('.')) {
          _inputExpression = '$_inputExpression.';
        }
      } else {
        if (_inputExpression == '0') {
          _inputExpression = key;
        } else if (_inputExpression.length < 15) {
          _inputExpression = '$_inputExpression$key';
        }
      }
    });

    _recordConversion();
  }

  void _swapUnits() {
    HapticFeedback.mediumImpact();
    setState(() {
      final temp = _fromUnit;
      _fromUnit = _toUnit;
      _toUnit = temp;
    });
    _recordConversion();
  }

  void _recordConversion() {
    final inputVal = double.tryParse(_inputExpression) ?? 0.0;
    final convertedVal = _fromUnit.convertTo(inputVal, _toUnit);
    ref.read(historyProvider.notifier).addRecord(
      category: widget.category.name,
      fromUnit: _fromUnit.symbol,
      toUnit: _toUnit.symbol,
      fromValue: inputVal,
      toValue: convertedVal,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final precision = ref.watch(precisionProvider);
    final inputVal = double.tryParse(_inputExpression) ?? 0.0;
    final convertedVal = _fromUnit.convertTo(inputVal, _toUnit);

    final convertedFormatted = convertedVal.toStringAsFixed(precision);

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text(
          widget.category.name,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          ),
        ),
        actions: [
          PopupMenuButton<int>(
            icon: Icon(
              Icons.tune_rounded,
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
            ),
            tooltip: 'Precision',
            onSelected: (p) => ref.read(precisionProvider.notifier).setPrecision(p),
            itemBuilder: (context) => [2, 3, 4, 6, 8].map((p) {
              return PopupMenuItem<int>(
                value: p,
                child: Text('$p Decimals ${p == precision ? "✓" : ""}'),
              );
            }).toList(),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Conversion Display Area
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                children: [
                  // FROM Unit Card
                  _buildUnitBox(
                    context: context,
                    isDark: isDark,
                    title: 'FROM',
                    selectedUnit: _fromUnit,
                    valueText: _inputExpression,
                    onSelectUnit: (u) => setState(() => _fromUnit = u),
                  ),

                  // Swap Button
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Center(
                      child: IconButton.filledTonal(
                        onPressed: _swapUnits,
                        style: IconButton.styleFrom(
                          backgroundColor: widget.category.getBadgeColor(isDark),
                          foregroundColor: widget.category.iconColor,
                        ),
                        icon: const Icon(Icons.swap_vert_rounded, size: 24),
                      ),
                    ),
                  ),

                  // TO Unit Card
                  _buildUnitBox(
                    context: context,
                    isDark: isDark,
                    title: 'TO',
                    selectedUnit: _toUnit,
                    valueText: convertedFormatted,
                    isTarget: true,
                    onSelectUnit: (u) => setState(() => _toUnit = u),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Custom Keypad
            _buildCustomKeypad(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildUnitBox({
    required BuildContext context,
    required bool isDark,
    required String title,
    required UnitDefinition selectedUnit,
    required String valueText,
    bool isTarget = false,
    required ValueChanged<UnitDefinition> onSelectUnit,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? MetricGlass.level1 : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isTarget
              ? (isDark ? Colors.white24 : widget.category.iconColor.withValues(alpha: 0.4))
              : (isDark ? MetricGlass.border : AppColors.cardBorderLight),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                  color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                ),
              ),
              InkWell(
                onTap: () => _showUnitPicker(context, isDark, onSelectUnit),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: widget.category.getBadgeColor(isDark),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${selectedUnit.symbol} (${selectedUnit.name})',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: widget.category.iconColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.arrow_drop_down_rounded, size: 20, color: widget.category.iconColor),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  valueText,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isTarget)
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  tooltip: 'Copy',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: valueText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Copied $valueText ${selectedUnit.symbol} to clipboard'),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showUnitPicker(
    BuildContext context,
    bool isDark,
    ValueChanged<UnitDefinition> onSelect,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Select ${widget.category.name} Unit',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.category.units.length,
                  itemBuilder: (context, index) {
                    final unit = widget.category.units[index];
                    return ListTile(
                      title: Text(
                        unit.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                        ),
                      ),
                      trailing: Text(
                        unit.symbol,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: widget.category.iconColor,
                        ),
                      ),
                      onTap: () {
                        onSelect(unit);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCustomKeypad(bool isDark) {
    final keys = [
      ['C', '±', '⌫'],
      ['7', '8', '9'],
      ['4', '5', '6'],
      ['1', '2', '3'],
      ['00', '0', '.'],
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? MetricColors.background : AppColors.surfaceLight,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(
            color: isDark ? MetricGlass.border : AppColors.cardBorderLight,
            width: 1.0,
          ),
        ),
      ),
      child: Column(
        children: keys.map((row) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: row.map((key) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _buildKeyButton(key, isDark),
                  ),
                );
              }).toList(),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildKeyButton(String key, bool isDark) {
    final isSpecial = ['C', '±', '⌫'].contains(key);
    return Material(
      color: isSpecial
          ? (isDark ? MetricGlass.level2 : widget.category.getBadgeColor(isDark))
          : (isDark ? MetricGlass.level1 : const Color(0xFFF1F4F9)),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _onKeyPress(key),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          child: Text(
            key,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: isSpecial
                  ? widget.category.iconColor
                  : (isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
            ),
          ),
        ),
      ),
    );
  }
}
