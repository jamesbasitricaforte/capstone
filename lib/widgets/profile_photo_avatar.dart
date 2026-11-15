import 'dart:typed_data';

import 'package:flutter/material.dart';

class ProfilePhotoAvatar extends StatelessWidget {
  const ProfilePhotoAvatar({
    super.key,
    required this.radius,
    this.photoUrl,
    this.photoBytes,
    this.placeholderIcon = Icons.person_outline,
    this.placeholderText,
  });

  final double radius;
  final String? photoUrl;
  final Uint8List? photoBytes;
  final IconData placeholderIcon;
  final String? placeholderText;

  @override
  Widget build(BuildContext context) {
    ImageProvider<Object>? image;
    if (photoBytes?.isNotEmpty == true) {
      image = MemoryImage(photoBytes!);
    } else if (photoUrl?.trim().isNotEmpty == true) {
      image = NetworkImage(photoUrl!);
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE9EFE5),
      child: image == null
          ? _placeholder()
          : ClipOval(
              child: Image(
                image: image,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _placeholder(),
              ),
            ),
    );
  }

  Widget _placeholder() {
    final text = placeholderText;
    if (text == null) {
      return Icon(
        placeholderIcon,
        color: const Color(0xFF245A40),
        size: radius,
      );
    }
    return Text(
      text,
      style: TextStyle(
        color: const Color(0xFF245A40),
        fontSize: radius * 0.57,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
