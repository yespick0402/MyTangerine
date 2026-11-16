// MARK: - 7-C. 변환 시 Command 키 조합으로 열리는 1~100% 퀄리티 선택 팝업 창 (Part 2)
struct ConvertQualityPopupView: View {
    let files: [URL]
    let targetExt: String
    @State private var quality: Double = 100.0
    @State private var origBytes: Int64 = 0
    @State private var estBytes: Int64 = 0
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.below.square.and.square.filled")
                    .font(.title2).foregroundColor(.orange)
                Text("\(targetExt.uppercased()) 변환 퀄리티 설정 (\(files.count)개 파일)")
                    .font(.headline)
            }
            
            HStack(spacing: 18) {
                VStack(spacing: 4) {
                    Text("원본 크기").font(.caption).foregroundColor(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: origBytes, countStyle: .file))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }
                Image(systemName: "arrow.right.circle.fill").font(.title2).foregroundColor(.orange)
                VStack(spacing: 4) {
                    Text("\(targetExt.uppercased()) 예상 크기").font(.caption).foregroundColor(.orange)
                    Text("~" + ByteCountFormatter.string(fromByteCount: estBytes, countStyle: .file))
                        .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundColor(.orange)
                }
                if Int(quality.rounded()) == 100 {
                    Text("원본 동일 최고화질")
                        .font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5).background(Color.orange, in: Capsule())
                }
            }
            .padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            
            VStack(spacing: 8) {
                HStack {
                    Text("변환 퀄리티: \(Int(quality.rounded()))%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.orange)
                    Spacer()
                    Text(Int(quality.rounded()) == 100 ? "100% = 무손실/원본 동일 퀄리티" : "낮출수록 용량이 줄어듭니다")
                        .font(.caption).foregroundColor(.secondary)
                }
                
                Slider(value: $quality, in: 1...100, step: 1)
                    .tint(.orange)
                    .onChange(of: quality) { recalculate() }
                
                HStack(spacing: 8) {
                    Text("빠른 선택:").font(.caption).foregroundColor(.secondary)
                    ForEach([25, 50, 75, 90, 100], id: \.self) { preset in
                        Button("\(preset)%") {
                            quality = Double(preset)
                            recalculate()
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(.horizontal, 8)
            
            Text("💡 메타데이터(EXIF 촬영일시, 카메라 정보, GPS)는 삭제되지 않고 그대로 보존됩니다.")
                .font(.caption2).foregroundColor(.secondary)
            
            HStack {
                Button("취소") { NSApp.keyWindow?.close() }
                Spacer()
                Button("\(Int(quality.rounded()))% 퀄리티로 \(targetExt.uppercased()) 변환 저장") {
                    FileProcessor.batchConvertFiles(files, to: targetExt, qualityPercent: quality)
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent).tint(.orange)
            }
            .padding(.horizontal, 8)
        }
        .padding(22)
        .onAppear {
            origBytes = AppState.shared.totalBytes > 0 ? AppState.shared.totalBytes :
                files.prefix(200).reduce(0) { $0 + ((try? FileManager.default.attributesOfItem(atPath: $1.path)[.size] as? Int64) ?? 0) }
            recalculate()
        }
    }
    
    func recalculate() {
        let q = quality
        let fList = files
        let orig = origBytes
        let tgt = targetExt
        DispatchQueue.global(qos: .userInteractive).async {
            let imageExts = ["png", "jpg", "jpeg", "heic", "webp", "tiff", "bmp", "pdf"]
            let est: Int64
            if imageExts.contains(tgt.lowercased()) {
                est = FileSizeEstimator.exactImageConversionBytes(files: fList, originalTotalBytes: orig, targetExt: tgt, qualityPercent: q)
            } else {
                est = FileSizeEstimator.estimateConversionBytes(files: fList, originalTotalBytes: orig, targetExt: tgt, qualityPercent: q)
            }
            DispatchQueue.main.async { self.estBytes = est }
        }
    }
}

// MARK: - 8. 전문가 사진 보정 창 (저장 시 원본 EXIF 메타데이터 100% 보존)
struct EditPhotoView: View {
    let fileURL: URL
    @State private var exposure: Double = 0.0
    @State private var brilliance: Double = 0.0
    @State private var highlights: Double = 1.0
    @State private var shadows: Double = 0.0
    @State private var brightness: Double = 0.0
    @State private var contrast: Double = 1.0
    @State private var blackPoint: Double = 0.0
    @State private var saturation: Double = 1.0
    @State private var vibrance: Double = 0.0
    @State private var warmth: Double = 0.0
    @State private var tint: Double = 0.0
    @State private var sharpness: Double = 0.0
    @State private var vignette: Double = 0.0
    @State private var sepia: Double = 0.0
    
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero
    @State private var showOriginal: Bool = false
    @State private var previewImage: NSImage?
    @State private var originalNSImage: NSImage?
    @State private var pixelSize: CGSize = .zero
    let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("\(Int(pixelSize.width)) × \(Int(pixelSize.height)) px").font(.caption.monospacedDigit()).foregroundColor(.secondary)
                    Text("💡 마우스 휠: 확대/축소 | 드래그: 화면 이동").font(.caption).foregroundColor(.orange)
                    Spacer()
                    Button(action: { adjustZoom(by: -0.25) }) { Image(systemName: "minus.magnifyingglass") }
                    Text("\(Int(zoomScale * 100))%").font(.caption.monospacedDigit()).frame(width: 48)
                    Button(action: { adjustZoom(by: 0.25) }) { Image(systemName: "plus.magnifyingglass") }
                    Button("화면 맞춤(중앙)") {
                        withAnimation(.easeOut(duration: 0.15)) { zoomScale = 1.0; panOffset = .zero; lastPanOffset = .zero }
                    }.font(.caption)
                    Toggle("원본 비교", isOn: $showOriginal).toggleStyle(.button).font(.caption)
                }
                .padding(10).background(.regularMaterial)
                
                GeometryReader { geo in
                    let fitSize = calculateFitSize(in: geo.size)
                    ZStack {
                        Color(white: 0.11)
                        if let img = (showOriginal ? originalNSImage : previewImage) {
                            Image(nsImage: img).resizable().interpolation(.high)
                                .frame(width: fitSize.width * zoomScale, height: fitSize.height * zoomScale)
                                .shadow(color: .black.opacity(0.5), radius: 16)
                                .offset(panOffset)
                                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        }
                        ScrollWheelCatcher { delta in
                            zoomScale = min(8.0, max(0.25, zoomScale + delta * 0.012))
                        }.allowsHitTesting(false)
                    }
                    .frame(width: geo.size.width, height: geo.size.height).clipped().contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { val in
                                panOffset = CGSize(width: lastPanOffset.width + val.translation.width, height: lastPanOffset.height + val.translation.height)
                            }
                            .onEnded { _ in lastPanOffset = panOffset }
                    )
                }
            }
            .frame(minWidth: 560, maxWidth: .infinity)
            
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Group {
                            sectionTitle("LIGHT (밝기 및 노출)")
                            sliderItem("노출 (Exposure)", val: $exposure, range: -3.0...3.0, def: 0.0)
                            sliderItem("휘도 (Brilliance)", val: $brilliance, range: -1.0...1.0, def: 0.0)
                            sliderItem("하이라이트 (Highlights)", val: $highlights, range: 0.0...2.0, def: 1.0)
                            sliderItem("그림자 (Shadows)", val: $shadows, range: -1.0...1.0, def: 0.0)
                            sliderItem("밝기 (Brightness)", val: $brightness, range: -0.6...0.6, def: 0.0)
                            sliderItem("대비 (Contrast)", val: $contrast, range: 0.3...2.5, def: 1.0)
                            sliderItem("블랙 포인트", val: $blackPoint, range: -0.3...0.3, def: 0.0)
                        }
                        Divider()
                        Group {
                            sectionTitle("COLOR (색감 및 온도)")
                            sliderItem("채도 (Saturation)", val: $saturation, range: 0.0...3.0, def: 1.0)
                            sliderItem("생동감 (Vibrance)", val: $vibrance, range: -1.0...2.0, def: 0.0)
                            sliderItem("색온도 (Warmth)", val: $warmth, range: -3000...3000, def: 0.0)
                            sliderItem("색조 (Tint)", val: $tint, range: -100...100, def: 0.0)
                        }
                        Divider()
                        Group {
                            sectionTitle("DETAIL & EFFECTS")
                            sliderItem("선명도 (Sharpness)", val: $sharpness, range: 0.0...3.0, def: 0.0)
                            sliderItem("비네팅 (Vignette)", val: $vignette, range: 0.0...2.0, def: 0.0)
                            sliderItem("세피아 필터 (Sepia)", val: $sepia, range: 0.0...1.0, def: 0.0)
                        }
                    }.padding(16)
                }
                Divider()
                HStack {
                    Button("전체 초기화") { resetAll() }
                    Spacer()
                    Button("원본 화질 저장 (메타데이터 유지)") { saveFullRes() }.buttonStyle(.borderedProminent).tint(.orange)
                }.padding(14).background(.regularMaterial)
            }.frame(width: 340)
        }
        .onAppear {
            if let cg = FileProcessor.loadRawCGImage(from: fileURL) {
                pixelSize = CGSize(width: cg.width, height: cg.height)
                originalNSImage = NSImage(cgImage: cg, size: pixelSize)
            }
            updatePreview()
        }
    }
    
    func adjustZoom(by delta: CGFloat) { zoomScale = min(8.0, max(0.25, zoomScale + delta)) }
    func calculateFitSize(in container: CGSize) -> CGSize {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return CGSize(width: 500, height: 400) }
        let ratio = min(max(200, container.width - 48) / pixelSize.width, max(200, container.height - 48) / pixelSize.height)
        return CGSize(width: pixelSize.width * ratio, height: pixelSize.height * ratio)
    }
    func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundColor(.orange)
    }
    func sliderItem(_ title: String, val: Binding<Double>, range: ClosedRange<Double>, def: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption.bold())
                Spacer()
                Text(String(format: "%.2f", val.wrappedValue)).font(.caption.monospacedDigit()).foregroundColor(.secondary)
                Button(action: { val.wrappedValue = def; updatePreview() }) { Image(systemName: "arrow.counterclockwise").font(.caption2) }.buttonStyle(.plain)
            }
            Slider(value: val, in: range).tint(.orange).onChange(of: val.wrappedValue) { updatePreview() }
        }
    }
    func resetAll() {
        exposure = 0.0; brilliance = 0.0; highlights = 1.0; shadows = 0.0
        brightness = 0.0; contrast = 1.0; blackPoint = 0.0
        saturation = 1.0; vibrance = 0.0; warmth = 0.0; tint = 0.0
        sharpness = 0.0; vignette = 0.0; sepia = 0.0
        updatePreview()
    }
    func applyFilters(to input: CIImage) -> CIImage {
        var current = input
        if abs(exposure) > 0.001 {
            let f = CIFilter.exposureAdjust(); f.inputImage = current; f.ev = Float(exposure)
            if let out = f.outputImage { current = out }
        }
        if abs(highlights - 1.0) > 0.001 || abs(shadows) > 0.001 {
            let f = CIFilter.highlightShadowAdjust(); f.inputImage = current
            f.highlightAmount = Float(highlights); f.shadowAmount = Float(shadows)
            if let out = f.outputImage { current = out }
        }
        if abs(brilliance) > 0.001 {
            let f = CIFilter.gammaAdjust(); f.inputImage = current; f.power = Float(pow(2.0, -brilliance * 0.8))
            if let out = f.outputImage { current = out }
        }
        if abs(brightness) > 0.001 || abs(contrast - 1.0) > 0.001 || abs(saturation - 1.0) > 0.001 || abs(blackPoint) > 0.001 {
            let f = CIFilter.colorControls(); f.inputImage = current
            f.brightness = Float(brightness - blackPoint * 0.5)
            f.contrast = Float(contrast + blackPoint)
            f.saturation = Float(saturation)
            if let out = f.outputImage { current = out }
        }
        if abs(vibrance) > 0.001 {
            let f = CIFilter.vibrance(); f.inputImage = current; f.amount = Float(vibrance)
            if let out = f.outputImage { current = out }
        }
        if abs(warmth) > 1.0 || abs(tint) > 0.5 {
            let f = CIFilter.temperatureAndTint(); f.inputImage = current
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: 6500 - CGFloat(warmth), y: CGFloat(tint))
            if let out = f.outputImage { current = out }
        }
        if sharpness > 0.001 {
            let f = CIFilter.sharpenLuminance(); f.inputImage = current; f.sharpness = Float(sharpness)
            if let out = f.outputImage { current = out }
        }
        if vignette > 0.001 {
            let f = CIFilter.vignette(); f.inputImage = current; f.intensity = Float(vignette); f.radius = 1.5
            if let out = f.outputImage { current = out }
        }
        if sepia > 0.001 {
            let f = CIFilter.sepiaTone(); f.inputImage = current; f.intensity = Float(sepia)
            if let out = f.outputImage { current = out }
        }
        return current.cropped(to: input.extent)
    }
    func updatePreview() {
        guard let input = CIImage(contentsOf: fileURL) else { return }
        let output = applyFilters(to: input)
        if let cgImg = ciContext.createCGImage(output, from: output.extent) {
            previewImage = NSImage(cgImage: cgImg, size: CGSize(width: cgImg.width, height: cgImg.height))
        }
    }
    func saveFullRes() {
        guard let input = CIImage(contentsOf: fileURL) else { return }
        let output = applyFilters(to: input)
        let ext = fileURL.pathExtension.isEmpty ? "jpg" : fileURL.pathExtension
        let outURL = FileProcessor.uniqueOutputURL(for: fileURL, newExt: ext, suffix: "_edited")
        if let cgImg = ciContext.createCGImage(output, from: output.extent) {
            FileProcessor.saveCGImage(cgImg, to: outURL, formatExt: ext, quality: 0.95, sourceURLForMetadata: fileURL)
            FileProcessor.showToast("보정 완료 (EXIF 메타데이터 보존됨): \(outURL.lastPathComponent)")
            NSApp.keyWindow?.close()
        }
    }
}

// MARK: - 9. Redact & 8방향 핸들 Crop 스튜디오
enum RedactStyle: String, CaseIterable {
    case pixelate = "픽셀 모자이크"
    case blur = "블러 (흐림)"
    case blackBox = "검은 박스"
}

struct RedactItem: Identifiable {
    let id = UUID()
    var normalizedRect: CGRect
    var style: RedactStyle
}

enum CropHandle: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
    case top, bottom, left, right
    case moveInside
}

struct RedactCropStudioView: View {
    let fileURL: URL
    @State var mode: Int
    @State private var redactStyle: RedactStyle = .pixelate
    @State private var strength: Double = 30.0
    @State private var redactItems: [RedactItem] = []
    @State private var activeDragRect: CGRect? = nil
    
    @State private var cropRect: CGRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    @State private var initialCropOnDrag: CGRect? = nil
    @State private var activeCropHandle: CropHandle? = nil
    
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero
    @State private var isPanMode: Bool = false
    @State private var rawCGImage: CGImage? = nil
    let ciContext = CIContext()
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Picker("작업", selection: $mode) {
                    Text("👁️ 가리기 (Redact)").tag(0)
                    Text("✂️ 자르기 (Crop)").tag(1)
                }.pickerStyle(.segmented).frame(width: 250)
                
                Toggle("✋ 화면 이동(Pan)", isOn: $isPanMode).toggleStyle(.button).tint(isPanMode ? .orange : .secondary)
                Divider().frame(height: 18)
                
                if mode == 0 {
                    Picker("스타일", selection: $redactStyle) {
                        ForEach(RedactStyle.allCases, id: \.self) { s in Text(s.rawValue).tag(s) }
                    }.frame(width: 155)
                    HStack(spacing: 4) {
                        Text("강도").font(.caption)
                        Slider(value: $strength, in: 10...80).frame(width: 80).tint(.orange)
                    }
                    Button("실행취소") { if !redactItems.isEmpty { redactItems.removeLast() } }.disabled(redactItems.isEmpty)
                    Button("초기화") { redactItems.removeAll() }.disabled(redactItems.isEmpty)
                } else {
                    HStack(spacing: 6) {
                        Text("비율:").font(.caption)
                        Button("전체") { cropRect = CGRect(x: 0, y: 0, width: 1, height: 1) }
                        Button("1:1") { setAspectCrop(1.0) }
                        Button("16:9") { setAspectCrop(16.0 / 9.0) }
                        Button("4:3") { setAspectCrop(4.0 / 3.0) }
                    }
                }
                Spacer()
                HStack(spacing: 6) {
                    Button(action: { zoomScale = max(0.25, zoomScale - 0.25) }) { Image(systemName: "minus.magnifyingglass") }
                    Text("\(Int(zoomScale * 100))%").font(.caption.monospacedDigit()).frame(width: 44)
                    Button(action: { zoomScale = min(8.0, zoomScale + 0.25) }) { Image(systemName: "plus.magnifyingglass") }
                    Button("중앙 맞춤") {
                        withAnimation(.easeOut(duration: 0.15)) { zoomScale = 1.0; panOffset = .zero; lastPanOffset = .zero }
                    }.font(.caption)
                }
            }.padding(10).background(.regularMaterial)
            
            GeometryReader { outerGeo in
                let baseFitSize = calculateFitSize(in: outerGeo.size)
                let scaledSize = CGSize(width: baseFitSize.width * zoomScale, height: baseFitSize.height * zoomScale)
                ZStack {
                    Color(white: 0.12)
                    ZStack(alignment: .topLeading) {
                        if let cg = rawCGImage {
                            Image(nsImage: NSImage(cgImage: cg, size: scaledSize))
                                .resizable().interpolation(.high)
                                .frame(width: scaledSize.width, height: scaledSize.height)
                        }
                        ForEach(redactItems) { item in
                            let r = CGRect(
                                x: item.normalizedRect.origin.x * scaledSize.width,
                                y: item.normalizedRect.origin.y * scaledSize.height,
                                width: item.normalizedRect.width * scaledSize.width,
                                height: item.normalizedRect.height * scaledSize.height
                            )
                            redactOverlayView(rect: r, style: item.style)
                        }
                        if mode == 0, let drag = activeDragRect { redactOverlayView(rect: drag, style: redactStyle) }
                        if mode == 1 { cropOverlayWith8Handles(canvasSize: scaledSize) }
                    }
                    .frame(width: scaledSize.width, height: scaledSize.height)
                    .contentShape(Rectangle())
                    .gesture(canvasDragGesture(canvasSize: scaledSize))
                    .offset(panOffset)
                    .position(x: outerGeo.size.width / 2, y: outerGeo.size.height / 2)
                    
                    ScrollWheelCatcher { delta in
                        zoomScale = min(8.0, max(0.25, zoomScale + delta * 0.012))
                    }.allowsHitTesting(false)
                }.frame(width: outerGeo.size.width, height: outerGeo.size.height).clipped()
            }
            
            HStack {
                if let cg = rawCGImage {
                    let outW = mode == 1 ? Int(CGFloat(cg.width) * cropRect.width) : cg.width
                    let outH = mode == 1 ? Int(CGFloat(cg.height) * cropRect.height) : cg.height
                    Text("출력 해상도: \(outW) × \(outH) px | 휠: 확대/축소 | '화면 이동' 버튼 활성 시 드래그로 위치 이동")
                        .font(.caption.monospacedDigit()).foregroundColor(.secondary)
                }
                Spacer()
                Button(mode == 1 ? "크롭 적용 및 원본 화질 저장" : "가리기 적용 및 원본 화질 저장") { saveExactPixelImage() }
                    .buttonStyle(.borderedProminent).tint(.orange)
            }.padding(12).background(.regularMaterial)
        }.onAppear { rawCGImage = FileProcessor.loadRawCGImage(from: fileURL) }
    }
    
    @ViewBuilder
    func cropOverlayWith8Handles(canvasSize: CGSize) -> some View {
        let cRect = CGRect(
            x: cropRect.origin.x * canvasSize.width,
            y: cropRect.origin.y * canvasSize.height,
            width: cropRect.width * canvasSize.width,
            height: cropRect.height * canvasSize.height
        )
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: canvasSize))
                path.addRect(cRect)
            }.fill(Color.black.opacity(0.58), style: FillStyle(eoFill: true))
            
            ZStack {
                Rectangle().stroke(Color.yellow, lineWidth: 2)
                VStack { Spacer(); Divider().background(Color.white.opacity(0.6)); Spacer(); Divider().background(Color.white.opacity(0.6)); Spacer() }
                HStack { Spacer(); Divider().background(Color.white.opacity(0.6)); Spacer(); Divider().background(Color.white.opacity(0.6)); Spacer() }
            }.frame(width: cRect.width, height: cRect.height).position(x: cRect.midX, y: cRect.midY)
            
            handleKnob(at: CGPoint(x: cRect.minX, y: cRect.minY))
            handleKnob(at: CGPoint(x: cRect.maxX, y: cRect.minY))
            handleKnob(at: CGPoint(x: cRect.minX, y: cRect.maxY))
            handleKnob(at: CGPoint(x: cRect.maxX, y: cRect.maxY))
            
            handleBar(at: CGPoint(x: cRect.midX, y: cRect.minY), horizontal: true)
            handleBar(at: CGPoint(x: cRect.midX, y: cRect.maxY), horizontal: true)
            handleBar(at: CGPoint(x: cRect.minX, y: cRect.midY), horizontal: false)
            handleBar(at: CGPoint(x: cRect.maxX, y: cRect.midY), horizontal: false)
        }
    }
    
    func handleKnob(at pt: CGPoint) -> some View {
        Circle().fill(Color.yellow).frame(width: 14, height: 14)
            .overlay(Circle().stroke(Color.black, lineWidth: 1.5)).shadow(radius: 2).position(pt)
    }
    func handleBar(at pt: CGPoint, horizontal: Bool) -> some View {
        Capsule().fill(Color.white).frame(width: horizontal ? 28 : 7, height: horizontal ? 7 : 28)
            .overlay(Capsule().stroke(Color.black, lineWidth: 1)).shadow(radius: 2).position(pt)
    }
    
    func canvasDragGesture(canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { val in
                if isPanMode || NSEvent.modifierFlags.contains(.option) {
                    panOffset = CGSize(width: lastPanOffset.width + val.translation.width, height: lastPanOffset.height + val.translation.height)
                    return
                }
                if mode == 0 {
                    let s = CGPoint(x: max(0, min(canvasSize.width, val.startLocation.x)), y: max(0, min(canvasSize.height, val.startLocation.y)))
                    let c = CGPoint(x: max(0, min(canvasSize.width, val.location.x)), y: max(0, min(canvasSize.height, val.location.y)))
                    activeDragRect = CGRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(c.x - s.x), height: abs(c.y - s.y))
                    return
                }
                if initialCropOnDrag == nil {
                    initialCropOnDrag = cropRect
                    activeCropHandle = detectCropHandle(at: val.startLocation, canvasSize: canvasSize)
                }
                guard let initRect = initialCropOnDrag else { return }
                let dx = val.translation.width / max(1, canvasSize.width)
                let dy = val.translation.height / max(1, canvasSize.height)
                let minLen: CGFloat = 0.04
                var minX = initRect.minX; var maxX = initRect.maxX
                var minY = initRect.minY; var maxY = initRect.maxY
                
                switch activeCropHandle {
                case .topLeft:
                    minX = min(maxX - minLen, max(0.0, initRect.minX + dx))
                    minY = min(maxY - minLen, max(0.0, initRect.minY + dy))
                case .topRight:
                    maxX = max(minX + minLen, min(1.0, initRect.maxX + dx))
                    minY = min(maxY - minLen, max(0.0, initRect.minY + dy))
                case .bottomLeft:
                    minX = min(maxX - minLen, max(0.0, initRect.minX + dx))
                    maxY = max(minY + minLen, min(1.0, initRect.maxY + dy))
                case .bottomRight:
                    maxX = max(minX + minLen, min(1.0, initRect.maxX + dx))
                    maxY = max(minY + minLen, min(1.0, initRect.maxY + dy))
                case .top: minY = min(maxY - minLen, max(0.0, initRect.minY + dy))
                case .bottom: maxY = max(minY + minLen, min(1.0, initRect.maxY + dy))
                case .left: minX = min(maxX - minLen, max(0.0, initRect.minX + dx))
                case .right: maxX = max(minX + minLen, min(1.0, initRect.maxX + dx))
                case .moveInside:
                    let w = initRect.width; let h = initRect.height
                    minX = max(0.0, min(1.0 - w, initRect.minX + dx))
                    minY = max(0.0, min(1.0 - h, initRect.minY + dy))
                    maxX = minX + w; maxY = minY + h
                case .none:
                    let sx = max(0, min(1, val.startLocation.x / canvasSize.width))
                    let sy = max(0, min(1, val.startLocation.y / canvasSize.height))
                    let cx = max(0, min(1, val.location.x / canvasSize.width))
                    let cy = max(0, min(1, val.location.y / canvasSize.height))
                    minX = min(sx, cx); maxX = max(minX + minLen, max(sx, cx))
                    minY = min(sy, cy); maxY = max(minY + minLen, max(sy, cy))
                }
                cropRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            }
            .onEnded { _ in
                if isPanMode || NSEvent.modifierFlags.contains(.option) { lastPanOffset = panOffset; return }
                if mode == 0, let drag = activeDragRect, drag.width > 4, drag.height > 4 {
                    let norm = CGRect(x: drag.origin.x / canvasSize.width, y: drag.origin.y / canvasSize.height, width: drag.width / canvasSize.width, height: drag.height / canvasSize.height)
                    redactItems.append(RedactItem(normalizedRect: norm, style: redactStyle))
                }
                activeDragRect = nil; initialCropOnDrag = nil; activeCropHandle = nil
            }
    }
    
    func detectCropHandle(at pt: CGPoint, canvasSize: CGSize) -> CropHandle? {
        let cRect = CGRect(x: cropRect.origin.x * canvasSize.width, y: cropRect.origin.y * canvasSize.height, width: cropRect.width * canvasSize.width, height: cropRect.height * canvasSize.height)
        let r: CGFloat = 22.0
        if hypot(pt.x - cRect.minX, pt.y - cRect.minY) <= r { return .topLeft }
        if hypot(pt.x - cRect.maxX, pt.y - cRect.minY) <= r { return .topRight }
        if hypot(pt.x - cRect.minX, pt.y - cRect.maxY) <= r { return .bottomLeft }
        if hypot(pt.x - cRect.maxX, pt.y - cRect.maxY) <= r { return .bottomRight }
        if abs(pt.y - cRect.minY) <= r && pt.x >= cRect.minX && pt.x <= cRect.maxX { return .top }
        if abs(pt.y - cRect.maxY) <= r && pt.x >= cRect.minX && pt.x <= cRect.maxX { return .bottom }
        if abs(pt.x - cRect.minX) <= r && pt.y >= cRect.minY && pt.y <= cRect.maxY { return .left }
        if abs(pt.x - cRect.maxX) <= r && pt.y >= cRect.minY && pt.y <= cRect.maxY { return .right }
        if cRect.contains(pt) { return .moveInside }
        return nil
    }
    
    @ViewBuilder
    func redactOverlayView(rect: CGRect, style: RedactStyle) -> some View {
        Group {
            switch style {
            case .blackBox: Rectangle().fill(Color.black)
            case .blur: Rectangle().fill(.ultraThinMaterial).overlay(Rectangle().stroke(Color.white.opacity(0.6), lineWidth: 1))
            case .pixelate:
                ZStack {
                    Rectangle().fill(Color.orange.opacity(0.35))
                    Text("MOSAIC").font(.system(size: 10, weight: .black)).foregroundColor(.white)
                }.overlay(Rectangle().stroke(Color.orange, lineWidth: 1.5))
            }
        }.frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
    }
    
    func calculateFitSize(in container: CGSize) -> CGSize {
        guard let cg = rawCGImage, cg.width > 0, cg.height > 0 else { return CGSize(width: 600, height: 400) }
        let ratio = min(max(240, container.width - 48) / CGFloat(cg.width), max(240, container.height - 48) / CGFloat(cg.height))
        return CGSize(width: CGFloat(cg.width) * ratio, height: CGFloat(cg.height) * ratio)
    }
    func setAspectCrop(_ targetAspect: CGFloat) {
        guard let cg = rawCGImage else { return }
        let imgAspect = CGFloat(cg.width) / CGFloat(cg.height)
        var w: CGFloat = 0.8; var h: CGFloat = 0.8
        if targetAspect > imgAspect { h = w * (imgAspect / targetAspect) } else { w = h * (targetAspect / imgAspect) }
        cropRect = CGRect(x: (1.0 - w) / 2.0, y: (1.0 - h) / 2.0, width: w, height: h)
    }
    func saveExactPixelImage() {
        guard let cg = rawCGImage else { return }
        let fullW = CGFloat(cg.width); let fullH = CGFloat(cg.height)
        var ciImage = CIImage(cgImage: cg)
        for item in redactItems {
            let pxRect = CGRect(
                x: item.normalizedRect.origin.x * fullW,
                y: (1.0 - item.normalizedRect.origin.y - item.normalizedRect.height) * fullH,
                width: item.normalizedRect.width * fullW,
                height: item.normalizedRect.height * fullH
            ).intersection(ciImage.extent)
            guard !pxRect.isEmpty else { continue }
            var patch: CIImage
            switch item.style {
            case .blackBox: patch = CIImage(color: .black).cropped(to: pxRect)
            case .pixelate:
                let f = CIFilter.pixellate(); f.inputImage = ciImage
                f.scale = Float(max(12.0, (max(fullW, fullH) / 1000.0) * strength))
                patch = (f.outputImage ?? ciImage).cropped(to: pxRect)
            case .blur:
                let f = CIFilter.gaussianBlur(); f.inputImage = ciImage.clampedToExtent()
                f.radius = Float(max(15.0, (max(fullW, fullH) / 1000.0) * strength))
                patch = (f.outputImage ?? ciImage).cropped(to: pxRect)
            }
            ciImage = patch.composited(over: ciImage)
        }
        if mode == 1 {
            let cropPx = CGRect(
                x: cropRect.origin.x * fullW,
                y: (1.0 - cropRect.origin.y - cropRect.height) * fullH,
                width: cropRect.width * fullW,
                height: cropRect.height * fullH
            ).intersection(ciImage.extent)
            if !cropPx.isEmpty { ciImage = ciImage.cropped(to: cropPx) }
        }
        let ext = fileURL.pathExtension.isEmpty ? "png" : fileURL.pathExtension
        let outURL = FileProcessor.uniqueOutputURL(for: fileURL, newExt: ext, suffix: mode == 1 ? "_cropped" : "_redacted")
        if let outCG = ciContext.createCGImage(ciImage, from: ciImage.extent) {
            FileProcessor.saveCGImage(outCG, to: outURL, formatExt: ext, quality: 0.96, sourceURLForMetadata: fileURL)
            FileProcessor.showToast("원본 화질 저장 완료 (메타데이터 유지됨): \(outURL.lastPathComponent)")
            NSApp.keyWindow?.close()
        }
    }
}

// MARK: - 10. QuickTime 비디오 프리뷰 + 20배 확대/축소 정밀 트림 타임라인 + 다중 채널 사운드 스튜디오
struct VideoPlayerPreview: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView(); v.player = player; v.controlsStyle = .none; v.videoGravity = .resizeAspect; return v
    }
    func updateNSView(_ nsView: AVPlayerView, context: Context) { if nsView.player !== player { nsView.player = player } }
}

class MultiChannelMediaController: ObservableObject {
    let fileURL: URL
    let player = AVPlayer()
    @Published var isVideo: Bool = false
    @Published var duration: Double = 10.0
    @Published var fps: Double = 30.0
    @Published var currentTime: Double = 0.0
    @Published var startTime: Double = 0.0
    @Published var endTime: Double = 10.0
    @Published var isPlaying: Bool = false
    @Published var channelCount: Int = 2
    @Published var channelEnabled: [Bool] = [true, true]
    @Published var soloChannel: Int? = nil
    @Published var previewVolume: Float = 1.0
    
    private var timeObserver: Any?
    private var audioEngine: AVAudioEngine?
    private var audioPlayerNode: AVAudioPlayerNode?
    private var audioFile: AVAudioFile?
    private var audioSegmentStartTime: Double = 0.0
    private var audioPlayTimer: Timer?
    
    init(url: URL) {
        self.fileURL = url
        let ext = url.pathExtension.lowercased()
        self.isVideo = ["mp4", "mov", "m4v", "mkv", "avi", "webm"].contains(ext)
        setupMedia()
    }
    var isCustomChannelFilterActive: Bool {
        if soloChannel != nil { return true }
        return channelEnabled.contains(false)
    }
    func setupMedia() {
        let asset = AVURLAsset(url: fileURL)
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        player.isMuted = false; player.volume = previewVolume
        
        if !isVideo, let af = try? AVAudioFile(forReading: fileURL) {
            self.audioFile = af
            let ch = Int(af.processingFormat.channelCount)
            if ch > 0 { channelCount = ch; channelEnabled = Array(repeating: true, count: ch) }
        }
        Task {
            if let cmDur = try? await asset.load(.duration) {
                let sec = CMTimeGetSeconds(cmDur)
                if sec.isFinite && sec > 0 { await MainActor.run { self.duration = sec; self.endTime = sec } }
            }
            if let vTracks = try? await asset.loadTracks(withMediaType: .video), let vTrack = vTracks.first {
                let rate = (try? await vTrack.load(.nominalFrameRate)) ?? 30.0
                await MainActor.run { self.isVideo = true; if rate > 0 { self.fps = Double(rate) } }
            }
            if let aTracks = try? await asset.loadTracks(withMediaType: .audio) {
                var detected = 0
                for track in aTracks {
                    if let descs = try? await track.load(.formatDescriptions), let desc = descs.first {
                        if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                            detected += Int(asbd.pointee.mChannelsPerFrame)
                        }
                    }
                }
                if detected > 0 {
                    let finalCh = min(16, max(1, detected))
                    await MainActor.run { self.channelCount = finalCh; self.channelEnabled = Array(repeating: true, count: finalCh) }
                }
            }
        }
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1.0 / 60.0, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self = self, self.audioEngine == nil else { return }
            let sec = CMTimeGetSeconds(time)
            if sec.isFinite {
                if sec < self.startTime - 0.02 { self.seek(to: self.startTime) }
                else if sec >= self.endTime { self.pause(); self.seek(to: self.startTime) }
                else { self.currentTime = sec }
            }
        }
    }
    func setPreviewVolume(_ vol: Float) {
        previewVolume = max(0.0, min(2.0, vol))
        player.volume = previewVolume
        audioEngine?.mainMixerNode.outputVolume = previewVolume
    }
    func togglePlay() {
        if isPlaying { pause() }
        else {
            if currentTime < startTime || currentTime >= endTime - 0.02 { seek(to: startTime) }
            play()
        }
    }
    func play() {
        isPlaying = true
        if !isVideo && isCustomChannelFilterActive && audioFile != nil {
            player.pause()
            playCustomMultiChannelAudio(from: currentTime)
        } else {
            stopAudioEngine()
            let anyActive = (0..<channelCount).contains { isChannelActive($0) }
            player.isMuted = !anyActive; player.volume = previewVolume
            player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: endTime, preferredTimescale: 6000)
            player.play()
        }
    }
    func pause() { isPlaying = false; player.pause(); stopAudioEngine() }
    private func stopAudioEngine() {
        audioPlayTimer?.invalidate(); audioPlayTimer = nil
        audioPlayerNode?.stop(); audioEngine?.stop()
        audioEngine = nil; audioPlayerNode = nil
    }
    func seek(to sec: Double) {
        let clampedToTrim = max(startTime, min(endTime, sec))
        currentTime = clampedToTrim
        player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: endTime, preferredTimescale: 6000)
        player.seek(to: CMTime(seconds: clampedToTrim, preferredTimescale: 6000), toleranceBefore: .zero, toleranceAfter: .zero)
        if isPlaying && !isVideo && isCustomChannelFilterActive && audioFile != nil {
            playCustomMultiChannelAudio(from: clampedToTrim)
        }
    }
    func stepFrames(_ deltaFrames: Int) {
        pause()
        seek(to: currentTime + Double(deltaFrames) * (1.0 / max(1.0, fps)))
    }
    func isChannelActive(_ idx: Int) -> Bool {
        if let solo = soloChannel { return solo == idx }
        guard idx < channelEnabled.count else { return true }
        return channelEnabled[idx]
    }
    func updateChannelRouting() {
        if isPlaying {
            let resumeTime = currentTime; pause(); seek(to: resumeTime); play()
        } else {
            player.isMuted = !(0..<channelCount).contains { isChannelActive($0) }
        }
    }
    private func playCustomMultiChannelAudio(from startSec: Double) {
        guard let af = audioFile else { return }
        stopAudioEngine()
        let fmt = af.processingFormat; let sr = fmt.sampleRate; let totalFrames = af.length
        let clampedStart = max(startTime, min(endTime, startSec))
        let startFrame = AVAudioFramePosition(max(0, min(Double(totalFrames), clampedStart * sr)))
        let endFrame = AVAudioFramePosition(max(Double(startFrame), min(Double(totalFrames), endTime * sr)))
        let requestedFrames = AVAudioFrameCount(max(0, endFrame - startFrame))
        guard requestedFrames > 0 else { isPlaying = false; return }
        
        let frameCount = min(requestedFrames, AVAudioFrameCount(sr * 30.0))
        guard let readBuf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frameCount) else { return }
        af.framePosition = startFrame
        try? af.read(into: readBuf, frameCount: frameCount)
        
        guard let stereoFmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2),
              let outBuf = AVAudioPCMBuffer(pcmFormat: stereoFmt, frameCapacity: frameCount) else { return }
        outBuf.frameLength = readBuf.frameLength
        
        let inChCount = Int(fmt.channelCount)
        if let inData = readBuf.floatChannelData, let outData = outBuf.floatChannelData {
            let len = Int(readBuf.frameLength)
            for i in 0..<len { outData[0][i] = 0.0; outData[1][i] = 0.0 }
            var activeIndices: [Int] = []
            for c in 0..<inChCount where isChannelActive(c) { activeIndices.append(c) }
            let gain = activeIndices.isEmpty ? 0.0 : (1.0 / Float(max(1, activeIndices.count)))
            for c in activeIndices {
                let src = inData[c]
                if soloChannel != nil || inChCount == 1 {
                    for i in 0..<len { outData[0][i] += src[i]; outData[1][i] += src[i] }
                } else {
                    let targetOut = c % 2
                    for i in 0..<len { outData[targetOut][i] += src[i] * min(1.0, gain * 1.5) }
                }
            }
        }
        let engine = AVAudioEngine(); let node = AVAudioPlayerNode()
        engine.attach(node); engine.connect(node, to: engine.mainMixerNode, format: stereoFmt)
        engine.mainMixerNode.outputVolume = previewVolume
        try? engine.start()
        audioSegmentStartTime = clampedStart
        node.scheduleBuffer(outBuf, at: nil, options: []); node.play()
        self.audioEngine = engine; self.audioPlayerNode = node
        
        let startedAt = Date()
        audioPlayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            let nowSec = self.audioSegmentStartTime + Date().timeIntervalSince(startedAt)
            if nowSec >= self.endTime { self.pause(); self.seek(to: self.startTime) }
            else { self.currentTime = nowSec }
        }
    }
    func formatTimecode(_ sec: Double) -> String {
        let safe = max(0.0, sec); let totalSecs = Int(safe)
        let h = totalSecs / 3600; let m = (totalSecs % 3600) / 60; let s = totalSecs % 60
        let f = Int(((safe - Double(totalSecs)) * fps).rounded()) % max(1, Int(fps.rounded()))
        return String(format: "%02d:%02d:%02d:%02d", h, m, s, f)
    }
    func splitTimecode(_ sec: Double) -> (h: Int, m: Int, s: Int, f: Int) {
        let safe = max(0.0, sec); let totalSecs = Int(safe)
        let h = totalSecs / 3600; let m = (totalSecs % 3600) / 60; let s = totalSecs % 60
        let f = Int(((safe - Double(totalSecs)) * fps).rounded()) % max(1, Int(fps.rounded()))
        return (h, m, s, f)
    }
    func composeSeconds(h: Int, m: Int, s: Int, f: Int) -> Double {
        let base = Double(max(0, h) * 3600 + max(0, m) * 60 + max(0, s))
        return min(duration, max(0.0, base + Double(max(0, f)) / max(1.0, fps)))
    }
    deinit {
        if let obs = timeObserver { player.removeTimeObserver(obs) }
        stopAudioEngine()
    }
}

struct ProMediaStudioView: View {
    let fileURL: URL
    let initialMode: String
    @StateObject private var ctrl: MultiChannelMediaController
    @State private var volumePercent: Double = 100.0
    @State private var trimSilence: Bool = false
    @State private var enableBleep: Bool = false
    @State private var inH: Int = 0; @State private var inM: Int = 0; @State private var inS: Int = 0; @State private var inF: Int = 0
    @State private var outH: Int = 0; @State private var outM: Int = 0; @State private var outS: Int = 0; @State private var outF: Int = 0
    @State private var timelineZoom: CGFloat = 1.0
    
    let sampleBars: [CGFloat] = (0..<240).map { i in
        let d = Double(i)
        return CGFloat(abs(sin(d * 0.29) * cos(d * 0.13)) * 0.78 + 0.18)
    }
    init(fileURL: URL, initialMode: String) {
        self.fileURL = fileURL; self.initialMode = initialMode
        _ctrl = StateObject(wrappedValue: MultiChannelMediaController(url: fileURL))
    }
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.black)
                if ctrl.isVideo {
                    VideoPlayerPreview(player: ctrl.player).cornerRadius(10).padding(4)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.circle.fill").font(.system(size: 46)).foregroundColor(.orange)
                        Text(fileURL.lastPathComponent).font(.headline).foregroundColor(.white)
                        Text("Multi-Channel Audio (\(ctrl.channelCount) Channels Detected)").font(.caption).foregroundColor(.gray)
                    }
                }
                VStack {
                    HStack {
                        Text("🔒 트림 구간 내 재생 잠금 활성화됨")
                            .font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5).background(Color.orange.opacity(0.85), in: Capsule())
                        Spacer()
                        Text("현재 위치: \(ctrl.formatTimecode(ctrl.currentTime))  (\(String(format: "%.2f", ctrl.fps)) fps)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(.yellow)
                            .padding(.horizontal, 10).padding(.vertical, 5).background(Color.black.opacity(0.75), in: Capsule())
                    }.padding(10)
                    Spacer()
                }
            }.frame(height: ctrl.isVideo ? 300 : 130)
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass.circle.fill").foregroundColor(.orange)
                    Text("타임라인 확대/축소:").font(.caption.bold())
                    Button(action: { timelineZoom = max(1.0, timelineZoom - 1.0) }) { Image(systemName: "minus.magnifyingglass") }
                    Slider(value: $timelineZoom, in: 1.0...20.0).frame(width: 140).tint(.orange)
                    Button(action: { timelineZoom = min(20.0, timelineZoom + 1.0) }) { Image(systemName: "plus.magnifyingglass") }
                    Text(String(format: "%.1fx", timelineZoom)).font(.caption.monospacedDigit().bold()).foregroundColor(.orange).frame(width: 38)
                    
                    Button("🎯 트림 구간만 확대") {
                        let trimLen = max(0.2, ctrl.endTime - ctrl.startTime)
                        let targetZoom = min(20.0, max(1.5, CGFloat(ctrl.duration / trimLen) * 0.85))
                        withAnimation(.easeOut(duration: 0.15)) { timelineZoom = targetZoom }
                    }.font(.caption)
                    
                    Button("1x 전체보기") {
                        withAnimation(.easeOut(duration: 0.15)) { timelineZoom = 1.0 }
                    }.font(.caption)
                    
                    Spacer()
                    Text("트림 길이: \(ctrl.formatTimecode(max(0, ctrl.endTime - ctrl.startTime)))")
                        .font(.caption.monospacedDigit().bold()).foregroundColor(.orange)
                }
                
                GeometryReader { outerGeo in
                    let baseW = max(200, outerGeo.size.width)
                    let totalW = baseW * timelineZoom
                    let h: CGFloat = 74
                    let visibleBars = min(sampleBars.count, max(80, Int(85.0 * timelineZoom)))
                    let tickCount = max(5, min(60, Int(5.0 * timelineZoom)))
                    
                    ScrollView(.horizontal, showsIndicators: true) {
                        let startX = CGFloat(ctrl.startTime / max(0.01, ctrl.duration)) * totalW
                        let endX = CGFloat(ctrl.endTime / max(0.01, ctrl.duration)) * totalW
                        let playX = CGFloat(ctrl.currentTime / max(0.01, ctrl.duration)) * totalW
                        
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.15))
                            
                            VStack {
                                HStack(spacing: 0) {
                                    ForEach(0..<tickCount, id: \.self) { tIdx in
                                        let tSec = (Double(tIdx) / Double(tickCount)) * ctrl.duration
                                        HStack(spacing: 2) {
                                            Rectangle().fill(Color.white.opacity(0.35)).frame(width: 1, height: 8)
                                            Text(ctrl.formatTimecode(tSec))
                                                .font(.system(size: 8.5, design: .monospaced))
                                                .foregroundColor(.white.opacity(0.55))
                                            Spacer()
                                        }
                                        .frame(width: totalW / CGFloat(tickCount))
                                    }
                                }
                                Spacer()
                            }
                            .padding(.top, 2)
                            
                            HStack(spacing: (totalW / CGFloat(visibleBars)) * 0.25) {
                                ForEach(0..<visibleBars, id: \.self) { idx in
                                    let t = (Double(idx) / Double(visibleBars)) * ctrl.duration
                                    let inTrim = (t >= ctrl.startTime && t <= ctrl.endTime)
                                    let barSample = sampleBars[idx % sampleBars.count]
                                    Capsule().fill(inTrim ? Color.orange.opacity(0.88) : Color.gray.opacity(0.22))
                                        .frame(width: max(2, (totalW / CGFloat(visibleBars)) * 0.65), height: (h - 24) * barSample)
                                }
                            }
                            .padding(.horizontal, 6)
                            .offset(y: 6)
                            
                            Rectangle().fill(Color.black.opacity(0.72)).frame(width: max(0, startX), height: h)
                            Rectangle().fill(Color.black.opacity(0.72)).frame(width: max(0, totalW - endX), height: h).offset(x: endX)
                            
                            RoundedRectangle(cornerRadius: 6).stroke(Color.yellow, lineWidth: 3)
                                .frame(width: max(10, endX - startX), height: h - 2).offset(x: startX)
                            
                            ZStack {
                                RoundedRectangle(cornerRadius: 4).fill(Color.yellow).frame(width: 14, height: h)
                                Rectangle().fill(Color.black).frame(width: 2, height: 18)
                            }.position(x: max(7, startX), y: h / 2).gesture(
                                DragGesture().onChanged { val in
                                    ctrl.pause()
                                    let sec = Double(val.location.x / totalW) * ctrl.duration
                                    ctrl.startTime = max(0.0, min(ctrl.endTime - (1.0 / ctrl.fps), sec))
                                    ctrl.seek(to: ctrl.startTime); syncTimecodeFields()
                                }
                            )
                            
                            ZStack {
                                RoundedRectangle(cornerRadius: 4).fill(Color.yellow).frame(width: 14, height: h)
                                Rectangle().fill(Color.black).frame(width: 2, height: 18)
                            }.position(x: min(totalW - 7, endX), y: h / 2).gesture(
                                DragGesture().onChanged { val in
                                    ctrl.pause()
                                    let sec = Double(val.location.x / totalW) * ctrl.duration
                                    ctrl.endTime = min(ctrl.duration, max(ctrl.startTime + (1.0 / ctrl.fps), sec))
                                    ctrl.seek(to: ctrl.endTime); syncTimecodeFields()
                                }
                            )
                            
                            ZStack {
                                Rectangle().fill(Color.red).frame(width: 2.5, height: h + 6)
                                Circle().fill(Color.red).frame(width: 11, height: 11).offset(y: -h / 2)
                            }.position(x: playX, y: h / 2)
                        }
                        .frame(width: totalW, height: h)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { val in
                            ctrl.seek(to: Double(max(0, min(totalW, val.location.x)) / totalW) * ctrl.duration)
                        })
                    }
                    .overlay(
                        ScrollWheelCatcher { delta in
                            timelineZoom = min(20.0, max(1.0, timelineZoom + delta * 0.04))
                        }
                        .allowsHitTesting(false)
                    )
                }.frame(height: 88)
            }
            
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Button(action: { ctrl.stepFrames(-1) }) { Image(systemName: "backward.frame.fill") }
                    Button(action: { ctrl.togglePlay() }) {
                        Image(systemName: ctrl.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 28)).foregroundColor(.orange)
                    }.buttonStyle(.plain)
                    Button(action: { ctrl.stepFrames(1) }) { Image(systemName: "forward.frame.fill") }
                    Button("시작점 보기") { ctrl.pause(); ctrl.seek(to: ctrl.startTime) }.font(.caption)
                    Button("끝점 보기") { ctrl.pause(); ctrl.seek(to: ctrl.endTime) }.font(.caption)
                }
                Divider().frame(height: 28)
                timecodeStepperBox(label: "시작(In)", h: $inH, m: $inM, s: $inS, f: $inF, onApply: {
                    ctrl.pause()
                    ctrl.startTime = min(ctrl.composeSeconds(h: inH, m: inM, s: inS, f: inF), ctrl.endTime - (1.0 / ctrl.fps))
                    ctrl.seek(to: ctrl.startTime); syncTimecodeFields()
                }, onStepFrame: { df in
                    ctrl.pause(); let fd = 1.0 / max(1.0, ctrl.fps)
                    ctrl.startTime = max(0, min(ctrl.endTime - fd, ctrl.startTime + Double(df) * fd))
                    ctrl.seek(to: ctrl.startTime); syncTimecodeFields()
                })
                timecodeStepperBox(label: "종료(Out)", h: $outH, m: $outM, s: $outS, f: $outF, onApply: {
                    ctrl.pause()
                    ctrl.endTime = max(ctrl.composeSeconds(h: outH, m: outM, s: outS, f: outF), ctrl.startTime + (1.0 / ctrl.fps))
                    ctrl.seek(to: ctrl.endTime); syncTimecodeFields()
                }, onStepFrame: { df in
                    ctrl.pause(); let fd = 1.0 / max(1.0, ctrl.fps)
                    ctrl.endTime = min(ctrl.duration, max(ctrl.startTime + frameDur(fd), ctrl.endTime + Double(df) * fd))
                    ctrl.seek(to: ctrl.endTime); syncTimecodeFields()
                })
            }.padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("🎛️ 다중 오디오 채널 믹서 (총 \(ctrl.channelCount)채널 감지됨 — 원하는 채널만 켜서 듣거나 내보낼 수 있습니다)")
                        .font(.caption.bold()).foregroundColor(.orange)
                    Spacer()
                    Button("전체 채널 켜기") {
                        ctrl.soloChannel = nil; ctrl.channelEnabled = Array(repeating: true, count: ctrl.channelCount); ctrl.updateChannelRouting()
                    }.font(.caption2)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(0..<ctrl.channelCount, id: \.self) { chIdx in
                            let isOn = ctrl.isChannelActive(chIdx)
                            let isSolo = (ctrl.soloChannel == chIdx)
                            VStack(spacing: 6) {
                                Text("CH \(chIdx + 1)").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundColor(isOn ? .primary : .secondary)
                                HStack(spacing: 6) {
                                    Button(action: {
                                        ctrl.soloChannel = nil
                                        if chIdx < ctrl.channelEnabled.count { ctrl.channelEnabled[chIdx].toggle(); ctrl.updateChannelRouting() }
                                    }) {
                                        Label(isOn ? "ON" : "MUTE", systemImage: isOn ? "speaker.wave.2.fill" : "speaker.slash.fill").font(.caption2.bold())
                                    }.buttonStyle(.borderedProminent).tint(isOn ? .green : .gray)
                                    Button(action: {
                                        ctrl.soloChannel = (ctrl.soloChannel == chIdx) ? nil : chIdx; ctrl.updateChannelRouting()
                                    }) { Text("SOLO").font(.system(size: 10, weight: .black)) }
                                    .buttonStyle(.borderedProminent).tint(isSolo ? .yellow : .secondary)
                                }
                            }
                            .padding(8).background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSolo ? Color.yellow : (isOn ? Color.green.opacity(0.6) : Color.clear), lineWidth: 1.5))
                        }
                    }
                }
            }.padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            
            HStack(spacing: 18) {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.3.fill").foregroundColor(.orange)
                    Text("볼륨").font(.caption)
                    Slider(value: $volumePercent, in: 20...200).frame(width: 110).tint(.orange)
                        .onChange(of: volumePercent) { ctrl.setPreviewVolume(Float(volumePercent / 100.0)) }
                    Text("\(Int(volumePercent))%").font(.caption.monospacedDigit()).frame(width: 40)
                }
                Toggle("앞뒤 무음 제거", isOn: $trimSilence).font(.caption)
                Toggle("Bleep(삐- 소리)", isOn: $enableBleep).font(.caption)
                Spacer()
                Button("트림 및 채널 설정 적용하여 저장") { exportEditedMedia() }.buttonStyle(.borderedProminent).tint(.orange)
            }
        }
        .padding(16)
        .onAppear {
            if initialMode == "tool_audio_bleep" { enableBleep = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { syncTimecodeFields() }
        }
        .onDisappear { ctrl.pause() }
    }
    
    func frameDur(_ fd: Double) -> Double { fd }
    func syncTimecodeFields() {
        let s = ctrl.splitTimecode(ctrl.startTime); inH = s.h; inM = s.m; inS = s.s; inF = s.f
        let e = ctrl.splitTimecode(ctrl.endTime); outH = e.h; outM = e.m; outS = e.s; outF = e.f
    }
    func timecodeStepperBox(label: String, h: Binding<Int>, m: Binding<Int>, s: Binding<Int>, f: Binding<Int>, onApply: @escaping () -> Void, onStepFrame: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption.bold()).foregroundColor(.orange)
            HStack(spacing: 2) {
                TextField("HH", value: h, format: .number).frame(width: 28)
                Text(":")
                TextField("MM", value: m, format: .number).frame(width: 28)
                Text(":")
                TextField("SS", value: s, format: .number).frame(width: 28)
                Text(":")
                TextField("FF", value: f, format: .number).frame(width: 28)
            }.textFieldStyle(.roundedBorder).font(.system(size: 11, weight: .semibold, design: .monospaced))
            Button("적용") { onApply() }.font(.caption2)
            Button("-1F") { onStepFrame(-1) }.font(.caption2)
            Button("+1F") { onStepFrame(1) }.font(.caption2)
        }
    }
    func exportEditedMedia() {
        ctrl.pause()
        let startSec = min(ctrl.startTime, ctrl.endTime); let endSec = max(ctrl.startTime, ctrl.endTime)
        let clipDur = max(0.1, endSec - startSec)
        let outURL = FileProcessor.uniqueOutputURL(for: fileURL, newExt: fileURL.pathExtension, suffix: "_trimmed")
        let jobTitle = "트림 편집: \(fileURL.lastPathComponent)"
        var activeChannels: [Int] = []
        for idx in 0..<ctrl.channelCount where ctrl.isChannelActive(idx) { activeChannels.append(idx) }
        
        if FileProcessor.ffmpegPath != nil {
            var filters: [String] = ["volume=\(volumePercent / 100.0)"]
            if activeChannels.count > 0 && activeChannels.count < ctrl.channelCount {
                if activeChannels.count == 1 { filters.append("pan=mono|c0=c\(activeChannels[0])") }
                else {
                    let exprs = activeChannels.enumerated().map { "c\($0.offset)=c\($0.element)" }.joined(separator: "|")
                    filters.append("pan=\(activeChannels.count)c|\(exprs)")
                }
            } else if activeChannels.isEmpty { filters.append("volume=0") }
            if trimSilence { filters.append("silenceremove=start_periods=1:start_silence=0.2:start_threshold=-45dB") }
            var args = ["-y", "-ss", String(format: "%.4f", startSec), "-to", String(format: "%.4f", endSec), "-i", fileURL.path, "-map_metadata", "0"]
            if ctrl.isVideo { args += ["-movflags", "use_metadata_tags", "-c:v", "libx264", "-preset", "fast", "-crf", "20"] }
            args += ["-af", filters.joined(separator: ","), outURL.path]
            
            FileProcessor.runFFmpegWithProgress(args: args, totalDuration: clipDur, jobTitle: jobTitle) { ok in
                if ok && FileManager.default.fileExists(atPath: outURL.path) {
                    FileProcessor.preserveFileDates(from: fileURL, to: outURL)
                    FileProcessor.showToast("편집 완료 (메타데이터 유지됨): \(outURL.lastPathComponent)")
                    NSApp.keyWindow?.close()
                } else {
                    nativeExportFallback(startSec: startSec, duration: clipDur, outURL: outURL, jobTitle: jobTitle)
                }
            }
        } else {
            nativeExportFallback(startSec: startSec, duration: clipDur, outURL: outURL, jobTitle: jobTitle)
        }
    }
    func nativeExportFallback(startSec: Double, duration: Double, outURL: URL, jobTitle: String) {
        let asset = AVURLAsset(url: fileURL)
        let preset = ctrl.isVideo ? AVAssetExportPresetHighestQuality : AVAssetExportPresetAppleM4A
        guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else { return }
        let finalURL = ctrl.isVideo ? outURL : FileProcessor.uniqueOutputURL(for: fileURL, newExt: "m4a", suffix: "_trimmed")
        exporter.outputURL = finalURL; exporter.outputFileType = ctrl.isVideo ? .mp4 : .m4a
        exporter.timeRange = CMTimeRange(start: CMTime(seconds: startSec, preferredTimescale: 6000), duration: CMTime(seconds: duration, preferredTimescale: 6000))
        let jobID = JobProgressManager.shared.startJob(title: jobTitle)
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            JobProgressManager.shared.updateJob(id: jobID, progress: Double(exporter.progress))
        }
        exporter.exportAsynchronously {
            DispatchQueue.main.async {
                timer.invalidate(); JobProgressManager.shared.finishJob(id: jobID)
                FileProcessor.preserveFileDates(from: fileURL, to: finalURL)
                FileProcessor.showToast("트림 저장 완료: \(finalURL.lastPathComponent)")
                NSApp.keyWindow?.close()
            }
        }
    }
}

// MARK: - 11. 배경 추가 창 / 압축 창 / 메타데이터 창
struct AddBGView: View {
    let fileURL: URL
    @State private var selectedPreset = 0
    @State private var paddingRatio: CGFloat = 0.12
    let gradients: [[Color]] = [
        [Color.cyan, Color.blue], [Color.orange, Color.pink, Color.purple],
        [Color.mint, Color.teal], [Color(white: 0.95), Color(white: 0.82)],
        [Color.pink, Color.orange], [Color.indigo, Color.black], [Color.green, Color.blue]
    ]
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                LinearGradient(colors: gradients[selectedPreset], startPoint: .topLeading, endPoint: .bottomTrailing).cornerRadius(16)
                if let img = NSImage(contentsOf: fileURL) {
                    Image(nsImage: img).resizable().scaledToFit().cornerRadius(10)
                        .shadow(color: .black.opacity(0.32), radius: 18, x: 0, y: 10).padding(450 * paddingRatio)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 12) {
                Text("배경 스타일").font(.caption.bold())
                ForEach(0..<gradients.count, id: \.self) { idx in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: gradients[idx], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 38, height: 30)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selectedPreset == idx ? Color.orange : Color.white, lineWidth: 2.5))
                        .onTapGesture { selectedPreset = idx }
                }
            }
            HStack(spacing: 16) {
                Text("여백 비율").font(.caption)
                Slider(value: $paddingRatio, in: 0.04...0.28).tint(.orange).frame(width: 220)
                Spacer()
                Button("고화질 배경 합성 저장") { saveImageWithBG() }.buttonStyle(.borderedProminent).tint(.orange)
            }
        }.padding(20)
    }
    @MainActor
    func saveImageWithBG() {
        let baseSize: CGFloat = 1800
        let renderView = ZStack {
            LinearGradient(colors: gradients[selectedPreset], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let img = NSImage(contentsOf: fileURL) {
                Image(nsImage: img).resizable().scaledToFit().cornerRadius(20)
                    .shadow(color: .black.opacity(0.35), radius: 30, x: 0, y: 16).padding(baseSize * paddingRatio)
            }
        }.frame(width: baseSize, height: baseSize * 0.8)
        let renderer = ImageRenderer(content: renderView)
        if let cg = renderer.cgImage {
            let out = FileProcessor.uniqueOutputURL(for: fileURL, newExt: "png", suffix: "_bg")
            FileProcessor.saveCGImage(cg, to: out, formatExt: "png", quality: 0.98, sourceURLForMetadata: fileURL)
            FileProcessor.showToast("배경 합성 저장 완료 (메타데이터 유지됨): \(out.lastPathComponent)")
            NSApp.keyWindow?.close()
        }
    }
}

struct CompressToolView: View {
    let files: [URL]
    @State private var quality: Double = 65.0
    @State private var origBytes: Int64 = 0
    @State private var estBytes: Int64 = 0
    var body: some View {
        VStack(spacing: 16) {
            Text("Compress \(files.count) File(s) (메타데이터 보존)").font(.headline)
            HStack(spacing: 18) {
                VStack(spacing: 4) {
                    Text("원본 크기").font(.caption).foregroundColor(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: origBytes, countStyle: .file)).font(.system(size: 16, weight: .bold, design: .rounded))
                }
                Image(systemName: "arrow.right.circle.fill").font(.title2).foregroundColor(.orange)
                VStack(spacing: 4) {
                    Text("예상 저장 크기").font(.caption).foregroundColor(.orange)
                    Text("~" + ByteCountFormatter.string(fromByteCount: estBytes, countStyle: .file)).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundColor(.orange)
                }
                if origBytes > 0 {
                    let savedRatio = max(0, Int(((1.0 - Double(estBytes) / Double(origBytes)) * 100.0).rounded()))
                    Text("-\(savedRatio)% 절감").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5).background(Color.green, in: Capsule())
                }
            }.padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            VStack(spacing: 6) {
                HStack {
                    Text("압축 품질 설정: \(Int(quality))%").font(.caption.bold())
                    Spacer()
                    Text("EXIF 촬영정보 및 메타데이터는 삭제되지 않고 그대로 보존됩니다").font(.caption2).foregroundColor(.orange)
                }
                Slider(value: $quality, in: 1...100).tint(.orange).onChange(of: quality) { recalculateEstimate() }
            }.padding(.horizontal, 8)
            HStack {
                Button("취소") { NSApp.keyWindow?.close() }
                Spacer()
                Button("압축 실행 및 저장") { runCompression() }.buttonStyle(.borderedProminent).tint(.orange)
            }.padding(.horizontal, 8)
        }.padding(22).onAppear { recalculateEstimate() }
    }
    func recalculateEstimate() {
        let q = quality; let targetFiles = files
        DispatchQueue.global(qos: .userInteractive).async {
            let res = FileSizeEstimator.estimateCompressedBytes(files: targetFiles, quality: q)
            DispatchQueue.main.async { self.origBytes = res.original; self.estBytes = res.estimated }
        }
    }
    func runCompression() {
        let targetFiles = files
        let q = quality
        NSApp.keyWindow?.close()
        
        let jobID = JobProgressManager.shared.startJob(title: "파일 압축 (\(targetFiles.count)개)")
        DispatchQueue.global(qos: .userInitiated).async {
            for (idx, f) in targetFiles.enumerated() {
                autoreleasepool {
                    let ext = f.pathExtension.lowercased()
                    if ["jpg", "jpeg", "png", "heic", "tiff", "bmp", "webp"].contains(ext), let cg = FileProcessor.loadRawCGImage(from: f) {
                        let out = FileProcessor.uniqueOutputURL(for: f, newExt: "jpg", suffix: "_compressed")
                        FileProcessor.saveCGImage(cg, to: out, formatExt: "jpg", quality: q / 100.0, sourceURLForMetadata: f)
                    } else if FileProcessor.ffmpegPath != nil {
                        let out = FileProcessor.uniqueOutputURL(for: f, newExt: ext, suffix: "_compressed")
                        let crf = q >= 99.5 ? 0 : Int(40.0 - (q / 100.0) * 22.0)
                        let dur = FileProcessor.mediaDurationSeconds(for: f)
                        FileProcessor.runFFmpegWithProgress(args: ["-y", "-i", f.path, "-map_metadata", "0", "-movflags", "use_metadata_tags", "-vcodec", "libx264", "-crf", "\(crf)", out.path], totalDuration: dur, jobTitle: "압축: \(f.lastPathComponent)") { _ in
                            FileProcessor.preserveFileDates(from: f, to: out)
                        }
                    } else {
                        let out = FileProcessor.uniqueOutputURL(for: f, newExt: "mp4", suffix: "_compressed")
                        FileProcessor.avAssetConvertWithProgress(file: f, to: "mp4", outURL: out, jobTitle: "압축: \(f.lastPathComponent)")
                    }
                }
                JobProgressManager.shared.updateJob(id: jobID, progress: Double(idx + 1) / Double(targetFiles.count))
            }
            JobProgressManager.shared.finishJob(id: jobID)
            FileProcessor.showToast("총 \(targetFiles.count)개 파일 압축 완료 (메타데이터 유지됨)!")
        }
    }
}

struct MetadataToolView: View {
    let fileURL: URL
    @State private var metaDict: [String: String] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(fileURL.lastPathComponent).font(.headline)
            List {
                ForEach(metaDict.keys.sorted(), id: \.self) { k in
                    HStack {
                        Text(k).font(.caption.bold()).frame(width: 140, alignment: .leading)
                        Text(metaDict[k] ?? "").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            HStack {
                Button("촬영일자로 이 파일 이름 바꾸기") {
                    FileProcessor.batchRenameFilesWithCaptureDate(files: [fileURL])
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent).tint(.orange)
                Spacer()
                Button("메타데이터 완전 삭제본 저장") {
                    FileProcessor.stripMetadata(file: fileURL); NSApp.keyWindow?.close()
                }.buttonStyle(.borderedProminent).tint(.red)
            }
        }.padding().onAppear { loadMeta() }
    }
    func loadMeta() {
        let info = FileProcessor.extractCaptureDateAndCamera(for: fileURL)
        metaDict["📌 감지된 촬영일시"] = CaptureDateInspector.displayDate(info.date)
        metaDict["📎 판단 상태"] = info.state == "ready" ? "촬영일 사용 가능" : (info.state == "review" ? "시간대·촬영일 확인 필요" : "촬영일 미확인")
        metaDict["🔎 근거 / 신뢰도"] = info.source + " / " + info.confidence
        metaDict["📝 원본 메타데이터"] = info.raw
        metaDict["⚠️ 참고"] = info.note
        if !info.camera.isEmpty { metaDict["📷 감지된 카메라"] = info.camera }
        
        if let src = CGImageSourceCreateWithURL(fileURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] {
            for (k, v) in props { metaDict[k] = "\(v)" }
        }
    }
}



// MARK: - 촬영일시 이름변경: Camera DateShift식 출처·신뢰도 점검 및 파일별 승인
struct RenameReviewView: View {
    let files: [URL]
    @State private var decisions: [RenameCandidate] = []
    @State private var selected: Set<String> = []
    @State private var quickTimeModes: [String:String] = [:]
    @State private var scanned = 0
    @State private var loading = true
    @State private var launched = false
    private var readyCount: Int { decisions.filter { $0.state == "ready" }.count }
    private var reviewCount: Int { decisions.filter { $0.state == "review" }.count }
    private var missingCount: Int { decisions.filter { $0.state == "missing" || $0.state == "error" }.count }

    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                VStack(alignment:.leading,spacing:4) {
                    Text("촬영일시 확인 후 이름 변경").font(.title2.bold())
                    Text("EXIF · Sony XML · 영상 내부 기록 우선 / 파일 생성·수정일 사용 안 함").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if loading { ProgressView().controlSize(.small) }
            }
            Text(loading ? "촬영일시 분석 중: \(scanned) / \(files.count)개" : "확인 가능 \(readyCount)개 · 검토 필요 \(reviewCount)개 · 촬영일 없음 \(missingCount)개")
                .font(.subheadline.bold()).foregroundColor(.orange)
            List {
                ForEach(decisions) { item in
                    reviewRow(item)
                }
            }
            .listStyle(.inset)
            HStack {
                Image(systemName:"info.circle")
                Text("시간대 미확정 항목은 기본 해제입니다. 파일별 원본 기록을 확인한 후 체크하면 이름 변경에 포함됩니다.")
                    .font(.caption).foregroundColor(.secondary)
            }
            HStack {
                Button("닫기") { NSApp.keyWindow?.close() }
                Spacer()
                Text("선택 \(selected.count)개").font(.caption).monospacedDigit()
                Button("확인된 항목만 이름 변경") {
                    let prepared = decisions.map { item in
                        CaptureDateInspector.adjustQuickTime(item,mode:quickTimeModes[item.id] ?? "utc")
                    }
                    let approved = selected
                    launched = true
                    FileProcessor.executeVerifiedRename(prepared, approved:approved)
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent).tint(.orange)
                .disabled(loading || selected.isEmpty || launched)
            }
        }
        .padding(18)
        .onAppear { startScan() }
    }
    @ViewBuilder private func reviewRow(_ item: RenameCandidate) -> some View {
        let displayed = CaptureDateInspector.adjustQuickTime(item,mode:quickTimeModes[item.id] ?? "utc")
        HStack(alignment:.top,spacing:10) {
            if item.date != nil && item.state != "missing" {
                Toggle("",isOn:Binding(get:{selected.contains(item.id)},set:{yes in
                    if yes {selected.insert(item.id)} else {selected.remove(item.id)}
                }))
                .labelsHidden().disabled(loading || launched)
            } else {
                Image(systemName:"minus.circle").foregroundColor(.secondary).frame(width:22)
            }
            VStack(alignment:.leading,spacing:4) {
                Text(item.url.lastPathComponent).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(CaptureDateInspector.displayDate(displayed.date) + " · " + displayed.source + " · " + displayed.confidence)
                    .font(.caption).textSelection(.enabled)
                if item.state == "review" && (item.source.contains("(UTC 가정)") || item.source.contains("(현지 숫자 가정)")) {
                    Picker("원시 시각 해석",selection:Binding(get:{quickTimeModes[item.id] ?? "utc"},set:{quickTimeModes[item.id] = $0})) {
                        Text("UTC 기준 → 이 Mac 시간대").tag("utc")
                        Text("카메라 현지시각 그대로").tag("local")
                    }
                    .pickerStyle(.segmented).frame(maxWidth:410)
                }
                if !item.note.isEmpty {
                    Text(item.note).font(.caption2).foregroundColor(item.state == "review" ? .orange : .secondary)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength:8)
            Text(item.state == "ready" ? "사용 가능" : (item.state == "review" ? "확인 필요" : "촬영일 없음"))
                .font(.caption2.bold()).foregroundColor(item.state == "ready" ? .green : .orange)
        }
        .padding(.vertical,3)
    }
    private func startScan() {
        let input = files
        DispatchQueue.global(qos:.userInitiated).async {
            var results: [RenameCandidate] = []
            var defaults: Set<String> = []
            for (index,url) in input.enumerated() {
                let item = autoreleasepool { CaptureDateInspector.scan(url) }
                results.append(item)
                if item.state == "ready" && item.date != nil { defaults.insert(item.id) }
                if index % 20 == 0 || index == input.count - 1 {
                    DispatchQueue.main.async { scanned = index + 1 }
                }
            }
            DispatchQueue.main.async {
                decisions = results
                selected = defaults
                loading = false
            }
        }
    }
}

// MARK: - 11-A. ACTIONS: 세로로 긴 이미지 합치기 (4.8 기능 유지, 새 파일만 생성)
// 이미지 순서/가로폭/간격/저장 형식은 전용 창에서 조정하고 원본은 읽기 전용으로 취급합니다.
struct ImageJoinView: View {
    @State private var imageFiles: [URL]
    @State private var widthPolicy: String = "first"
    @State private var outputFormat: String = "auto"
    @State private var spacingPixels: Double = 0
    @State private var processing = false

    init(files: [URL]) {
        var seen = Set<String>()
        let filtered = files.filter { ImageJoinProcessor.isSupportedImage($0) && seen.insert($0.path).inserted }
        _imageFiles = State(initialValue: filtered)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection
            orderedImageList
            settingsSection
            actionSection
        }
        .padding(22)
    }

    private var headerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.stack")
                .font(.system(size: 25)).foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text("이미지 세로 합치기").font(.title2.bold())
                Text("위에서 아래로 연결 · 원본 유지 · 첫 이미지와 같은 폴더에 저장")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text("\(imageFiles.count)장").font(.subheadline.bold()).monospacedDigit()
        }
    }

    private var orderedImageList: some View {
        VStack(spacing: 8) {
            HStack {
                Text("합쳐질 순서 (맨 위가 첫 번째)").font(.subheadline.bold())
                Spacer()
                Button("파일명순 정렬") {
                    imageFiles.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                }.disabled(processing)
            }
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(imageFiles.indices, id: \.self) { idx in
                        imageRow(at: idx)
                    }
                }.padding(7)
            }
            .frame(maxHeight: 305)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 18) {
                Picker("가로폭", selection: $widthPolicy) {
                    Text("첫 이미지 너비로 맞춤").tag("first")
                    Text("원본 너비 유지(중앙 정렬)").tag("original")
                }
                .frame(maxWidth: 380)
                Picker("파일 형식", selection: $outputFormat) {
                    Text("자동 (초장축은 TIFF)").tag("auto")
                    Text("PNG (무손실)").tag("png")
                    Text("JPG (품질 95%)").tag("jpg")
                    Text("TIFF/BigTIFF (긴 이미지)").tag("tiff")
                }
                .frame(maxWidth: 270)
            }
            HStack(spacing: 12) {
                Text("사진 간격").font(.subheadline)
                Slider(value: $spacingPixels, in: 0...100, step: 1).tint(.orange)
                Text("\(Int(spacingPixels))px").monospacedDigit().frame(width: 54, alignment: .trailing)
            }
            Text("자동 모드는 일반 크기에 PNG, 32,000px 또는 안전 픽셀 예산을 초과하는 길이에는 TIFF/BigTIFF를 사용합니다. TIFF는 작은 구간씩 기록하므로 매우 긴 이미지를 하나로 저장할 수 있지만 파일이 커지고 일부 앱에서 BigTIFF 미리보기가 제한될 수 있습니다. GIF는 첫 프레임만 사용합니다.")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    private var actionSection: some View {
        HStack(spacing: 12) {
            Button("취소") { NSApp.keyWindow?.close() }
            Spacer()
            Button("위에서 아래로 합치기") {
                guard imageFiles.count >= 2, !processing else { return }
                processing = true
                ImageJoinProcessor.start(files: imageFiles,
                                         widthPolicy: widthPolicy,
                                         format: outputFormat,
                                         spacing: Int(spacingPixels))
                NSApp.keyWindow?.close()
            }
            .buttonStyle(.borderedProminent).tint(.orange)
            .disabled(imageFiles.count < 2 || processing)
        }
    }

    @ViewBuilder
    private func imageRow(at idx: Int) -> some View {
        let file = imageFiles[idx]
        HStack(spacing: 10) {
            Text("\(idx + 1)").font(.caption.monospacedDigit()).foregroundColor(.secondary)
                .frame(width: 28, alignment: .trailing)
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                .resizable().interpolation(.high).frame(width: 30, height: 30)
            Text(file.lastPathComponent).font(.system(size: 13)).lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Button(action: { if idx > 0 { imageFiles.swapAt(idx, idx - 1) } }) {
                Image(systemName: "arrow.up")
            }.disabled(idx == 0 || processing).help("한 칸 위로")
            Button(action: { if idx + 1 < imageFiles.count { imageFiles.swapAt(idx, idx + 1) } }) {
                Image(systemName: "arrow.down")
            }.disabled(idx + 1 >= imageFiles.count || processing).help("한 칸 아래로")
            Button(action: { imageFiles.remove(at: idx) }) {
                Image(systemName: "xmark").foregroundColor(.secondary)
            }.disabled(processing).help("목록에서 제외 (원본 삭제 안 함)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Color.primary.opacity(idx.isMultiple(of: 2) ? 0.045 : 0.02), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct ImageJoinEntry {
    let url: URL
    let pixelWidth: Int
    let pixelHeight: Int
    let scaledHeight: Int
}

class ImageJoinProcessor {
    private static let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "webp", "tif", "tiff", "bmp", "gif", "avif"]
    private static let maxCanvasHeight = 32000
    // 1억 1천만 픽셀을 넘는 단일 비트맵 생성을 방지하여 메모리 급증/앱 종료 위험 완화.
    private static let maxCanvasPixels = 110_000_000

    static func isSupportedImage(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased()) && !url.hasDirectoryPath
    }

    private static func readPixelSize(of url: URL) -> (Int, Int)? {
        let options: [String: Any] = [kCGImageSourceShouldCache as String: false]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary),
              CGImageSourceGetCount(src) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any],
              let width = props[kCGImagePropertyPixelWidth as String] as? Int,
              let height = props[kCGImagePropertyPixelHeight as String] as? Int,
              width > 0, height > 0 else { return nil }
        let orientation = (props[kCGImagePropertyOrientation as String] as? Int) ?? 1
        return [5, 6, 7, 8].contains(orientation) ? (height, width) : (width, height)
    }

    // EXIF 회전까지 반영된 CGImage. 전체 크기로 읽고, 필요한 한 장씩만 디코드합니다.
    private static func decodeOrientedImage(from url: URL, maxPixel: Int) -> CGImage? {
        let noCache: [String: Any] = [kCGImageSourceShouldCache as String: false]
        guard let src = CGImageSourceCreateWithURL(url as CFURL, noCache as CFDictionary) else { return nil }
        let opts: [String: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways as String: true,
            kCGImageSourceCreateThumbnailWithTransform as String: true,
            kCGImageSourceThumbnailMaxPixelSize as String: maxPixel,
            kCGImageSourceShouldCacheImmediately as String: false
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(src, 0, noCache as CFDictionary)
    }

    static func start(files: [URL], widthPolicy: String, format: String, spacing: Int) {
        let jobID = JobProgressManager.shared.startJob(title: "이미지 세로 합치기 (\(files.count)장)")
        DispatchQueue.global(qos: .userInitiated).async {
            let result = render(files: files, widthPolicy: widthPolicy, format: format, spacing: spacing, jobID: jobID)
            DispatchQueue.main.async {
                JobProgressManager.shared.finishJob(id: jobID)
                if !result.outputs.isEmpty {
                    NSWorkspace.shared.activateFileViewerSelecting(result.outputs)
                    if result.outputs.count == 1 {
                        FileProcessor.showToast("세로 이미지 합치기 완료: \(result.outputs[0].lastPathComponent)")
                    } else {
                        FileProcessor.showToast("긴 이미지를 \(result.outputs.count)개 파일로 나누어 저장했습니다.")
                    }
                }
                if let error = result.error {
                    let alert = NSAlert()
                    alert.messageText = "이미지 합치기 안내"
                    alert.informativeText = error
                    alert.alertStyle = result.outputs.isEmpty ? .warning : .informational
                    alert.runModal()
                }
            }
        }
    }

    private static func render(files: [URL], widthPolicy: String, format: String, spacing: Int, jobID: UUID) -> (outputs: [URL], error: String?) {
        let files = files.filter(isSupportedImage)
        guard files.count >= 2 else { return ([], "이미지 두 장 이상을 선택해 주세요.") }
        var sizes: [(URL, Int, Int)] = []
        for file in files {
            guard let (w, h) = readPixelSize(of: file) else {
                return ([], "이미지 크기를 읽을 수 없습니다: \(file.lastPathComponent)")
            }
            sizes.append((file, w, h))
        }
        let canvasWidth = widthPolicy == "first" ? sizes[0].1 : (sizes.map { $0.1 }.max() ?? sizes[0].1)
        guard canvasWidth > 0 && canvasWidth <= 16000 else { return ([], "합칠 이미지의 가로폭이 너무 큽니다. 16,000픽셀 이하에서 이용해 주세요.") }
        let gap = max(0, min(100, spacing))
        let safeMaxHeight = min(maxCanvasHeight, maxCanvasPixels / canvasWidth)
        var entries: [ImageJoinEntry] = []
        for (url, width, height) in sizes {
            let scale = widthPolicy == "first" ? Double(canvasWidth) / Double(width) : 1.0
            let scaledHeightDouble = Double(height) * scale
            guard scaledHeightDouble.isFinite && scaledHeightDouble >= 1,
                  scaledHeightDouble <= 1_000_000 else {
                return ([], "한 장의 이미지가 지원 범위를 초과합니다: \(url.lastPathComponent)")
            }
            let scaledHeight = max(1, Int(scaledHeightDouble.rounded()))
            entries.append(ImageJoinEntry(url: url, pixelWidth: width, pixelHeight: height, scaledHeight: scaledHeight))
        }
        let fullHeight = entries.reduce(Int64(0)) { $0 + Int64($1.scaledHeight) } + Int64(gap) * Int64(max(0, entries.count - 1))
        let effectiveFormat = format == "auto" ? (fullHeight > Int64(safeMaxHeight) ? "tiff" : "png") : format
        if effectiveFormat == "tiff" {
            return renderLongTIFF(entries:entries, width:canvasWidth, widthPolicy:widthPolicy, gap:gap, jobID:jobID)
        }
        // PNG/JPG는 기존 메모리 보호·자동 분할 방식 유지.
        for entry in entries where entry.scaledHeight > safeMaxHeight {
            return ([], "한 장이 PNG/JPG 안전 영역을 초과했습니다. 파일 형식을 ‘TIFF/BigTIFF’ 또는 ‘자동’으로 바꿔주세요: \(entry.url.lastPathComponent)")
        }

        // 이미지가 매우 길면 한 장씩의 경계에서 자동 분할 (렌더링 중 메모리 폭주 방지).
        var batches: [[ImageJoinEntry]] = []
        var current: [ImageJoinEntry] = []
        var currentHeight = 0
        for entry in entries {
            let candidateHeight = currentHeight + (current.isEmpty ? 0 : gap) + entry.scaledHeight
            if !current.isEmpty && candidateHeight > safeMaxHeight {
                batches.append(current)
                current = []
                currentHeight = 0
            }
            currentHeight += (current.isEmpty ? 0 : gap) + entry.scaledHeight
            current.append(entry)
        }
        if !current.isEmpty { batches.append(current) }

        var outputs: [URL] = []
        var finished = 0
        let rootFile = sizes[0].0
        for (batchIdx, batch) in batches.enumerated() {
            let height = batch.reduce(0) { $0 + $1.scaledHeight } + gap * max(0, batch.count - 1)
            let nameSuffix = batches.count == 1 ? "_vertical_merged" : String(format: "_vertical_merged_part%02d", batchIdx + 1)
            let outURL = FileProcessor.uniqueOutputURL(for: rootFile, newExt: format == "jpg" ? "jpg" : "png", suffix: nameSuffix)
            let ok: Bool = autoreleasepool {
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                guard let context = CGContext(data: nil, width: canvasWidth, height: height,
                                              bitsPerComponent: 8, bytesPerRow: 0,
                                              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return false }
                // PNG는 투명 영역을 보존하고, JPG만 흰 배경으로 채웁니다.
                if format == "jpg" {
                    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                    context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: height))
                } else {
                    context.clear(CGRect(x: 0, y: 0, width: canvasWidth, height: height))
                }
                var drawTop = height
                for entry in batch {
                    let drawWidth: Int = widthPolicy == "first" ? canvasWidth : entry.pixelWidth
                    let image: CGImage? = autoreleasepool {
                        decodeOrientedImage(from: entry.url, maxPixel: max(drawWidth, entry.scaledHeight))
                    }
                    guard let image = image else { return false }
                    let x = (canvasWidth - drawWidth) / 2
                    drawTop -= entry.scaledHeight
                    context.interpolationQuality = .high
                    context.draw(image, in: CGRect(x: x, y: drawTop, width: drawWidth, height: entry.scaledHeight))
                    drawTop -= gap
                    finished += 1
                    JobProgressManager.shared.updateJob(id: jobID, progress: Double(finished) / Double(entries.count))
                }
                guard let mergedCGImage = context.makeImage() else { return false }
                let utType: CFString = (format == "jpg" ? UTType.jpeg.identifier : UTType.png.identifier) as CFString
                guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, utType, 1, nil) else { return false }
                let props: [String: Any] = [kCGImageDestinationLossyCompressionQuality as String: 0.95]
                CGImageDestinationAddImage(dest, mergedCGImage, (format == "jpg" ? props as CFDictionary : nil))
                return CGImageDestinationFinalize(dest)
            }
            if !ok {
                try? FileManager.default.removeItem(at: outURL)
                return (outputs, "일부 이미지를 처리하지 못했습니다. \(batchIdx + 1)번째 묶음을 저장하지 못했습니다. 이전에 저장된 파일은 유지됩니다.")
            }
            outputs.append(outURL)
        }
        let note = batches.count > 1 ? "최대 이미지 크기 제한을 넘어서 \(batches.count)장으로 자동 분할했습니다. 파일은 첫 번째 이미지가 있는 폴더에 저장되었습니다." : nil
        return (outputs, note)
    }

    // TIFF 64비트 오프셋(BigTIFF), 압축 없는 RGBA scanline을 256행씩 기록합니다.
    // 전체 초장축 이미지를 CGContext 하나에 올리지 않아 고용량에서 메모리 사용량을 제한합니다.
    private static func renderLongTIFF(entries: [ImageJoinEntry], width: Int, widthPolicy: String, gap: Int, jobID: UUID) -> (outputs:[URL], error:String?) {
        guard let first = entries.first else { return ([],"선택한 이미지가 없습니다.") }
        let totalHeight64 = entries.reduce(Int64(0)) { $0 + Int64($1.scaledHeight) } + Int64(gap) * Int64(max(0,entries.count - 1))
        guard totalHeight64 > 0, totalHeight64 <= 1_000_000,
              width <= 16000, Int64(width) * totalHeight64 <= 6_000_000_000 else {
            return ([],"TIFF 안전 범위(높이 최대 1,000,000px)를 초과합니다. 가로폭을 낮추거나 이미지들을 나눠주세요.")
        }
        let totalHeight = Int(totalHeight64)
        let rowBytes = width * 4
        let rowsPerStrip = 256
        let strips = (totalHeight + rowsPerStrip - 1) / rowsPerStrip
        let entryCount = 11
        // 4GB 미만이면 호환성 좋은 클래식 TIFF(32비트), 그 이상일 때만 BigTIFF(64비트).
        let classicIFDEnd = 8 + 2 + entryCount * 12 + 4
        let classicBits = ((classicIFDEnd + 3) / 4) * 4
        let classicOffsetTable = classicBits + 8
        let classicByteCountTable = classicOffsetTable + (strips > 1 ? strips * 4 : 0)
        let classicPixelStart = classicByteCountTable + (strips > 1 ? strips * 4 : 0)
        let classicBytes = Int64(classicPixelStart) + totalHeight64 * Int64(rowBytes)
        let isBig = classicBytes >= 4_000_000_000
        let bigIFDLength = 8 + entryCount * 20 + 8
        let bigOffsetTable = ((16 + bigIFDLength + 7) / 8) * 8
        let bigByteCountTable = bigOffsetTable + (strips > 1 ? strips * 8 : 0)
        let bigPixelStart = bigByteCountTable + (strips > 1 ? strips * 8 : 0)
        let pixelStart = isBig ? bigPixelStart : classicPixelStart
        let fileBytes = Int64(pixelStart) + totalHeight64 * Int64(rowBytes)
        let folder = first.url.deletingLastPathComponent()
        if let fs = try? FileManager.default.attributesOfFileSystem(forPath:folder.path),
           let free = fs[.systemFreeSize] as? NSNumber,
           free.int64Value < fileBytes + 64 * 1024 * 1024 {
            return ([],"예상 TIFF 용량: \(ByteCountFormatter.string(fromByteCount:fileBytes,countStyle:.file)). 저장 공간이 부족합니다.")
        }
        let output = FileProcessor.uniqueOutputURL(for:first.url,newExt:"tif",suffix:"_vertical_merged")
        guard FileManager.default.createFile(atPath: output.path,contents:nil) else { return ([],"출력 TIFF 파일을 만들 수 없습니다.") }
        do {
            let handle = try FileHandle(forWritingTo:output)
            defer { try? handle.close() }
            var header = Data()
            func u16(_ v: UInt16) { var x=v.littleEndian; withUnsafeBytes(of:&x){header.append(contentsOf:$0)} }
            func u32(_ v: UInt32) { var x=v.littleEndian; withUnsafeBytes(of:&x){header.append(contentsOf:$0)} }
            func u64(_ v: UInt64) { var x=v.littleEndian; withUnsafeBytes(of:&x){header.append(contentsOf:$0)} }
            if isBig {
                func tag(_ id:UInt16,_ type:UInt16,_ count:UInt64,_ value:UInt64) {
                    u16(id);u16(type);u64(count);u64(value)
                }
                u16(0x4949);u16(43);u16(8);u16(0);u64(16)
                u64(UInt64(entryCount))
                tag(256,4,1,UInt64(width))
                tag(257,4,1,UInt64(totalHeight))
                tag(258,3,4,0x0008_0008_0008_0008)
                tag(259,3,1,1)
                tag(262,3,1,2)
                tag(273,16,UInt64(strips),strips == 1 ? UInt64(pixelStart) : UInt64(bigOffsetTable))
                tag(277,3,1,4)
                tag(278,4,1,UInt64(rowsPerStrip))
                tag(279,16,UInt64(strips),strips == 1 ? UInt64(totalHeight * rowBytes) : UInt64(bigByteCountTable))
                tag(284,3,1,1)
                tag(338,3,1,1)
                u64(0)
                while header.count < bigOffsetTable { header.append(0) }
                if strips > 1 {
                    var at = UInt64(pixelStart)
                    for n in 0..<strips {
                        u64(at)
                        at += UInt64(min(rowsPerStrip,totalHeight - n * rowsPerStrip) * rowBytes)
                    }
                    for n in 0..<strips { u64(UInt64(min(rowsPerStrip,totalHeight - n * rowsPerStrip) * rowBytes)) }
                } else { while header.count < pixelStart { header.append(0) } }
            } else {
                func tag(_ id:UInt16,_ type:UInt16,_ count:UInt32,_ value:UInt32) {
                    u16(id);u16(type);u32(count);u32(value)
                }
                u16(0x4949);u16(42);u32(8)
                u16(UInt16(entryCount))
                tag(256,4,1,UInt32(width))
                tag(257,4,1,UInt32(totalHeight))
                tag(258,3,4,UInt32(classicBits))
                tag(259,3,1,1)
                tag(262,3,1,2)
                tag(273,4,UInt32(strips),UInt32(strips == 1 ? pixelStart : classicOffsetTable))
                tag(277,3,1,4)
                tag(278,4,1,UInt32(rowsPerStrip))
                tag(279,4,UInt32(strips),UInt32(strips == 1 ? totalHeight * rowBytes : classicByteCountTable))
                tag(284,3,1,1)
                tag(338,3,1,1)
                u32(0)
                while header.count < classicBits { header.append(0) }
                u16(8);u16(8);u16(8);u16(8)
                if strips > 1 {
                    var at = UInt32(pixelStart)
                    for n in 0..<strips {
                        u32(at)
                        at += UInt32(min(rowsPerStrip,totalHeight - n * rowsPerStrip) * rowBytes)
                    }
                    for n in 0..<strips { u32(UInt32(min(rowsPerStrip,totalHeight - n * rowsPerStrip) * rowBytes)) }
                }
            }
            guard header.count == pixelStart else { throw NSError(domain:"TIFF",code:1,userInfo:[NSLocalizedDescriptionKey:"헤더 오프셋 계산 실패"]) }
            try handle.write(contentsOf:header)

            var placements: [(entry:ImageJoinEntry,top:Int)] = []
            var top = 0
            for e in entries { placements.append((e,top)); top += e.scaledHeight + gap }
            var activeIndex = -1
            var activeImage:CGImage?
            var nextEntryIndex = 0
            for strip in 0..<strips {
                let stripTop = strip * rowsPerStrip
                let stripRows = min(rowsPerStrip,totalHeight - stripTop)
                var success = false
                let stripe: Data? = autoreleasepool {
                    guard let context = CGContext(data:nil,width:width,height:stripRows,bitsPerComponent:8,
                                                  bytesPerRow:rowBytes,space:CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo:CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
                    context.clear(CGRect(x:0,y:0,width:width,height:stripRows))
                    while nextEntryIndex < placements.count &&
                          placements[nextEntryIndex].top + placements[nextEntryIndex].entry.scaledHeight <= stripTop {
                        nextEntryIndex += 1
                    }
                    var idx = nextEntryIndex
                    while idx < placements.count {
                        let entry = placements[idx].entry
                        let imageTop = placements[idx].top
                        if imageTop >= stripTop + stripRows { break }
                        if imageTop + entry.scaledHeight > stripTop {
                            if activeIndex != idx {
                                activeImage = decodeOrientedImage(from:entry.url,maxPixel:max(width,entry.scaledHeight))
                                activeIndex = idx
                            }
                            guard let image = activeImage else { return nil }
                            let drawWidth = widthPolicy == "first" ? width : entry.pixelWidth
                            let x = (width - drawWidth) / 2
                            let localY = stripTop + stripRows - (imageTop + entry.scaledHeight)
                            context.interpolationQuality = .high
                            context.draw(image,in:CGRect(x:x,y:localY,width:drawWidth,height:entry.scaledHeight))
                        }
                        idx += 1
                    }
                    guard let raw = context.data else { return nil }
                    success = true
                    return Data(bytes:raw,count:rowBytes * stripRows)
                }
                guard success, let bytes = stripe else { throw NSError(domain:"TIFF",code:2,userInfo:[NSLocalizedDescriptionKey:"이미지 스트립 생성 실패: \(strip + 1)"]) }
                try handle.write(contentsOf:bytes)
                if strip % 4 == 0 || strip == strips - 1 {
                    JobProgressManager.shared.updateJob(id:jobID,progress:Double(strip + 1)/Double(strips))
                }
            }
            let finalOffset = try handle.offset()
            guard finalOffset == UInt64(fileBytes) else { throw NSError(domain:"TIFF",code:3,userInfo:[NSLocalizedDescriptionKey:"출력 TIFF 길이 불일치"]) }
            return ([output],"\(isBig ? "BigTIFF" : "TIFF") 한 장으로 \(totalHeight)px를 저장했습니다. 무압축 저장이며, 일부 이미지 앱은 초장축/BigTIFF 미리보기를 지원하지 않을 수 있습니다.")
        } catch {
            try? FileManager.default.removeItem(at:output)
            return ([],"초장축 TIFF 생성 실패: \(error.localizedDescription)")
        }
    }

}

// MARK: - 12. 초경량·대용량(2,000개+) 무누락 앱 델리게이트
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var wheelPanel: NSPanel?
    var wheelCenterPoint: NSPoint = .zero
    
    let dragPboard = NSPasteboard(name: .drag)
    var dragCountAtMouseDown: Int = -1
    var isCurrentMouseStrokeValidFileDrag: Bool = false
    var eventTap: CFMachPort?
    var isSyntheticMouseUp: Bool = false
    var previousRawFlags: NSEvent.ModifierFlags = []
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.automaticTerminationSupportEnabled = false
        NSApp.setActivationPolicy(.accessory)
        applyPureTransparentCustomIconToAppBundle()
        
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusBarMenu()
        JobProgressManager.shared.onUpdate = { [weak self] in self?.updateStatusBarMenu() }
        
        setupUltraLightEventTap()
    }
    
    func applyPureTransparentCustomIconToAppBundle() {
        guard let rawIcon = FileProcessor.customAppIconImage() else { return }
        NSApp.applicationIconImage = rawIcon
        // 서명된 .app 폴더를 실행 도중 수정하지 않습니다.
        // Finder 아이콘은 번들에 포함된 AppIcon.icns가 담당합니다.
    }
    
    func updateStatusBarMenu() {
        let jobs = JobProgressManager.shared.jobs
        if let btn = statusItem.button {
            if let overall = JobProgressManager.shared.overallProgress {
                let pct = Int((overall * 100.0).rounded())
                btn.image = NSImage(systemSymbolName: "gearshape.arrow.triangle.2.circlepath", accessibilityDescription: "Processing")
                btn.title = " \(pct)%"
            } else {
                if let customIcon = FileProcessor.customAppIconImage() {
                    let menuIcon = (customIcon.copy() as? NSImage) ?? customIcon
                    menuIcon.size = NSSize(width: 18, height: 18)
                    menuIcon.isTemplate = false
                    btn.image = menuIcon
                } else {
                    btn.image = NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "MyTangerine")
                }
                btn.title = ""
            }
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "🍊 MyTangerine 4.8 Pro (대용량 초고속 최적화)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        if jobs.isEmpty {
            menu.addItem(NSMenuItem(title: "대기 중 (현재 진행 중인 변환 작업 없음)", action: nil, keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "⚡ 진행 중인 작업 (\(jobs.count)건):", action: nil, keyEquivalent: ""))
            for job in jobs {
                let pct = Int((job.progress * 100.0).rounded())
                let barCount = max(1, min(10, pct / 10))
                let bar = String(repeating: "█", count: barCount) + String(repeating: "░", count: 10 - barCount)
                menu.addItem(NSMenuItem(title: "[\(bar)] \(pct)% — \(job.title)", action: nil, keyEquivalent: ""))
            }
        }
        menu.addItem(NSMenuItem.separator())
        let helpItem = NSMenuItem(title: "📖 설명 및 설정 (단축키 / 홀드·토글 / 이름 양식)...", action: #selector(openHelpAndSettings), keyEquivalent: ",")
        helpItem.target = self
        menu.addItem(helpItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "종료 (Quit)", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }
    @objc func openHelpAndSettings() { ToolWindowManager.shared.showHelpAndSettingsWindow() }
    @objc func quitApp() { NSApp.terminate(nil) }
    
    func ensureWheelPanel() -> NSPanel {
        if let existing = wheelPanel { return existing }
        let size = NSRect(x: 0, y: 0, width: 440, height: 440)
        let panel = NSPanel(contentRect: size, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        self.wheelPanel = panel
        return panel
    }
    
    func setupUltraLightEventTap() {
        let mask = (1 << CGEventType.leftMouseDown.rawValue) |
                   (1 << CGEventType.leftMouseUp.rawValue) |
                   (1 << CGEventType.leftMouseDragged.rawValue) |
                   (1 << CGEventType.flagsChanged.rawValue)
        
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let mySelf = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
            
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = mySelf.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            
            if type == .leftMouseDown {
                mySelf.dragCountAtMouseDown = mySelf.dragPboard.changeCount
                mySelf.isCurrentMouseStrokeValidFileDrag = false
                mySelf.previousRawFlags = []
                return Unmanaged.passUnretained(event)
            }
            
            if type == .leftMouseUp {
                if mySelf.isSyntheticMouseUp {
                    mySelf.isSyntheticMouseUp = false
                    event.flags = []
                    return Unmanaged.passUnretained(event)
                }
                mySelf.previousRawFlags = []
                if AppState.shared.isDragging {
                    let dropLocation = event.location
                    let rawFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
                    let qReq = ShortcutSettings.shared.qualityFlags
                    let wantsQualityPopup = (!qReq.isEmpty && rawFlags.isSuperset(of: qReq)) || AppState.shared.isQualityOptionActive
                    mySelf.isCurrentMouseStrokeValidFileDrag = false
                    DispatchQueue.main.async {
                        mySelf.handleMouseUp(openQualityPopup: wantsQualityPopup)
                    }
                    mySelf.cancelFinderDragAndRestoreFocus(at: dropLocation)
                    return nil
                } else {
                    mySelf.isCurrentMouseStrokeValidFileDrag = false
                    return Unmanaged.passUnretained(event)
                }
            }
            
            let mousePressed = (NSEvent.pressedMouseButtons & 1) != 0
            guard mousePressed else {
                return Unmanaged.passUnretained(event)
            }
            
            if !mySelf.isCurrentMouseStrokeValidFileDrag {
                let currentCount = mySelf.dragPboard.changeCount
                guard currentCount != mySelf.dragCountAtMouseDown else {
                    return Unmanaged.passUnretained(event)
                }
                let files = mySelf.readValidDraggedFiles(from: mySelf.dragPboard)
                guard !files.isEmpty else {
                    mySelf.dragCountAtMouseDown = currentCount
                    return Unmanaged.passUnretained(event)
                }
                mySelf.isCurrentMouseStrokeValidFileDrag = true
                let bytes = mySelf.calculateTotalBytesFast(files: files)
                let sizeStr = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                DispatchQueue.main.async {
                    AppState.shared.draggedFiles = files
                    AppState.shared.totalBytes = bytes
                    AppState.shared.totalSizeText = sizeStr
                }
            }
            
            let rawFlags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)).intersection([.shift, .option, .control, .command])
            let qReq = ShortcutSettings.shared.qualityFlags
            let qualityPressed = !qReq.isEmpty && rawFlags.isSuperset(of: qReq)
            
            if AppState.shared.isQualityOptionActive != qualityPressed {
                DispatchQueue.main.async {
                    AppState.shared.isQualityOptionActive = qualityPressed
                }
            }
            
            let matched = ShortcutSettings.shared.matchWheelMode(for: rawFlags)
            let isToggle = ShortcutSettings.shared.isToggleMode
            
            if type == .flagsChanged {
                let newlyPressed = !rawFlags.subtracting(mySelf.previousRawFlags).isEmpty
                mySelf.previousRawFlags = rawFlags
                
                if isToggle {
                    if let m = matched {
                        if newlyPressed {
                            let mouseLoc = NSEvent.mouseLocation
                            DispatchQueue.main.async {
                                if AppState.shared.isDragging && AppState.shared.wheelMode == m && !qualityPressed {
                                    mySelf.hideWheel()
                                } else {
                                    mySelf.showOrSwitchWheel(mode: m, mouseLocation: mouseLoc)
                                }
                            }
                        } else if AppState.shared.isDragging && AppState.shared.wheelMode != m {
                            let mouseLoc = NSEvent.mouseLocation
                            DispatchQueue.main.async {
                                mySelf.showOrSwitchWheel(mode: m, mouseLocation: mouseLoc)
                            }
                        }
                        event.flags.remove([.maskAlternate, .maskShift, .maskControl, .maskCommand])
                        return nil
                    }
                    if AppState.shared.isDragging {
                        event.flags.remove([.maskAlternate, .maskShift, .maskControl, .maskCommand])
                        return nil
                    }
                } else {
                    if let m = matched {
                        let mouseLoc = NSEvent.mouseLocation
                        DispatchQueue.main.async {
                            mySelf.showOrSwitchWheel(mode: m, mouseLocation: mouseLoc)
                        }
                        event.flags.remove([.maskAlternate, .maskShift, .maskControl, .maskCommand])
                        return nil
                    } else if AppState.shared.isDragging {
                        DispatchQueue.main.async { mySelf.hideWheel() }
                        event.flags.remove([.maskAlternate, .maskShift, .maskControl, .maskCommand])
                        return nil
                    }
                }
            } else if type == .leftMouseDragged {
                if let m = matched, !isToggle, !AppState.shared.isDragging {
                    let mouseLoc = NSEvent.mouseLocation
                    DispatchQueue.main.async {
                        mySelf.showOrSwitchWheel(mode: m, mouseLocation: mouseLoc)
                    }
                } else if AppState.shared.isDragging {
                    mySelf.updateHoveredSliceLightweight(mouseLocation: NSEvent.mouseLocation)
                }
                if AppState.shared.isDragging || matched != nil {
                    event.flags.remove([.maskAlternate, .maskShift, .maskControl, .maskCommand])
                }
            }
            
            return Unmanaged.passUnretained(event)
        }
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        if let tap = CGEvent.tapCreate(
            tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask), callback: callback, userInfo: selfPtr
        ) {
            self.eventTap = tap
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        } else if let sessionTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask), callback: callback, userInfo: selfPtr
        ) {
            self.eventTap = sessionTap
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, sessionTap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: sessionTap, enable: true)
        }
    }
    
    func cancelFinderDragAndRestoreFocus(at pt: CGPoint) {
        let src = CGEventSource(stateID: .hidSystemState)
        if let escDown = CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: true),
           let escUp = CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: false) {
            escDown.flags = []; escUp.flags = []
            escDown.post(tap: .cgSessionEventTap)
            escUp.post(tap: .cgSessionEventTap)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self = self else { return }
            self.isSyntheticMouseUp = true
            let cleanSrc = CGEventSource(stateID: .hidSystemState)
            if let cleanUp = CGEvent(mouseEventSource: cleanSrc, mouseType: .leftMouseUp, mouseCursorPosition: pt, mouseButton: .left) {
                cleanUp.flags = []
                cleanUp.post(tap: .cghidEventTap)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if NSApp.WindowsHaveNoVisibleTools {
                    if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
                        finder.activate(options: [])
                    }
                }
            }
        }
    }
    
    func showOrSwitchWheel(mode: WheelMode, mouseLocation: NSPoint) {
        // 휠을 띄우는 시점에 파인더가 마저 채워 넣은 전체 파일 목록(예: 2,000개)을 다시 한번 스캔하여 업데이트!
        let latestFiles = readValidDraggedFiles(from: dragPboard)
        var fileListChanged = false
        if latestFiles.count > AppState.shared.draggedFiles.count {
            AppState.shared.draggedFiles = latestFiles
            let bytes = calculateTotalBytesFast(files: latestFiles)
            AppState.shared.totalBytes = bytes
            AppState.shared.totalSizeText = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            fileListChanged = true
        }
        
        guard !AppState.shared.draggedFiles.isEmpty else { return }
        if !AppState.shared.isDragging {
            AppState.shared.wheelMode = mode
            AppState.shared.updateItems()
            showWheel(at: mouseLocation)
        } else if AppState.shared.wheelMode != mode || fileListChanged {
            AppState.shared.wheelMode = mode
            // 뒤늦게 발견된 추가 드래그 파일도 ACTIONS 휠의 이미지 합치기 항목에 반영합니다.
            AppState.shared.updateItems()
        }
        updateHoveredSliceLightweight(mouseLocation: mouseLocation)
    }
    
    // MARK: 핵심 해결 — 파인더에서 2,000개 이상의 파일을 드래그할 때 33개에서 잘리지 않도록 3가지 경로(readObjects + pasteboardItems + NSFilenamesPboardType)를 모두 취합하여 100% 전수 추출!
    func readValidDraggedFiles(from pboard: NSPasteboard) -> [URL] {
        var collected: [URL] = []
        var seenPaths = Set<String>()
        
        // 1) readObjects로 전체 NSURL 객체 추출
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            for u in urls {
                let p = u.path
                if !p.isEmpty && seenPaths.insert(p).inserted {
                    collected.append(u)
                }
            }
        }
        
        // 2) pasteboardItems 개별 순회 (대량 드래그 시 누락된 항목 보완)
        if let items = pboard.pasteboardItems, items.count > collected.count {
            for item in items {
                if let str = item.string(forType: .fileURL),
                   let u = URL(string: str)?.standardizedFileURL {
                    let p = u.path
                    if !p.isEmpty && seenPaths.insert(p).inserted {
                        collected.append(u)
                    }
                }
            }
        }
        
        // 3) 레거시 NSFilenamesPboardType 배열 확인 (Finder 대량 파일 목록 폴백)
        let legacyType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        if let pathList = pboard.propertyList(forType: legacyType) as? [String], pathList.count > collected.count {
            for p in pathList where !p.isEmpty {
                if seenPaths.insert(p).inserted {
                    collected.append(URL(fileURLWithPath: p))
                }
            }
        }
        
        // 파일이 100개 이하일 때만 개별 fileExists 검사를 수행하고, 수천 개일 때는 지체 없이 즉시 반환!
        if collected.count <= 100 {
            return collected.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        return collected
    }
    
    // 파일이 수천 개일 때는 앞쪽 100개 샘플로 즉시 전체 용량을 추정하여 드래그 시작 시 렉(멈춤) 원천 방지!
    func calculateTotalBytesFast(files: [URL]) -> Int64 {
        guard !files.isEmpty else { return 0 }
        let sampleLimit = 100
        var sum: Int64 = 0
        let sampleCount = min(files.count, sampleLimit)
        for i in 0..<sampleCount {
            if let res = try? files[i].resourceValues(forKeys: [.fileSizeKey]),
               let sz = res.fileSize {
                sum += Int64(sz)
            }
        }
        if files.count > sampleLimit && sampleCount > 0 {
            return Int64(Double(sum) * (Double(files.count) / Double(sampleCount)))
        }
        return sum
    }
    
    func showWheel(at point: NSPoint) {
        wheelCenterPoint = point
        AppState.shared.isDragging = true
        AppState.shared.hoveredIndex = nil
        let panel = ensureWheelPanel()
        if panel.contentView == nil {
            panel.contentView = NSHostingView(rootView: RadialWheelView())
        }
        panel.setFrameOrigin(NSPoint(x: point.x - 220, y: point.y - 220))
        panel.orderFrontRegardless()
    }
    
    func hideWheel() {
        AppState.shared.isDragging = false
        AppState.shared.isQualityOptionActive = false
        AppState.shared.hoveredIndex = nil
        wheelPanel?.orderOut(nil)
        wheelPanel?.contentView = nil
    }
    
    func updateHoveredSliceLightweight(mouseLocation: NSPoint) {
        let dx = mouseLocation.x - wheelCenterPoint.x
        let dy = mouseLocation.y - wheelCenterPoint.y
        let dist = hypot(dx, dy)
        let newIdx: Int?
        if dist <= 48 || dist >= 195 {
            newIdx = nil
        } else {
            var degrees = atan2(dx, dy) * 180.0 / .pi
            if degrees < 0 { degrees += 360.0 }
            let count = max(AppState.shared.items.count, 1)
            let step = 360.0 / Double(count)
            let shifted = (degrees + step / 2.0).truncatingRemainder(dividingBy: 360.0)
            newIdx = Int(shifted / step) % count
        }
        if AppState.shared.hoveredIndex != newIdx {
            DispatchQueue.main.async {
                if AppState.shared.hoveredIndex != newIdx {
                    AppState.shared.hoveredIndex = newIdx
                }
            }
        }
    }
    
    func handleMouseUp(openQualityPopup: Bool = false) {
        isCurrentMouseStrokeValidFileDrag = false
        guard AppState.shared.isDragging else { return }
        let selectedIdx = AppState.shared.hoveredIndex
        
        // 마우스를 놓는 최종 순간에 드래그 보드를 한 번 더 스캔하여 2,000개 전체 목록이 빠짐없이 들어왔는지 최종 확인!
        let latestFiles = readValidDraggedFiles(from: dragPboard)
        let files = latestFiles.count > AppState.shared.draggedFiles.count ? latestFiles : AppState.shared.draggedFiles
        let items = AppState.shared.items
        hideWheel()
        if let idx = selectedIdx, idx < items.count {
            FileProcessor.execute(actionKey: items[idx].actionKey, files: files, openQualityPopup: openQualityPopup)
        }
    }
}

extension NSApplication {
    var WindowsHaveNoVisibleTools: Bool {
        return !ToolWindowManager.shared.activeWindows.contains { $0.isVisible }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()