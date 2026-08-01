import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sitemark/l10n/app_strings.dart';

/// App-bar search field shared by both capture-list surfaces.
class CaptureSearchField extends StatefulWidget {
  const CaptureSearchField({
    super.key,
    required this.initialText,
    required this.onChanged,
  });

  final String initialText;
  final ValueChanged<String> onChanged;

  @override
  State<CaptureSearchField> createState() => _CaptureSearchFieldState();
}

class _CaptureSearchFieldState extends State<CaptureSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialText,
  );
  Timer? _debounce;
  late String _lastCommittedText = widget.initialText;
  late String _pendingText = widget.initialText;

  @override
  void didUpdateWidget(covariant CaptureSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialText != oldWidget.initialText &&
        widget.initialText != _controller.text) {
      _debounce?.cancel();
      _controller.value = TextEditingValue(
        text: widget.initialText,
        selection: TextSelection.collapsed(offset: widget.initialText.length),
      );
      _pendingText = widget.initialText;
      _lastCommittedText = widget.initialText;
    }
  }

  void _schedule(String value) {
    if (value == _pendingText) return;
    setState(() => _pendingText = value);
    _debounce?.cancel();
    if (value == _lastCommittedText) return;
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted || value != _pendingText || value == _lastCommittedText) {
        return;
      }
      _lastCommittedText = value;
      widget.onChanged(value);
    });
  }

  void _clear() {
    if (_controller.text.isEmpty) return;
    _controller.clear();
    _schedule('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return TextField(
      key: const Key('capture-search-field'),
      controller: _controller,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onChanged: _schedule,
      decoration: InputDecoration(
        hintText: strings.searchCapturesHint,
        border: InputBorder.none,
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                key: const Key('clear-capture-search'),
                tooltip: strings.clearSearch,
                onPressed: _clear,
                icon: const Icon(Icons.close),
              ),
      ),
    );
  }
}
