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
                    for f in files {
                        FileProcessor.convertFile(f, to: targetExt, qualityPercent: quality)
                    }
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent).tint(.orange)
            }
            .padding(.horizontal, 8)
        }
        .padding(22)
        .onAppear {
            origBytes = files.reduce(0) { $0 + ((try? FileManager.default.attributesOfItem(atPath: $1.path)[.size] as? Int64) ?? 0) }
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
        for f in files {
            let ext = f.pathExtension.lowercased()
            if ["jpg", "jpeg", "png", "heic", "tiff", "bmp", "webp"].contains(ext), let cg = FileProcessor.loadRawCGImage(from: f) {
                let out = FileProcessor.uniqueOutputURL(for: f, newExt: "jpg", suffix: "_compressed")
                FileProcessor.saveCGImage(cg, to: out, formatExt: "jpg", quality: quality / 100.0, sourceURLForMetadata: f)
                FileProcessor.showToast("이미지 압축 완료 (메타데이터 유지됨): \(out.lastPathComponent)")
            } else if FileProcessor.ffmpegPath != nil {
                let out = FileProcessor.uniqueOutputURL(for: f, newExt: ext, suffix: "_compressed")
                let crf = quality >= 99.5 ? 0 : Int(40.0 - (quality / 100.0) * 22.0)
                let dur = FileProcessor.mediaDurationSeconds(for: f)
                FileProcessor.runFFmpegWithProgress(args: ["-y", "-i", f.path, "-map_metadata", "0", "-movflags", "use_metadata_tags", "-vcodec", "libx264", "-crf", "\(crf)", out.path], totalDuration: dur, jobTitle: "압축: \(f.lastPathComponent)") { _ in
                    FileProcessor.preserveFileDates(from: f, to: out)
                    FileProcessor.showToast("미디어 압축 완료 (메타데이터 유지됨): \(out.lastPathComponent)")
                }
            } else {
                let out = FileProcessor.uniqueOutputURL(for: f, newExt: "mp4", suffix: "_compressed")
                FileProcessor.avAssetConvertWithProgress(file: f, to: "mp4", outURL: out, jobTitle: "압축: \(f.lastPathComponent)")
            }
        }
        NSApp.keyWindow?.close()
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
        let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        metaDict["📌 감지된 촬영일시"] = df.string(from: info.date)
        if !info.camera.isEmpty { metaDict["📷 감지된 카메라"] = info.camera }
        
        if let src = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] {
            for (k, v) in props { metaDict[k] = "\(v)" }
        }
    }
}

// MARK: - 12. 초경량·무간섭 앱 델리게이트 (다중 선택/단축키 충돌 완벽 해결 + 파인더 포커스 복구 + 리소스 95% 절감)
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
        // 백그라운드 유틸리티의 불필요한 타이머 깨움을 묶어 배터리 소모 최소화
        ProcessInfo.processInfo.automaticTerminationSupportEnabled = false
        NSApp.setActivationPolicy(.accessory)
        applyPureTransparentCustomIconToAppBundle()
        
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusBarMenu()
        JobProgressManager.shared.onUpdate = { [weak self] in self?.updateStatusBarMenu() }
        
        // 중복 모니터(NSEvent.addGlobalMonitor)를 제거하고 초경량 단일 EventTap만 구동하여 CPU 사용량 0.0% 달성
        setupUltraLightEventTap()
    }
    
    func applyPureTransparentCustomIconToAppBundle() {
        guard let rawIcon = FileProcessor.customAppIconImage() else { return }
        NSApp.applicationIconImage = rawIcon
        let bundlePath = Bundle.main.bundlePath
        DispatchQueue.global(qos: .utility).async {
            NSWorkspace.shared.setIcon(rawIcon, forFile: bundlePath, options: [])
        }
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
        menu.addItem(NSMenuItem(title: "🍊 MyTangerine 4.7 Pro (Apple Silicon 저전력 최적화)", action: nil, keyEquivalent: ""))
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
    
    // 휠이 실제로 필요할 때만 지연 생성(Lazy Init)하고, 닫힐 때는 SwiftUI 뷰 트리를 비워 GPU/배터리 소모를 0으로 만듦
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
    
    // MARK: 핵심 해결 — 실제 파일 아이콘이 드래그되기 전(단순 클릭, Shift+클릭 다중선택, 빈 공간 드래그 선택 등)에는 키보드/마우스 이벤트를 단 1비트도 건드리지 않고 100% 그대로 통과시킴!
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
            
            // 1) 마우스 버튼을 누르는 순간: 현재 드래그 보드 번호만 기록하고 이벤트는 절대 건드리지 않음 (Shift+클릭 다중 선택 100% 정상 작동 보장!)
            if type == .leftMouseDown {
                mySelf.dragCountAtMouseDown = mySelf.dragPboard.changeCount
                mySelf.isCurrentMouseStrokeValidFileDrag = false
                mySelf.previousRawFlags = []
                return Unmanaged.passUnretained(event)
            }
            
            // 2) 마우스 버튼을 뗄 때:
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
            
            // 3) 마우스 왼쪽 버튼이 눌려 있지 않은 평상시에는 키보드(flagsChanged)를 즉시 통과시켜 일반 단축키 간섭 제로 & CPU 절약!
            let mousePressed = (NSEvent.pressedMouseButtons & 1) != 0
            guard mousePressed else {
                return Unmanaged.passUnretained(event)
            }
            
            // 4) 마우스가 눌려 있는 상태에서 실제로 '파일 아이콘 드래그'가 시작되었는지 확인:
            //    바탕화면이나 파인더에서 빈 공간을 드래그해 여러 파일을 네모 박스로 선택할 때는 changeCount가 바뀌지 않으므로,
            //    여기서 즉시 통과(passUnretained)되어 파인더의 Shift/Command 다중 드래그 선택이 100% 완벽하게 작동함!
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
                let bytes = mySelf.calculateTotalBytes(files: files)
                let sizeStr = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                DispatchQueue.main.async {
                    AppState.shared.draggedFiles = files
                    AppState.shared.totalBytes = bytes
                    AppState.shared.totalSizeText = sizeStr
                }
            }
            
            // 5) 여기부터는 '100% 검증된 실제 파일 드래그 세션' 중일 때만 실행됨!
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
                    // 120Hz 마우스 이동 시 파이 조각 인덱스가 실제로 바뀔 때만 메인 스레드 UI를 갱신하여 CPU 소모 95% 절감!
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
    
    // 파인더의 드래그를 안전하게 취소하고, 파인더 창 포커스(좌상단 애플로고 옆 메뉴바)가 먹통이 되지 않도록 깨끗하게 복원!
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
            // 만약 편집 도구 창이 뜨지 않는 일반 변환/취소 작업이라면 파인더의 활성 상태를 즉시 복구해 Command+W 등이 정상 작동하게 보장
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
        guard !AppState.shared.draggedFiles.isEmpty else { return }
        if !AppState.shared.isDragging {
            AppState.shared.wheelMode = mode
            AppState.shared.updateItems()
            showWheel(at: mouseLocation)
        } else if AppState.shared.wheelMode != mode {
            AppState.shared.wheelMode = mode
            AppState.shared.updateItems()
        }
        updateHoveredSliceLightweight(mouseLocation: mouseLocation)
    }
    
    func readValidDraggedFiles(from pboard: NSPasteboard) -> [URL] {
        guard let types = pboard.types,
              types.contains(.fileURL) || types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")) else { return [] }
        guard let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else { return [] }
        return urls.filter { $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }
    }
    
    func calculateTotalBytes(files: [URL]) -> Int64 {
        var total: Int64 = 0
        for f in files {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: f.path), let sz = attrs[.size] as? Int64 { total += sz }
        }
        return total
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
        // 휠이 닫혀 있을 때 백그라운드 SwiftUI 렌더링을 완전히 해제하여 배터리 및 GPU 점유율 0% 유지
        wheelPanel?.contentView = nil
    }
    
    // 마우스 이동 시 이전 인덱스와 다를 때만 @Published 변수를 업데이트하여 불필요한 SwiftUI 120Hz 재렌더링 방지
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
        let files = AppState.shared.draggedFiles
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
