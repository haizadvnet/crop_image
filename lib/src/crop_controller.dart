import 'dart:ui' as ui;
import 'dart:math' as math;

import 'crop_rect.dart';
import 'crop_rotation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

@immutable
class CropControllerValue {
  final double? aspectRatio; 
  final Rect cropMaskRect;    
  final CropRotation rotation;
  final Size? minCropSize;    
  final Size? maxCropSize;    
  final double imageZoomFactor;
  final Offset imagePanOffset;
  final bool resizeEnabled;

  const CropControllerValue({
    this.aspectRatio,
    required this.cropMaskRect,
    this.rotation = CropRotation.up,
    this.minCropSize, // This is now the BASE min size at 1x zoom
    this.maxCropSize,
    this.imageZoomFactor = 1.0,
    this.imagePanOffset = Offset.zero,
    this.resizeEnabled = true,
  });

  CropControllerValue copyWith({
    ValueWrapper<double?>? aspectRatioWrapped,
    Rect? cropMaskRect,
    CropRotation? rotation,
    ValueWrapper<Size?>? minCropSizeWrapped, 
    ValueWrapper<Size?>? maxCropSizeWrapped, 
    double? imageZoomFactor,
    Offset? imagePanOffset,
    bool? resizeEnabled,
  }) {
    return CropControllerValue(
      aspectRatio: aspectRatioWrapped != null ? aspectRatioWrapped.value : this.aspectRatio,
      cropMaskRect: cropMaskRect ?? this.cropMaskRect,
      rotation: rotation ?? this.rotation,
      minCropSize: minCropSizeWrapped != null ? minCropSizeWrapped.value : this.minCropSize,
      maxCropSize: maxCropSizeWrapped != null ? maxCropSizeWrapped.value : this.maxCropSize,
      imageZoomFactor: imageZoomFactor ?? this.imageZoomFactor,
      imagePanOffset: imagePanOffset ?? this.imagePanOffset,
      resizeEnabled: resizeEnabled ?? this.resizeEnabled,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CropControllerValue &&
        other.aspectRatio == aspectRatio &&
        other.cropMaskRect == cropMaskRect &&
        other.rotation == rotation &&
        other.minCropSize == minCropSize &&
        other.maxCropSize == maxCropSize &&
        other.imageZoomFactor == imageZoomFactor &&
        other.imagePanOffset == imagePanOffset &&
        other.resizeEnabled == resizeEnabled;
  }

  @override
  int get hashCode => Object.hash(
        aspectRatio, cropMaskRect, rotation, minCropSize, maxCropSize,
        imageZoomFactor, imagePanOffset, resizeEnabled,
      );
}

class ValueWrapper<T> {
  final T value;
  const ValueWrapper(this.value);
}

class CropController extends ValueNotifier<CropControllerValue> {
  ui.Image? _image;
  Size _imageSize = Size.zero;         
  Size _viewportSize = Size.zero;     

  final Size? _constructorInitialCropSizePx;
  final double? _constructorInitialAspectRatio;

  void updateViewportSize(Size newViewportSize) {
    if (_viewportSize == newViewportSize || newViewportSize.isEmptyOrInvalid) return;
    final oldViewportAR = _viewportSize.isEmptyOrInvalid ? 0.0 : _viewportSize.width / _viewportSize.height;
    final newViewportAR = newViewportSize.isEmptyOrInvalid ? 0.0 : newViewportSize.width / newViewportSize.height;
    _viewportSize = newViewportSize;

    if ((oldViewportAR - newViewportAR).abs() > 0.01 || oldViewportAR == 0.0) {
        this.cropMaskRect = value.cropMaskRect; 
    }
  }

  double? get aspectRatio => value.aspectRatio; 
  set aspectRatio(double? newAspectRatio) {
    if (value.aspectRatio == newAspectRatio && newAspectRatio != null) return;
    if (value.aspectRatio == null && newAspectRatio == null) return;

    Rect newMask = _enforceConstraints(
        value.cropMaskRect, newAspectRatio, value.minCropSize, 
        value.maxCropSize, Alignment.center 
    );
    this.value = value.copyWith(aspectRatioWrapped: ValueWrapper(newAspectRatio), cropMaskRect: newMask);
  }

  Rect get cropMaskRect => value.cropMaskRect;
  set cropMaskRect(Rect newMask) { 
    Rect constrainedMask = _enforceConstraints(
        newMask, value.aspectRatio, value.minCropSize, 
        value.maxCropSize, null 
    );
    if (value.cropMaskRect == constrainedMask) return;
    this.value = value.copyWith(cropMaskRect: constrainedMask);
  }
  
  void updateCropMaskRectFromGesture(Rect proposedMask, Alignment? anchor) {
    Rect constrainedMask = _enforceConstraints(
        proposedMask, value.aspectRatio, value.minCropSize, 
        value.maxCropSize, anchor 
    );
    if (value.cropMaskRect == constrainedMask) return;
    this.value = value.copyWith(cropMaskRect: constrainedMask);
  }
  
  void updateResizingCropMaskInProgress(Rect proposedMaskByGesture, Alignment? anchor) {
      Rect visuallyCorrectedMask = proposedMaskByGesture.OutOfBounds(minWidth: 0.01, minHeight: 0.01);
      if (this.aspectRatio != null && !this._viewportSize.isEmptyOrInvalid) {
          visuallyCorrectedMask = this._adjustMaskAspectRatio( 
              visuallyCorrectedMask,
              this.aspectRatio!, 
              anchor,                     
              this._viewportSize          
          );
      }
      visuallyCorrectedMask = visuallyCorrectedMask.OutOfBounds(minWidth: 0.01, minHeight: 0.01);

      if (this.value.cropMaskRect != visuallyCorrectedMask) {
          this.value = this.value.copyWith(cropMaskRect: visuallyCorrectedMask);
      }
  }

  void updateMovedMaskAndPanPreservingSize(Rect translatedMask, Offset newImagePanOffset) {
      final double w = math.max(0.01, translatedMask.width).clamp(0.0, 1.0);
      final double h = math.max(0.01, translatedMask.height).clamp(0.0, 1.0);
      double clampedLeft = translatedMask.left.clamp(0.0, 1.0 - w);
      double clampedTop = translatedMask.top.clamp(0.0, 1.0 - h);
      clampedLeft = clampedLeft.clamp(0.0, 1.0-w); 
      clampedTop = clampedTop.clamp(0.0, 1.0-h);   
      Rect positionallyClampedMask = Rect.fromLTWH(clampedLeft, clampedTop, w, h);

      final effectiveZoom = value.imageZoomFactor > 0.00001 ? value.imageZoomFactor : 1.0;
      Offset clampedImagePanOffset = newImagePanOffset;
      if (effectiveZoom >= 1.01) { 
        final maxPanX = math.max(0.0, 1.0 - 1.0 / effectiveZoom);
        final maxPanY = math.max(0.0, 1.0 - 1.0 / effectiveZoom);
        clampedImagePanOffset = Offset(
            newImagePanOffset.dx.clamp(0.0, maxPanX),
            newImagePanOffset.dy.clamp(0.0, maxPanY), );
      } else {
        clampedImagePanOffset = Offset.zero;
      }

      if (value.cropMaskRect == positionallyClampedMask && value.imagePanOffset == clampedImagePanOffset) return;
      this.value = value.copyWith( cropMaskRect: positionallyClampedMask, imagePanOffset: clampedImagePanOffset );
  }

  void updateCropMaskSize({double? normWidth, double? normHeight, Alignment anchor = Alignment.center}) {
    Rect currentMask = value.cropMaskRect;
    double newW = normWidth ?? currentMask.width;
    double newH = normHeight ?? currentMask.height;

    if (value.aspectRatio != null) {
        if (normWidth != null && normHeight == null) { 
            if (!_viewportSize.isEmptyOrInvalid && value.aspectRatio! > 0) {
                double viewportAR = _viewportSize.width / _viewportSize.height;
                if (viewportAR > 0) { 
                    double targetNormShapeAR = value.aspectRatio! / viewportAR;
                    if (targetNormShapeAR > 0) newH = newW / targetNormShapeAR;
                }
            } else if (value.aspectRatio! > 0) { newH = newW / value.aspectRatio!; }
        } else if (normHeight != null && normWidth == null) { 
             if (!_viewportSize.isEmptyOrInvalid && value.aspectRatio! > 0) {
                double viewportAR = _viewportSize.width / _viewportSize.height;
                if (viewportAR > 0) { 
                    double targetNormShapeAR = value.aspectRatio! / viewportAR;
                    newW = newH * targetNormShapeAR;
                }
            } else if (value.aspectRatio! > 0) { newW = newH * value.aspectRatio!; }
        }
    }
    Rect proposedMask = _createRectFromDimensions(currentMask, newW, newH, anchor);
    this.cropMaskRect = proposedMask; 
}

  bool get resizeEnabled => value.resizeEnabled;
  set resizeEnabled(bool enabled) {
    if (value.resizeEnabled == enabled) return;
    this.value = value.copyWith(resizeEnabled: enabled);
  }

  CropRotation get rotation => value.rotation;
  set rotation(CropRotation newRotation) {
    if (value.rotation == newRotation) return;
    Rect currentMask = value.cropMaskRect;
    this.value = value.copyWith(
        rotation: newRotation, imagePanOffset: Offset.zero, imageZoomFactor: 1.0,
        cropMaskRect: _enforceConstraints(currentMask, value.aspectRatio, value.minCropSize, value.maxCropSize, Alignment.center, newZoomOverride: 1.0) );
  }

  double get imageZoomFactor => value.imageZoomFactor;
  set imageZoomFactor(double newZoom) {
    final clampedNewZoom = newZoom.clamp(1.0, 8.0);
    bool isActualChange = (value.imageZoomFactor - clampedNewZoom).abs() >= 0.001;
    bool isZoomingOutToReset = (clampedNewZoom < 1.01 && !value.resizeEnabled && value.imageZoomFactor >= 1.01);
    if (!isActualChange && !isZoomingOutToReset) {
        if (clampedNewZoom < 1.01 && value.imagePanOffset != Offset.zero) {
            this.value = value.copyWith(imagePanOffset: Offset.zero); 
        }
        return;
    }
    Offset newPan; Rect finalMaskRect; 
    if (isZoomingOutToReset) {
        newPan = Offset.zero; Rect baseMaskForReset;
        if (_constructorInitialCropSizePx != null && !_imageSize.isEmptyOrInvalid) {
            Size targetPxSize = _constructorInitialCropSizePx!;
            if (_constructorInitialAspectRatio != null) targetPxSize = _adjustPixelSizeToAspectRatio(targetPxSize, _constructorInitialAspectRatio!);
            double normW = _imageSize.width > 0 ? (targetPxSize.width / _imageSize.width).clamp(0.01, 1.0) : 0.5;
            double normH = _imageSize.height > 0 ? (targetPxSize.height / _imageSize.height).clamp(0.01, 1.0) : 0.5;
            baseMaskForReset = Rect.fromCenter(center: const Offset(0.5, 0.5), width: normW, height: normH);
        } else baseMaskForReset = const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8);
        finalMaskRect = _enforceConstraints( baseMaskForReset, _constructorInitialAspectRatio, 
            value.minCropSize, value.maxCropSize, Alignment.center, newZoomOverride: 1.0 );
    } else {
        finalMaskRect = value.cropMaskRect; 
        final oldZoom = value.imageZoomFactor; final oldPan = value.imagePanOffset;
        final currentMaskCenter = finalMaskRect.center; 
        final visiblePortionLeftOld = oldPan.dx; final visiblePortionTopOld = oldPan.dy;
        final safeOldZoom = oldZoom < 0.00001 ? 1.0 : oldZoom;
        final visiblePortionWidthOld = 1.0 / safeOldZoom; final visiblePortionHeightOld = 1.0 / safeOldZoom;
        final imagePointAtMaskCenterX = visiblePortionLeftOld + currentMaskCenter.dx * visiblePortionWidthOld;
        final imagePointAtMaskCenterY = visiblePortionTopOld + currentMaskCenter.dy * visiblePortionHeightOld;
        final safeNewZoom = clampedNewZoom < 0.00001 ? 1.0 : clampedNewZoom;
        double panX = imagePointAtMaskCenterX - currentMaskCenter.dx / safeNewZoom;
        double panY = imagePointAtMaskCenterY - currentMaskCenter.dy / safeNewZoom;
        newPan = Offset(panX, panY);
        if (safeNewZoom < 1.01) newPan = Offset.zero; 
        else {
          final maxPanX = math.max(0.0, 1.0 - 1.0 / safeNewZoom);
          final maxPanY = math.max(0.0, 1.0 - 1.0 / safeNewZoom);
          newPan = Offset(newPan.dx.clamp(0.0, maxPanX), newPan.dy.clamp(0.0, maxPanY)); }
    }
    this.value = value.copyWith(imageZoomFactor: clampedNewZoom, imagePanOffset: newPan, cropMaskRect: finalMaskRect );
  }

  Offset get imagePanOffset => value.imagePanOffset;
  set imagePanOffset(Offset newPan) {
    final effectiveZoom = value.imageZoomFactor > 0.00001 ? value.imageZoomFactor : 1.0;
    if (effectiveZoom < 1.01) { 
      if (value.imagePanOffset == Offset.zero) return;
      this.value = value.copyWith(imagePanOffset: Offset.zero);
      return;
    }
    final maxPanX = math.max(0.0, 1.0 - 1.0 / effectiveZoom);
    final maxPanY = math.max(0.0, 1.0 - 1.0 / effectiveZoom);
    final clampedPan = Offset( newPan.dx.clamp(0.0, maxPanX), newPan.dy.clamp(0.0, maxPanY) );
    if (value.imagePanOffset == clampedPan) return;
    this.value = value.copyWith(imagePanOffset: clampedPan);
  }

  ui.Image? get image => _image;
  set image(ui.Image? newImage) {
    if (_image == newImage) return;
    _image = newImage;
    if (newImage != null) _imageSize = Size(newImage.width.toDouble(), newImage.height.toDouble());
    else _imageSize = Size.zero;
    Rect targetSetupMask;
    if (_constructorInitialCropSizePx != null && !_imageSize.isEmptyOrInvalid) {
        Size targetPxSize = _constructorInitialCropSizePx!;
        if (_constructorInitialAspectRatio != null) targetPxSize = _adjustPixelSizeToAspectRatio(targetPxSize, _constructorInitialAspectRatio!);
        double normW = _imageSize.width > 0 ? (targetPxSize.width / _imageSize.width).clamp(0.01, 1.0) : 0.5;
        double normH = _imageSize.height > 0 ? (targetPxSize.height / _imageSize.height).clamp(0.01, 1.0) : 0.5;
        targetSetupMask = Rect.fromCenter(center: const Offset(0.5, 0.5), width: normW, height: normH);
    } else targetSetupMask = (newImage == null) ? const Rect.fromLTWH(0.1,0.1,0.8,0.8) : value.cropMaskRect;
    Rect fullyConstrainedMask = _enforceConstraints( targetSetupMask, _constructorInitialAspectRatio ?? value.aspectRatio, 
        value.minCropSize, value.maxCropSize, Alignment.center, newZoomOverride: 1.0 );
    this.value = CropControllerValue( aspectRatio: _constructorInitialAspectRatio ?? value.aspectRatio, 
      cropMaskRect: fullyConstrainedMask, rotation: CropRotation.up, 
      minCropSize: value.minCropSize, maxCropSize: value.maxCropSize, 
      imageZoomFactor: 1.0, imagePanOffset: Offset.zero, resizeEnabled: value.resizeEnabled );
  }
  
  Size get imageSize => _imageSize; Size get viewportSize => _viewportSize; 

  CropController({
    double? initialAspectRatio, Rect initialCropMaskRect = const Rect.fromLTWH(0.1,0.1,0.8,0.8),
    Size? initialCropSizePx, CropRotation initialRotation = CropRotation.up,
    Size? minCropSize, Size? maxCropSize, bool initialResizeEnabled = true,
  }) : _constructorInitialCropSizePx = initialCropSizePx, _constructorInitialAspectRatio = initialAspectRatio,
       super( CropControllerValue( aspectRatio: initialAspectRatio, 
            cropMaskRect: initialCropMaskRect.OutOfBounds(minWidth:0.01,minHeight:0.01),
            rotation: initialRotation, minCropSize: minCropSize, maxCropSize: maxCropSize,
            imageZoomFactor: 1.0, imagePanOffset: Offset.zero, resizeEnabled: initialResizeEnabled )) {
            if (initialAspectRatio != null) {
                 Rect adjustedInitialMask = _adjustMaskAspectRatio(
                    this.value.cropMaskRect, 
                    initialAspectRatio, 
                    Alignment.center, 
                    const Size(1,1)
                );
                this.value = this.value.copyWith(cropMaskRect: adjustedInitialMask);
            }
          }

  Size _adjustPixelSizeToAspectRatio(Size pxSize, double targetAR) {
    double w = pxSize.width; double h = pxSize.height; if (w <= 0 || h <= 0 || targetAR <= 0) return Size(math.max(1,w), math.max(1,h)); 
    double currentAR = w / h; if ((currentAR - targetAR).abs() < 0.001) return Size(math.max(1,w), math.max(1,h)); 
    if (currentAR > targetAR) w = h * targetAR; else h = w / targetAR;
    return Size(math.max(1,w), math.max(1,h)); 
  }

  Rect _enforceConstraints( 
      Rect mask, double? targetVisualAspectRatio,
      Size? minCropPxSize, Size? maxCropPxSize, // These are the BASE sizes at zoom 1.0
      Alignment? anchor, {double? newZoomOverride} 
  ) {
    final currentImageZoom = newZoomOverride ?? this.value.imageZoomFactor;
    final Size currentOriginalImageSize = this._imageSize; 
    final Size currentViewportSize = this._viewportSize;  

    Rect currentMask = mask.OutOfBounds(minWidth: 0.01, minHeight: 0.01);
    Alignment effectiveAnchor = anchor ?? Alignment.center; 

    for (int i = 0; i < 3; i++) { Rect previousMaskInLoop = currentMask;
        if (targetVisualAspectRatio != null && !currentViewportSize.isEmptyOrInvalid) {
          currentMask = _adjustMaskAspectRatio(currentMask, targetVisualAspectRatio, effectiveAnchor, currentViewportSize); 
        }
        if (!currentOriginalImageSize.isEmptyOrInvalid && currentImageZoom > 0) {
            final double imgWidth = currentOriginalImageSize.width; final double imgHeight = currentOriginalImageSize.height;
            final safeCurrentImageZoom = currentImageZoom < 0.00001 ? 1.0 : currentImageZoom;
            Size getCurrentMaskOrigPxSize() => Size(
                math.max(0,currentMask.width * (imgWidth / safeCurrentImageZoom)),
                math.max(0,currentMask.height * (imgHeight / safeCurrentImageZoom)) );

            // ***** MODIFIED LOGIC HERE *****
            // Calculate effective min/max pixel sizes based on zoom factor
            final Size? effectiveMinPxSize = minCropPxSize == null 
              ? null 
              : minCropPxSize / safeCurrentImageZoom; 
            final Size? effectiveMaxPxSize = maxCropPxSize == null
              ? null
              : maxCropPxSize; // Max size usually remains absolute regardless of zoom. Or should it scale too? 
                               // Let's assume max size is absolute and min size scales with zoom.
                               // User said "minCropSize should be minCropSize:imageZoomFactor"
                               // This implies scaling. Let's apply to min only as is most common.
            
            if (effectiveMinPxSize != null) { Size currentPx = getCurrentMaskOrigPxSize(); bool minSizeAdjusted = false;
                if (currentPx.width < effectiveMinPxSize.width - 0.001) { 
                    double targetMaskWidthVP = (effectiveMinPxSize.width / imgWidth) * safeCurrentImageZoom;
                    currentMask = _resizeMaskDimension(currentMask, targetMaskWidthVP.clamp(0.01, 1.0), null, effectiveAnchor, currentViewportSize, targetVisualAspectRatio); 
                    minSizeAdjusted = true; }
                currentPx = getCurrentMaskOrigPxSize(); 
                if (currentPx.height < effectiveMinPxSize.height - 0.001) {
                    double targetMaskHeightVP = (effectiveMinPxSize.height / imgHeight) * safeCurrentImageZoom;
                    currentMask = _resizeMaskDimension(currentMask, null, targetMaskHeightVP.clamp(0.01, 1.0), effectiveAnchor, currentViewportSize, targetVisualAspectRatio); 
                    minSizeAdjusted = true;  }
                if (minSizeAdjusted && targetVisualAspectRatio != null && !currentViewportSize.isEmptyOrInvalid){
                    currentMask = _adjustMaskAspectRatio(currentMask, targetVisualAspectRatio, effectiveAnchor, currentViewportSize); }}
            if (maxCropPxSize != null) { Size currentPx = getCurrentMaskOrigPxSize(); bool maxSizeAdjusted = false;
                if (currentPx.width > maxCropPxSize.width + 0.001) {
                    double targetMaskWidthVP = (maxCropPxSize.width / imgWidth) * safeCurrentImageZoom;
                    currentMask = _resizeMaskDimension(currentMask, targetMaskWidthVP.clamp(0.01, 1.0), null, effectiveAnchor, currentViewportSize, targetVisualAspectRatio); 
                    maxSizeAdjusted = true; }
                currentPx = getCurrentMaskOrigPxSize();
                if (currentPx.height > maxCropPxSize.height + 0.001) {
                    double targetMaskHeightVP = (maxCropPxSize.height / imgHeight) * safeCurrentImageZoom;
                    currentMask = _resizeMaskDimension(currentMask, null, targetMaskHeightVP.clamp(0.01, 1.0), effectiveAnchor, currentViewportSize, targetVisualAspectRatio); 
                    maxSizeAdjusted = true; }
                if (maxSizeAdjusted && targetVisualAspectRatio != null && !currentViewportSize.isEmptyOrInvalid){
                    currentMask = _adjustMaskAspectRatio(currentMask, targetVisualAspectRatio, effectiveAnchor, currentViewportSize); }}
        } if (currentMask == previousMaskInLoop) break; 
    } return currentMask.OutOfBounds(minWidth: 0.01, minHeight: 0.01);
  }
  
  Rect _createRectFromDimensions(Rect oldM, double nW, double nH, Alignment anc) { 
    nW=nW.clamp(0.01,1.0); nH=nH.clamp(0.01,1.0); double nL=oldM.left; double nT=oldM.top;
    if(anc==Alignment.topLeft){} else if(anc==Alignment.topCenter){nL=oldM.center.dx-nW/2;} else if(anc==Alignment.topRight){nL=oldM.right-nW;}
    else if(anc==Alignment.centerLeft){nT=oldM.center.dy-nH/2;} else if(anc==Alignment.centerRight){nL=oldM.right-nW;nT=oldM.center.dy-nH/2;}
    else if(anc==Alignment.bottomLeft){nT=oldM.bottom-nH;} else if(anc==Alignment.bottomCenter){nL=oldM.center.dx-nW/2;nT=oldM.bottom-nH;}
    else if(anc==Alignment.bottomRight){nL=oldM.right-nW;nT=oldM.bottom-nH;} else{nL=oldM.center.dx-nW/2;nT=oldM.center.dy-nH/2;}
    return Rect.fromLTWH(nL,nT,nW,nH).OutOfBounds(minWidth:0.01,minHeight:0.01);
}

  Rect _resizeMaskDimension( Rect m, double? nWVP, double? nHVP, Alignment? anc, Size vpSize, double? visAR ) { 
    double finNW = nWVP??m.width; double finNH = nHVP??m.height;
    if (visAR!=null && !vpSize.isEmptyOrInvalid) { final double vpAR=vpSize.width/vpSize.height;
        if (vpAR>0) { final double normAR=visAR/vpAR; if (normAR>0) {
            if(nWVP!=null && nHVP==null) finNH=finNW/normAR; else if(nHVP!=null && nWVP==null) finNW=finNH*normAR;
            else if(nWVP!=null && nHVP!=null) finNH=finNW/normAR; }}}
    finNW=math.max(0.01,finNW).clamp(0.0,1.0); finNH=math.max(0.01,finNH).clamp(0.0,1.0);
    double nL=m.left; double nT=m.top;
    if(anc==Alignment.topLeft){} else if(anc==Alignment.topCenter){nL=m.center.dx-finNW/2;} else if(anc==Alignment.topRight){nL=m.right-finNW;}
    else if(anc==Alignment.centerLeft){nT=m.center.dy-finNH/2;} else if(anc==Alignment.centerRight){nL=m.right-finNW;nT=m.center.dy-finNH/2;}
    else if(anc==Alignment.bottomLeft){nT=m.bottom-finNH;} else if(anc==Alignment.bottomCenter){nL=m.center.dx-finNW/2;nT=m.bottom-finNH;}
    else if(anc==Alignment.bottomRight){nL=m.right-finNW;nT=m.bottom-finNH;} else{nL=m.center.dx-finNW/2;nT=m.center.dy-finNH/2;}
    return Rect.fromLTWH(nL,nT,finNW,finNH).OutOfBounds(minWidth:0.01,minHeight:0.01);
  }

  Rect _adjustMaskAspectRatio(Rect m, double visAR, Alignment? anc, Size vpSize) { 
    if(vpSize.isEmptyOrInvalid)return m.OutOfBounds(minWidth:0.01,minHeight:0.01);
    final double vpAR=vpSize.width/vpSize.height; if(vpAR<=0)return m.OutOfBounds(minWidth:0.01,minHeight:0.01);
    final double normAR=visAR/vpAR; double curNW=m.width; double curNH=m.height;
    if(curNW<=0.00001&&curNH<=0.00001)return m.OutOfBounds(minWidth:0.01,minHeight:0.01);
    if(normAR<=0)return m.OutOfBounds(minWidth:0.01,minHeight:0.01);
    if(curNW<=0.00001)curNW=math.max(0.01,curNH*normAR); else if(curNH<=0.00001)curNH=math.max(0.01,curNW/normAR);
    double nNW=curNW; double nNH=curNH;
    final curNormAR=curNH>0.00001?curNW/curNH:normAR; 
    if((curNormAR-normAR).abs()>0.001){if(curNormAR>normAR)nNW=curNH*normAR; else nNH=curNW/normAR;}
    nNW=math.max(0.01,nNW);nNH=math.max(0.01,nNH);
    return _resizeMaskDimension(m,nNW,nNH,anc,vpSize,null); 
  }
  
  Future<ui.Image?> croppedBitmap({double? maxSize, ui.FilterQuality quality = FilterQuality.high}) async {
    if(_image==null||_imageSize.isEmpty)return null; final ui.Image oImg=_image!;final Size oPx=_imageSize; 
    final curZ=value.imageZoomFactor > 0.00001 ? value.imageZoomFactor : 1.0;
    double srcNW=1.0/curZ;double srcNH=1.0/curZ; double srcNX=value.imagePanOffset.dx;double srcNY=value.imagePanOffset.dy;
    Rect visOrigNorm=Rect.fromLTWH(srcNX,srcNY,srcNW,srcNH);
    Rect finCropOrigNorm=Rect.fromLTWH(visOrigNorm.left+value.cropMaskRect.left*visOrigNorm.width, visOrigNorm.top+value.cropMaskRect.top*visOrigNorm.height,
      value.cropMaskRect.width*visOrigNorm.width,value.cropMaskRect.height*visOrigNorm.height);
    Rect finPx=finCropOrigNorm.multiply(oPx);
    final ui.PictureRecorder rec=ui.PictureRecorder();final Canvas c=Canvas(rec);
    final double outWUS,outHUS; if(value.rotation.isSideways){outWUS=finPx.height;outHUS=finPx.width;}else{outWUS=finPx.width;outHUS=finPx.height;}
    if(outWUS<=0.001||outHUS<=0.001)return null; double sF=1.0;
    if(maxSize!=null){if(outWUS>maxSize||outHUS>maxSize){if(outWUS>outHUS)sF=maxSize/outWUS;else sF=maxSize/outHUS;}}
    final double finOutW=outWUS*sF;final double finOutH=outHUS*sF;
    c.save();c.translate(finOutW/2,finOutH/2);c.rotate(value.rotation.radians);
    final Rect dstRot; if(value.rotation.isSideways){dstRot=Rect.fromLTWH(-finPx.height*sF/2,-finPx.width*sF/2,finPx.height*sF,finPx.width*sF);}
    else{dstRot=Rect.fromLTWH(-finPx.width*sF/2,-finPx.height*sF/2,finPx.width*sF,finPx.height*sF);}
    c.drawImageRect(oImg,finPx,dstRot,Paint()..filterQuality=quality);c.restore();
    return rec.endRecording().toImage(finOutW.round(),finOutH.round());
  }
}

extension RectSafeArea on Rect {
  Rect OutOfBounds({double minWidth = 0.0, double minHeight = 0.0}) {
    double l = left.clamp(0.0, 1.0); double t = top.clamp(0.0, 1.0);
    double w = width; double h = height;
    if(w<0)w=0; if(h<0)h=0;
    final effMinW = minWidth > 0 ? minWidth : 0.0; final effMinH = minHeight > 0 ? minHeight : 0.0;
    if(w<effMinW)w=effMinW; if(h<effMinH)h=effMinH;
    l=l.clamp(0.0,(1.0-w).clamp(0.0,1.0)); t=t.clamp(0.0,(1.0-h).clamp(0.0,1.0)); 
    w=w.clamp(effMinW,1.0-l); h=h.clamp(effMinH,1.0-t); 
    return Rect.fromLTWH(l,t,w,h);
  }
}
extension on Size { bool get isEmptyOrInvalid => isEmpty || width <= 0 || height <= 0; }

class UiImageProvider extends ImageProvider<UiImageProvider> { /* ... (no changes) ... */ 
  final ui.Image image; const UiImageProvider(this.image);
  @override Future<UiImageProvider> obtainKey(ImageConfiguration configuration) => SynchronousFuture<UiImageProvider>(this);
  @override ImageStreamCompleter loadImage(UiImageProvider key, ImageDecoderCallback decode) => OneFrameImageStreamCompleter(_loadAsync(key));
  Future<ImageInfo> _loadAsync(UiImageProvider key) async { assert(key == this); return ImageInfo(image: image); }
  @override bool operator ==(Object other) => identical(this, other) || other is UiImageProvider && runtimeType == other.runtimeType && image == other.image;
  @override int get hashCode => image.hashCode;
}