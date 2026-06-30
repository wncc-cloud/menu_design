import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/models/business_model.dart';
import '../../shared/services/cloudinary_service.dart';
import '../../shared/services/image_service.dart';
import '../../../core/constants/app_constants.dart';
import '../auth/auth_provider.dart';
import 'settings_provider.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _instagramCtrl;
  late final TextEditingController _mapsCtrl;
  late final TextEditingController _hoursCtrl;

  BusinessModel? _current;
  bool _saving = false;
  bool _logoUploading = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _instagramCtrl = TextEditingController();
    _mapsCtrl = TextEditingController();
    _hoursCtrl = TextEditingController();
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _phoneCtrl,
      _instagramCtrl,
      _mapsCtrl,
      _hoursCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _loadIntoControllers(BusinessModel b) {
    _current = b;
    _nameCtrl.text = b.cafeName;
    _phoneCtrl.text = b.phone;
    _instagramCtrl.text = b.instagram;
    _mapsCtrl.text = b.mapsUrl;
    _hoursCtrl.text = b.openingHours;
  }

  BusinessModel _buildFromControllers() {
    final base = _current ?? BusinessModel.empty();
    return base.copyWith(
      cafeName: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      instagram: _instagramCtrl.text.trim(),
      mapsUrl: _mapsCtrl.text.trim(),
      openingHours: _hoursCtrl.text.trim(),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final updated = _buildFromControllers();
    final error =
        await ref.read(settingsProvider.notifier).save(updated);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saveError = error;
      if (error == null) _current = updated;
    });
    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved.')),
      );
    }
  }

  Future<void> _uploadLogo() async {
    final picker = ImagePicker();
    final xFile =
        await picker.pickImage(source: ImageSource.gallery);
    if (xFile == null || !mounted) return;

    setState(() => _logoUploading = true);
    try {
      final bytes = await xFile.readAsBytes();
      final compressed = await ImageService().compress(bytes);
      // Unsigned presets cannot overwrite. Append timestamp so each upload
      // gets a unique public_id; the old logo is orphaned (acceptable).
      final ts = DateTime.now().millisecondsSinceEpoch;
      final result = await CloudinaryService().upload(
        bytes: compressed,
        publicId: '${AppConstants.cloudinaryFolder}/logo_$ts',
      );
      if (!mounted) return;

      final updated = _buildFromControllers().copyWith(
        logoUrl: result.secureUrl,
        logoCloudinaryId: result.publicId,
      );
      final error =
          await ref.read(settingsProvider.notifier).save(updated);
      if (!mounted) return;
      if (error == null) {
        setState(() => _current = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logo updated.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Logo save failed: $error'),
              backgroundColor: Colors.red),
        );
      }
    } catch (e, _) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Logo upload failed: $e'),
            backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _logoUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit =
        ref.watch(permissionServiceProvider)?.canManageBusinessSettings ?? false;
    final settingsAsync = ref.watch(settingsProvider);

    if (!canEdit) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF2E7D32),
          foregroundColor: Colors.white,
          title: const Text('Settings',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 48, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Settings are restricted to owners.',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        title: const Text('Settings',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))),
            )
          else
            TextButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading settings: $e')),
        data: (business) {
          // Populate controllers once when data first arrives.
          if (_current == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _loadIntoControllers(business ?? BusinessModel.empty());
                setState(() {});
              }
            });
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo section
                  Center(
                    child: Column(
                      children: [
                        _LogoPreview(
                          logoUrl: _current?.logoUrl ?? business?.logoUrl ?? '',
                          uploading: _logoUploading,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _logoUploading ? null : _uploadLogo,
                          icon: const Icon(Icons.upload_rounded),
                          label: Text(_logoUploading
                              ? 'Uploading…'
                              : ((_current?.logoUrl ?? business?.logoUrl ?? '')
                                      .isNotEmpty
                                  ? 'Change Logo'
                                  : 'Upload Logo')),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  _SectionLabel('Cafe Information'),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Cafe name *'),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Cafe name is required'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      hintText: '+91 98765 43210',
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _instagramCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Instagram handle',
                      hintText: '@cafecountryside',
                      prefixText: '@',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _mapsCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Google Maps URL',
                      hintText: 'https://maps.google.com/...',
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _hoursCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Opening hours',
                      hintText: 'Mon–Sun: 8:00 AM – 10:00 PM',
                    ),
                    maxLines: 2,
                  ),

                  if (_saveError != null) ...[
                    const SizedBox(height: 16),
                    Text(_saveError!,
                        style: const TextStyle(color: Colors.red)),
                  ],

                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: const Text('Save Settings'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LogoPreview extends StatelessWidget {
  final String logoUrl;
  final bool uploading;

  const _LogoPreview({required this.logoUrl, required this.uploading});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
        border: Border.all(
            color: const Color(0xFF2E7D32).withValues(alpha: 0.3), width: 2),
      ),
      child: ClipOval(
        child: uploading
            ? const Center(child: CircularProgressIndicator())
            : logoUrl.isNotEmpty
                ? Image.network(logoUrl, fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.storefront,
                      size: 48,
                      color: Color(0xFF2E7D32),
                    ))
                : const Icon(Icons.storefront,
                    size: 48, color: Color(0xFF2E7D32)),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(color: Colors.grey[600], fontWeight: FontWeight.bold),
    );
  }
}
