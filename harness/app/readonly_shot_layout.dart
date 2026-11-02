import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'logical_capture.dart';

/// Numeric layout observations at two boundaries of one original readback.
/// These are not a paint/frame pin or a screenshot acceptance decision.
const List<String> _keys = <String>[
  'window-caption', 'window-body', 'home_hero', 'home_send',
  'nodes_tab_pillars', 'nodes_tab_sentinels', 'staking_stake_button',
  'plasma_open_fuse', 'tokens_filter_held', 'p2p_start_swap',
  'node_settings_add', 'apps_settings_web_switch',
  'transfer_card', 'accelerator_strip', 'bell_panel',
];

/// Unknown widget _keys, text, values and original errors are never copied.
List<Map<String, Object?>> observeReadonlyShotLayout(Element? root) {
  final Map<String, List<Element>> found = <String, List<Element>>{
    for (final String key in _keys) key: <Element>[],
  };
  int visited = 0;
  bool overflow = false;
  void visit(Element element) {
    if (overflow) return;
    if (++visited > 16384) {
      overflow = true;
      return;
    }
    final Widget widget = element.widget;
    if (widget is Offstage && widget.offstage) return;
    if (widget is Visibility && !widget.visible) return;
    final Key? key = widget.key;
    if (key is ValueKey<String> && found.containsKey(key.value)) {
      // Only zero, one or more-than-one matters; retain no unbounded list.
      final List<Element> matches = found[key.value]!;
      if (matches.length < 2) matches.add(element);
    }
    element.visitChildren(visit);
  }
  if (root != null) visit(root);
  return <Map<String, Object?>>[
    for (final String key in _keys)
      if (overflow) <String, Object?>{'key': key, 'status': 'LIMIT'}
      else _bounds(key, found[key]!),
  ];
}

Map<String, Object?> _bounds(String key, List<Element> matches) {
  if (matches.isEmpty) {
    return <String, Object?>{'key': key, 'status': 'MISSING'};
  }
  if (matches.length != 1) {
    return <String, Object?>{'key': key, 'status': 'DUPLICATE'};
  }
  try {
    final RenderObject? original = matches.single.renderObject;
    if (original is RenderBox && original.attached && original.hasSize) {
      final Rect rect = logicalClientRect(original);
      final List<double> values = <double>[
        rect.left, rect.top, rect.right, rect.bottom,
      ];
      if (values.every((double value) => value.isFinite &&
          value.abs() <= 32768) && rect.width > 0 && rect.height > 0) {
        return <String, Object?>{
          'key': key, 'status': 'OBSERVED',
          'rect': <int>[for (final double value in values) value.round()],
        };
      }
    }
  } on Object {
    // Only the fixed status is shared; no original diagnostic is exported.
  }
  return <String, Object?>{'key': key, 'status': 'UNAVAILABLE'};
}

/// Pairs observations without asserting a retained or atomic paint frame.
Map<String, Object?> pairReadonlyShotLayout(
  List<Map<String, Object?>> before,
  List<Map<String, Object?>> after,
) => <String, Object?>{
  'schema': 1,
  'scope': 'readonly_shot_layout_observation',
  'boundaries': <String>['before_raster', 'after_encoding'],
  'before': before,
  'after': after,
  'unchanged': jsonEncode(before) == jsonEncode(after),
};
