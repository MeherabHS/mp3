import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/app/app.dart';

/// Returns the greeting the HomeScreen will show for the given hour.
String greetingFor(int hour) {
  if (hour < 12) return 'Good morning,';
  if (hour < 17) return 'Good afternoon,';
  return 'Good evening,';
}

void main() {
  testWidgets('App renders Home, Navigation and Output card', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MusicPlayerApp(),
      ),
    );

    await tester.pumpAndSettle();

    // Greeting is time-aware — derive expected value from the current hour.
    final expectedGreeting = greetingFor(DateTime.now().hour);
    expect(find.text(expectedGreeting), findsOneWidget);

    // Home screen sections
    expect(find.text('Recently Played'), findsOneWidget);
    expect(find.text('Recently Added'), findsOneWidget);

    // Bottom Navigation Bar
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Acquisition'), findsOneWidget);
    expect(find.text('Equalizer'), findsOneWidget);

    // Library tab
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(find.text('Songs'), findsOneWidget);
    expect(find.text('Albums'), findsOneWidget);

    // Equalizer tab
    await tester.tap(find.text('Equalizer'));
    await tester.pumpAndSettle();
    expect(find.text('Audio Tuning Presets'), findsOneWidget);
    expect(find.text('Audiophile Hi-Fi'), findsOneWidget);

    // Enhancement section added in this session
    expect(find.text('Sound Enhancement'), findsOneWidget);
  });
}
