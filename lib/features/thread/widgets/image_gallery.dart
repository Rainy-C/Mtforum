part of '../thread_detail_page.dart';

/// 全屏图片查看器（支持缩放、滑动）
class _FullScreenImageViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  const _FullScreenImageViewer({required this.images, required this.initialIndex});

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  late int _currentIndex;
  late PageController _controller;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        PhotoViewGallery.builder(
          pageController: _controller,
          itemCount: widget.images.length,
          onPageChanged: (i) => setState(() => _currentIndex = i),
          builder: (context, index) => PhotoViewGalleryPageOptions(
            imageProvider: CachedNetworkImageProvider(widget.images[index]),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 3,
            heroAttributes: PhotoViewHeroAttributes(tag: 'image_$index'),
          ),
          backgroundDecoration: const BoxDecoration(color: Colors.black),
          loadingBuilder: (_, __) => const Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
        // 顶部关闭按钮
        Positioned(top: MediaQuery.of(context).padding.top + 8, right: 16,
          child: IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context)),
        ),
        // 底部页码
        if (widget.images.length > 1)
          Positioned(bottom: MediaQuery.of(context).padding.bottom + 16, left: 0, right: 0,
            child: Center(child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
              child: Text('${_currentIndex + 1} / ${widget.images.length}',
                style: const TextStyle(color: Colors.white, fontSize: 14))))),
      ]),
    );
  }
}
