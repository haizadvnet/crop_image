import 'dart:math' as math;
import 'dart:ui' as ui;

import 'crop_controller.dart'; //
// import 'crop_grid.dart'; 
import 'crop_rect.dart';    //
import 'crop_rotation.dart';  //
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

extension on Size { 
  bool get isEmptyOrInvalid => isEmpty || width <= 0 || height <= 0;
}

enum _InteractionTarget {
  none, cornerUL, cornerUR, cornerLR, cornerLL,
  sideL, sideT, sideR, sideB, maskMove, imagePan,
}

class CropImage extends StatefulWidget {
  final CropController controller;
  final Image image; 
  final Color gridColor; final Color gridInnerColor; final Color gridCornerColor;
  final double paddingSize; final double touchSize; final double gridCornerSize; 
  final bool showCorners; 
  final double gridThinWidth; final double gridThickWidth;
  final Color scrimColor; final bool alwaysShowThirdLines;
  final ValueChanged<Rect>? onCropMaskChanged; 
  final CustomPainter? overlayPainterOnMask; 
  final Widget loadingPlaceholder;

  const CropImage({
    super.key, required this.controller, required this.image, 
    this.gridColor = Colors.white70, Color? gridInnerColor, Color? gridCornerColor,
    this.paddingSize = 0, this.touchSize = 48, this.gridCornerSize = 24,
    this.showCorners = true, 
    this.gridThinWidth = 2, this.gridThickWidth = 5,
    this.scrimColor = Colors.black54, this.alwaysShowThirdLines = false,
    this.onCropMaskChanged, this.overlayPainterOnMask,
    this.loadingPlaceholder = const CircularProgressIndicator.adaptive(),
  })  : gridInnerColor = gridInnerColor ?? gridColor,
        gridCornerColor = gridCornerColor ?? gridColor,
        assert(gridCornerSize > 0), assert(touchSize > 0),
        assert(gridThinWidth > 0), assert(gridThickWidth > 0);

  @override State<CropImage> createState() => _CropImageState();
}

class _CropImageState extends State<CropImage> {
  ImageStream? _stream; ImageStreamListener? _streamListener; 
  bool _initialImageResolved = false; 
  Size _imageDisplayAreaSize = Size.zero; 
  _PanStartInfo? _panStartInfo; Alignment? _dragAnchor; 

  @override void initState() { super.initState(); widget.controller.addListener(_onControllerChanged); }
  @override void didChangeDependencies() { super.didChangeDependencies(); if (!_initialImageResolved) _resolveImage(); }

  void _resolveImage() {
    if (_stream != null && _streamListener != null) _stream!.removeListener(_streamListener!);
    _stream = null; _streamListener = null; _initialImageResolved = false; 
    final ImageConfiguration config = createLocalImageConfiguration(context); 
    _streamListener = ImageStreamListener( _handleImageFrame,
      onError: (e, s) { if (mounted) { _initialImageResolved = true; debugPrint("Error: $e");
        if (widget.controller.image != null) widget.controller.image = null; else setStateIfMounted(() {}); }},
    );
    if (widget.image.image == null) { _initialImageResolved = true; debugPrint("Null provider");
      if (mounted) { if (widget.controller.image != null) widget.controller.image = null; else setStateIfMounted((){}); } return; }
    _stream = widget.image.image.resolve(config); _stream!.addListener(_streamListener!);
  }
  void _handleImageFrame(ImageInfo info, bool sync) { if (!mounted) {info.dispose(); return;} _initialImageResolved = true; widget.controller.image = info.image; }
  void setStateIfMounted(VoidCallback fn) { if (mounted) setState(fn); }
  
  @override void didUpdateWidget(CropImage old) { super.didUpdateWidget(old);
    bool controllerChanged = false;
    if (widget.controller != old.controller) { old.controller.removeListener(_onControllerChanged); widget.controller.addListener(_onControllerChanged); controllerChanged = true; }
    if (widget.image.image != old.image.image || (controllerChanged && widget.controller.image == null)) _resolveImage(); 
    else if (controllerChanged && widget.controller.image != null) { _initialImageResolved = true; setStateIfMounted((){}); }
  }
  @override void dispose() { widget.controller.removeListener(_onControllerChanged);
    if (_stream != null && _streamListener != null) _stream!.removeListener(_streamListener!);
    _streamListener = null; _stream = null; super.dispose(); }
  void _onControllerChanged() { setStateIfMounted(() {}); }

  Size _calculateImageDisplayAreaSize(double mW, double mH) {
    final img = widget.controller.image; if (img == null) return Size.zero;
    final double iW = img.width.toDouble(); final double iH = img.height.toDouble();
    if (iW <= 0 || iH <= 0) return Size.zero;
    double iAR = iW / iH; if (widget.controller.rotation.isSideways) iAR = 1 / iAR;
    final screenAR = (mW > 0 && mH > 0) ? mW / mH : 1.0;
    double dW, dH;
    if (iAR > screenAR) { dW = mW; dH = (iAR > 0) ? (dW / iAR) : mH; } 
    else { dH = mH; dW = (iAR > 0) ? (dH * iAR) : mW; }
    return Size(math.max(0, dW), math.max(0, dH));
  }
  Offset _screenToNormalizedDisplayAreaPoint(Offset sP) {
    if (_imageDisplayAreaSize.isEmptyOrInvalid) return Offset.zero; 
    return Offset( ((sP.dx - widget.paddingSize) / _imageDisplayAreaSize.width).clamp(0.0, 1.0),
                   ((sP.dy - widget.paddingSize) / _imageDisplayAreaSize.height).clamp(0.0, 1.0) );
  }

  @override
  Widget build(BuildContext context) {
    final currentImage = widget.controller.image;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (currentImage == null) return Center(child: widget.loadingPlaceholder);
        final double availW = math.max(0, constraints.maxWidth - 2 * widget.paddingSize);
        final double availH = math.max(0, constraints.maxHeight - 2 * widget.paddingSize);
        Size newDispSize = _calculateImageDisplayAreaSize(availW, availH);
        if (newDispSize != _imageDisplayAreaSize && !newDispSize.isEmptyOrInvalid) {
            _imageDisplayAreaSize = newDispSize;
            WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) widget.controller.updateViewportSize(_imageDisplayAreaSize); });
        }
        if (_imageDisplayAreaSize.isEmptyOrInvalid) return Center(child: widget.loadingPlaceholder); 

        final bool interactiveCorners = widget.showCorners && widget.controller.resizeEnabled;

        return Stack( alignment: Alignment.center, children: <Widget>[
            SizedBox( width: _imageDisplayAreaSize.width, height: _imageDisplayAreaSize.height,
              child: CustomPaint(painter: _RotatedImagePainter( currentImage,
                  widget.controller.rotation, widget.controller.imageZoomFactor, widget.controller.imagePanOffset,))),
            SizedBox( width: _imageDisplayAreaSize.width + 2 * widget.paddingSize, height: _imageDisplayAreaSize.height + 2 * widget.paddingSize,
              child: GestureDetector(
                onPanStart: _onPanStart, onPanUpdate: _onPanUpdate, onPanEnd: _onPanEnd,
                child: CustomPaint( 
                  painter: CropGridPainter( 
                    cropRect: widget.controller.cropMaskRect, gridColor: widget.gridColor, gridInnerColor: widget.gridInnerColor,
                    gridCornerColor: widget.gridCornerColor, cornerSize: interactiveCorners ? widget.gridCornerSize : 0, 
                    thinWidth: widget.gridThinWidth, thickWidth: widget.gridThickWidth,
                    scrimColor: widget.scrimColor, showCorners: interactiveCorners, 
                    alwaysShowThirdLines: widget.alwaysShowThirdLines, isMoving: _panStartInfo != null,
                    imageDisplaySize: _imageDisplayAreaSize, paddingSize: widget.paddingSize ),
                  foregroundPainter: widget.overlayPainterOnMask != null && !_imageDisplayAreaSize.isEmptyOrInvalid 
                    ? _MaskOverlayPainter(
                        maskRectPx: widget.controller.cropMaskRect.multiply(_imageDisplayAreaSize), 
                        overlayPainter: widget.overlayPainterOnMask!,
                        baseOffset: Offset(widget.paddingSize, widget.paddingSize) ) : null,
                )))] );
      },);
  }

  void _onPanStart(DragStartDetails details) {
    if (widget.controller.image == null || _imageDisplayAreaSize.isEmptyOrInvalid) return;
    final Offset normalizedPointOnDisplay = _screenToNormalizedDisplayAreaPoint(details.localPosition);
    final Rect currentMask = widget.controller.cropMaskRect; 
    _InteractionTarget target = _InteractionTarget.none;
    _dragAnchor = null; 
    final double touchMarginX = (_imageDisplayAreaSize.width > 0) ? (widget.touchSize / 2) / _imageDisplayAreaSize.width : 0.05;
    final double touchMarginY = (_imageDisplayAreaSize.height > 0) ? (widget.touchSize / 2) / _imageDisplayAreaSize.height : 0.05;

    if (widget.controller.resizeEnabled) {
      if (widget.showCorners) {
          if (Rect.fromCenter(center:currentMask.topLeft,width:touchMarginX*2,height:touchMarginY*2).contains(normalizedPointOnDisplay)) {target=_InteractionTarget.cornerUL; _dragAnchor=Alignment.bottomRight;}
          else if (Rect.fromCenter(center:currentMask.topRight,width:touchMarginX*2,height:touchMarginY*2).contains(normalizedPointOnDisplay)) {target=_InteractionTarget.cornerUR; _dragAnchor=Alignment.bottomLeft;}
          else if (Rect.fromCenter(center:currentMask.bottomLeft,width:touchMarginX*2,height:touchMarginY*2).contains(normalizedPointOnDisplay)) {target=_InteractionTarget.cornerLL; _dragAnchor=Alignment.topRight;}
          else if (Rect.fromCenter(center:currentMask.bottomRight,width:touchMarginX*2,height:touchMarginY*2).contains(normalizedPointOnDisplay)) {target=_InteractionTarget.cornerLR; _dragAnchor=Alignment.topLeft;}
      }
      if (target == _InteractionTarget.none) {
          bool onL=(normalizedPointOnDisplay.dx-currentMask.left).abs()<touchMarginX && normalizedPointOnDisplay.dy>=currentMask.top+touchMarginY && normalizedPointOnDisplay.dy<=currentMask.bottom-touchMarginY;
          bool onR=(normalizedPointOnDisplay.dx-currentMask.right).abs()<touchMarginX && normalizedPointOnDisplay.dy>=currentMask.top+touchMarginY && normalizedPointOnDisplay.dy<=currentMask.bottom-touchMarginY;
          bool onT=(normalizedPointOnDisplay.dy-currentMask.top).abs()<touchMarginY && normalizedPointOnDisplay.dx>=currentMask.left+touchMarginX && normalizedPointOnDisplay.dx<=currentMask.right-touchMarginX;
          bool onB=(normalizedPointOnDisplay.dy-currentMask.bottom).abs()<touchMarginY && normalizedPointOnDisplay.dx>=currentMask.left+touchMarginX && normalizedPointOnDisplay.dx<=currentMask.right-touchMarginX;
          if(onL){target=_InteractionTarget.sideL;_dragAnchor=Alignment.centerRight;} else if(onR){target=_InteractionTarget.sideR;_dragAnchor=Alignment.centerLeft;}
          else if(onT){target=_InteractionTarget.sideT;_dragAnchor=Alignment.bottomCenter;} else if(onB){target=_InteractionTarget.sideB;_dragAnchor=Alignment.topCenter;}
      }
    } 
    if (target == _InteractionTarget.none && currentMask.contains(normalizedPointOnDisplay)) {
        target = _InteractionTarget.maskMove; _dragAnchor = Alignment.center; 
    }
    if (target == _InteractionTarget.none) target = _InteractionTarget.imagePan;
    _panStartInfo = _PanStartInfo(target:target,startPanPointNorm:normalizedPointOnDisplay,startPanPointScreen:details.localPosition,initialMaskRect:currentMask);
    if(mounted) setStateIfMounted((){}); 
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_panStartInfo == null || widget.controller.image == null || _imageDisplayAreaSize.isEmptyOrInvalid) return;
    if (widget.controller.imageZoomFactor <= 0 && _panStartInfo!.target != _InteractionTarget.imagePan) return;

    final Offset normCurrPtDisplay = _screenToNormalizedDisplayAreaPoint(details.localPosition);
    final Offset screenDelta = details.delta;
    
    switch(_panStartInfo!.target) {
        case _InteractionTarget.imagePan:
            if (widget.controller.imageZoomFactor > 1.01) {
                final effZoom = math.max(0.001, widget.controller.imageZoomFactor);
                if (_imageDisplayAreaSize.width * effZoom == 0 || _imageDisplayAreaSize.height * effZoom == 0) return;
                final double dx = screenDelta.dx / (_imageDisplayAreaSize.width * effZoom);
                final double dy = screenDelta.dy / (_imageDisplayAreaSize.height * effZoom);
                widget.controller.imagePanOffset = widget.controller.imagePanOffset - Offset(dx, dy);
            } break;
        case _InteractionTarget.maskMove: 
            final Offset totalNormDeltaOnDisplay = normCurrPtDisplay - _panStartInfo!.startPanPointNorm;
            Rect newMaskProposal = _panStartInfo!.initialMaskRect.translate(totalNormDeltaOnDisplay.dx, totalNormDeltaOnDisplay.dy);
            Offset newImagePanOffset = widget.controller.imagePanOffset;
            if (widget.controller.imageZoomFactor > 1.01) {
                final effZoom = math.max(0.001, widget.controller.imageZoomFactor);
                if (!_imageDisplayAreaSize.isEmptyOrInvalid && effZoom > 0) { 
                    final double panDx = screenDelta.dx / (_imageDisplayAreaSize.width * effZoom);
                    final double panDy = screenDelta.dy / (_imageDisplayAreaSize.height * effZoom);
                    newImagePanOffset = widget.controller.imagePanOffset + Offset(panDx, panDy);
                }
            }
            widget.controller.updateMovedMaskAndPanPreservingSize(newMaskProposal, newImagePanOffset);
            break;
        
        case _InteractionTarget.cornerUL: case _InteractionTarget.cornerUR:
        case _InteractionTarget.cornerLL: case _InteractionTarget.cornerLR:
        case _InteractionTarget.sideL: case _InteractionTarget.sideT:
        case _InteractionTarget.sideR: case _InteractionTarget.sideB:
            if (!widget.controller.resizeEnabled) break; 
            double nL=_panStartInfo!.initialMaskRect.left, nT=_panStartInfo!.initialMaskRect.top;
            double nR=_panStartInfo!.initialMaskRect.right, nB=_panStartInfo!.initialMaskRect.bottom;
            final target = _panStartInfo!.target;
            if (target==_InteractionTarget.cornerUL || target==_InteractionTarget.sideL || target==_InteractionTarget.cornerLL) nL = normCurrPtDisplay.dx;
            if (target==_InteractionTarget.cornerUL || target==_InteractionTarget.sideT || target==_InteractionTarget.cornerUR) nT = normCurrPtDisplay.dy;
            if (target==_InteractionTarget.cornerUR || target==_InteractionTarget.sideR || target==_InteractionTarget.cornerLR) nR = normCurrPtDisplay.dx;
            if (target==_InteractionTarget.cornerLL || target==_InteractionTarget.sideB || target==_InteractionTarget.cornerLR) nB = normCurrPtDisplay.dy;
            final double minSep = 0.00001; 
            Rect rawNewMask = Rect.fromLTRB( math.min(nL, nR - minSep), math.min(nT, nB - minSep), 
                                     math.max(nR, nL + minSep), math.max(nB, nT + minSep) );
            widget.controller.updateResizingCropMaskInProgress(rawNewMask, _dragAnchor);
            break;
        case _InteractionTarget.none: break; 
    }
    if (_panStartInfo!.target != _InteractionTarget.imagePan && _panStartInfo!.target != _InteractionTarget.none) {
      widget.onCropMaskChanged?.call(widget.controller.cropMaskRect); 
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (_panStartInfo == null) return;
    
    final _InteractionTarget gestureTarget = _panStartInfo!.target;
    final Alignment? gestureAnchor = _dragAnchor; 

    setStateIfMounted(() { 
      _panStartInfo = null;
      _dragAnchor = null;
    });

    if (gestureTarget != _InteractionTarget.maskMove && 
        gestureTarget != _InteractionTarget.imagePan &&
        gestureTarget != _InteractionTarget.none) {
        widget.controller.updateCropMaskRectFromGesture(widget.controller.value.cropMaskRect, gestureAnchor);
    }
  }
}

class _PanStartInfo { 
  final _InteractionTarget target;
  final Offset startPanPointNorm; final Offset startPanPointScreen; 
  final Rect initialMaskRect; 
  _PanStartInfo({required this.target, required this.startPanPointNorm, required this.startPanPointScreen, required this.initialMaskRect});
}

class _RotatedImagePainter extends CustomPainter { /* ... (no changes) ... */ 
  final ui.Image image; final CropRotation rotation;
  final double imageZoomFactor; final Offset imagePanOffset; 
  _RotatedImagePainter(this.image, this.rotation, this.imageZoomFactor, this.imagePanOffset);
  final Paint _paint = Paint()..filterQuality = FilterQuality.high;
  @override
  void paint(Canvas canvas, Size size) { 
    if (size.isEmptyOrInvalid || image.width == 0 || image.height == 0) return;
    final double effZoom = math.max(0.00001, imageZoomFactor);
    canvas.save();
    final double imgW = image.width.toDouble(); final double imgH = image.height.toDouble();
    final double srcW = imgW/effZoom; final double srcH = imgH/effZoom;
    final double srcX = imagePanOffset.dx * imgW; final double srcY = imagePanOffset.dy * imgH;
    final Rect src = Rect.fromLTWH(srcX, srcY, srcW, srcH);
    final Rect dst = Rect.fromLTWH(0,0,size.width,size.height);
    final double dCX = dst.width/2; final double dCY = dst.height/2;
    canvas.translate(dCX,dCY); canvas.rotate(rotation.radians); canvas.translate(-dCX,-dCY);
    canvas.drawImageRect(image, src, dst, _paint);
    canvas.restore();
  }
  @override bool shouldRepaint(_RotatedImagePainter o) => o.image!=image||o.rotation!=rotation||o.imageZoomFactor!=imageZoomFactor||o.imagePanOffset!=imagePanOffset;
}

class _MaskOverlayPainter extends CustomPainter { /* ... (no changes) ... */ 
  final Rect maskRectPx; final CustomPainter overlayPainter; final Offset baseOffset; 
  _MaskOverlayPainter({required this.maskRectPx, required this.overlayPainter, required this.baseOffset});
  @override
  void paint(Canvas canvas, Size size) { 
    canvas.save(); canvas.translate(baseOffset.dx+maskRectPx.left, baseOffset.dy+maskRectPx.top);
    if (maskRectPx.width > 0 && maskRectPx.height > 0) {
      canvas.clipRect(Rect.fromLTWH(0,0,maskRectPx.width,maskRectPx.height));
      overlayPainter.paint(canvas, maskRectPx.size); }
    canvas.restore();
  }
  @override bool shouldRepaint(_MaskOverlayPainter o) => o.maskRectPx!=maskRectPx||o.overlayPainter!=overlayPainter||o.baseOffset!=baseOffset;
}

class CropGridPainter extends CustomPainter { /* ... (no changes) ... */ 
  final Rect cropRect; final Color gridColor; final Color gridInnerColor; final Color gridCornerColor;
  final double cornerSize; final bool showCorners; final double thinWidth; final double thickWidth;
  final Color scrimColor; final bool alwaysShowThirdLines; final bool isMoving;
  final Size imageDisplaySize; final double paddingSize; 
  CropGridPainter({
    required this.cropRect, required this.gridColor, required this.gridInnerColor, required this.gridCornerColor,
    required this.cornerSize, required this.showCorners, required this.thinWidth, required this.thickWidth,
    required this.scrimColor, required this.alwaysShowThirdLines, required this.isMoving,
    required this.imageDisplaySize, required this.paddingSize});
  @override
  void paint(Canvas canvas, Size size) { 
    if (imageDisplaySize.isEmptyOrInvalid) return;
    final Rect maskPx = Rect.fromLTWH( paddingSize + cropRect.left * imageDisplaySize.width, paddingSize + cropRect.top * imageDisplaySize.height,
      cropRect.width * imageDisplaySize.width, cropRect.height * imageDisplaySize.height );
    if (maskPx.width <=0 || maskPx.height <= 0) return;
    final Rect imgAreaCanvas = Rect.fromLTWH(paddingSize, paddingSize, imageDisplaySize.width, imageDisplaySize.height);
    final Path scrimPath = Path()..addRect(imgAreaCanvas)..addRect(maskPx)..fillType = ui.PathFillType.evenOdd; 
    canvas.drawPath(scrimPath, Paint()..color = scrimColor);
    final Paint thickP = Paint()..color=gridCornerColor..style=PaintingStyle.stroke..strokeWidth=thickWidth..strokeCap=StrokeCap.round;
    final Paint thinP = Paint()..color=gridColor..style=PaintingStyle.stroke..strokeWidth=thinWidth;
    final Paint innerP = Paint()..color=gridInnerColor..style=PaintingStyle.stroke..strokeWidth=thinWidth;
    canvas.drawRect(maskPx, thinP);
    if (isMoving || alwaysShowThirdLines) {
      if (maskPx.width > thinWidth*2 && maskPx.height > thinWidth*2) { 
        final double thW = maskPx.width/3.0; final double thH = maskPx.height/3.0;
        for(int i=1; i<3; ++i) { canvas.drawLine(maskPx.topLeft.translate(thW*i,0),maskPx.bottomLeft.translate(thW*i,0),innerP); canvas.drawLine(maskPx.topLeft.translate(0,thH*i),maskPx.topRight.translate(0,thH*i),innerP); }
      }
    }
    if (showCorners && cornerSize > 0) {
      final double cSz = math.min(cornerSize, math.min(maskPx.width/2, maskPx.height/2)); 
      if (cSz > 0) {
        canvas.drawLine(maskPx.topLeft,maskPx.topLeft.translate(cSz,0),thickP); canvas.drawLine(maskPx.topLeft,maskPx.topLeft.translate(0,cSz),thickP);
        canvas.drawLine(maskPx.topRight,maskPx.topRight.translate(-cSz,0),thickP); canvas.drawLine(maskPx.topRight,maskPx.topRight.translate(0,cSz),thickP);
        canvas.drawLine(maskPx.bottomRight,maskPx.bottomRight.translate(-cSz,0),thickP); canvas.drawLine(maskPx.bottomRight,maskPx.bottomRight.translate(0,-cSz),thickP);
        canvas.drawLine(maskPx.bottomLeft,maskPx.bottomLeft.translate(cSz,0),thickP); canvas.drawLine(maskPx.bottomLeft,maskPx.bottomLeft.translate(0,-cSz),thickP);
      }
    }
  }
  @override bool shouldRepaint(CropGridPainter o) => o.cropRect!=cropRect||o.gridColor!=gridColor||o.gridInnerColor!=gridInnerColor||o.gridCornerColor!=gridCornerColor||o.cornerSize!=cornerSize||o.showCorners!=showCorners||o.thinWidth!=thinWidth||o.thickWidth!=thickWidth||o.scrimColor!=scrimColor||o.alwaysShowThirdLines!=alwaysShowThirdLines||o.isMoving!=isMoving||o.imageDisplaySize!=imageDisplaySize||o.paddingSize!=paddingSize;
}