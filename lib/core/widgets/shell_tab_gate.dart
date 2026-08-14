import 'package:flutter/material.dart';

/// يوفّر رقم التبويب النشط داخل [MainShell].
class ShellScope extends InheritedWidget {
  const ShellScope({
    super.key,
    required this.currentIndex,
    required super.child,
  });

  final int currentIndex;

  static ShellScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ShellScope>();
  }

  @override
  bool updateShouldNotify(ShellScope oldWidget) {
    return oldWidget.currentIndex != currentIndex;
  }
}

/// يبني الشاشة فقط بعد أول زيارة للتبويب — يقلّل مستمعي Firestore عند الإقلاع.
class ShellTabGate extends StatefulWidget {
  const ShellTabGate({
    super.key,
    required this.tabIndex,
    required this.child,
  });

  final int tabIndex;
  final Widget child;

  @override
  State<ShellTabGate> createState() => _ShellTabGateState();
}

class _ShellTabGateState extends State<ShellTabGate> {
  bool _activated = false;

  @override
  Widget build(BuildContext context) {
    final scope = ShellScope.maybeOf(context);
    final active = scope?.currentIndex == widget.tabIndex;
    if (active) {
      _activated = true;
    }
    if (!_activated) {
      return const SizedBox.shrink();
    }
    return widget.child;
  }
}
