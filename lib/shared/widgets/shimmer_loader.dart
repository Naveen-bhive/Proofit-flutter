import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/constants/app_colors.dart';

class ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const ShimmerBox({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor:    AppColors.dark3,
      highlightColor: AppColors.dark4,
      child: Container(
        width: width, height: height,
        decoration: BoxDecoration(
          color: AppColors.dark3,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

// Dashboard list shimmer (stats are shown separately on owner home).
class DashboardShimmer extends StatelessWidget {
  const DashboardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const ShimmerBox(height: 18, width: 120),
        const SizedBox(height: 12),
        ...List.generate(3, (_) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _reportCardShimmer(),
        )),
      ],
    );
  }

  Widget _reportCardShimmer() => Container(
    height: 80,
    decoration: BoxDecoration(color: AppColors.dark2, borderRadius: BorderRadius.circular(14)),
    padding: const EdgeInsets.all(14),
    child: Row(children: [
      const ShimmerBox(width: 52, height: 52, radius: 10),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: const [
        ShimmerBox(width: 140, height: 15),
        SizedBox(height: 8),
        ShimmerBox(width: 100, height: 12),
      ])),
      const ShimmerBox(width: 50, height: 22, radius: 6),
    ]),
  );
}

// Staff list shimmer
class StaffListShimmer extends StatelessWidget {
  const StaffListShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        height: 72,
        decoration: BoxDecoration(color: AppColors.dark2, borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          const ShimmerBox(width: 40, height: 40, radius: 100),
          const SizedBox(width: 12),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            ShimmerBox(width: 120, height: 15),
            SizedBox(height: 8),
            ShimmerBox(width: 80, height: 12),
          ])),
          const ShimmerBox(width: 60, height: 22, radius: 100),
        ]),
      ),
    );
  }
}

// Report list shimmer — Column only (safe inside CustomScrollView / SliverList)
class ReportListShimmer extends StatelessWidget {
  const ReportListShimmer({super.key});

  static Widget _row() => Container(
    margin: const EdgeInsets.only(bottom: 10),
    height: 80,
    decoration: BoxDecoration(color: AppColors.dark2, borderRadius: BorderRadius.circular(14)),
    padding: const EdgeInsets.all(14),
    child: Row(children: [
      const ShimmerBox(width: 52, height: 52, radius: 10),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: const [
        ShimmerBox(width: 160, height: 15),
        SizedBox(height: 8),
        ShimmerBox(width: 100, height: 12),
      ])),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(6, (_) => _row()),
    );
  }
}