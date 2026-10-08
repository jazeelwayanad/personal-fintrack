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
          SizedBox(
            width: 100,
            child: LinearProgressIndicator(
              value: MediaQuery.disableAnimationsOf(context) ? 1 : null,
            ),
          ),
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

class FinDock extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;
  const FinDock({super.key, required this.selected, required this.onSelected});
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    child: Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            for (final entry in [
              ('home', 'Home'),
              ('plans', 'Plans'),
              ('activity', 'Activity'),
              ('reports', 'Reports'),
              ('settings', 'Settings'),
            ].asMap().entries)
              Expanded(
                child: Semantics(
                  selected: selected == entry.key,
                  child: Container(
                    decoration: BoxDecoration(
                      color: selected == entry.key
                          ? const Color(0xff073b3b)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: () => onSelected(entry.key),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FinIcon(
                              entry.value.$1,
                              size: 19,
                              color: selected == entry.key
                                  ? Colors.white
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              entry.value.$2,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: selected == entry.key
                                    ? Colors.white
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class FinContact extends StatelessWidget {
  final String icon, label, value;
  final VoidCallback? onTap;
  const FinContact({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: FinIcon(
                icon,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, size: 18),
        ],
      ),
    ),
  );
}
