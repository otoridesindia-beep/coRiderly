import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sharemyride/main.dart';

void main() {
  test('local HTML experience uses the four-digit MPIN auth flow', () async {
    final html = await rootBundle.loadString('assets/web/index.html');
    final script = await rootBundle.loadString('assets/web/script.js');
    final styles = await rootBundle.loadString('assets/web/styles.css');

    expect(html, contains('4-digit MPIN'));
    expect(html, contains('CoRiderly'));
    expect(html, isNot(contains('ShareMyRide')));
    expect(html, contains('href="styles.css"'));
    expect(html, contains('src="script.js"'));
    expect(script, contains('/functions/v1/phone-pin-auth'));
    expect(script, contains('action: registering ? \'register\' : \'login\''));
    expect(script, contains('/functions/v1/ride-payment'));
    expect(script, contains("action: 'create_order'"));
    expect(script, contains("action: 'verify_payment'"));
    expect(script, contains('window.PineLabsCheckout'));
    expect(script, contains("document.addEventListener('nativeappresume'"));
    expect(script, contains('order.provider_order_id'));
    expect(html, contains('Pine Labs secure checkout'));
    expect(script, contains('action: \'verify_payment\''));
    expect(script, isNot(contains('phonepe')));
    expect(script, isNot(contains('razorpay')));
    expect(script, contains("addEventListener('touchstart'"));
    expect(script, contains("addEventListener('touchend'"));
    expect(script, contains("deltaX < 0"));
    expect(script, isNot(contains("supabaseRequest('rest/v1/rides',")));
    expect(script, contains('rest/v1/rides'));
    expect(script, contains('async function loadRides()'));
    expect(script, contains('ride-card-modern'));
    expect(script, contains('ride-pickup'));
    expect(styles, contains('.ride-card-modern'));
    expect(styles, contains('.ride-card-footer'));
    expect(html, contains('class="bottom-nav"'));
    expect(html, contains('id="bottom-bookings"'));
    expect(html, contains('id="profile-logout-menu"'));
    expect(html, contains('id="profile-logout-dialog"'));
    expect(html, contains('Pay ₹39 &amp; publish ride'));
    expect(script, contains('function signOut()'));
    expect(script, contains("document.getElementById('bottom-my-rides')"));
    expect(styles, contains('.bottom-nav-tab.active'));
  });

  test('Pine Labs checkout links are restricted to HTTPS provider domains', () {
    expect(
      isPineLabsCheckoutUrl('https://checkout.pluralonline.com/order/123'),
      isTrue,
    );
    expect(isPineLabsCheckoutUrl('https://api.pluralpay.in/checkout'), isTrue);
    expect(isPineLabsCheckoutUrl('http://checkout.pluralonline.com'), isFalse);
    expect(
      isPineLabsCheckoutUrl('https://pluralonline.com.attacker.test'),
      isFalse,
    );
    expect(isPineLabsCheckoutUrl('upi://pay?pa=merchant@upi'), isFalse);
  });

  testWidgets('profile edit returns the updated name', (
    WidgetTester tester,
  ) async {
    String? updatedName;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                updatedName = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => const ProfilePage(
                      fullName: 'Member 2829',
                      phone: '+919380002829',
                    ),
                  ),
                );
              },
              child: const Text('Open profile'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open profile'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Rider Name');
    await tester.tap(find.text('Save profile'));
    await tester.pumpAndSettle();

    expect(updatedName, 'Rider Name');
  });

  testWidgets('ride home exposes search and publish actions', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: RideHome(phone: '+919380002829', fullName: 'Rider Name'),
      ),
    );

    expect(find.text('Looking for a ride'), findsOneWidget);
    expect(find.text('Publish a ride'), findsOneWidget);
    expect(find.text('Travel date'), findsOneWidget);
    expect(find.text('Passengers'), findsOneWidget);
    expect(find.text('Find a ride'), findsOneWidget);
  });

  testWidgets('publish ride form includes private local document selection', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      const MaterialApp(home: OfferRidePage(driverName: 'Rider Name')),
    );

    expect(find.text('Vehicle registration number'), findsOneWidget);
    expect(find.text('Car name / model'), findsOneWidget);
    await tester.ensureVisible(find.text('Aadhaar card — front'));
    expect(find.text('Aadhaar card — front'), findsOneWidget);
    expect(find.text('RC — front'), findsOneWidget);
    expect(find.text('Insurance copy'), findsOneWidget);
    expect(find.textContaining('Pine Labs payment'), findsOneWidget);
    expect(
      find.textContaining('selected documents stay on this device'),
      findsOneWidget,
    );
  });

  test('normalizes Indian mobile numbers for Supabase Auth', () {
    expect(SupabaseAuth.normalizePhoneNumber('9380002829'), '+919380002829');
    expect(SupabaseAuth.normalizePhoneNumber('919380002829'), '+919380002829');
    expect(
      SupabaseAuth.normalizePhoneNumber('+91 93800 02829'),
      '+919380002829',
    );
  });
}
