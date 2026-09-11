import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:flutter/material.dart';

class FadeOnScroll extends StatefulWidget {
  final ScrollController scrollController;
  final double zeroOpacityOffset;
  final double fullOpacityOffset;
  final Widget child;

  FadeOnScroll(
      {Key? key,
        required this.scrollController,
        required this.child,
        this.zeroOpacityOffset = 0,
        this.fullOpacityOffset = 0
      });

  @override
  State<StatefulWidget> createState() => _FadeOnScrollState();
}

class _FadeOnScrollState extends OptimizedState<FadeOnScroll> {
  late double _offset;

  @override
  initState() {
    super.initState();
    if (widget.scrollController.positions.length > 1) {
      _offset = 0;
    } else {
      _offset = widget.scrollController.offset;
    }
    widget.scrollController.addListener(_setOffset);
  }

  @override
  dispose() {
    widget.scrollController.removeListener(_setOffset);
    super.dispose();
  }

  void _setOffset() {
    setState(() {
      _offset = widget.scrollController.offset;
    });
  }

  double _calculateOpacity() {
    if (widget.fullOpacityOffset == widget.zeroOpacityOffset) {
      return 1;
    } else if (widget.fullOpacityOffset > widget.zeroOpacityOffset) {
      // fading in
      if (_offset <= widget.zeroOpacityOffset) {
        return 0;
      } else if (_offset >= widget.fullOpacityOffset) {
        return 1;
      } else {
        return (_offset - widget.zeroOpacityOffset) / (widget.fullOpacityOffset - widget.zeroOpacityOffset);
      }
    } else {
      // fading out
      if (_offset <= widget.fullOpacityOffset) {
        return 1;
      } else if (_offset >= widget.zeroOpacityOffset) {
        return 0;
      } else {
        return (_offset - widget.zeroOpacityOffset) / (widget.fullOpacityOffset - widget.zeroOpacityOffset);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final opacity = _calculateOpacity();
    // faded out means not painted: an Opacity of 0 still lets a BackdropFilter
    // inside sample and blur the backdrop, which is the smear at the top of a
    // scrolled list. maintainSize keeps the scroll extent steady.
    return Visibility(
      visible: opacity > 0.01,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: Opacity(
        opacity: opacity,
        child: widget.child,
      ),
    );
  }
}