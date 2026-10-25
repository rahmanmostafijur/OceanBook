import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child, {double scale = 1, double width = 360}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: app!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child),
      ),
    ),
  );
}

const _months = [
  ChartDatum(label: 'Aug', value: 0, semanticLabel: 'August: 0'),
  ChartDatum(label: 'Sep', value: 2, semanticLabel: 'September: 2'),
  ChartDatum(label: 'Oct', value: 5, semanticLabel: 'October: 5'),
];

void main() {
  testWidgets('a stat tile is read as one phrase', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      const StatTile(icon: Icons.book, label: 'Books', value: '12', caption: '3 new', tone: StatTone.success),
    );
    expect(find.bySemanticsLabel('Books, 12, 3 new'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a column chart reads every bar and prints non-zero counts', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const ColumnChart(data: _months));
    expect(find.bySemanticsLabel('August: 0; September: 2; October: 5'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('0'), findsNothing, reason: 'empty bars carry no number');
    handle.dispose();
  });

  testWidgets('ranked bars scale to the given maximum', (tester) async {
    await _pump(
      tester,
      const RankedBars(data: [ChartDatum(label: 'Reading', value: 2)], maxValue: 8),
    );
    final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, 0.25);
  });

  testWidgets('settings sections have a header and dividers between rows only', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      const SettingsSection(
        title: 'Appearance',
        children: [
          ListTile(title: Text('Theme')),
          ListTile(title: Text('Language')),
          ListTile(title: Text('Font')),
        ],
      ),
    );
    expect(tester.getSemantics(find.text('Appearance')).flagsCollection.isHeader, isTrue);
    expect(find.byType(Divider), findsNWidgets(2));
    handle.dispose();
  });

  testWidgets('cards and charts do not overflow at 200 % text on a narrow screen', (tester) async {
    await _pump(
      tester,
      const Column(
        children: [
          SurfaceCard(
            title: 'Books finished in the last twelve months',
            subtitle: 'Two books',
            child: ColumnChart(data: _months),
          ),
          StatTile(icon: Icons.book, label: 'Pages finished', value: '12,345'),
          RankedBars(data: [ChartDatum(label: 'A very long publisher name that wraps', value: 3)]),
        ],
      ),
      scale: 2,
      width: 320,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('crowded charts show fewer, readable labels instead of shrinking them all', (tester) async {
    final year = [for (var i = 1; i <= 12; i++) ChartDatum(label: 'M$i', value: i)];
    await _pump(tester, ColumnChart(data: year), scale: 2, width: 320);
    final shown = [
      for (var i = 1; i <= 12; i++)
        if (find.text('M$i').evaluate().isNotEmpty) i,
    ];
    expect(shown, contains(12), reason: 'the newest bar keeps its label');
    expect(shown.length, lessThan(12));
    final newest = tester.getSize(find.text('M12'));
    expect(newest.height, greaterThanOrEqualTo(11 * 2 * 0.9), reason: 'label keeps its scaled size');
    expect(tester.takeException(), isNull);
  });

  testWidgets('chart counts use the given number format', (tester) async {
    await _pump(
      tester,
      ColumnChart(data: _months, format: (n) => '#$n'),
    );
    expect(find.text('#5'), findsOneWidget);
  });
}
