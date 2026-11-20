import 'package:flutter/material.dart';

import '../../data/models/chat_message.dart';

typedef ChatMessagePresented = void Function(ChatMessage message);

class ChatVisibleMessage extends StatefulWidget {
  const ChatVisibleMessage({
    required this.message,
    required this.generation,
    required this.onPresented,
    required this.child,
    super.key,
  });

  final ChatMessage message;
  final int generation;
  final ChatMessagePresented onPresented;
  final Widget child;

  @override
  State<ChatVisibleMessage> createState() => _ChatVisibleMessageState();
}

class _ChatVisibleMessageState extends State<ChatVisibleMessage> {
  @override
  void initState() {
    super.initState();
    _scheduleCheck();
  }

  @override
  void didUpdateWidget(covariant ChatVisibleMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.generation != widget.generation ||
        oldWidget.message.id != widget.message.id) {
      _scheduleCheck();
    }
  }

  void _scheduleCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (!isChatMessageVisibleInViewport(context)) {
        return;
      }
      widget.onPresented(widget.message);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

bool isChatMessageVisibleInViewport(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize || !box.attached) {
    return false;
  }
  final scrollable = Scrollable.maybeOf(context);
  if (scrollable == null) {
    return false;
  }
  final viewport = scrollable.context.findRenderObject();
  if (viewport is! RenderBox || !viewport.hasSize) {
    return false;
  }
  final itemRect = box.localToGlobal(Offset.zero) & box.size;
  final viewportRect = viewport.localToGlobal(Offset.zero) & viewport.size;
  final overlap = itemRect.intersect(viewportRect);
  if (overlap.isEmpty || overlap.width <= 0 || overlap.height <= 0) {
    return false;
  }
  return overlap.height >= 24 || overlap.height >= box.size.height * 0.35;
}
