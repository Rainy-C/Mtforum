import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../services/api_service.dart';

class AvatarUploadPage extends StatefulWidget {
  const AvatarUploadPage({super.key});

  @override
  State<AvatarUploadPage> createState() => _AvatarUploadPageState();
}

class _AvatarUploadPageState extends State<AvatarUploadPage> {
  final _api = ApiService.instance;
  final _picker = ImagePicker();

  Uint8List? _jpeg;
  bool _processing = false;
  bool _uploading = false;

  Future<void> _pick() async {
    if (_processing || _uploading) return;
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    setState(() => _processing = true);
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        _show('无法解析这张图片');
        return;
      }

      var image = img.bakeOrientation(decoded);
      const maxSide = 1024;
      if (image.width > maxSide || image.height > maxSide) {
        if (image.width >= image.height) {
          image = img.copyResize(image, width: maxSide);
        } else {
          image = img.copyResize(image, height: maxSide);
        }
      }

      final encoded = img.encodeJpg(image, quality: 88);
      if (!mounted) return;
      setState(() => _jpeg = Uint8List.fromList(encoded));
    } catch (e) {
      _show('图片处理失败：$e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _upload() async {
    final jpeg = _jpeg;
    if (jpeg == null || _uploading) return;
    setState(() => _uploading = true);
    final result = await _api.uploadAvatarJpeg(jpeg);
    if (!mounted) return;
    setState(() => _uploading = false);
    _show(result.message);
    if (result.success) Navigator.pop(context, true);
  }

  void _show(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('修改头像')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
        children: [
          Center(
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                shape: BoxShape.circle,
                image: _jpeg == null
                    ? null
                    : DecorationImage(
                        image: MemoryImage(_jpeg!),
                        fit: BoxFit.cover,
                      ),
              ),
              alignment: Alignment.center,
              child: _jpeg == null
                  ? Icon(
                      Icons.person_rounded,
                      size: 70,
                      color: colors.outline,
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.tonalIcon(
            onPressed: _processing || _uploading ? null : _pick,
            icon: _processing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.photo_library_outlined),
            label: Text(_jpeg == null ? '选择图片' : '重新选择'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _jpeg == null || _uploading ? null : _upload,
            icon: _uploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined),
            label: const Text('上传头像'),
          ),
          const SizedBox(height: 12),
          Text(
            '选择后会自动校正方向、缩放到最长边 1024px，并以 JPEG 88% 质量上传。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.outline,
            ),
          ),
        ],
      ),
    );
  }
}
