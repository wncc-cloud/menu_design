import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../shared/models/draft_item_model.dart';
import '../../../shared/models/draft_section_model.dart';
import '../../../shared/services/cloudinary_service.dart';
import '../../../shared/services/image_service.dart';

class ItemFormDialog extends StatefulWidget {
  final List<DraftSectionModel> sections;
  final DraftItemModel? existing;

  const ItemFormDialog({
    super.key,
    required this.sections,
    this.existing,
  });

  @override
  State<ItemFormDialog> createState() => _ItemFormDialogState();
}

class _ItemFormDialogState extends State<ItemFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _ingCtrl;
  late final TextEditingController _fromCtrl;
  late final TextEditingController _tillCtrl;

  late String _sectionId;
  late bool _isVeg;
  late bool _isBestseller;
  late bool _available;

  late String _imageUrl;
  late String _cloudinaryPublicId;
  bool _imageUploading = false;
  String? _imageError;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _priceCtrl = TextEditingController(
        text: e != null ? e.price.toStringAsFixed(0) : '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _ingCtrl = TextEditingController(text: e?.ingredients ?? '');
    _fromCtrl = TextEditingController(text: e?.availableFrom ?? '');
    _tillCtrl = TextEditingController(text: e?.availableTill ?? '');
    _sectionId = e?.sectionId ?? widget.sections.first.id;
    _isVeg = e?.isVeg ?? true;
    _isBestseller = e?.isBestseller ?? false;
    _available = e?.available ?? true;
    _imageUrl = e?.imageUrl ?? '';
    _cloudinaryPublicId = e?.cloudinaryPublicId ?? '';
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl,
      _priceCtrl,
      _descCtrl,
      _ingCtrl,
      _fromCtrl,
      _tillCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickTime(TextEditingController ctrl) async {
    final parts = ctrl.text.split(':');
    final initial = parts.length == 2
        ? TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 0,
            minute: int.tryParse(parts[1]) ?? 0)
        : TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    ctrl.text =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery);
    if (xFile == null || !mounted) return;

    setState(() {
      _imageUploading = true;
      _imageError = null;
    });

    try {
      final bytes = await xFile.readAsBytes();
      final compressed = await ImageService().compress(bytes);

      // Unsigned presets cannot overwrite. Always include a timestamp so the
      // public_id is unique — old images are orphaned (acceptable per plan).
      final ts = DateTime.now().millisecondsSinceEpoch;
      final baseId = widget.existing?.id.isNotEmpty == true
          ? widget.existing!.id
          : ts.toString();

      final result = await CloudinaryService().upload(
        bytes: compressed,
        publicId: '${AppConstants.cloudinaryFolder}/item_${baseId}_$ts',
      );

      if (!mounted) return;
      setState(() {
        _imageUrl = result.secureUrl;
        _cloudinaryPublicId = result.publicId;
        _imageUploading = false;
      });
    } catch (e, st) {
      // ignore: avoid_print
      print('[ItemForm] image upload error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _imageError = 'Upload failed: $e';
        _imageUploading = false;
      });
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;
    final now = DateTime.now();
    final result = DraftItemModel(
      id: widget.existing?.id ?? '',
      sectionId: _sectionId,
      name: _nameCtrl.text.trim(),
      price: price,
      description: _descCtrl.text.trim(),
      ingredients: _ingCtrl.text.trim(),
      imageUrl: _imageUrl,
      cloudinaryPublicId: _cloudinaryPublicId,
      isVeg: _isVeg,
      isBestseller: _isBestseller,
      available: _available,
      availableFrom: _fromCtrl.text.trim(),
      availableTill: _tillCtrl.text.trim(),
      sortOrder: widget.existing?.sortOrder ?? 0,
      businessId: 'default',
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 680),
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: const Color(0xFF2E7D32),
            foregroundColor: Colors.white,
            title: Text(isEdit ? 'Edit Item' : 'Add Item',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.white70)),
              ),
              TextButton(
                onPressed: _imageUploading ? null : _submit,
                child: const Text('Save',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          body: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Image section
                _ImageSection(
                  imageUrl: _imageUrl,
                  uploading: _imageUploading,
                  error: _imageError,
                  onPickImage: _pickAndUploadImage,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name *'),
                  textCapitalization: TextCapitalization.words,
                  autofocus: true,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Name is required'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _priceCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Price (₹) *', prefixText: '₹ '),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
                  ],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Price is required';
                    if (double.tryParse(v.trim()) == null) {
                      return 'Enter a valid number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _sectionId,
                  decoration: const InputDecoration(labelText: 'Section *'),
                  items: widget.sections
                      .map((s) =>
                          DropdownMenuItem(value: s.id, child: Text(s.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _sectionId = v!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _ingCtrl,
                  decoration: const InputDecoration(labelText: 'Ingredients'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _fromCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Available from',
                          hintText: 'HH:MM',
                          suffixIcon: Icon(Icons.access_time),
                        ),
                        readOnly: true,
                        onTap: () => _pickTime(_fromCtrl),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _tillCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Available till',
                          hintText: 'HH:MM',
                          suffixIcon: Icon(Icons.access_time),
                        ),
                        readOnly: true,
                        onTap: () => _pickTime(_tillCtrl),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _ToggleRow(
                  label: 'Vegetarian',
                  value: _isVeg,
                  onChanged: (v) => setState(() => _isVeg = v),
                  activeColor: const Color(0xFF2E7D32),
                ),
                _ToggleRow(
                  label: 'Bestseller',
                  value: _isBestseller,
                  onChanged: (v) => setState(() => _isBestseller = v),
                  activeColor: Colors.orange,
                ),
                _ToggleRow(
                  label: 'Available now',
                  value: _available,
                  onChanged: (v) => setState(() => _available = v),
                  activeColor: const Color(0xFF2E7D32),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageSection extends StatelessWidget {
  final String imageUrl;
  final bool uploading;
  final String? error;
  final VoidCallback onPickImage;

  const _ImageSection({
    required this.imageUrl,
    required this.uploading,
    required this.error,
    required this.onPickImage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Thumbnail
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey[200],
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: uploading
                    ? const Center(child: CircularProgressIndicator())
                    : imageUrl.isNotEmpty
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.broken_image, color: Colors.grey),
                          )
                        : const Icon(Icons.image_outlined,
                            size: 36, color: Colors.grey),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    onPressed: uploading ? null : onPickImage,
                    icon: const Icon(Icons.upload_rounded, size: 18),
                    label: Text(uploading
                        ? 'Uploading…'
                        : imageUrl.isNotEmpty
                            ? 'Change image'
                            : 'Add image'),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 36)),
                  ),
                  if (imageUrl.isNotEmpty && !uploading)
                    Text('Image uploaded',
                        style: TextStyle(
                            fontSize: 11, color: Colors.green[700])),
                  if (error != null)
                    Text(error!,
                        style:
                            const TextStyle(fontSize: 11, color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color activeColor;

  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      value: value,
      onChanged: onChanged,
      activeTrackColor: activeColor.withValues(alpha: 0.4),
      activeThumbColor: activeColor,
    );
  }
}
