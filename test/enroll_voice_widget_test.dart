import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartpoc/auth/auth_provider.dart';
import 'package:smartpoc/auth/enroll_voice_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(envString: 'GOOGLE_WEB_CLIENT_ID=mock-id');

    // Mock platform channel for AudioRecorder
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('com.llfbandit.record/messages'), (MethodCall methodCall) async {
      return null;
    });
  });

  testWidgets('EnrollVoiceScreen renders paragraph and record button correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
        ],
        child: const MaterialApp(
          home: EnrollVoiceScreen(),
        ),
      ),
    );

    // Give time for async initState (_initVerification) to complete
    await tester.runAsync(() async {
      await Future.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    // Verify title and paragraph text are rendered
    expect(find.text('Voice Enrollment'), findsOneWidget);
    expect(find.text('Enroll Your Voice'), findsOneWidget);
    expect(find.textContaining('Once upon a time in a quiet village'), findsOneWidget);

    // Verify initial status and progress counter
    expect(find.textContaining('Progress: 0 / 4'), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(find.text('Tap the button to start recording, tap again when done'), findsOneWidget);
  });
}
