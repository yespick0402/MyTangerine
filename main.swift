import Cocoa
import SwiftUI
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import PDFKit
import Vision
import UniformTypeIdentifiers

// MARK: - 글로벌 상태 및 데이터 모델
enum WheelMode: String {
    case convert = "CONVERT"
    case tools = "TOOLS"
    case actions = "ACTIONS"
}

struct WheelItem: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let actionKey: String
}

class AppState: ObservableObject {
    static let shared = AppState()
    @Published var isDragging = false
    @Published var wheelMode: WheelMode = .convert
    @Published var draggedFiles: [URL] = []
    @Published var totalSizeText: String = ""
    @Published var hoveredIndex: Int? = nil
    @Published var items: [WheelItem] = []
    
    var firstFileExtension: String {
        draggedFiles.first?.pathExtension.lowercased() ?? ""
    }
    
    func updateItems() {
        let ext = firstFileExtension
        let imageExts = ["png", "jpg", "jpeg", "heic", "webp", "tiff", "bmp", "gif", "avif"]
        let videoExts = ["mp4", "mov", "mkv", "avi", "webm", "m4v"]
        let audioExts = ["mp3", "m4a", "wav", "flac", "ogg", "aac", "aiff"]
        
        switch wheelMode {
        case .convert:
            if imageExts.contains(ext) {
                items = [
                    WheelItem(title: "JPG", icon: "photo", actionKey: "conv_jpg"),
                    WheelItem(title: "PNG", icon: "photo.fill", actionKey: "conv_png"),
                    WheelItem(title: "WEBP", icon: "globe", actionKey: "conv_webp"),
                    WheelItem(title: "HEIC", icon: "camera", actionKey: "conv_heic"),
                    WheelItem(title: "TIFF", icon: "doc.richtext", actionKey: "conv_tiff"),
                    WheelItem(title: "BMP", icon: "square.grid.2x2", actionKey: "conv_bmp"),
                    WheelItem(title: "PDF", icon: "doc.fill", actionKey: "conv_pdf"),
                    WheelItem(title: "ICO/ICNS", icon: "app.dashed", actionKey: "conv_ico")
                ]
            } else if videoExts.contains(ext) {
                items = [
                    WheelItem(title: "MP4", icon: "film", actionKey: "conv_mp4"),
                    WheelItem(title: "MOV", icon: "video", actionKey: "conv_mov"),
                    WheelItem(title: "GIF", icon: "sparkles.tv", actionKey: "conv_gif"),
                    WheelItem(title: "WEBM", icon: "network", actionKey: "conv_webm"),
                    WheelItem(title: "MKV", icon: "play.rectangle", actionKey: "conv_mkv"),
                    WheelItem(title: "MP3 (음원)", icon: "music.note", actionKey: "conv_mp3"),
                    WheelItem(title: "WAV (음원)", icon: "waveform", actionKey: "conv_wav")
                ]
            } else if audioExts.contains(ext) {
                items = [
                    WheelItem(title: "MP3", icon: "music.note", actionKey: "conv_mp3"),
                    WheelItem(title: "M4A", icon: "music.quarternote.3", actionKey: "conv_m4a"),
                    WheelItem(title: "WAV", icon: "waveform", actionKey: "conv_wav"),
                    WheelItem(title: "FLAC", icon: "hifispeaker", actionKey: "conv_flac"),
                    WheelItem(title: "AIFF", icon: "opticaldisc", actionKey: "conv_aiff"),
                    WheelItem(title: "OGG", icon: "speaker.wave.2", actionKey: "conv_ogg")
                ]
            } else {
                items = [
                    WheelItem(title: "ZIP 압축", icon: "doc.zipper", actionKey: "conv_zip"),
                    WheelItem(title: "TAR.GZ", icon: "archivebox", actionKey: "conv_targz"),
                    WheelItem(title: "PDF 변환", icon: "doc.richtext", actionKey: "conv_pdf"),
                    WheelItem(title: "TXT 변환", icon: "doc.text", actionKey: "conv_txt")
                ]
            }
        case .tools:
            if imageExts.contains(ext) {
                items = [
                    WheelItem(title: "COMPRESS", icon: "arrow.down.right.and.arrow.up.left", actionKey: "tool_compress"),
                    WheelItem(title: "METADATA", icon: "tag", actionKey: "tool_metadata"),
                    WheelItem(title: "EDIT", icon: "slider.horizontal.3", actionKey: "tool_edit_photo"),
                    WheelItem(title: "ADD BG", icon: "photo.artframe", actionKey: "tool_add_bg"),
                    WheelItem(title: "REDACT/CROP", icon: "eye.slash", actionKey: "tool_redact"),
                    WheelItem(title: "QR 코드 읽기", icon: "qrcode.viewfinder", actionKey: "tool_qr"),
                    WheelItem(title: "PDF로 합치기", icon: "doc.on.doc", actionKey: "tool_merge_pdf")
                ]
            } else if audioExts.contains(ext) || videoExts.contains(ext) {
                items = [
                    WheelItem(title: "TRIM / 편집", icon: "scissors", actionKey: "tool_audio_video_trim"),
                    WheelItem(title: "COMPRESS", icon: "arrow.down.right.and.arrow.up.left", actionKey: "tool_compress"),
                    WheelItem(title: "CHANNELS", icon: "speaker.wave.3", actionKey: "tool_audio_channels"),
                    WheelItem(title: "BLEEP (삐-)", icon: "waveform.badge.exclamationmark", actionKey: "tool_audio_bleep"),
                    WheelItem(title: "2배속 만들기", icon: "forward.fill", actionKey: "tool_speed_2x"),
                    WheelItem(title: "메타데이터 삭제", icon: "trash.slash", actionKey: "tool_strip_meta")
                ]
            } else {
                items = [
                    WheelItem(title: "ZIP 압축", icon: "doc.zipper", actionKey: "conv_zip"),
                    WheelItem(title: "PDF 병합", icon: "doc.on.doc.fill", actionKey: "tool_merge_pdf"),
                    WheelItem(title: "용량 압축", icon: "arrow.down.right.and.arrow.up.left", actionKey: "tool_compress"),
                    WheelItem(title: "메타데이터 삭제", icon: "tag.slash", actionKey: "tool_strip_meta")
                ]
            }
        case .actions:
            items = [
                WheelItem(title: "경로 복사", icon: "doc.on.clipboard", actionKey: "act_copy_path"),
                WheelItem(title: "터미널 열기", icon: "terminal", actionKey: "act_terminal"),
                WheelItem(title: "AirDrop", icon: "airplayaudio", actionKey: "act_airdrop"),
                WheelItem(title: "Finder 표시", icon: "folder", actionKey: "act_finder"),
                WheelItem(title: "사본 만들기", icon: "plus.square.on.square", actionKey: "act_duplicate")
            ]
        }
    }
}

// MARK: - 파일 처리 및 변환 엔진
class FileProcessor {
    static var ffmpegPath: String {
        if let bundled = Bundle.main.path(forResource: "ffmpeg", ofType: nil) { return bundled }
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ffmpeg") { return "/opt/homebrew/bin/ffmpeg" }
        if FileManager.default.fileExists(atPath: "/usr/local/bin/ffmpeg") { return "/usr/local/bin/ffmpeg" }
        return "ffmpeg"
    }
    
    static func uniqueOutputURL(for url: URL, newExt: String, suffix: String = "") -> URL {
        let folder = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent + suffix
        var outURL = folder.appendingPathComponent("\(baseName).\(newExt)")
        var counter = 1
        while FileManager.default.fileExists(atPath: outURL.path) {
            outURL = folder.appendingPathComponent("\(baseName)_\(counter).\(newExt)")
            counter += 1
        }
        return outURL
    }
    
    static func runShell(_ launchPath: String, args: [String], completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: launchPath)
            task.arguments = args
            do {
                try task.run()
                task.waitUntilExit()
                DispatchQueue.main.async { completion(task.terminationStatus == 0) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }
    
    static func execute(actionKey: String, files: [URL]) {
        guard !files.isEmpty else { return }
        
        if actionKey == "tool_edit_photo", let first = files.first {
            ToolWindowManager.shared.showEditPhotoWindow(url: first)
            return
        }
        if actionKey == "tool_add_bg", let first = files.first {
            ToolWindowManager.shared.showAddBGWindow(url: first)
            return
        }
        if actionKey == "tool_redact", let first = files.first {
            ToolWindowManager.shared.showRedactWindow(url: first)
            return
        }
        if actionKey == "tool_compress" {
            ToolWindowManager.shared.showCompressWindow(urls: files)
            return
        }
        if actionKey == "tool_metadata", let first = files.first {
            ToolWindowManager.shared.showMetadataWindow(url: first)
            return
        }
        if ["tool_audio_video_trim", "tool_audio_channels", "tool_audio_bleep"].contains(actionKey), let first = files.first {
            ToolWindowManager.shared.showAudioToolWindow(url: first, initialTab: actionKey)
            return
        }
        if actionKey == "tool_qr", let first = files.first {
            readQRCode(from: first)
            return
        }
        if actionKey == "tool_merge_pdf" {
            mergeToPDF(files: files)
            return
        }
        
        if actionKey == "act_copy_path" {
            let paths = files.map { $0.path }.joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(paths, forType: .string)
            showToast("파일 경로가 클립보드에 복사되었습니다.")
            return
        }
        if actionKey == "act_terminal", let first = files.first {
            let folder = first.hasDirectoryPath ? first.path : first.deletingLastPathComponent().path
            runShell("/usr/bin/open", args: ["-a", "Terminal", folder]) { _ in }
            return
        }
        if actionKey == "act_finder" {
            NSWorkspace.shared.activateFileViewerSelecting(files)
            return
        }
        if actionKey == "act_airdrop" {
            if let service = NSSharingService(named: .sendViaAirDrop) {
                service.perform(withItems: files)
            }
            return
        }
        if actionKey == "act_duplicate" {
            for f in files {
                let out = uniqueOutputURL(for: f, newExt: f.pathExtension, suffix: "_copy")
                try? FileManager.default.copyItem(at: f, to: out)
            }
            showToast("사본 생성이 완료되었습니다.")
            return
        }
        
        for file in files {
            if actionKey.hasPrefix("conv_") {
                let targetExt = actionKey.replacingOccurrences(of: "conv_", with: "")
                convertFile(file, to: targetExt)
            } else if actionKey == "tool_speed_2x" {
                let out = uniqueOutputURL(for: file, newExt: file.pathExtension, suffix: "_2x")
                runShell(ffmpegPath, args: ["-y", "-i", file.path, "-filter:v", "setpts=0.5*PTS", "-filter:a", "atempo=2.0", out.path]) { _ in
                    showToast("2배속 변환 완료: \(out.lastPathComponent)")
                }
            } else if actionKey == "tool_strip_meta" {
                stripMetadata(file: file)
            }
        }
    }
    
    static func convertFile(_ file: URL, to ext: String) {
        if ext == "zip" {
            let out = uniqueOutputURL(for: file, newExt: "zip")
            runShell("/usr/bin/ditto", args: ["-c", "-k", "--sequesterRsrc", file.path, out.path]) { _ in
                showToast("ZIP 압축 완료: \(out.lastPathComponent)")
            }
            return
        }
        if ext == "targz" {
            let out = uniqueOutputURL(for: file, newExt: "tar.gz")
            runShell("/usr/bin/tar", args: ["-czf", out.path, "-C", file.deletingLastPathComponent().path, file.lastPathComponent]) { _ in
                showToast("TAR.GZ 압축 완료: \(out.lastPathComponent)")
            }
            return
        }
        
        let sipsFormats = ["jpg": "jpeg", "png": "png", "heic": "heic", "tiff": "tiff", "bmp": "bmp"]
        if let sipsFormat = sipsFormats[ext] {
            let out = uniqueOutputURL(for: file, newExt: ext)
            runShell("/usr/bin/sips", args: ["-s", "format", sipsFormat, file.path, "--out", out.path]) { ok in
                if ok { showToast("\(ext.uppercased()) 변환 완료!") }
                else { convertWithFFmpeg(file, to: ext) }
            }
            return
        }
        
        if ext == "pdf", let img = NSImage(contentsOf: file) {
            let out = uniqueOutputURL(for: file, newExt: "pdf")
            let pdf = PDFDocument()
            if let page = PDFPage(image: img) {
                pdf.insert(page, at: 0)
                pdf.write(to: out)
                showToast("PDF 변환 완료: \(out.lastPathComponent)")
                return
            }
        }
        
        convertWithFFmpeg(file, to: ext)
    }
    
    static func convertWithFFmpeg(_ file: URL, to ext: String) {
        let out = uniqueOutputURL(for: file, newExt: ext)
        var args = ["-y", "-i", file.path]
        if ext == "gif" {
            args += ["-vf", "fps=12,scale=640:-1:flags=lanczos", out.path]
        } else {
            args.append(out.path)
        }
        runShell(ffmpegPath, args: args) { ok in
            showToast(ok ? "\(ext.uppercased()) 변환 완료!" : "변환 실패 (지원되지 않는 코덱)")
        }
    }
    
    static func stripMetadata(file: URL) {
        let out = uniqueOutputURL(for: file, newExt: file.pathExtension, suffix: "_clean")
        if let img = NSImage(contentsOf: file),
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) {
            try? data.write(to: out)
            showToast("메타데이터가 제거된 파일이 저장되었습니다.")
        } else {
            runShell(ffmpegPath, args: ["-y", "-i", file.path, "-map_metadata", "-1", "-c:v", "copy", "-c:a", "copy", out.path]) { _ in
                showToast("미디어 메타데이터 제거 완료!")
            }
        }
    }
    
    static func readQRCode(from url: URL) {
        guard let ciImage = CIImage(contentsOf: url) else { return }
        let request = VNDetectBarcodesRequest { req, _ in
            if let results = req.results as? [VNBarcodeObservation],
               let payload = results.first?.payloadStringValue {
                DispatchQueue.main.async {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(payload, forType: .string)
                    let alert = NSAlert()
                    alert.messageText = "QR 코드 인식 성공 (클립보드에 자동 복사됨)"
                    alert.informativeText = payload
                    alert.runModal()
                }
            } else {
                DispatchQueue.main.async { showToast("이미지에서 QR 코드를 찾지 못했습니다.") }
            }
        }
        try? VNImageRequestHandler(ciImage: ciImage, options: [:]).perform([request])
    }
    
    static func mergeToPDF(files: [URL]) {
        guard let first = files.first else { return }
        let pdf = PDFDocument()
        for f in files {
            if f.pathExtension.lowercased() == "pdf", let sub = PDFDocument(url: f) {
                for i in 0..<sub.pageCount {
                    if let page = sub.page(at: i) { pdf.insert(page, at: pdf.pageCount) }
                }
            } else if let img = NSImage(contentsOf: f), let page = PDFPage(image: img) {
                pdf.insert(page, at: pdf.pageCount)
            }
        }
        let out = uniqueOutputURL(for: first, newExt: "pdf", suffix: "_merged")
        pdf.write(to: out)
        showToast("PDF 병합 완료: \(out.lastPathComponent)")
    }
    
    static func showToast(_ message: String) {
        DispatchQueue.main.async {
            ToolWindowManager.shared.showBanner(message: message)
        }
    }
}

// MARK: - 원형 다이얼 휠 UI (Radial Pie Menu)
struct PieSliceShape: Shape {
    var startAngle: Angle
    var endAngle: Angle
    var innerRadiusRatio: CGFloat = 0.34
    
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * innerRadiusRatio
        
        var path = Path()
        path.addArc(center: center, radius: innerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.addArc(center: center, radius: outerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        path.closeSubpath()
        return path
    }
}

struct RadialWheelView: View {
    @ObservedObject var state = AppState.shared
    let wheelSize: CGFloat = 310
    
    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: wheelSize + 16, height: wheelSize + 16)
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.32), radius: 18, x: 0, y: 8)
            
            slicesView
            centerBadgeView
        }
        .frame(width: wheelSize + 30, height: wheelSize + 30)
    }
    
    var slicesView: some View {
        let count = max(state.items.count, 1)
        let angleStep = 360.0 / Double(count)
        return ForEach(0..<state.items.count, id: \.self) { index in
            sliceItemView(index: index, angleStep: angleStep)
        }
    }
    
    func sliceItemView(index: Int, angleStep: Double) -> some View {
        let item = state.items[index]
        let start = Angle(degrees: Double(index) * angleStep - 90.0 - angleStep / 2.0 + 1.8)
        let end = Angle(degrees: Double(index + 1) * angleStep - 90.0 - angleStep / 2.0 - 1.8)
        let midAngle = (start.radians + end.radians) / 2.0
        let isHovered = (state.hoveredIndex == index)
        let labelRadius = (wheelSize / 2.0) * 0.67
        
        let fillGrad = isHovered ?
            LinearGradient(colors: [Color.orange, Color.red], startPoint: .topLeading, endPoint: .bottomTrailing) :
            LinearGradient(colors: [Color.white.opacity(0.75), Color.white.opacity(0.45)], startPoint: .top, endPoint: .bottom)
        
        return ZStack {
            PieSliceShape(startAngle: start, endAngle: end)
                .fill(fillGrad)
                .overlay(
                    PieSliceShape(startAngle: start, endAngle: end)
                        .stroke(isHovered ? Color.white : Color.black.opacity(0.08), lineWidth: 1.2)
                )
            
            VStack(spacing: 4) {
                Image(systemName: item.icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(item.title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundColor(isHovered ? .white : .black.opacity(0.85))
            .position(
                x: wheelSize / 2.0 + CGFloat(cos(midAngle)) * labelRadius,
                y: wheelSize / 2.0 + CGFloat(sin(midAngle)) * labelRadius
            )
        }
        .frame(width: wheelSize, height: wheelSize)
    }
    
    var centerBadgeView: some View {
        VStack(spacing: 2) {
            Text(state.wheelMode.rawValue)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundColor(.orange)
            Text(state.totalSizeText)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text("\(state.draggedFiles.count)개 파일")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
    }
}

// MARK: - 미니 편집 도구 창 매니저
class ToolWindowManager {
    static let shared = ToolWindowManager()
    var activeWindows: [NSWindow] = []
    var bannerWindow: NSPanel?
    
    func openWindow<V: View>(title: String, view: V, size: NSSize) {
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = title
        win.titlebarAppearsTransparent = true
        win.isReleasedWhenClosed = false
        win.center()
        win.contentView = NSHostingView(rootView: view)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        activeWindows.append(win)
    }
    
    func showBanner(message: String) {
        bannerWindow?.close()
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 50),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - 170, y: screen.frame.maxY - 90))
        }
        panel.contentView = NSHostingView(rootView:
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.orange).font(.title2)
                Text(message).font(.system(size: 13, weight: .semibold)).foregroundColor(.primary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 10)
        )
        panel.orderFrontRegardless()
        bannerWindow = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            panel.close()
        }
    }
    
    func showEditPhotoWindow(url: URL) {
        openWindow(title: "Edit Photo", view: EditPhotoView(fileURL: url), size: NSSize(width: 480, height: 560))
    }
    
    func showAddBGWindow(url: URL) {
        openWindow(title: "Add BG", view: AddBGView(fileURL: url), size: NSSize(width: 480, height: 540))
    }
    
    func showRedactWindow(url: URL) {
        openWindow(title: "Redact / Crop Image", view: RedactPhotoView(fileURL: url), size: NSSize(width: 520, height: 560))
    }
    
    func showCompressWindow(urls: [URL]) {
        openWindow(title: "Compress Files", view: CompressToolView(files: urls), size: NSSize(width: 400, height: 300))
    }
    
    func showMetadataWindow(url: URL) {
        openWindow(title: "File Metadata", view: MetadataToolView(fileURL: url), size: NSSize(width: 440, height: 460))
    }
    
    func showAudioToolWindow(url: URL, initialTab: String) {
        openWindow(title: "Audio & Media Studio", view: AudioStudioView(fileURL: url, initialMode: initialTab), size: NSSize(width: 520, height: 430))
    }
}

// 1. 사진 보정 창
struct EditPhotoView: View {
    let fileURL: URL
    @State private var exposure: Double = 0.0
    @State private var brightness: Double = 0.0
    @State private var contrast: Double = 1.0
    @State private var saturation: Double = 1.0
    @State private var previewImage: NSImage?
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Photo").font(.headline).padding(.top, 8)
            
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.black)
                if let img = previewImage {
                    Image(nsImage: img).resizable().scaledToFit().padding(8)
                }
            }
            .frame(height: 270)
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Light & Color").font(.subheadline.bold()).foregroundColor(.orange)
                sliderRow("Exposure", value: $exposure, range: -2.0...2.0, def: 0.0)
                sliderRow("Brightness", value: $brightness, range: -0.5...0.5, def: 0.0)
                sliderRow("Contrast", value: $contrast, range: 0.5...1.8, def: 1.0)
                sliderRow("Saturation", value: $saturation, range: 0.0...2.0, def: 1.0)
            }
            .padding(.horizontal)
            
            HStack {
                Button("Reset") {
                    exposure = 0; brightness = 0; contrast = 1; saturation = 1
                    updatePreview()
                }
                Spacer()
                Button("Save Edited Copy") {
                    saveEditedImage()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(.horizontal)
            .padding(.bottom, 14)
        }
        .padding()
        .background(LinearGradient(colors: [Color.orange.opacity(0.18), Color.pink.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .onAppear { updatePreview() }
    }
    
    func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, def: Double) -> some View {
        HStack {
            Text(title).frame(width: 80, alignment: .leading).font(.caption)
            Slider(value: value, in: range).tint(.orange).onChange(of: value.wrappedValue) { _ in updatePreview() }
            Text(String(format: "%.2f", value.wrappedValue)).font(.caption.monospacedDigit()).frame(width: 44)
            Button(action: { value.wrappedValue = def; updatePreview() }) {
                Image(systemName: "arrow.counterclockwise").font(.caption)
            }.buttonStyle(.plain)
        }
    }
    
    func renderCIImage() -> CIImage? {
        guard let input = CIImage(contentsOf: fileURL) else { return nil }
        let expFilter = CIFilter.exposureAdjust()
        expFilter.inputImage = input
        expFilter.ev = Float(exposure)
        
        let colorFilter = CIFilter.colorControls()
        colorFilter.inputImage = expFilter.outputImage
        colorFilter.brightness = Float(brightness)
        colorFilter.contrast = Float(contrast)
        colorFilter.saturation = Float(saturation)
        return colorFilter.outputImage
    }
    
    func updatePreview() {
        guard let output = renderCIImage() else { return }
        let rep = NSCIImageRep(ciImage: output)
        let nsImg = NSImage(size: rep.size)
        nsImg.addRepresentation(rep)
        previewImage = nsImg
    }
    
    func saveEditedImage() {
        guard let output = renderCIImage() else { return }
        let ctx = CIContext()
        let outURL = FileProcessor.uniqueOutputURL(for: fileURL, newExt: "jpg", suffix: "_edited")
        if let cgImg = ctx.createCGImage(output, from: output.extent) {
            let rep = NSBitmapImageRep(cgImage: cgImg)
            if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.92]) {
                try? data.write(to: outURL)
                FileProcessor.showToast("보정 이미지 저장 완료: \(outURL.lastPathComponent)")
                NSApp.keyWindow?.close()
            }
        }
    }
}

// 2. 배경 추가 창 (Add BG)
struct AddBGView: View {
    let fileURL: URL
    @State private var selectedPreset = 0
    @State private var paddingRatio: CGFloat = 0.14
    
    let gradients: [[Color]] = [
        [Color.cyan, Color.blue],
        [Color.orange, Color.pink, Color.purple],
        [Color.mint, Color.teal],
        [Color(white: 0.95), Color(white: 0.82)],
        [Color.pink, Color.orange],
        [Color.indigo, Color.black],
        [Color.green, Color.blue]
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Add BG").font(.headline).padding(.top, 8)
            
            ZStack {
                LinearGradient(colors: gradients[selectedPreset], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .cornerRadius(16)
                if let img = NSImage(contentsOf: fileURL) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(8)
                        .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 8)
                        .padding(320 * paddingRatio)
                }
            }
            .frame(width: 340, height: 320)
            
            HStack(spacing: 10) {
                Text("Background").font(.caption.bold())
                ForEach(0..<gradients.count, id: \.self) { idx in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: gradients[idx], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 34, height: 28)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selectedPreset == idx ? Color.red : Color.white, lineWidth: 2))
                        .onTapGesture { selectedPreset = idx }
                }
            }
            
            HStack {
                Text("여백 크기").font(.caption)
                Slider(value: $paddingRatio, in: 0.05...0.30).tint(.orange)
                Button("Save Image") {
                    saveImageWithBG()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(.horizontal)
        }
        .padding()
    }
    
    @MainActor
    func saveImageWithBG() {
        let renderView = ZStack {
            LinearGradient(colors: gradients[selectedPreset], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let img = NSImage(contentsOf: fileURL) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.3), radius: 24, x: 0, y: 12)
                    .padding(1200 * paddingRatio)
            }
        }.frame(width: 1200, height: 1000)
        
        if #available(macOS 13.0, *) {
            let renderer = ImageRenderer(content: renderView)
            if let nsImg = renderer.nsImage,
               let tiff = nsImg.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                let out = FileProcessor.uniqueOutputURL(for: fileURL, newExt: "png", suffix: "_bg")
                try? png.write(to: out)
                FileProcessor.showToast("배경 합성 저장 완료: \(out.lastPathComponent)")
                NSApp.keyWindow?.close()
            }
        }
    }
}

// 3. 이미지 모자이크(Redact) 창
struct RedactPhotoView: View {
    let fileURL: URL
    @State private var redactRects: [CGRect] = []
    @State private var currentDrag: CGRect? = nil
    
    var body: some View {
        VStack(spacing: 12) {
            Text("마우스로 드래그하여 가릴 영역(모자이크/검은 박스)을 지정하세요").font(.caption)
            GeometryReader { geo in
                ZStack {
                    if let img = NSImage(contentsOf: fileURL) {
                        Image(nsImage: img).resizable().scaledToFit().frame(width: geo.size.width, height: geo.size.height)
                    }
                    ForEach(0..<redactRects.count, id: \.self) { i in
                        Rectangle().fill(Color.black).frame(width: redactRects[i].width, height: redactRects[i].height)
                            .position(x: redactRects[i].midX, y: redactRects[i].midY)
                    }
                    if let cur = currentDrag {
                        Rectangle().fill(Color.black.opacity(0.7)).frame(width: cur.width, height: cur.height)
                            .position(x: cur.midX, y: cur.midY)
                    }
                }
                .gesture(DragGesture(minimumDistance: 2)
                    .onChanged { val in
                        let x = min(val.startLocation.x, val.location.x)
                        let y = min(val.startLocation.y, val.location.y)
                        let w = abs(val.location.x - val.startLocation.x)
                        let h = abs(val.location.y - val.startLocation.y)
                        currentDrag = CGRect(x: x, y: y, width: w, height: h)
                    }
                    .onEnded { _ in
                        if let cur = currentDrag { redactRects.append(cur); currentDrag = nil }
                    }
                )
            }
            .frame(width: 460, height: 380)
            .background(Color.black.opacity(0.1))
            .cornerRadius(8)
            
            HStack {
                Button("지우기 초기화") { redactRects.removeAll() }
                Spacer()
                Button("가린 상태로 저장") { saveRedacted() }.buttonStyle(.borderedProminent).tint(.orange)
            }
        }.padding()
    }
    
    @MainActor
    func saveRedacted() {
        let content = ZStack {
            if let img = NSImage(contentsOf: fileURL) {
                Image(nsImage: img).resizable().scaledToFit().frame(width: 460, height: 380)
            }
            ForEach(0..<redactRects.count, id: \.self) { i in
                Rectangle().fill(Color.black).frame(width: redactRects[i].width, height: redactRects[i].height)
                    .position(x: redactRects[i].midX, y: redactRects[i].midY)
            }
        }.frame(width: 460, height: 380)
        
        if #available(macOS 13.0, *) {
            let renderer = ImageRenderer(content: content)
            if let nsImg = renderer.nsImage,
               let tiff = nsImg.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                let out = FileProcessor.uniqueOutputURL(for: fileURL, newExt: "png", suffix: "_redacted")
                try? png.write(to: out)
                FileProcessor.showToast("모자이크 저장 완료: \(out.lastPathComponent)")
                NSApp.keyWindow?.close()
            }
        }
    }
}

// 4. 오디오 파형 편집 / 채널 변환 / Bleep 스튜디오 (컴파일 최적화 완료)
struct AudioStudioView: View {
    let fileURL: URL
    let initialMode: String
    @State private var startRatio: Double = 0.0
    @State private var endRatio: Double = 1.0
    @State private var trimSilence: Bool = false
    @State private var isMono: Bool = false
    @State private var volumePercent: Double = 100.0
    @State private var bleepStartRatio: Double = 0.3
    @State private var bleepEndRatio: Double = 0.45
    @State private var enableBleep: Bool = false
    @State private var duration: Double = 40.0
    
    let sampleBars: [CGFloat] = AudioStudioView.makeSampleBars()
    
    static func makeSampleBars() -> [CGFloat] {
        var result: [CGFloat] = []
        for i in 0..<65 {
            let d = Double(i)
            let val = abs(sin(d * 0.35) * cos(d * 0.15)) * 0.8 + 0.15
            result.append(CGFloat(val))
        }
        return result
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection
            waveformSection
            trimSlidersSection
            Toggle("Trim silent ends automatically (앞뒤 무음 자동 제거)", isOn: $trimSilence)
                .font(.caption)
            Divider()
            channelAndVolumeSection
            bleepSection
            bottomButtonsSection
        }
        .padding(18)
        .background(LinearGradient(colors: [Color.orange.opacity(0.22), Color.red.opacity(0.12)], startPoint: .top, endPoint: .bottom))
        .onAppear {
            if initialMode == "tool_audio_bleep" { enableBleep = true }
            loadAudioDuration()
        }
    }
    
    var headerSection: some View {
        HStack {
            Text("Trim & Convert Audio").font(.headline)
            Spacer()
            let selectedSec = duration * (endRatio - startRatio)
            Text(String(format: "%.2fs selected", selectedSec))
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
        }
    }
    
    var waveformSection: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.yellow.opacity(0.25))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red, lineWidth: 2))
            
            HStack(spacing: 3) {
                ForEach(0..<sampleBars.count, id: \.self) { idx in
                    waveformBar(at: idx)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 105)
    }
    
    func waveformBar(at idx: Int) -> some View {
        let pos = Double(idx) / Double(sampleBars.count)
        let inRange = (pos >= startRatio && pos <= endRatio)
        let inBleep = enableBleep && (pos >= bleepStartRatio && pos <= bleepEndRatio)
        let barColor: Color = inBleep ? .purple : (inRange ? .red : Color.gray.opacity(0.35))
        return Capsule()
            .fill(barColor)
            .frame(width: 4, height: 85 * sampleBars[idx])
    }
    
    var trimSlidersSection: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Start: \(String(format: "%.1fs", duration * startRatio))").font(.caption)
                Slider(value: $startRatio, in: 0.0...0.95).tint(.red)
            }
            VStack(alignment: .leading) {
                Text("End: \(String(format: "%.1fs", duration * endRatio))").font(.caption)
                Slider(value: $endRatio, in: 0.05...1.0).tint(.red)
            }
        }
    }
    
    var channelAndVolumeSection: some View {
        HStack(spacing: 20) {
            Picker("채널", selection: $isMono) {
                Text("Stereo").tag(false)
                Text("Mono").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            
            HStack {
                Text("볼륨").font(.caption)
                Slider(value: $volumePercent, in: 20...200).tint(.orange)
                Text("\(Int(volumePercent))%").font(.caption.monospacedDigit()).frame(width: 40)
            }
        }
    }
    
    var bleepSection: some View {
        HStack {
            Toggle("Bleep (삐- 소리 덮어쓰기)", isOn: $enableBleep).font(.caption.bold())
            if enableBleep {
                Slider(value: $bleepStartRatio, in: 0.0...0.9).tint(.purple)
                Text("~")
                Slider(value: $bleepEndRatio, in: 0.05...1.0).tint(.purple)
            }
        }
    }
    
    var bottomButtonsSection: some View {
        HStack {
            Button("▶ Play Preview") {
                NSWorkspace.shared.open(fileURL)
            }
            Spacer()
            Button("Apply & Save") {
                applyAudioChanges()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
    }
    
    func loadAudioDuration() {
        Task {
            let asset = AVURLAsset(url: fileURL)
            if let cmTime = try? await asset.load(.duration) {
                let sec = CMTimeGetSeconds(cmTime)
                if sec.isFinite && sec > 0 {
                    await MainActor.run { duration = sec }
                }
            }
        }
    }
    
    func applyAudioChanges() {
        let actualStart = min(startRatio, endRatio)
        let actualEnd = max(startRatio, endRatio)
        let startSec = duration * actualStart
        let endSec = duration * actualEnd
        let outURL = FileProcessor.uniqueOutputURL(for: fileURL, newExt: fileURL.pathExtension, suffix: "_edited")
        
        var filters: [String] = []
        filters.append("volume=\(volumePercent / 100.0)")
        if trimSilence {
            filters.append("silenceremove=start_periods=1:start_silence=0.2:start_threshold=-45dB")
        }
        
        var args = ["-y", "-ss", "\(startSec)", "-to", "\(endSec)", "-i", fileURL.path]
        if isMono { args += ["-ac", "1"] }
        if !filters.isEmpty { args += ["-af", filters.joined(separator: ",")] }
        args.append(outURL.path)
        
        FileProcessor.runShell(FileProcessor.ffmpegPath, args: args) { ok in
            FileProcessor.showToast(ok ? "오디오 편집 완료: \(outURL.lastPathComponent)" : "오디오 편집 실패")
            NSApp.keyWindow?.close()
        }
    }
}

// 5. 압축 도구 창
struct CompressToolView: View {
    let files: [URL]
    @State private var quality: Double = 65.0
    
    var body: some View {
        VStack(spacing: 18) {
            Text("Compress \(files.count) File(s)").font(.headline)
            Text("목표 품질: \(Int(quality))% (낮을수록 용량이 크게 줄어듭니다)").font(.caption)
            Slider(value: $quality, in: 15...95).tint(.orange).padding(.horizontal)
            
            Button("압축 시작") {
                for f in files {
                    let ext = f.pathExtension.lowercased()
                    let out = FileProcessor.uniqueOutputURL(for: f, newExt: ext, suffix: "_compressed")
                    if ["jpg", "jpeg", "png", "heic", "tiff"].contains(ext),
                       let img = NSImage(contentsOf: f),
                       let tiff = img.tiffRepresentation,
                       let rep = NSBitmapImageRep(data: tiff),
                       let data = rep.representation(using: .jpeg, properties: [.compressionFactor: quality / 100.0]) {
                        try? data.write(to: out)
                        FileProcessor.showToast("이미지 압축 완료: \(out.lastPathComponent)")
                    } else {
                        let crf = Int(38.0 - (quality / 100.0) * 18.0)
                        FileProcessor.runShell(FileProcessor.ffmpegPath, args: ["-y", "-i", f.path, "-vcodec", "libx264", "-crf", "\(crf)", out.path]) { _ in
                            FileProcessor.showToast("미디어 압축 완료: \(out.lastPathComponent)")
                        }
                    }
                }
                NSApp.keyWindow?.close()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }.padding(24)
    }
}

// 6. 메타데이터 확인 및 삭제 창
struct MetadataToolView: View {
    let fileURL: URL
    @State private var metaDict: [String: String] = [:]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(fileURL.lastPathComponent).font(.headline)
            List {
                ForEach(metaDict.keys.sorted(), id: \.self) { k in
                    HStack {
                        Text(k).font(.caption.bold()).frame(width: 130, alignment: .leading)
                        Text(metaDict[k] ?? "").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            HStack {
                Spacer()
                Button("메타데이터 완전 삭제본 저장") {
                    FileProcessor.stripMetadata(file: fileURL)
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding()
        .onAppear { loadMeta() }
    }
    
    func loadMeta() {
        if let src = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any] {
            for (k, v) in props { metaDict[k] = "\(v)" }
        }
        if metaDict.isEmpty {
            metaDict["File Path"] = fileURL.path
            metaDict["Info"] = "표시할 EXIF 사진 정보가 없거나 일반 파일입니다."
        }
    }
}

// MARK: - 앱 델리게이트 및 글로벌 마우스 드래그 감지
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var wheelPanel: NSPanel!
    var lastPasteboardChangeCount: Int = 0
    var wheelCenterPoint: NSPoint = .zero
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "MyTangerine")
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "🍊 MyTangerine 실행 중", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "사용법: 파일 드래그 중 Shift (변환) / Option+Shift (도구) / Control (액션)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "종료 (Quit)", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
        
        setupWheelPanel()
        startGlobalMonitors()
    }
    
    @objc func quitApp() {
        NSApp.terminate(nil)
    }
    
    func setupWheelPanel() {
        wheelPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 340),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        wheelPanel.isOpaque = false
        wheelPanel.backgroundColor = .clear
        wheelPanel.level = .screenSaver
        wheelPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        wheelPanel.ignoresMouseEvents = true
        wheelPanel.contentView = NSHostingView(rootView: RadialWheelView())
    }
    
    func startGlobalMonitors() {
        let dragPboard = NSPasteboard(name: .drag)
        lastPasteboardChangeCount = dragPboard.changeCount
        
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .flagsChanged]) { [weak self] event in
            self?.handleDragOrFlags(event: event)
        }
        
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            self?.handleMouseUp()
        }
    }
    
    func handleDragOrFlags(event: NSEvent) {
        let flags = NSEvent.modifierFlags
        let shiftPressed = flags.contains(.shift)
        let optionPressed = flags.contains(.option)
        let controlPressed = flags.contains(.control)
        
        let wantsWheel = shiftPressed || controlPressed
        let mousePressed = NSEvent.pressedMouseButtons & 1 != 0
        
        guard mousePressed && wantsWheel else {
            if AppState.shared.isDragging { hideWheel() }
            return
        }
        
        let newMode: WheelMode = controlPressed ? .actions : (optionPressed && shiftPressed ? .tools : .convert)
        
        if !AppState.shared.isDragging {
            let files = readDraggedFiles()
            guard !files.isEmpty else { return }
            AppState.shared.draggedFiles = files
            AppState.shared.totalSizeText = calculateSizeText(files: files)
            AppState.shared.wheelMode = newMode
            AppState.shared.updateItems()
            showWheel(at: NSEvent.mouseLocation)
        } else if AppState.shared.wheelMode != newMode {
            AppState.shared.wheelMode = newMode
            AppState.shared.updateItems()
        }
        
        updateHoveredSlice(mouseLocation: NSEvent.mouseLocation)
    }
    
    func readDraggedFiles() -> [URL] {
        let pboard = NSPasteboard(name: .drag)
        guard let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else {
            return []
        }
        return urls
    }
    
    func calculateSizeText(files: [URL]) -> String {
        var total: Int64 = 0
        for f in files {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: f.path),
               let sz = attrs[.size] as? Int64 {
                total += sz
            }
        }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }
    
    func showWheel(at point: NSPoint) {
        wheelCenterPoint = point
        AppState.shared.isDragging = true
        AppState.shared.hoveredIndex = nil
        wheelPanel.setFrameOrigin(NSPoint(x: point.x - 170, y: point.y - 170))
        wheelPanel.orderFrontRegardless()
    }
    
    func hideWheel() {
        AppState.shared.isDragging = false
        AppState.shared.hoveredIndex = nil
        wheelPanel.orderOut(nil)
    }
    
    func updateHoveredSlice(mouseLocation: NSPoint) {
        let dx = mouseLocation.x - wheelCenterPoint.x
        let dy = mouseLocation.y - wheelCenterPoint.y
        let dist = hypot(dx, dy)
        
        guard dist > 45 && dist < 190 else {
            AppState.shared.hoveredIndex = nil
            return
        }
        
        var degrees = atan2(dx, dy) * 180.0 / .pi
        if degrees < 0 { degrees += 360.0 }
        
        let count = max(AppState.shared.items.count, 1)
        let step = 360.0 / Double(count)
        let shifted = (degrees + step / 2.0).truncatingRemainder(dividingBy: 360.0)
        let idx = Int(shifted / step) % count
        AppState.shared.hoveredIndex = idx
    }
    
    func handleMouseUp() {
        guard AppState.shared.isDragging else { return }
        let selectedIdx = AppState.shared.hoveredIndex
        let files = AppState.shared.draggedFiles
        let items = AppState.shared.items
        hideWheel()
        
        if let idx = selectedIdx, idx < items.count {
            let item = items[idx]
            FileProcessor.execute(actionKey: item.actionKey, files: files)
        }
    }
}

// MARK: - 앱 진입점
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
