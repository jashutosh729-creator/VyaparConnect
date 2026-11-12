import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {
    // A clear setup prompt is shown in app when Firebase isn't configured.
  }
  runApp(const VyaparConnectApp());
}

class VyaparConnectApp extends StatelessWidget {
  const VyaparConnectApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'VyaparConnect',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF16745A), primary: const Color(0xFF16745A), secondary: const Color(0xFFDA9B43)),
          scaffoldBackgroundColor: const Color(0xFFF7F8F5),
          appBarTheme: const AppBarTheme(backgroundColor: Color(0xFFF7F8F5), foregroundColor: Color(0xFF162C29)),
          inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
        ),
        home: const AuthGate(),
      );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    if (Firebase.apps.isEmpty) return const AuthPage(configMissing: true);
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, auth) {
        if (auth.connectionState == ConnectionState.waiting) return const LoadingPage();
        final user = auth.data;
        if (user == null) return const AuthPage();
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
          builder: (context, profile) {
            if (profile.connectionState == ConnectionState.waiting) return const LoadingPage();
            if (profile.hasError) return ErrorPage(message: 'Could not load your profile: ${profile.error}');
            final data = profile.data?.data();
            if (data == null) return AuthPage(configMissing: false, profileMissing: true, user: user);
            return Dashboard(uid: user.uid, email: user.email ?? '', role: data['role'] as String? ?? 'retailer', name: data['name'] as String? ?? '', business: data['businessName'] as String? ?? '');
          },
        );
      },
    );
  }
}

class LoadingPage extends StatelessWidget {
  const LoadingPage({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class ErrorPage extends StatelessWidget {
  const ErrorPage({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(message))));
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, this.configMissing = false, this.profileMissing = false, this.user});
  final bool configMissing;
  final bool profileMissing;
  final User? user;
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController();
  final business = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  final phone = TextEditingController();
  final city = TextEditingController();
  final category = TextEditingController();
  bool login = true;
  bool busy = false;
  bool obscure = true;
  String role = 'retailer';

  @override
  void initState() {
    super.initState();
    if (widget.profileMissing) {
      login = false;
      email.text = widget.user?.email ?? '';
    }
  }

  @override
  void dispose() {
    for (final c in [name, business, email, password, phone, city, category]) { c.dispose(); }
    super.dispose();
  }

  String? requiredField(String? value) => value == null || value.trim().isEmpty ? 'Required' : null;
  void message(String text) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }

  Future<void> submit() async {
    if (widget.configMissing) { message('Firebase setup is needed. Follow the steps in README.md.'); return; }
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      if (login) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: email.text.trim(), password: password.text);
      } else {
        final credential = widget.user == null
            ? await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email.text.trim(), password: password.text)
            : null;
        final profileUser = widget.user ?? credential!.user!;
        await FirebaseFirestore.instance.collection('users').doc(profileUser.uid).set({
          'uid': profileUser.uid,
          'email': profileUser.email,
          'role': role,
          'name': name.text.trim(),
          'businessName': business.text.trim(),
          'phone': phone.text.trim(),
          'city': city.text.trim(),
          'category': category.text.trim(),
          'approvalStatus': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } on FirebaseAuthException catch (e) {
      message(switch (e.code) {
        'user-not-found' || 'wrong-password' || 'invalid-credential' => 'Email or password is incorrect.',
        'email-already-in-use' => 'An account already exists for this email.',
        'weak-password' => 'Choose a password with at least 6 characters.',
        'invalid-email' => 'Enter a valid email address.',
        _ => e.message ?? 'Authentication failed.',
      });
    } on FirebaseException catch (e) {
      message(e.code == 'permission-denied' ? 'Firestore permission denied. Check Firebase rules.' : 'Firebase error: ${e.message ?? e.code}');
    } catch (e) { message('Could not complete request: $e'); }
    finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> resetPassword() async {
    if (email.text.trim().isEmpty) { message('Enter your email first.'); return; }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.text.trim());
      message('Reset link sent to your email.');
    } on FirebaseAuthException catch (e) { message(e.message ?? 'Could not send reset link.'); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(child: LayoutBuilder(builder: (context, box) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 30),
          child: ConstrainedBox(constraints: BoxConstraints(minHeight: box.maxHeight - 54), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Container(width: 46, height: 46, decoration: BoxDecoration(color: const Color(0xFF16745A), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.storefront_rounded, color: Colors.white)), const SizedBox(width: 12), const Text('VyaparConnect', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF162C29)))]),
              const SizedBox(height: 42),
              Text(widget.configMissing ? 'Firebase setup needed' : widget.profileMissing ? 'Finish your profile' : login ? 'Trade direct.\nGrow together.' : 'Join the marketplace', style: const TextStyle(fontSize: 32, height: 1.12, fontWeight: FontWeight.w800, color: Color(0xFF162C29))),
              const SizedBox(height: 10),
              Text(widget.configMissing ? 'Connect your Firebase project to enable account access.' : 'A better way for manufacturers and retailers to do business.', style: const TextStyle(color: Color(0xFF68756E), fontSize: 15)),
              const SizedBox(height: 30),
              if (!widget.configMissing) Form(key: form, child: Column(children: [
                if (!login) ...[
                  SegmentedButton<String>(segments: const [ButtonSegment(value: 'retailer', label: Text('Retailer')), ButtonSegment(value: 'manufacturer', label: Text('Manufacturer'))], selected: {role}, onSelectionChanged: (v) => setState(() => role = v.first)),
                  const SizedBox(height: 14),
                  field(name, 'Full name', Icons.person_outline), const SizedBox(height: 12),
                  field(business, role == 'retailer' ? 'Shop / business name' : 'Company name', Icons.business_outlined), const SizedBox(height: 12),
                  if (role == 'manufacturer') ...[field(category, 'Manufacturing category', Icons.category_outlined), const SizedBox(height: 12)],
                  field(phone, 'Phone number', Icons.phone_outlined, type: TextInputType.phone), const SizedBox(height: 12),
                  field(city, 'City', Icons.location_city_outlined), const SizedBox(height: 12),
                ],
                field(email, 'Email address', Icons.mail_outline, type: TextInputType.emailAddress, validator: (v) => v != null && v.contains('@') ? null : 'Enter a valid email'), const SizedBox(height: 12),
                TextFormField(controller: password, obscureText: obscure, validator: (v) => v == null || v.length < 6 ? 'Use at least 6 characters' : null, decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(onPressed: () => setState(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined)))),
                if (login) Align(alignment: Alignment.centerRight, child: TextButton(onPressed: resetPassword, child: const Text('Forgot password?'))),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: ElevatedButton(onPressed: busy ? null : submit, child: busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(widget.configMissing ? 'Setup required' : widget.profileMissing ? 'Save profile' : login ? 'Sign in' : 'Create account'))),
                if (!widget.profileMissing) TextButton(onPressed: () => setState(() => login = !login), child: Text(login ? 'New here? Create an account' : 'Already registered? Sign in')),
              ])),
              if (widget.configMissing) Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: const Color(0xFFE8F3ED), borderRadius: BorderRadius.circular(16)), child: const Text('Firebase setup (run from project root):\n1. Install FlutterFire CLI: dart pub global activate flutterfire_cli\n2. Configure Android: flutterfire configure --platforms=android\n3. Enable Email/Password in Firebase Console → Authentication → Sign-in method\n4. Create Firestore database in Firebase Console\n5. Run: flutter pub get\n6. Start the app: flutter run', style: TextStyle(height: 1.7, color: Color(0xFF162C29)))),
            ]),
            if (!widget.configMissing) const Padding(padding: EdgeInsets.only(top: 28), child: Text('By continuing, you agree to use VyaparConnect for business trade.', style: TextStyle(fontSize: 12, color: Color(0xFF87918C)))),
          ])),
        ))),
      );

  Widget field(TextEditingController controller, String label, IconData icon, {TextInputType? type, String? Function(String?)? validator}) => TextFormField(controller: controller, keyboardType: type, validator: validator ?? requiredField, decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)));
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key, required this.uid, required this.email, required this.role, required this.name, required this.business});
  final String uid, email, role, name, business;
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  int index = 0;
  bool get manufacturer => widget.role == 'manufacturer';
  List<(String, IconData)> get tabs => manufacturer ? [('Overview', Icons.space_dashboard_outlined), ('Products', Icons.inventory_2_outlined), ('Orders', Icons.receipt_long_outlined), ('Messages', Icons.chat_outlined), ('Profile', Icons.person_outline)] : [('Home', Icons.home_outlined), ('Products', Icons.grid_view_outlined), ('Cart', Icons.shopping_cart_outlined), ('Orders', Icons.receipt_long_outlined), ('Profile', Icons.person_outline)];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('VyaparConnect', style: TextStyle(fontWeight: FontWeight.w800)), actions: [IconButton(onPressed: () => FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout))]),
    body: index == 0 ? overview() : index == 1 && !manufacturer ? ProductCatalog(uid: widget.uid, name: widget.name, business: widget.business) : index == 1 ? ProductManager(uid: widget.uid) : index == 2 && manufacturer ? OrderList(uid: widget.uid, incoming: true) : index == 2 ? RetailerCart(uid: widget.uid, name: widget.name) : index == 3 ? OrderList(uid: widget.uid, incoming: manufacturer) : index == 3 && !manufacturer ? ChatHub(uid: widget.uid) : ProfilePage(uid: widget.uid, email: widget.email, name: widget.name, business: widget.business, role: widget.role),
    bottomNavigationBar: NavigationBar(selectedIndex: index, onDestinationSelected: (i) => setState(() => index = i), destinations: [for (final tab in tabs) NavigationDestination(icon: Icon(tab.$2), label: tab.$1)]),
  );

  Widget overview() => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance.collection('products').where('manufacturerId', isEqualTo: widget.uid).snapshots(),
    builder: (context, products) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('orders').where(manufacturer ? 'manufacturerId' : 'retailerId', isEqualTo: widget.uid).snapshots(),
      builder: (context, orders) {
        final count = manufacturer ? products.data?.docs.length ?? 0 : 0;
        final orderCount = orders.data?.docs.length ?? 0;
        return ListView(padding: const EdgeInsets.all(20), children: [
          Text('Good day, ${widget.name.isEmpty ? 'there' : widget.name.split(' ').first}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF162C29))),
          const SizedBox(height: 6), Text(manufacturer ? 'Your business, moving forward.' : 'What would you like to source today?', style: const TextStyle(color: Color(0xFF68756E))),
          const SizedBox(height: 24),
          if (manufacturer) Row(children: [Expanded(child: statCard('Products', '$count', Icons.inventory_2_outlined)), const SizedBox(width: 12), Expanded(child: statCard('Orders', '$orderCount', Icons.receipt_long_outlined))])
          else TextField(readOnly: true, onTap: () => setState(() => index = 1), decoration: const InputDecoration(hintText: 'Search products', prefixIcon: Icon(Icons.search))),
          const SizedBox(height: 22), Text(manufacturer ? 'Quick actions' : 'Explore VyaparConnect', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          GridView.count(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.3, children: manufacturer ? [action('Add product', Icons.add_box_outlined), action('My products', Icons.inventory_2_outlined), action('Incoming orders', Icons.receipt_long_outlined), action('Messages', Icons.chat_outlined)] : [action('Browse products', Icons.category_outlined), action('Your cart', Icons.shopping_cart_outlined), action('My orders', Icons.receipt_long_outlined), action('Chat', Icons.chat_outlined)]),
          const SizedBox(height: 22), Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFFE8F3ED), borderRadius: BorderRadius.circular(18)), child: const Text('A stronger local supply chain\n\nConnect with businesses directly and build lasting trade relationships.', style: TextStyle(height: 1.45, color: Color(0xFF162C29)))),
        ]);
      },
    ),
  );

  Widget statCard(String title, String value, IconData icon) => Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: const Color(0xFF16745A)), const SizedBox(height: 14), Text(value, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800)), Text(title, style: const TextStyle(color: Color(0xFF68756E)))]));
  Widget action(String title, IconData icon) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: const Color(0xFF16745A)), const Spacer(), Text(title, style: const TextStyle(fontWeight: FontWeight.w700))]));
}

class ProductCatalog extends StatefulWidget {
  const ProductCatalog({super.key, required this.uid, required this.name, required this.business});
  final String uid, name, business;
  @override
  State<ProductCatalog> createState() => _ProductCatalogState();
}

class _ProductCatalogState extends State<ProductCatalog> {
  final search = TextEditingController();
  String query = '';
  @override
  void dispose() { search.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Column(children: [Padding(padding: const EdgeInsets.all(16), child: TextField(controller: search, onChanged: (v) => setState(() => query = v.toLowerCase()), decoration: const InputDecoration(hintText: 'Search products', prefixIcon: Icon(Icons.search)))), Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: FirebaseFirestore.instance.collection('products').orderBy('createdAt', descending: true).snapshots(), builder: (context, snap) {
    if (snap.hasError) return Center(child: Text('Could not load products: ${snap.error}'));
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    final items = snap.data!.docs.where((doc) => (doc.data()['name'] as String? ?? '').toLowerCase().contains(query)).toList();
    if (items.isEmpty) return const Center(child: Text('No products yet. Manufacturers can add the first listing.'));
    return ListView.builder(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), itemCount: items.length, itemBuilder: (context, i) => ProductCard(doc: items[i], retailerId: widget.uid, retailerName: widget.name, retailerBusiness: widget.business));
  }))]);
}

class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.doc, required this.retailerId, required this.retailerName, required this.retailerBusiness});
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final String retailerId, retailerName, retailerBusiness;
  @override
  Widget build(BuildContext context) {
    final p = doc.data();
    return Card(color: Colors.white, margin: const EdgeInsets.only(bottom: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(p['name'] as String? ?? 'Product', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))), Text('₹${p['price'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF16745A), fontSize: 17))]),
      const SizedBox(height: 5), Text('${p['category'] ?? 'Other'} · ${p['manufacturerName'] ?? 'Manufacturer'}', style: const TextStyle(color: Color(0xFF68756E))),
      if ((p['description'] as String? ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(p['description'] as String)),
      const SizedBox(height: 9), Row(children: [Text('Stock: ${p['quantity'] ?? 0}', style: const TextStyle(fontSize: 12, color: Color(0xFF68756E))), const Spacer(), OutlinedButton.icon(onPressed: () => openChat(context, retailerId: retailerId, retailerName: retailerName, manufacturerId: p['manufacturerId'] as String? ?? '', manufacturerName: p['manufacturerName'] as String? ?? 'Manufacturer', productId: doc.id, productName: p['name'] as String? ?? '', negotiation: true), icon: const Icon(Icons.price_change_outlined), label: const Text('Negotiate')), const SizedBox(width: 8), FilledButton(onPressed: () => addToCart(context, doc, retailerId), child: const Text('Add'))]),
    ])));
  }
}

Future<void> addToCart(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> product, String uid) async {
  try {
    await FirebaseFirestore.instance.collection('carts').doc(uid).collection('items').doc(product.id).set({'productId': product.id, ...product.data(), 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to cart')));
  } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add to cart: $e'))); }
}

class ProductManager extends StatelessWidget {
  const ProductManager({super.key, required this.uid});
  final String uid;
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.transparent, body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: FirebaseFirestore.instance.collection('products').where('manufacturerId', isEqualTo: uid).snapshots(), builder: (context, snap) {
    if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    if (snap.data!.docs.isEmpty) return const Center(child: Text('No products yet. Tap + to add your first product.'));
    return ListView(padding: const EdgeInsets.all(16), children: [for (final product in snap.data!.docs) ListTile(title: Text(product.data()['name'] as String? ?? ''), subtitle: Text('₹${product.data()['price'] ?? 0} · Stock ${product.data()['quantity'] ?? 0}'), trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => product.reference.delete()))]);
  }), floatingActionButton: FloatingActionButton.extended(onPressed: () => showProductForm(context, uid), icon: const Icon(Icons.add), label: const Text('Add product')));
}

Future<void> showProductForm(BuildContext context, String uid) async {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(), desc = TextEditingController(), price = TextEditingController(), qty = TextEditingController();
  String category = 'Clothing';
  final profile = await FirebaseFirestore.instance.collection('users').doc(uid).get();
  final manufacturerName = profile.data()?['businessName'] as String? ?? profile.data()?['name'] as String? ?? 'Manufacturer';
  if (!context.mounted) return;
  await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (sheetContext) => StatefulBuilder(builder: (sheetContext, setSheet) => Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(sheetContext).bottom + 20), child: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Add a product', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)), const SizedBox(height: 18), TextFormField(controller: name, validator: (v) => v == null || v.isEmpty ? 'Required' : null, decoration: const InputDecoration(labelText: 'Product name')), const SizedBox(height: 10), TextFormField(controller: desc, decoration: const InputDecoration(labelText: 'Description')), const SizedBox(height: 10), DropdownButtonFormField<String>(initialValue: category, items: const ['Clothing','Footwear','Electronics','Grocery','Furniture','Cosmetics','Hardware','Other'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), onChanged: (v) => setSheet(() => category = v!), decoration: const InputDecoration(labelText: 'Category')), const SizedBox(height: 10), Row(children: [Expanded(child: TextFormField(controller: price, keyboardType: TextInputType.number, validator: (v) => double.tryParse(v ?? '') == null ? 'Enter price' : null, decoration: const InputDecoration(labelText: 'Wholesale price (₹)'))), const SizedBox(width: 10), Expanded(child: TextFormField(controller: qty, keyboardType: TextInputType.number, validator: (v) => int.tryParse(v ?? '') == null ? 'Enter quantity' : null, decoration: const InputDecoration(labelText: 'Stock quantity')))]), const SizedBox(height: 16), SizedBox(width: double.infinity, child: FilledButton(onPressed: () async { if (!form.currentState!.validate()) return; try { await FirebaseFirestore.instance.collection('products').add({'name': name.text.trim(), 'description': desc.text.trim(), 'category': category, 'price': double.parse(price.text), 'quantity': int.parse(qty.text), 'manufacturerId': uid, 'manufacturerName': manufacturerName, 'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()}); if (sheetContext.mounted) Navigator.pop(sheetContext); } catch (e) { if (sheetContext.mounted) ScaffoldMessenger.of(sheetContext).showSnackBar(SnackBar(content: Text('Could not save: $e'))); } }, child: const Text('Publish product')))]))))));
  name.dispose(); desc.dispose(); price.dispose(); qty.dispose();
}

class RetailerCart extends StatelessWidget {
  const RetailerCart({super.key, required this.uid, required this.name});
  final String uid, name;
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: FirebaseFirestore.instance.collection('carts').doc(uid).collection('items').snapshots(), builder: (context, snap) {
    if (snap.hasError) return Center(child: Text('Cart error: ${snap.error}'));
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    final docs = snap.data!.docs;
    if (docs.isEmpty) return const Center(child: Text('Your cart is empty. Browse products to add items.'));
    final total = docs.fold<double>(0, (runningTotal, d) => runningTotal + ((d.data()['price'] as num?)?.toDouble() ?? 0));
    return Column(children: [Expanded(child: ListView(children: [for (final d in docs) ListTile(title: Text(d.data()['name'] as String? ?? ''), subtitle: Text('₹${d.data()['price'] ?? 0} · ${d.data()['manufacturerName'] ?? ''}'), trailing: IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => d.reference.delete()))])), Padding(padding: const EdgeInsets.all(16), child: Column(children: [Text('Total: ₹${total.toStringAsFixed(2)}'), const SizedBox(height: 10), SizedBox(width: double.infinity, child: FilledButton(onPressed: () async { try { final db = FirebaseFirestore.instance; final batch = db.batch(); for (final d in docs) { final p = d.data(); final order = db.collection('orders').doc(); batch.set(order, {'productId': p['productId'], 'productName': p['name'], 'price': p['price'], 'retailerId': uid, 'retailerName': name, 'manufacturerId': p['manufacturerId'], 'manufacturerName': p['manufacturerName'], 'status': 'pending', 'createdAt': FieldValue.serverTimestamp()}); batch.delete(d.reference); } await batch.commit(); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order placed'))); } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not place order: $e'))); } }, child: const Text('Place order')))]))]);
  });
}

class OrderList extends StatelessWidget {
  const OrderList({super.key, required this.uid, required this.incoming});
  final String uid;
  final bool incoming;
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: FirebaseFirestore.instance.collection('orders').where(incoming ? 'manufacturerId' : 'retailerId', isEqualTo: uid).snapshots(), builder: (context, snap) {
    if (snap.hasError) return Center(child: Text('Orders error: ${snap.error}'));
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    if (snap.data!.docs.isEmpty) return const Center(child: Text('No orders yet.'));
    return ListView(padding: const EdgeInsets.all(12), children: [for (final doc in snap.data!.docs) Builder(builder: (context) { final o = doc.data(); final status = o['status'] as String? ?? 'pending'; return Card(color: Colors.white, child: ListTile(title: Text(o['productName'] as String? ?? 'Order'), subtitle: Text('₹${o['price'] ?? 0} · ${incoming ? o['retailerName'] ?? 'Retailer' : o['manufacturerName'] ?? 'Manufacturer'}\nStatus: $status'), isThreeLine: true, trailing: incoming && status == 'pending' ? PopupMenuButton<String>(onSelected: (v) => doc.reference.update({'status': v, 'updatedAt': FieldValue.serverTimestamp()}), itemBuilder: (_) => const [PopupMenuItem(value: 'accepted', child: Text('Accept')), PopupMenuItem(value: 'rejected', child: Text('Reject'))]) : null)); })]);
  });
}

String chatIdFor(String a, String b) { final ids = [a, b]..sort(); return ids.join('_'); }

Future<void> openChat(BuildContext context, {required String retailerId, required String retailerName, required String manufacturerId, required String manufacturerName, String? productId, String? productName, bool negotiation = false}) async {
  if (manufacturerId.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Manufacturer profile missing.'))); return; }
  final id = chatIdFor(retailerId, manufacturerId);
  await FirebaseFirestore.instance.collection('chats').doc(id).set({'participants': [retailerId, manufacturerId], 'retailerId': retailerId, 'manufacturerId': manufacturerId, 'retailerName': retailerName, 'manufacturerName': manufacturerName, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  if (!context.mounted) return;
  await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(chatId: id, senderId: retailerId, senderName: retailerName, otherName: manufacturerName, productId: productId, productName: productName, negotiation: negotiation)));
}

class ChatHub extends StatelessWidget {
  const ChatHub({super.key, required this.uid});
  final String uid;
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: FirebaseFirestore.instance.collection('chats').where('participants', arrayContains: uid).snapshots(), builder: (context, snap) {
    if (snap.hasError) return Center(child: Text('Messages error: ${snap.error}'));
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    if (snap.data!.docs.isEmpty) return const Center(child: Text('No conversations yet. Open a product and tap Negotiate to start.'));
    return ListView(children: [for (final d in snap.data!.docs) ListTile(leading: const CircleAvatar(child: Icon(Icons.storefront)), title: Text(d.data()['retailerName'] as String? ?? 'Retailer'), subtitle: const Text('Open conversation'), onTap: () { final data = d.data(); Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(chatId: d.id, senderId: uid, senderName: 'Manufacturer', otherName: data['retailerName'] as String? ?? 'Retailer'))); })]);
  });
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.chatId, required this.senderId, required this.senderName, required this.otherName, this.productId, this.productName, this.negotiation = false});
  final String chatId, senderId, senderName, otherName;
  final String? productId, productName;
  final bool negotiation;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final text = TextEditingController(), price = TextEditingController(), quantity = TextEditingController();
  @override
  void dispose() { text.dispose(); price.dispose(); quantity.dispose(); super.dispose(); }
  Future<void> send(String type) async {
    final message = type == 'text' ? text.text.trim() : 'Price proposal: ₹${price.text} for ${quantity.text} units';
    if (message.isEmpty || (type == 'negotiation' && (double.tryParse(price.text) == null || int.tryParse(quantity.text) == null))) return;
    final db = FirebaseFirestore.instance;
    await db.collection('chats').doc(widget.chatId).collection('messages').add({'senderId': widget.senderId, 'senderName': widget.senderName, 'text': message, 'type': type, 'status': type == 'negotiation' ? 'pending' : null, 'productId': widget.productId, 'productName': widget.productName, 'createdAt': FieldValue.serverTimestamp()});
    await db.collection('chats').doc(widget.chatId).set({'lastMessage': message, 'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    text.clear();
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(widget.otherName)), body: Column(children: [Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').orderBy('createdAt').snapshots(), builder: (context, snap) { if (snap.hasError) return Center(child: Text('Chat error: ${snap.error}')); if (!snap.hasData) return const Center(child: CircularProgressIndicator()); return ListView(padding: const EdgeInsets.all(14), children: [for (final d in snap.data!.docs) _messageBubble(context, d)]); })), if (widget.negotiation) Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [Expanded(child: TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Proposed price (₹)'))), const SizedBox(width: 8), Expanded(child: TextField(controller: quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity'))), IconButton(onPressed: () => send('negotiation'), icon: const Icon(Icons.price_change, color: Color(0xFF16745A)))])), SafeArea(child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [Expanded(child: TextField(controller: text, decoration: const InputDecoration(hintText: 'Write a message'))), IconButton(onPressed: () => send('text'), icon: const Icon(Icons.send, color: Color(0xFF16745A)))])))]));

  Widget _messageBubble(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) { final m = doc.data(); final mine = m['senderId'] == widget.senderId; final isNegotiation = m['type'] == 'negotiation'; final status = m['status'] as String? ?? ''; return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), constraints: const BoxConstraints(maxWidth: 300), decoration: BoxDecoration(color: mine ? const Color(0xFFE4F2EA) : Colors.white, borderRadius: BorderRadius.circular(14)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(m['text'] as String? ?? ''), if (isNegotiation && !mine && status == 'pending') Row(mainAxisSize: MainAxisSize.min, children: [TextButton(onPressed: () => doc.reference.update({'status': 'accepted'}), child: const Text('Accept')), TextButton(onPressed: () => doc.reference.update({'status': 'rejected'}), child: const Text('Reject'))]), if (isNegotiation && status.isNotEmpty) Text('Status: $status', style: const TextStyle(fontSize: 12, color: Color(0xFF68756E)))]))); }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.uid, required this.email, required this.name, required this.business, required this.role});
  final String uid, email, name, business, role;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [const CircleAvatar(radius: 34, child: Icon(Icons.person, size: 34)), const SizedBox(height: 18), Center(child: Text(business.isEmpty ? name : business, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))), Center(child: Text(role.toUpperCase(), style: const TextStyle(color: Color(0xFF16745A)))), const Divider(height: 32), ListTile(leading: const Icon(Icons.mail_outline), title: Text(email)), ListTile(leading: const Icon(Icons.badge_outlined), title: Text(name)), ListTile(leading: const Icon(Icons.fingerprint), title: Text(uid)), FilledButton.icon(onPressed: () => FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout), label: const Text('Sign out'))]);
}
