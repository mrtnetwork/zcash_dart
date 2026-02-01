import 'dart:collection';
import 'package:blockchain_utils/utils/utils.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/utility/layouter.dart';
import 'package:zcash_dart/src/zk_proof/halo2/src/plonk/column.dart';

/// A region allocated within a column.
class AllocatedRegion with Equality implements Comparable<AllocatedRegion> {
  final int start;
  final int length;
  int get end => start + length;

  const AllocatedRegion({
    required this.start,
    required this.length,
  });

  @override
  int compareTo(AllocatedRegion other) {
    return start.compareTo(other.start);
  }

  @override
  String toString() => 'AllocatedRegion(start: $start, length: $length)';

  @override
  List<dynamic> get variables => [start, length];
}

/// An area of empty space within a column.
class EmptySpace {
  final int start;
  final int? end; // null means unbounded

  const EmptySpace({required this.start, required this.end});

  ({int start, int end})? range() {
    final end = this.end;
    if (end == null) return null;
    return (start: start, end: end);
  }
}

/// Allocated rows within a column.
///
/// This is a set of [a_start, a_end) pairs representing disjoint allocated intervals.
class AllocationsRegion {
  final SplayTreeSet<AllocatedRegion> _regions;

  AllocationsRegion() : _regions = SplayTreeSet();

  /// Returns the row that forms the unbounded unallocated interval [row, None).
  int unboundedIntervalStart() {
    if (_regions.isEmpty) return 0;
    final last = _regions.last;
    return last.start + last.length;
  }

  /// Return all unallocated intervals intersecting [start, end).
  Iterable<EmptySpace> freeIntervals(int start, int? end) sync* {
    int row = start;

    for (final region in _regions) {
      if (end != null && region.start >= end) break;

      if (row < region.start) {
        yield EmptySpace(start: row, end: region.start);
      }

      row = IntUtils.max(row, region.end);
    }

    if (end == null || row < end) {
      yield EmptySpace(start: row, end: end);
    }
  }

  void add(int start, int length) {
    _regions.add(AllocatedRegion(start: start, length: length));
  }
}

class FloorPlannerUtils {
  /// First-fit region placement.
  static int? firstFitRegion(
    Map<RegionColumn, AllocationsRegion> columnAllocations,
    List<RegionColumn> regionColumns,
    int regionLength,
    int start,
    int? slack,
  ) {
    if (regionColumns.isEmpty) return start;

    final c = regionColumns.first;
    final remainingColumns = regionColumns.sublist(1);

    final end = slack != null ? start + regionLength + slack : null;

    final allocations =
        columnAllocations.putIfAbsent(c, () => AllocationsRegion());

    // Lazy iteration over free intervals (updates visible to recursion)
    for (final space in allocations.freeIntervals(start, end)) {
      final sSlack = space.end != null
          ? (space.end! - space.start) - regionLength
          : null; // unbounded remains null

      if (slack != null && sSlack != null) {
        assert(sSlack <= slack);
      }

      if ((sSlack ?? 1 << 30) >= 0) {
        final row = firstFitRegion(
          columnAllocations,
          remainingColumns,
          regionLength,
          space.start,
          sSlack,
        );

        if (row != null) {
          // Allocate this region in the current column
          allocations.add(row, regionLength);
          return row;
        }
      }
    }

    return null; // no fit
  }

  /// Positions the regions starting at the earliest row for which none of the
  /// columns are in use.
  /// Slot regions in earliest possible row.
  static (List<(int, RegionShape)>, Map<RegionColumn, AllocationsRegion>)
      slotIn(List<RegionShape> regionShapes) {
    final columnAllocations = <RegionColumn, AllocationsRegion>{};
    final regions = <(int, RegionShape)>[];

    for (final region in regionShapes) {
      // Sort columns deterministically to match Rust behavior
      final regionColumns = region.columns.toList()..sort();
      final regionStart = firstFitRegion(
        columnAllocations,
        regionColumns,
        region.rowCount,
        0,
        null,
      )!;

      regions.add((regionStart, region));
    }

    return (regions, columnAllocations);
  }

  /// Sorts the regions by advice area and then lays them out.
  static (List<int>, Map<RegionColumn, AllocationsRegion>)
      slotInBiggestAdviceFirst(List<RegionShape> regionShapes) {
    List<RegionShape> sortedRegions = List<RegionShape>.from(regionShapes);

    int sortKey(RegionShape shape) {
      final adviceCols = shape.columns.where((c) {
        if (c is RegionColumnColumn) {
          return c.column.columnType == AnyAdvice();
        }
        return false;
      }).length;
      return adviceCols * shape.rowCount;
    }

    sortedRegions.sort((a, b) {
      final c = sortKey(a).compareTo(sortKey(b));
      if (c != 0) return c;
      return regionShapes.indexOf(a).compareTo(regionShapes.indexOf(b));
    });
    sortedRegions = sortedRegions.reversed.toList();
    final (regionsWithShapes, columnAllocations) = slotIn(sortedRegions);
    regionsWithShapes
        .sort((a, b) => a.$2.regionIndex.compareTo(b.$2.regionIndex));
    final regionStarts = regionsWithShapes.map((e) => e.$1).toList();
    return (regionStarts, columnAllocations);
  }
}
