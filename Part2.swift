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
        estBytes = FileSizeEstimator.estimateConversionBytes(files: files, originalTotalBytes: origBytes, targetExt: targetExt, qualityPercent: quality)
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
