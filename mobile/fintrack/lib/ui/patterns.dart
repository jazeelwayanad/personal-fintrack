import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../domain/finance.dart';

class FinIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;
  const FinIcon(this.name, {super.key, this.size = 22, this.color});
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/icons/$name.svg',
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(
      color ?? Theme.of(context).colorScheme.onSurface,
      BlendMode.srcIn,
    ),
  );
}

Color categoryColor(List<Doc> records, String id) {
  final hex = text(
    records.where((r) => r.id == id && !r.deleted).firstOrNull?.data ?? {},
    'color',
    '#74aa89',
  );
  return RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)
      ? Color(int.parse('ff${hex.substring(1)}', radix: 16))
      : const Color(0xff74aa89);
}

class BrandLoading extends StatelessWidget {
  final String label;
  const BrandLoading({super.key, required this.label});
  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      liveRegion: true,
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset(
              'assets/fintrack-icon.png',
              width: 88,
              height: 88,
            ),
          ),
          const SizedBox(height: 24),
          Text(label),
          const SizedBox(height: 20),
          const SizedBox(width: 100, child: LinearProgressIndicator()),
        ],
      ),
    ),
  );
}

class FinEmpty extends StatelessWidget {
  final String message;
  const FinEmpty(this.message, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
  );
}
