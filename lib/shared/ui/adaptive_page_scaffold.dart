import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sitemark/motion.dart';
import 'package:sitemark/navigation/scroll_chrome.dart';

/// Standard page scaffold that follows each platform's navigation shape.
///
/// Android and every other platform keep the Material `AppBar` over a content
/// list. On iOS the page gets a `CupertinoSliverNavigationBar`: a collapsing
/// large title over a translucent blur bar, the navigation shape of the
/// Liquid Glass era (iOS 26/27).
class AdaptivePageScaffold extends StatelessWidget {
  const AdaptivePageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.titleWidget,
    this.actions,
    this.bottom,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.hideOnScroll = false,
    this.iosBodyPadding = const EdgeInsets.all(20),
  }) : _wrapBodyInList = true;

  /// Raw variant for pages whose body owns its scrolling (stream builders,
  /// forms, inner lists); the Material branch uses it as-is.
  const AdaptivePageScaffold.raw({
    super.key,
    required this.title,
    required this.body,
    this.titleWidget,
    this.actions,
    this.bottom,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.hideOnScroll = false,
    this.iosBodyPadding = const EdgeInsets.all(20),
  }) : _wrapBodyInList = false;

  final String title;

  /// Optional widget replacing the title text in the nav bar on both
  /// platforms — e.g. an inline search field that swaps in while a search is
  /// active. [title] stays the fallback and the accessibility label source.
  final Widget? titleWidget;
  final Widget body;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;

  /// WeChat-style overlay chrome: the top bar slides away on scroll down.
  final bool hideOnScroll;

  /// iOS wraps the boxed [body] in this padding; Material bodies are used
  /// verbatim, so screens that manage their own content padding pass
  /// [EdgeInsets.zero].
  final EdgeInsetsGeometry iosBodyPadding;
  final bool _wrapBodyInList;

  @override
  Widget build(BuildContext context) {
    if (hideOnScroll) {
      return _hideOnScrollScaffold(context);
    }
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return Scaffold(
        appBar: AppBar(
          title: titleWidget ?? Text(title),
          actions: actions,
          bottom: bottom,
        ),
        body: _wrapBodyInList
            ? ListView(padding: const EdgeInsets.all(20), children: [body])
            : body,
        bottomNavigationBar: bottomNavigationBar,
        floatingActionButton: floatingActionButton,
      );
    }
    final navBar = CupertinoSliverNavigationBar(
      largeTitle: titleWidget ?? Text(title),
      trailing: actions == null
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: actions!),
    );
    final Widget scrollBody = _wrapBodyInList
        ? CustomScrollView(
            slivers: [
              navBar,
              SliverPadding(
                padding: iosBodyPadding,
                sliver: SliverToBoxAdapter(child: body),
              ),
            ],
          )
        : NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [navBar],
            body: Padding(padding: iosBodyPadding, child: body),
          );
    return Scaffold(
      body: scrollBody,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    );
  }

  Widget _hideOnScrollScaffold(BuildContext context) {
    final visible = ScrollChromeScope.visibleOf(context);
    final pageBody = _wrapBodyInList
        ? ListView(padding: const EdgeInsets.all(20), children: [body])
        : body;
    // Plain Color, not WidgetState: M3 otherwise swaps to surfaceContainer.
    final appBarColor = Theme.of(context).colorScheme.surface;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(
          kToolbarHeight + (bottom?.preferredSize.height ?? 0),
        ),
        child: AnimatedSlide(
          duration: scrollChromeAnimationOf(context),
          curve: AppMotion.emphasized,
          offset: visible ? Offset.zero : const Offset(0, -1),
          child: IgnorePointer(
            ignoring: !visible,
            child: AppBar(
              title: titleWidget ?? Text(title),
              actions: actions,
              bottom: bottom,
              backgroundColor: appBarColor,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
            ),
          ),
        ),
      ),
      body: pageBody,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
    );
  }
}

NestedScrollViewState? nestedScrollViewStateOf(BuildContext context) {
  return context.findAncestorStateOfType<NestedScrollViewState>();
}

ScrollController? nestedInnerScrollControllerOf(BuildContext context) {
  if (nestedScrollViewStateOf(context) == null) {
    return null;
  }
  return PrimaryScrollController.maybeOf(context);
}

void jumpNestedScrollViewsToTop(BuildContext context) {
  final nested = nestedScrollViewStateOf(context);
  if (nested == null) {
    return;
  }
  void jump() {
    if (!nested.mounted) {
      return;
    }
    void jumpController(ScrollController controller) {
      if (!controller.hasClients) {
        return;
      }
      controller.jumpTo(controller.position.minScrollExtent);
    }

    jumpController(nested.innerController);
    jumpController(nested.outerController);
  }

  jump();
  WidgetsBinding.instance.addPostFrameCallback((_) => jump());
}
