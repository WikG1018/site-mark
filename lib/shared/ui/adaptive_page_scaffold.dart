import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
    this.bottomNavigationBar,
    this.floatingActionButton,
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
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.iosBodyPadding = const EdgeInsets.all(20),
  }) : _wrapBodyInList = false;

  final String title;

  /// Optional widget replacing the title text in the nav bar on both
  /// platforms — e.g. an inline search field that swaps in while a search is
  /// active. [title] stays the fallback and the accessibility label source.
  final Widget? titleWidget;
  final Widget body;
  final List<Widget>? actions;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;

  /// iOS wraps the boxed [body] in this padding; Material bodies are used
  /// verbatim, so screens that manage their own content padding pass
  /// [EdgeInsets.zero].
  final EdgeInsetsGeometry iosBodyPadding;
  final bool _wrapBodyInList;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return Scaffold(
        appBar: AppBar(title: titleWidget ?? Text(title), actions: actions),
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
