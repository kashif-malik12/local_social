import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _name = TextEditingController();
  final _bio = TextEditingController();
  String _accountType = 'person';
  int _radiusKm = 5;

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw 'Not logged in';

      await Supabase.instance.client
          .from('profiles')
          .update({
            'full_name': _name.text.trim(),
            'bio': _bio.text.trim().isEmpty ? null : _bio.text.trim(),
            'account_type': _accountType,
            'radius_km': _radiusKm,
          })
          .eq('id', user.id);

      if (mounted) context.go('/home');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complete Profile')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              value: _accountType,
              items: const [
                DropdownMenuItem(value: 'person', child: Text('Person')),
                DropdownMenuItem(value: 'business', child: Text('Business')),
              ],
              onChanged: (v) => setState(() => _accountType = v ?? 'person'),
              decoration: const InputDecoration(labelText: 'Account type'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bio,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Bio (optional)'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _radiusKm,
              items: const [
                DropdownMenuItem(value: 5, child: Text('5 km')),
                DropdownMenuItem(value: 10, child: Text('10 km')),
                DropdownMenuItem(value: 20, child: Text('20 km')),
              ],
              onChanged: (v) => setState(() => _radiusKm = v ?? 5),
              decoration: const InputDecoration(labelText: 'Feed radius'),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _save,
                child: Text(_loading ? 'Saving...' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
