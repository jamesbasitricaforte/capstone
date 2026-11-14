import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class DesktopPhonePreview extends StatelessWidget {
  const DesktopPhonePreview({super.key, required this.child});

  final Widget child;

  static const _frameSize = Size(430, 900);
  static const _screenSize = Size(410, 880);
  static const _frameColor = Color(0xFF202824);
  static const _screenColor = Color(0xFFF7F5EE);

  bool get _isDesktop =>
      kIsWeb ||
      switch (defaultTargetPlatform) {
        TargetPlatform.windows ||
        TargetPlatform.macOS ||
        TargetPlatform.linux => true,
        _ => false,
      };

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) return child;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760 ||
            !constraints.maxWidth.isFinite ||
            !constraints.maxHeight.isFinite ||
            constraints.maxHeight <= 0) {
          return child;
        }

        const margin = 32.0;
        final availableWidth = math.max(0.0, constraints.maxWidth - margin * 2);
        final availableHeight = math.max(
          0.0,
          constraints.maxHeight - margin * 2,
        );
        final scale = math
            .min(
              math.min(
                availableWidth / _frameSize.width,
                availableHeight / _frameSize.height,
              ),
              1.08,
            )
            .toDouble();
        if (scale <= 0) return child;

        final previewSize = Size(
          _frameSize.width * scale,
          _frameSize.height * scale,
        );

        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE7EBE3), Color(0xFFD8DED5)],
            ),
          ),
          child: Center(
            child: SizedBox(
              key: const ValueKey('desktop-phone-preview'),
              width: previewSize.width,
              height: previewSize.height,
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: _frameSize.width,
                  height: _frameSize.height,
                  child: _PhoneFrame(child: child),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final inheritedMedia = MediaQuery.of(context);
    final phoneMedia = inheritedMedia.copyWith(
      size: DesktopPhonePreview._screenSize,
      padding: const EdgeInsets.only(top: 44, bottom: 22),
      viewPadding: const EdgeInsets.only(top: 44, bottom: 22),
      viewInsets: EdgeInsets.zero,
    );

    return Container(
      decoration: BoxDecoration(
        color: DesktopPhonePreview._frameColor,
        borderRadius: BorderRadius.circular(54),
        border: Border.all(color: const Color(0xFF47514A), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x330D1912),
            blurRadius: 38,
            offset: Offset(0, 22),
          ),
          BoxShadow(color: Color(0x668A968B), blurRadius: 3, spreadRadius: 1),
        ],
      ),
      padding: const EdgeInsets.all(10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(44),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: DesktopPhonePreview._screenColor,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              MediaQuery(data: phoneMedia, child: child),
              const Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: _CameraIsland(key: ValueKey('phone-camera-island')),
                  ),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                top: 14,
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          TimeOfDay.now().format(context),
                          style: const TextStyle(
                            color: Color(0xFF29352D),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Row(
                          children: [
                            Icon(Icons.signal_cellular_alt, size: 13),
                            SizedBox(width: 4),
                            Icon(Icons.wifi, size: 13),
                            SizedBox(width: 4),
                            Icon(Icons.battery_full, size: 15),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 9,
                child: IgnorePointer(
                  child: Center(
                    child: ExcludeSemantics(
                      child: SizedBox(
                        width: 104,
                        height: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Color(0xFF29352D),
                            borderRadius: BorderRadius.all(Radius.circular(4)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraIsland extends StatelessWidget {
  const _CameraIsland({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 112,
      height: 27,
      decoration: BoxDecoration(
        color: const Color(0xFF101511),
        borderRadius: BorderRadius.circular(18),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 12),
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: Color(0xFF283B36),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
