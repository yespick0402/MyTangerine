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
                    WheelItem(title: "ICNS", icon: "app.dashed", actionKey: "conv_icns")
                ]
            } else if videoExts.contains(ext) {
                items = [
                    WheelItem(title: "MP4", icon: "film", actionKey: "conv_mp4"),
                    WheelItem(title: "MOV", icon: "video", actionKey: "conv_mov"),
                    WheelItem(title: "GIF", icon: "sparkles.tv", actionKey: "conv_gif"),
                    WheelItem(title: "M4A (음원)", icon: "music.quarternote.3", actionKey: "conv_m4a"),
                    WheelItem(title: "MP3 (음원)", icon: "music.note", actionKey: "conv_mp3"),
                    WheelItem(title: "WAV (음원)", icon: "waveform", actionKey: "conv_wav"),
                    WheelItem(title: "MKV", icon: "play.rectangle", actionKey: "conv_mkv")
                ]
            } else if audioExts.contains(ext) {
                items = [
                    WheelItem(title: "M4A", icon: "music.quarternote.3", actionKey: "conv_m4a"),
                    WheelItem(title: "WAV", icon: "waveform", actionKey: "conv_wav"),
                    WheelItem(title: "MP3", icon: "music.note", actionKey: "conv_mp3"),
                    WheelItem(title: "FLAC", icon: "hifispeaker", actionKey: "conv_flac"),
                    WheelItem(title: "AIFF", icon: "opticaldisc", actionKey: "conv_aiff"),
                    WheelItem(title: "CAF", icon: "speaker.wave.2", actionKey: "conv_caf")
                ]
            } else {
                items = [
                    WheelItem(title: "ZIP 압축", icon: "doc.zipper", actionKey: "conv_zip"),
                    WheelItem(title: "TAR.GZ", icon: "archivebox", actionKey: "conv_targz"),
                    WheelItem(title: "PDF 변환", icon: "doc.richtext", actionKey: "conv_pdf")
                ]
            }
        case .tools:
            if imageExts.contains(ext) {
                items = [
                    WheelItem(title: "EDIT PHOTO", icon: "slider.horizontal.3", actionKey: "tool_edit_photo"),
                    WheelItem(title: "CROP", icon: "crop", actionKey: "tool_crop"),
                    WheelItem(title: "REDACT", icon: "eye.slash", actionKey: "tool_redact"),
                    WheelItem(title: "ADD BG", icon: "photo.artframe", actionKey: "tool_add_bg"),
                    WheelItem(title: "COMPRESS", icon: "arrow.down.right.and.arrow.up.left", actionKey: "tool_compress"),
                    WheelItem(title: "METADATA", icon: "tag", actionKey: "tool_metadata"),
                    WheelItem(title: "QR 코드", icon: "qrcode.viewfinder", actionKey: "tool_qr"),
                    WheelItem(title: "PDF 병합", icon: "doc.on.doc", actionKey: "tool_merge_pdf")
                ]
            } else if audioExts.contains(ext) || videoExts.contains(ext) {
                items = [
                    WheelItem(title: "TRIM / 편집", icon: "scissors", actionKey: "tool_audio_video_trim"),
                    WheelItem(title: "COMPRESS", icon: "arrow.down.right.and.arrow.up.left", actionKey: "tool_compress"),
                    WheelItem(title: "CHANNELS", icon: "speaker.wave.3", actionKey: "tool_audio_channels"),
                    WheelItem(title: "BLEEP (삐-)", icon: "waveform.badge.exclamationmark", actionKey: "tool_audio_bleep"),
                    WheelItem(title: "메타데이터 삭제", icon: "trash.slash", actionKey: "tool_strip_meta")
                ]
            } else {
                items = [
                    WheelItem(title: "ZIP 압축", icon: "doc.zipper", actionKey: "conv_zip"),
                    WheelItem(title: "PDF 병합", icon: "doc.on.doc.fill", actionKey: "tool_merge_pdf"),
                    WheelItem(title: "용량 압축", icon: "arrow.down.right.and.arrow.up.left", actionKey: "tool_compress")
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

// MARK: - 파일 처리 및 하이브리드 변환 엔진 (Native AVFoundation + Standalone FFmpeg)
class FileProcessor {
    static var ffmpegPath: String? {
        let candidates = [
            Bundle.main.path(forResource: "ffmpeg", ofType: nil),
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg"
        ].compactMap { $0 }
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
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
        if actionKey == "tool_crop", let first = files.first {
            ToolWindowManager.shared.showRedactCropWindow(url: first, initialTab: 1)
            return
        }
        if actionKey == "tool_redact", let first = files.first {
            ToolWindowManager.shared.showRedactCropWindow(url: first, initialTab: 0)
            return
        }
        if actionKey == "tool_add_bg", let first = files.first {
            ToolWindowManager.shared.showAddBGWindow(url: first)
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
            showToast("사본 생성 완료!")
            return
        }
        
        for file in files {
            if actionKey.hasPrefix("conv_") {
                let targetExt = actionKey.replacingOccurrences(of: "conv_", with: "")
                convertFile(file, to: targetExt)
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
        
        // 1. 이미지 변환 (macOS 기본 sips 활용)
        let sipsFormats = ["jpg": "jpeg", "png": "png", "heic": "heic", "tiff": "tiff", "bmp": "bmp", "icns": "icns"]
        if let sipsFormat = sipsFormats[ext] {
            let out = uniqueOutputURL(for: file, newExt: ext)
            runShell("/usr/bin/sips", args: ["-s", "format", sipsFormat, file.path, "--out", out.path]) { ok in
                if ok { showToast("\(ext.uppercased()) 변환 완료!") }
                else { convertMediaHybrid(file, to: ext) }
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
        
        convertMediaHybrid(file, to: ext)
    }
    
    // 2. 비디오 및 오디오 하이브리드 변환 (FFmpeg 우선 시도 -> 실패 시 macOS Native AVFoundation / afconvert 즉시 작동)
    static func convertMediaHybrid(_ file: URL, to ext: String) {
        let out = uniqueOutputURL(for: file, newExt: ext)
        
        if let ffmpeg = ffmpegPath {
            var args = ["-y", "-i", file.path]
            if ext == "mp4" {
                args += ["-c:v", "libx264", "-preset", "fast", "-crf", "22", "-c:a", "aac", "-pix_fmt", "yuv420p", out.path]
            } else if ext == "mov" {
                args += ["-c:v", "libx264", "-c:a", "aac", out.path]
            } else if ext == "gif" {
                args += ["-vf", "fps=12,scale=640:-1:flags=lanczos", out.path]
            } else if ext == "mp3" {
                args += ["-vn", "-c:a", "libmp3lame", "-q:a", "2", out.path]
            } else if ext == "m4a" {
                args += ["-vn", "-c:a", "aac", "-b:a", "192k", out.path]
            } else if ext == "wav" {
                args += ["-vn", "-c:a", "pcm_s16le", out.path]
            } else if ext == "flac" {
                args += ["-vn", "-c:a", "flac", out.path]
            } else {
                args.append(out.path)
            }
            
            runShell(ffmpeg, args: args) { ok in
                if ok && FileManager.default.fileExists(atPath: out.path) {
                    showToast("\(ext.uppercased()) 변환 완료: \(out.lastPathComponent)")
                } else {
                    try? FileManager.default.removeItem(at: out)
                    nativeAppleMediaConvert(file, to: ext, outURL: out)
                }
            }
        } else {
            nativeAppleMediaConvert(file, to: ext, outURL: out)
        }
    }
    
    static func nativeAppleMediaConvert(_ file: URL, to ext: String, outURL: URL) {
        // macOS 내장 오디오 변환기 (/usr/bin/afconvert) 활용
        let afFormats: [String: (String, String)] = [
            "m4a": ("m4af", "aac"),
            "wav": ("WAVE", "LEI16"),
            "aiff": ("AIFF", "BEI16"),
            "caf": ("caff", "aac"),
            "flac": ("flac", "flac")
        ]
        
        if let (fileType, dataFormat) = afFormats[ext] {
            let inputExt = file.pathExtension.lowercased()
            let videoExts = ["mp4", "mov", "m4v"]
            if !videoExts.contains(inputExt) {
                runShell("/usr/bin/afconvert", args: ["-f", fileType, "-d", dataFormat, file.path, outURL.path]) { ok in
                    if ok {
                        showToast("\(ext.uppercased()) 네이티브 변환 완료!")
                    } else {
                        avAssetConvert(file: file, to: ext, outURL: outURL)
                    }
                }
                return
            }
        }
        
        avAssetConvert(file: file, to: ext, outURL: outURL)
    }
    
    static func avAssetConvert(file: URL, to ext: String, outURL: URL) {
        let asset = AVURLAsset(url: file)
        let isAudioOnly = ["m4a", "mp3", "wav", "aiff", "flac", "caf"].contains(ext)
        let preset = isAudioOnly ? AVAssetExportPresetAppleM4A : AVAssetExportPresetHighestQuality
        
        guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else {
            showToast("변환기를 초기화할 수 없습니다.")
            return
        }
        
        var targetURL = outURL
        if isAudioOnly {
            targetURL = uniqueOutputURL(for: file, newExt: "m4a")
            exporter.outputFileType = .m4a
        } else if ext == "mp4" {
            exporter.outputFileType = .mp4
        } else {
            exporter.outputFileType = .mov
        }
        
        exporter.outputURL = targetURL
        exporter.exportAsynchronously {
            DispatchQueue.main.async {
                if exporter.status == .completed {
                    if ext == "wav" || ext == "aiff" || ext == "flac" {
                        let finalURL = uniqueOutputURL(for: file, newExt: ext)
                        let fmt = ext == "wav" ? "WAVE" : (ext == "aiff" ? "AIFF" : "flac")
                        let dat = ext == "flac" ? "flac" : (ext == "wav" ? "LEI16" : "BEI16")
                        runShell("/usr/bin/afconvert", args: ["-f", fmt, "-d", dat, targetURL.path, finalURL.path]) { ok in
                            try? FileManager.default.removeItem(at: targetURL)
                            showToast(ok ? "\(ext.uppercased()) 변환 완료!" : "변환 완료: \(targetURL.lastPathComponent)")
                        }
                    } else {
                        showToast("변환 완료: \(targetURL.lastPathComponent)")
                    }
                } else {
                    showToast("변환 실패: \(exporter.error?.localizedDescription ?? "지원되지 않는 형식")")
                }
            }
        }
    }
    
    static func stripMetadata(file: URL) {
        let out = uniqueOutputURL(for: file, newExt: file.pathExtension, suffix: "_clean")
        if let cgImg = loadRawCGImage(from: file) {
            saveCGImage(cgImg, to: out, formatExt: file.pathExtension)
            showToast("메타데이터가 제거된 원본 화질 이미지가 저장되었습니다.")
        } else if let ffmpeg = ffmpegPath {
            runShell(ffmpeg, args: ["-y", "-i", file.path, "-map_metadata", "-1", "-c", "copy", out.path]) { _ in
                showToast("미디어 메타데이터 제거 완료!")
            }
        }
    }
    
    static func loadRawCGImage(from url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
    
    static func saveCGImage(_ cgImage: CGImage, to url: URL, formatExt: String, quality: Double = 0.95) {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let ext = formatExt.lowercased()
        let data: Data?
        if ext == "png" {
            data = rep.representation(using: .png, properties: [:])
        } else if ext == "tiff" {
            data = rep.representation(using: .tiff, properties: [:])
        } else if ext == "bmp" {
            data = rep.representation(using: .bmp, properties: [:])
        } else {
            data = rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        }
        try? data?.write(to: url)
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
                    alert.messageText = "QR 코드 인식 성공 (클립보드 복사됨)"
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

// MARK: - 원형 다이얼 휠 UI
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

// MARK: - 크기 조절 및 확대/축소 지원 도구 창 매니저
class ToolWindowManager {
    static let shared = ToolWindowManager()
    var activeWindows: [NSWindow] = []
    var bannerWindow: NSPanel?
    
    func openWindow<V: View>(title: String, view: V, size: NSSize, minSize: NSSize = NSSize(width: 600, height: 480)) {
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = title
        win.minSize = minSize
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
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - 190, y: screen.frame.maxY - 90))
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            panel.close()
        }
    }
    
    func showEditPhotoWindow(url: URL) {
        openWindow(title: "Pro Photo Editor — \(url.lastPathComponent)", view: EditPhotoView(fileURL: url), size: NSSize(width: 1060, height: 760), minSize: NSSize(width: 820, height: 600))
    }
    
    func showRedactCropWindow(url: URL, initialTab: Int) {
        openWindow(title: "Redact & Crop Studio — \(url.lastPathComponent)", view: RedactCropStudioView(fileURL: url, mode: initialTab), size: NSSize(width: 1040, height: 760), minSize: NSSize(width: 800, height: 580))
    }
    
    func showAddBGWindow(url: URL) {
        openWindow(title: "Add Background — \(url.lastPathComponent)", view: AddBGView(fileURL: url), size: NSSize(width: 820, height: 680))
    }
    
    func showCompressWindow(urls: [URL]) {
        openWindow(title: "Compress Files", view: CompressToolView(files: urls), size: NSSize(width: 460, height: 320), minSize: NSSize(width: 400, height: 280))
    }
    
    func showMetadataWindow(url: URL) {
        openWindow(title: "File Metadata", view: MetadataToolView(fileURL: url), size: NSSize(width: 560, height: 520))
    }
    
    func showAudioToolWindow(url: URL, initialTab: String) {
        openWindow(title: "Audio & Media Studio — \(url.lastPathComponent)", view: AudioStudioView(fileURL: url, initialMode: initialTab), size: NSSize(width: 680, height: 500))
    }
}

// MARK: - 1. 전문가급 사진 보정 창 (14종 슬라이더 + 확대/축소 + 대형 프리뷰 + 원본 해상도 저장)
struct EditPhotoView: View {
    let fileURL: URL
    
    // Light
    @State private var exposure: Double = 0.0        // -3.0 ... 3.0
    @State private var brilliance: Double = 0.0      // -1.0 ... 1.0
    @State private var highlights: Double = 1.0      // 0.0 ... 2.0 (1.0 기본)
    @State private var shadows: Double = 0.0         // -1.0 ... 1.0
    @State private var brightness: Double = 0.0      // -0.6 ... 0.6
    @State private var contrast: Double = 1.0        // 0.3 ... 2.5
    @State private var blackPoint: Double = 0.0      // -0.3 ... 0.3
    
    // Color & Detail
    @State private var saturation: Double = 1.0      // 0.0 ... 3.0
    @State private var vibrance: Double = 0.0        // -1.0 ... 2.0
    @State private var warmth: Double = 0.0          // -3000 ... 3000
    @State private var tint: Double = 0.0            // -100 ... 100
    @State private var sharpness: Double = 0.0       // 0.0 ... 3.0
    @State private var vignette: Double = 0.0        // 0.0 ... 2.0
    @State private var sepia: Double = 0.0           // 0.0 ... 1.0
    
    // Zoom & Preview
    @State private var zoomScale: CGFloat = 1.0
    @State private var showOriginal: Bool = false
    @State private var previewImage: NSImage?
    @State private var originalNSImage: NSImage?
    @State private var pixelSize: CGSize = .zero
    
    let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    var body: some View {
        HSplitView {
            // 좌측: 확대/축소가 가능한 대형 이미지 프리뷰 영역
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("\(Int(pixelSize.width)) × \(Int(pixelSize.height)) px")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: { zoomScale = max(0.25, zoomScale - 0.25) }) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    Text("\(Int(zoomScale * 100))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 45)
                    Button(action: { zoomScale = min(4.0, zoomScale + 0.25) }) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    Button("100% 맞춤") { zoomScale = 1.0 }
                        .font(.caption)
                    
                    Toggle("원본 비교", isOn: $showOriginal)
                        .toggleStyle(.button)
                        .font(.caption)
                }
                .padding(10)
                .background(.regularMaterial)
                
                ScrollView([.horizontal, .vertical]) {
                    ZStack {
                        Color(white: 0.12)
                        if let img = (showOriginal ? originalNSImage : previewImage) {
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 640 * zoomScale, height: 600 * zoomScale)
                                .padding(20)
                        }
                    }
                    .frame(minWidth: 660, minHeight: 620)
                }
                .background(Color(white: 0.12))
            }
            .frame(minWidth: 520, maxWidth: .infinity)
            
            // 우측: 14종 전문가 보정 컨트롤 패널
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
                            sectionTitle("COLOR (색감 및 화이트밸런스)")
                            sliderItem("채도 (Saturation)", val: $saturation, range: 0.0...3.0, def: 1.0)
                            sliderItem("생동감 (Vibrance)", val: $vibrance, range: -1.0...2.0, def: 0.0)
                            sliderItem("색온도 (Warmth)", val: $warmth, range: -3000...3000, def: 0.0)
                            sliderItem("색조 (Tint)", val: $tint, range: -100...100, def: 0.0)
                        }
                        
                        Divider()
                        
                        Group {
                            sectionTitle("DETAIL & EFFECTS (선명도 및 효과)")
                            sliderItem("선명도 (Sharpness)", val: $sharpness, range: 0.0...3.0, def: 0.0)
                            sliderItem("비네팅 (Vignette)", val: $vignette, range: 0.0...2.0, def: 0.0)
                            sliderItem("세피아 필터 (Sepia)", val: $sepia, range: 0.0...1.0, def: 0.0)
                        }
                    }
                    .padding(16)
                }
                
                Divider()
                
                HStack {
                    Button("전체 초기화") { resetAll() }
                    Spacer()
                    Button("원본 해상도로 저장") { saveFullRes() }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                }
                .padding(14)
                .background(.regularMaterial)
            }
            .frame(width: 350)
        }
        .onAppear {
            if let cg = FileProcessor.loadRawCGImage(from: fileURL) {
                pixelSize = CGSize(width: cg.width, height: cg.height)
                originalNSImage = NSImage(cgImage: cg, size: pixelSize)
            }
            updatePreview()
        }
    }
    
    func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundColor(.orange)
    }
    
    func sliderItem(_ title: String, val: Binding<Double>, range: ClosedRange<Double>, def: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption.bold())
                Spacer()
                Text(String(format: "%.2f", val.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                Button(action: { val.wrappedValue = def; updatePreview() }) {
                    Image(systemName: "arrow.counterclockwise").font(.caption2)
                }.buttonStyle(.plain)
            }
            Slider(value: val, in: range)
                .tint(.orange)
                .onChange(of: val.wrappedValue) { _ in updatePreview() }
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
        
        // 1. 노출
        if abs(exposure) > 0.001 {
            let f = CIFilter.exposureAdjust()
            f.inputImage = current
            f.ev = Float(exposure)
            if let out = f.outputImage { current = out }
        }
        
        // 2. 하이라이트 & 그림자
        if abs(highlights - 1.0) > 0.001 || abs(shadows) > 0.001 {
            let f = CIFilter.highlightShadowAdjust()
            f.inputImage = current
            f.highlightAmount = Float(highlights)
            f.shadowAmount = Float(shadows)
            if let out = f.outputImage { current = out }
        }
        
        // 3. 휘도(Brilliance) & 블랙포인트 (감마 및 톤 조정)
        if abs(brilliance) > 0.001 {
            let f = CIFilter.gammaAdjust()
            f.inputImage = current
            f.power = Float(pow(2.0, -brilliance * 0.8))
            if let out = f.outputImage { current = out }
        }
        
        // 4. 밝기 / 대비 / 채도
        if abs(brightness) > 0.001 || abs(contrast - 1.0) > 0.001 || abs(saturation - 1.0) > 0.001 || abs(blackPoint) > 0.001 {
            let f = CIFilter.colorControls()
            f.inputImage = current
            f.brightness = Float(brightness - blackPoint * 0.5)
            f.contrast = Float(contrast + blackPoint)
            f.saturation = Float(saturation)
            if let out = f.outputImage { current = out }
        }
        
        // 5. 생동감 (Vibrance)
        if abs(vibrance) > 0.001 {
            let f = CIFilter.vibrance()
            f.inputImage = current
            f.amount = Float(vibrance)
            if let out = f.outputImage { current = out }
        }
        
        // 6. 색온도 & 색조
        if abs(warmth) > 1.0 || abs(tint) > 0.5 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = current
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: 6500 - CGFloat(warmth), y: CGFloat(tint))
            if let out = f.outputImage { current = out }
        }
        
        // 7. 선명도
        if sharpness > 0.001 {
            let f = CIFilter.sharpenLuminance()
            f.inputImage = current
            f.sharpness = Float(sharpness)
            if let out = f.outputImage { current = out }
        }
        
        // 8. 비네팅
        if vignette > 0.001 {
            let f = CIFilter.vignette()
            f.inputImage = current
            f.intensity = Float(vignette)
            f.radius = 1.5
            if let out = f.outputImage { current = out }
        }
        
        // 9. 세피아
        if sepia > 0.001 {
            let f = CIFilter.sepiaTone()
            f.inputImage = current
            f.intensity = Float(sepia)
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
            FileProcessor.saveCGImage(cgImg, to: outURL, formatExt: ext, quality: 0.95)
            FileProcessor.showToast("원본 화질 보정 완료: \(outURL.lastPathComponent)")
            NSApp.keyWindow?.close()
        }
    }
}

// MARK: - 2. Redact(모자이크/블러/가리기) & Crop(자르기) 통합 스튜디오 (100% 원본 픽셀 보존, 여백 제로)
enum RedactStyle: String, CaseIterable {
    case pixelate = "픽셀 모자이크"
    case blur = "블러 (흐림)"
    case blackBox = "검은 박스"
}

struct RedactItem: Identifiable {
    let id = UUID()
    var normalizedRect: CGRect // 0.0 ~ 1.0 비율 좌표 (창 크기나 줌에 영향받지 않고 원본 해상도에 정확히 매칭)
    var style: RedactStyle
}

struct RedactCropStudioView: View {
    let fileURL: URL
    @State var mode: Int // 0 = Redact(가리기), 1 = Crop(자르기)
    @State private var redactStyle: RedactStyle = .pixelate
    @State private var strength: Double = 30.0
    @State private var redactItems: [RedactItem] = []
    @State private var activeDragRect: CGRect? = nil
    
    // Crop 영역 (0.0 ~ 1.0 정규화 좌표)
    @State private var cropRect: CGRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    @State private var zoomScale: CGFloat = 1.0
    @State private var rawCGImage: CGImage? = nil
    
    let ciContext = CIContext()
    
    var body: some View {
        VStack(spacing: 0) {
            // 상단 툴바
            HStack(spacing: 16) {
                Picker("모드", selection: $mode) {
                    Text("👁️ 가리기 / 모자이크 (Redact)").tag(0)
                    Text("✂️ 이미지 자르기 (Crop)").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
                
                if mode == 0 {
                    Picker("스타일", selection: $redactStyle) {
                        ForEach(RedactStyle.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .frame(width: 180)
                    
                    HStack(spacing: 6) {
                        Text("강도").font(.caption)
                        Slider(value: $strength, in: 10...80).frame(width: 90).tint(.orange)
                    }
                    
                    Button("실행 취소(Undo)") {
                        if !redactItems.isEmpty { redactItems.removeLast() }
                    }.disabled(redactItems.isEmpty)
                    
                    Button("초기화") { redactItems.removeAll() }.disabled(redactItems.isEmpty)
                } else {
                    HStack(spacing: 8) {
                        Text("비율 프리셋:").font(.caption)
                        Button("전체") { cropRect = CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0) }
                        Button("1:1") { setAspectCrop(1.0) }
                        Button("16:9") { setAspectCrop(16.0 / 9.0) }
                        Button("4:3") { setAspectCrop(4.0 / 3.0) }
                        Text("(이미지 위를 마우스로 드래그해 자를 영역을 지정하세요)").font(.caption).foregroundColor(.orange)
                    }
                }
                
                Spacer()
                
                // 줌 컨트롤
                HStack(spacing: 6) {
                    Button(action: { zoomScale = max(0.25, zoomScale - 0.25) }) { Image(systemName: "minus.magnifyingglass") }
                    Text("\(Int(zoomScale * 100))%").font(.caption.monospacedDigit()).frame(width: 44)
                    Button(action: { zoomScale = min(4.0, zoomScale + 0.25) }) { Image(systemName: "plus.magnifyingglass") }
                    Button("맞춤") { zoomScale = 1.0 }.font(.caption)
                }
            }
            .padding(12)
            .background(.regularMaterial)
            
            // 중앙 캔버스 (여백 없이 이미지 비율에 정확히 맞춘 작업대)
            GeometryReader { outerGeo in
                ScrollView([.horizontal, .vertical]) {
                    let displaySize = calculateFitSize(in: outerGeo.size, scale: zoomScale)
                    
                    ZStack(alignment: .topLeading) {
                        if let cg = rawCGImage {
                            Image(nsImage: NSImage(cgImage: cg, size: displaySize))
                                .resizable()
                                .frame(width: displaySize.width, height: displaySize.height)
                        }
                        
                        // 가리기(Redact) 박스 표시
                        ForEach(redactItems) { item in
                            let r = CGRect(
                                x: item.normalizedRect.origin.x * displaySize.width,
                                y: item.normalizedRect.origin.y * displaySize.height,
                                width: item.normalizedRect.width * displaySize.width,
                                height: item.normalizedRect.height * displaySize.height
                            )
                            redactOverlayView(rect: r, style: item.style)
                        }
                        
                        // 현재 드래그 중인 가리기 박스
                        if mode == 0, let drag = activeDragRect {
                            redactOverlayView(rect: drag, style: redactStyle)
                        }
                        
                        // 자르기(Crop) 모드일 때 자를 영역 표시
                        if mode == 1 {
                            let cRect = CGRect(
                                x: cropRect.origin.x * displaySize.width,
                                y: cropRect.origin.y * displaySize.height,
                                width: cropRect.width * displaySize.width,
                                height: cropRect.height * displaySize.height
                            )
                            ZStack(alignment: .topLeading) {
                                Color.black.opacity(0.55)
                                    .frame(width: displaySize.width, height: displaySize.height)
                                
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: cRect.width, height: cRect.height)
                                    .overlay(
                                        ZStack {
                                            Rectangle().stroke(Color.yellow, lineWidth: 2.5)
                                            // 3분할 가이드라인
                                            VStack { Spacer(); Divider().background(Color.white); Spacer(); Divider().background(Color.white); Spacer() }
                                            HStack { Spacer(); Divider().background(Color.white); Spacer(); Divider().background(Color.white); Spacer() }
                                        }
                                    )
                                    .position(x: cRect.midX, y: cRect.midY)
                            }
                        }
                    }
                    .frame(width: displaySize.width, height: displaySize.height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { val in
                                let clampedStart = CGPoint(
                                    x: max(0, min(displaySize.width, val.startLocation.x)),
                                    y: max(0, min(displaySize.height, val.startLocation.y))
                                )
                                let clampedCur = CGPoint(
                                    x: max(0, min(displaySize.width, val.location.x)),
                                    y: max(0, min(displaySize.height, val.location.y))
                                )
                                let rect = CGRect(
                                    x: min(clampedStart.x, clampedCur.x),
                                    y: min(clampedStart.y, clampedCur.y),
                                    width: abs(clampedCur.x - clampedStart.x),
                                    height: abs(clampedCur.y - clampedStart.y)
                                )
                                if mode == 0 {
                                    activeDragRect = rect
                                } else {
                                    cropRect = CGRect(
                                        x: rect.origin.x / displaySize.width,
                                        y: rect.origin.y / displaySize.height,
                                        width: max(0.02, rect.width / displaySize.width),
                                        height: max(0.02, rect.height / displaySize.height)
                                    )
                                }
                            }
                            .onEnded { _ in
                                if mode == 0, let drag = activeDragRect, drag.width > 4, drag.height > 4 {
                                    let norm = CGRect(
                                        x: drag.origin.x / displaySize.width,
                                        y: drag.origin.y / displaySize.height,
                                        width: drag.width / displaySize.width,
                                        height: drag.height / displaySize.height
                                    )
                                    redactItems.append(RedactItem(normalizedRect: norm, style: redactStyle))
                                }
                                activeDragRect = nil
                            }
                    )
                    .frame(
                        minWidth: max(outerGeo.size.width, displaySize.width + 40),
                        minHeight: max(outerGeo.size.height, displaySize.height + 40)
                    )
                }
                .background(Color(white: 0.14))
            }
            
            // 하단 상태 표시 및 원본 저장 버튼
            HStack {
                if let cg = rawCGImage {
                    let outW = mode == 1 ? Int(CGFloat(cg.width) * cropRect.width) : cg.width
                    let outH = mode == 1 ? Int(CGFloat(cg.height) * cropRect.height) : cg.height
                    Text("출력 해상도: \(outW) × \(outH) px (화질 손실 및 여백 없음)")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(mode == 1 ? "자르기 적용 및 원본 화질 저장" : "가리기 적용 및 원본 화질 저장") {
                    saveExactPixelImage()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(14)
            .background(.regularMaterial)
        }
        .onAppear {
            rawCGImage = FileProcessor.loadRawCGImage(from: fileURL)
        }
    }
    
    @ViewBuilder
    func redactOverlayView(rect: CGRect, style: RedactStyle) -> some View {
        Group {
            switch style {
            case .blackBox:
                Rectangle().fill(Color.black)
            case .blur:
                Rectangle().fill(.ultraThinMaterial).overlay(Rectangle().stroke(Color.white.opacity(0.6), lineWidth: 1))
            case .pixelate:
                ZStack {
                    Rectangle().fill(Color.orange.opacity(0.35))
                    Text("MOSAIC").font(.system(size: 10, weight: .black)).foregroundColor(.white)
                }
                .overlay(Rectangle().stroke(Color.orange, lineWidth: 1.5))
            }
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
    }
    
    func calculateFitSize(in container: CGSize, scale: CGFloat) -> CGSize {
        guard let cg = rawCGImage, cg.width > 0, cg.height > 0 else {
            return CGSize(width: 600, height: 400)
        }
        let imgW = CGFloat(cg.width)
        let imgH = CGFloat(cg.height)
        let availW = max(300, container.width - 40)
        let availH = max(300, container.height - 40)
        let ratio = min(availW / imgW, availH / imgH)
        return CGSize(width: imgW * ratio * scale, height: imgH * ratio * scale)
    }
    
    func setAspectCrop(_ targetAspect: CGFloat) {
        guard let cg = rawCGImage else { return }
        let imgAspect = CGFloat(cg.width) / CGFloat(cg.height)
        var w: CGFloat = 0.8
        var h: CGFloat = 0.8
        if targetAspect > imgAspect {
            h = w * (imgAspect / targetAspect)
        } else {
            w = h * (targetAspect / imgAspect)
        }
        cropRect = CGRect(x: (1.0 - w) / 2.0, y: (1.0 - h) / 2.0, width: w, height: h)
    }
    
    // 원본 픽셀에 직접 필터/자르기를 연산하여 여백 없이 100% 원본 화질로 저장
    func saveExactPixelImage() {
        guard let cg = rawCGImage else { return }
        let fullW = CGFloat(cg.width)
        let fullH = CGFloat(cg.height)
        var ciImage = CIImage(cgImage: cg)
        
        // 1. 가리기(Redact) 영역들을 원본 픽셀 좌표계(CIImage는 좌하단이 원점)에 정확히 합성
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
            case .blackBox:
                patch = CIImage(color: .black).cropped(to: pxRect)
            case .pixelate:
                let f = CIFilter.pixellate()
                f.inputImage = ciImage
                f.scale = Float(max(12.0, ( max(fullW, fullH) / 1000.0 ) * strength))
                patch = (f.outputImage ?? ciImage).cropped(to: pxRect)
            case .blur:
                let f = CIFilter.gaussianBlur()
                f.inputImage = ciImage.clampedToExtent()
                f.radius = Float(max(15.0, ( max(fullW, fullH) / 1000.0 ) * strength))
                patch = (f.outputImage ?? ciImage).cropped(to: pxRect)
            }
            ciImage = patch.composited(over: ciImage)
        }
        
        // 2. 자르기(Crop) 모드일 경우 정확한 픽셀 영역만 잘라냄
        if mode == 1 {
            let cropPx = CGRect(
                x: cropRect.origin.x * fullW,
                y: (1.0 - cropRect.origin.y - cropRect.height) * fullH,
                width: cropRect.width * fullW,
                height: cropRect.height * fullH
            ).intersection(ciImage.extent)
            
            if !cropPx.isEmpty {
                ciImage = ciImage.cropped(to: cropPx)
            }
        }
        
        let ext = fileURL.pathExtension.isEmpty ? "png" : fileURL.pathExtension
        let suffix = mode == 1 ? "_cropped" : "_redacted"
        let outURL = FileProcessor.uniqueOutputURL(for: fileURL, newExt: ext, suffix: suffix)
        
        if let outCG = ciContext.createCGImage(ciImage, from: ciImage.extent) {
            FileProcessor.saveCGImage(outCG, to: outURL, formatExt: ext, quality: 0.96)
            FileProcessor.showToast("원본 화질 저장 완료: \(outURL.lastPathComponent)")
            NSApp.keyWindow?.close()
        }
    }
}

// MARK: - 3. 배경 추가 창 (Add BG)
struct AddBGView: View {
    let fileURL: URL
    @State private var selectedPreset = 0
    @State private var paddingRatio: CGFloat = 0.12
    
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
            ZStack {
                LinearGradient(colors: gradients[selectedPreset], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .cornerRadius(16)
                if let img = NSImage(contentsOf: fileURL) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(10)
                        .shadow(color: .black.opacity(0.32), radius: 18, x: 0, y: 10)
                        .padding(450 * paddingRatio)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
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
                Button("고화질 배경 합성 저장") { saveImageWithBG() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
        }
        .padding(20)
    }
    
    @MainActor
    func saveImageWithBG() {
        let baseSize: CGFloat = 1800
        let renderView = ZStack {
            LinearGradient(colors: gradients[selectedPreset], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let img = NSImage(contentsOf: fileURL) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.35), radius: 30, x: 0, y: 16)
                    .padding(baseSize * paddingRatio)
            }
        }.frame(width: baseSize, height: baseSize * 0.8)
        
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

// MARK: - 4. 오디오 및 영상 편집 스튜디오 (FFmpeg + AVFoundation 하이브리드 지원)
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
    @State private var duration: Double = 30.0
    
    let sampleBars: [CGFloat] = AudioStudioView.makeSampleBars()
    
    static func makeSampleBars() -> [CGFloat] {
        var result: [CGFloat] = []
        for i in 0..<70 {
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
            Toggle("Trim silent ends automatically (앞뒤 무음 자동 제거)", isOn: $trimSilence).font(.caption)
            Divider()
            channelAndVolumeSection
            bleepSection
            Spacer()
            bottomButtonsSection
        }
        .padding(20)
        .onAppear {
            if initialMode == "tool_audio_bleep" { enableBleep = true }
            loadAudioDuration()
        }
    }
    
    var headerSection: some View {
        HStack {
            Text("Audio & Video Trim Studio").font(.headline)
            Spacer()
            let selectedSec = duration * abs(endRatio - startRatio)
            Text(String(format: "선택 구간: %.2f초 (전체 %.2f초)", selectedSec, duration))
                .font(.caption.monospacedDigit())
                .foregroundColor(.orange)
        }
    }
    
    var waveformSection: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.orange.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange, lineWidth: 1.5))
            
            HStack(spacing: 3) {
                ForEach(0..<sampleBars.count, id: \.self) { idx in
                    waveformBar(at: idx)
                }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 120)
    }
    
    func waveformBar(at idx: Int) -> some View {
        let pos = Double(idx) / Double(sampleBars.count)
        let inRange = (pos >= min(startRatio, endRatio) && pos <= max(startRatio, endRatio))
        let inBleep = enableBleep && (pos >= bleepStartRatio && pos <= bleepEndRatio)
        let barColor: Color = inBleep ? .purple : (inRange ? .orange : Color.gray.opacity(0.3))
        return Capsule()
            .fill(barColor)
            .frame(width: 5, height: 95 * sampleBars[idx])
    }
    
    var trimSlidersSection: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading) {
                Text("시작 지점: \(String(format: "%.1fs", duration * startRatio))").font(.caption.bold())
                Slider(value: $startRatio, in: 0.0...0.95).tint(.orange)
            }
            VStack(alignment: .leading) {
                Text("종료 지점: \(String(format: "%.1fs", duration * endRatio))").font(.caption.bold())
                Slider(value: $endRatio, in: 0.05...1.0).tint(.orange)
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
            .frame(width: 180)
            
            HStack {
                Text("볼륨 증폭").font(.caption)
                Slider(value: $volumePercent, in: 20...200).tint(.orange)
                Text("\(Int(volumePercent))%").font(.caption.monospacedDigit()).frame(width: 45)
            }
        }
    }
    
    var bleepSection: some View {
        HStack {
            Toggle("Bleep (특정 구간 삐- 소리 처리)", isOn: $enableBleep).font(.caption.bold())
            if enableBleep {
                Slider(value: $bleepStartRatio, in: 0.0...0.9).tint(.purple)
                Text("~")
                Slider(value: $bleepEndRatio, in: 0.05...1.0).tint(.purple)
            }
        }
    }
    
    var bottomButtonsSection: some View {
        HStack {
            Button("▶ 기본 플레이어로 미리듣기") { NSWorkspace.shared.open(fileURL) }
            Spacer()
            Button("편집 적용 및 저장") { applyAudioChanges() }
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
        let actualStart = min(startRatio, endRatio) * duration
        let actualEnd = max(startRatio, endRatio) * duration
        let outURL = FileProcessor.uniqueOutputURL(for: fileURL, newExt: fileURL.pathExtension, suffix: "_trimmed")
        
        if let ffmpeg = FileProcessor.ffmpegPath {
            var filters: [String] = ["volume=\(volumePercent / 100.0)"]
            if trimSilence {
                filters.append("silenceremove=start_periods=1:start_silence=0.2:start_threshold=-45dB")
            }
            var args = ["-y", "-ss", "\(actualStart)", "-to", "\(actualEnd)", "-i", fileURL.path]
            if isMono { args += ["-ac", "1"] }
            args += ["-af", filters.joined(separator: ","), outURL.path]
            
            FileProcessor.runShell(ffmpeg, args: args) { ok in
                if ok && FileManager.default.fileExists(atPath: outURL.path) {
                    FileProcessor.showToast("편집 저장 완료: \(outURL.lastPathComponent)")
                    NSApp.keyWindow?.close()
                } else {
                    nativeTrimFallback(startSec: actualStart, endSec: actualEnd, outURL: outURL)
                }
            }
        } else {
            nativeTrimFallback(startSec: actualStart, endSec: actualEnd, outURL: outURL)
        }
    }
    
    func nativeTrimFallback(startSec: Double, endSec: Double, outURL: URL) {
        let asset = AVURLAsset(url: fileURL)
        let ext = fileURL.pathExtension.lowercased()
        let isAudio = ["m4a", "mp3", "wav", "aac", "flac", "aiff"].contains(ext)
        let preset = isAudio ? AVAssetExportPresetAppleM4A : AVAssetExportPresetHighestQuality
        guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else { return }
        
        let finalURL = isAudio ? FileProcessor.uniqueOutputURL(for: fileURL, newExt: "m4a", suffix: "_trimmed") : outURL
        exporter.outputURL = finalURL
        exporter.outputFileType = isAudio ? .m4a : .mp4
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: startSec, preferredTimescale: 600),
            duration: CMTime(seconds: max(0.5, endSec - startSec), preferredTimescale: 600)
        )
        exporter.exportAsynchronously {
            DispatchQueue.main.async {
                FileProcessor.showToast("구간 자르기 완료: \(finalURL.lastPathComponent)")
                NSApp.keyWindow?.close()
            }
        }
    }
}

// MARK: - 5. 압축 도구 창
struct CompressToolView: View {
    let files: [URL]
    @State private var quality: Double = 65.0
    
    var body: some View {
        VStack(spacing: 18) {
            Text("Compress \(files.count) File(s)").font(.headline)
            Text("목표 품질: \(Int(quality))% (낮을수록 파일 크기가 줄어듭니다)").font(.caption)
            Slider(value: $quality, in: 10...95).tint(.orange).padding(.horizontal)
            
            Button("압축 실행") {
                for f in files {
                    let ext = f.pathExtension.lowercased()
                    if ["jpg", "jpeg", "png", "heic", "tiff", "bmp"].contains(ext),
                       let cg = FileProcessor.loadRawCGImage(from: f) {
                        let out = FileProcessor.uniqueOutputURL(for: f, newExt: "jpg", suffix: "_compressed")
                        FileProcessor.saveCGImage(cg, to: out, formatExt: "jpg", quality: quality / 100.0)
                        FileProcessor.showToast("이미지 압축 완료: \(out.lastPathComponent)")
                    } else if let ffmpeg = FileProcessor.ffmpegPath {
                        let out = FileProcessor.uniqueOutputURL(for: f, newExt: ext, suffix: "_compressed")
                        let crf = Int(40.0 - (quality / 100.0) * 20.0)
                        FileProcessor.runShell(ffmpeg, args: ["-y", "-i", f.path, "-vcodec", "libx264", "-crf", "\(crf)", out.path]) { _ in
                            FileProcessor.showToast("미디어 압축 완료: \(out.lastPathComponent)")
                        }
                    } else {
                        let out = FileProcessor.uniqueOutputURL(for: f, newExt: "mp4", suffix: "_compressed")
                        let asset = AVURLAsset(url: f)
                        if let exp = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality) {
                            exp.outputURL = out
                            exp.outputFileType = .mp4
                            exp.exportAsynchronously {
                                FileProcessor.showToast("미디어 압축 완료: \(out.lastPathComponent)")
                            }
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

// MARK: - 6. 메타데이터 확인 및 삭제 창
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
            metaDict["Info"] = "표시할 EXIF 정보가 없거나 일반 문서/미디어 파일입니다."
        }
    }
}

// MARK: - 앱 델리게이트 및 글로벌 드래그 감지
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var wheelPanel: NSPanel!
    var wheelCenterPoint: NSPoint = .zero
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "MyTangerine")
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "🍊 MyTangerine 2.0 (Apple Silicon Native)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Shift + 드래그: 포맷 변환 / Option+Shift + 드래그: 편집 도구 / Control + 드래그: 빠른 액션", action: nil, keyEquivalent: ""))
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
        return (pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
