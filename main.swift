import Cocoa
import SwiftUI
import AVFoundation
import AVKit
import CoreImage
import CoreImage.CIFilterBuiltins
import PDFKit
import Vision
import UniformTypeIdentifiers
import AudioToolbox

// MARK: - 1. 작업 진행률(Progress) 매니저 (메뉴바 실시간 % 연동)
struct ActiveJob: Identifiable {
    let id: UUID
    let title: String
    var progress: Double // 0.0 ~ 1.0
}

class JobProgressManager: ObservableObject {
    static let shared = JobProgressManager()
    @Published var jobs: [ActiveJob] = []
    var onUpdate: (() -> Void)?
    
    var overallProgress: Double? {
        guard !jobs.isEmpty else { return nil }
        let sum = jobs.reduce(0.0) { $0 + $1.progress }
        return sum / Double(jobs.count)
    }
    
    func startJob(title: String) -> UUID {
        let id = UUID()
        DispatchQueue.main.async {
            self.jobs.append(ActiveJob(id: id, title: title, progress: 0.0))
            self.onUpdate?()
        }
        return id
    }
    
    func updateJob(id: UUID, progress: Double) {
        DispatchQueue.main.async {
            if let idx = self.jobs.firstIndex(where: { $0.id == id }) {
                self.jobs[idx].progress = min(0.99, max(0.0, progress))
                self.onUpdate?()
            }
        }
    }
    
    func finishJob(id: UUID) {
        DispatchQueue.main.async {
            self.jobs.removeAll { $0.id == id }
            self.onUpdate?()
        }
    }
}

// MARK: - 2. 글로벌 상태 및 휠 메뉴 모델
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
        let audioExts = ["mp3", "m4a", "wav", "flac", "ogg", "aac", "aiff", "caf"]
        
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
                    WheelItem(title: "CHANNELS", icon: "speaker.wave.3", actionKey: "tool_audio_channels"),
                    WheelItem(title: "COMPRESS", icon: "arrow.down.right.and.arrow.up.left", actionKey: "tool_compress"),
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

// MARK: - 3. 파일 처리 및 실시간 진행률(%) 파싱 엔진
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
    
    static func mediaDurationSeconds(for url: URL) -> Double {
        let asset = AVURLAsset(url: url)
        let sec = CMTimeGetSeconds(asset.duration)
        return (sec.isFinite && sec > 0) ? sec : 0
    }
    
    // FFmpeg 실행 중 time=00:00:00.00 로그를 실시간 추적하여 메뉴바 퍼센트(%) 업데이트
    static func runFFmpegWithProgress(args: [String], totalDuration: Double, jobTitle: String, completion: @escaping (Bool) -> Void) {
        guard let ffmpeg = ffmpegPath else {
            completion(false)
            return
        }
        let jobID = JobProgressManager.shared.startJob(title: jobTitle)
        
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: ffmpeg)
            task.arguments = args
            
            let pipe = Pipe()
            task.standardError = pipe
            
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
                if totalDuration > 0, let currentSec = parseFFmpegTime(from: line) {
                    let ratio = min(0.99, max(0.01, currentSec / totalDuration))
                    JobProgressManager.shared.updateJob(id: jobID, progress: ratio)
                }
            }
            
            do {
                try task.run()
                task.waitUntilExit()
                pipe.fileHandleForReading.readabilityHandler = nil
                JobProgressManager.shared.finishJob(id: jobID)
                DispatchQueue.main.async { completion(task.terminationStatus == 0) }
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                JobProgressManager.shared.finishJob(id: jobID)
                DispatchQueue.main.async { completion(false) }
            }
        }
    }
    
    static func parseFFmpegTime(from log: String) -> Double? {
        guard let range = log.range(of: "time=") else { return nil }
        let sub = log[range.upperBound...]
        let timeStr = String(sub.prefix(11))
        let parts = timeStr.split(separator: ":")
        guard parts.count == 3,
              let h = Double(parts[0]),
              let m = Double(parts[1]),
              let s = Double(parts[2].split(separator: " ").first ?? "") else { return nil }
        return h * 3600.0 + m * 60.0 + s
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
            ToolWindowManager.shared.showMediaStudioWindow(url: first, initialTab: actionKey)
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
    
    static func convertMediaHybrid(_ file: URL, to ext: String) {
        let out = uniqueOutputURL(for: file, newExt: ext)
        let duration = mediaDurationSeconds(for: file)
        let jobTitle = "\(file.lastPathComponent) → \(ext.uppercased())"
        
        if ffmpegPath != nil {
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
            
            runFFmpegWithProgress(args: args, totalDuration: duration, jobTitle: jobTitle) { ok in
                if ok && FileManager.default.fileExists(atPath: out.path) {
                    showToast("\(ext.uppercased()) 변환 완료: \(out.lastPathComponent)")
                } else {
                    try? FileManager.default.removeItem(at: out)
                    avAssetConvertWithProgress(file: file, to: ext, outURL: out, jobTitle: jobTitle)
                }
            }
        } else {
            avAssetConvertWithProgress(file: file, to: ext, outURL: out, jobTitle: jobTitle)
        }
    }
    
    static func avAssetConvertWithProgress(file: URL, to ext: String, outURL: URL, jobTitle: String) {
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
        
        let jobID = JobProgressManager.shared.startJob(title: jobTitle)
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            JobProgressManager.shared.updateJob(id: jobID, progress: Double(exporter.progress))
        }
        
        exporter.exportAsynchronously {
            DispatchQueue.main.async {
                timer.invalidate()
                JobProgressManager.shared.finishJob(id: jobID)
                if exporter.status == .completed {
                    if ["wav", "aiff", "flac", "caf"].contains(ext) {
                        let finalURL = uniqueOutputURL(for: file, newExt: ext)
                        let fmt = ext == "wav" ? "WAVE" : (ext == "aiff" ? "AIFF" : (ext == "caf" ? "caff" : "flac"))
                        let dat = ext == "flac" ? "flac" : (ext == "wav" ? "LEI16" : (ext == "caf" ? "aac" : "BEI16"))
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
            showToast("메타데이터 제거 완료: \(out.lastPathComponent)")
        } else if ffmpegPath != nil {
            let dur = mediaDurationSeconds(for: file)
            runFFmpegWithProgress(args: ["-y", "-i", file.path, "-map_metadata", "-1", "-c", "copy", out.path], totalDuration: dur, jobTitle: "메타데이터 삭제") { _ in
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

// MARK: - 4. 마우스 휠 확대/축소 감지용 헬퍼 뷰 (ScrollWheel Zoom + 중앙 정렬)
struct ScrollWheelCatcher: NSViewRepresentable {
    var onScroll: (CGFloat) -> Void
    
    func makeNSView(context: Context) -> ScrollWheelNSView {
        let v = ScrollWheelNSView()
        v.onScroll = onScroll
        return v
    }
    
    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onScroll = onScroll
    }
    
    class ScrollWheelNSView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        override func scrollWheel(with event: NSEvent) {
            let delta = event.scrollingDeltaY
            if abs(delta) > 0.01 {
                onScroll?(delta)
            }
        }
    }
}

// MARK: - 5. 원형 다이얼 휠 UI
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

// MARK: - 6. 도구 창 매니저
class ToolWindowManager {
    static let shared = ToolWindowManager()
    var activeWindows: [NSWindow] = []
    var bannerWindow: NSPanel?
    
    func openWindow<V: View>(title: String, view: V, size: NSSize, minSize: NSSize = NSSize(width: 720, height: 520)) {
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
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - 200, y: screen.frame.maxY - 90))
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
        openWindow(title: "Pro Photo Editor — \(url.lastPathComponent)", view: EditPhotoView(fileURL: url), size: NSSize(width: 1120, height: 780), minSize: NSSize(width: 860, height: 600))
    }
    
    func showRedactCropWindow(url: URL, initialTab: Int) {
        openWindow(title: "Redact & Crop Studio — \(url.lastPathComponent)", view: RedactCropStudioView(fileURL: url, mode: initialTab), size: NSSize(width: 1100, height: 780), minSize: NSSize(width: 860, height: 600))
    }
    
    func showAddBGWindow(url: URL) {
        openWindow(title: "Add Background — \(url.lastPathComponent)", view: AddBGView(fileURL: url), size: NSSize(width: 840, height: 680))
    }
    
    func showCompressWindow(urls: [URL]) {
        openWindow(title: "Compress Files", view: CompressToolView(files: urls), size: NSSize(width: 460, height: 320), minSize: NSSize(width: 400, height: 280))
    }
    
    func showMetadataWindow(url: URL) {
        openWindow(title: "File Metadata", view: MetadataToolView(fileURL: url), size: NSSize(width: 560, height: 520))
    }
    
    func showMediaStudioWindow(url: URL, initialTab: String) {
        openWindow(title: "QuickTime & Multi-Channel Studio — \(url.lastPathComponent)", view: ProMediaStudioView(fileURL: url, initialMode: initialTab), size: NSSize(width: 1060, height: 800), minSize: NSSize(width: 900, height: 680))
    }
}

// MARK: - 7. 전문가 사진 보정 창 (정중앙 배치 + 마우스 휠 확대/축소 + 드래그 이동)
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
    
    // 줌 & 패닝 상태
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
            // 좌측: 중앙 정렬 & 마우스 휠 줌 & 드래그 패닝 캔버스
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text("\(Int(pixelSize.width)) × \(Int(pixelSize.height)) px")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                    
                    Text("💡 마우스 휠: 확대/축소 | 드래그: 화면 이동")
                        .font(.caption)
                        .foregroundColor(.orange)
                    
                    Spacer()
                    
                    Button(action: { adjustZoom(by: -0.25) }) { Image(systemName: "minus.magnifyingglass") }
                    Text("\(Int(zoomScale * 100))%").font(.caption.monospacedDigit()).frame(width: 48)
                    Button(action: { adjustZoom(by: 0.25) }) { Image(systemName: "plus.magnifyingglass") }
                    Button("화면 맞춤(중앙)") {
                        withAnimation(.easeOut(duration: 0.15)) {
                            zoomScale = 1.0
                            panOffset = .zero
                            lastPanOffset = .zero
                        }
                    }.font(.caption)
                    
                    Toggle("원본 비교", isOn: $showOriginal)
                        .toggleStyle(.button)
                        .font(.caption)
                }
                .padding(10)
                .background(.regularMaterial)
                
                GeometryReader { geo in
                    let fitSize = calculateFitSize(in: geo.size)
                    ZStack {
                        Color(white: 0.11)
                        
                        if let img = (showOriginal ? originalNSImage : previewImage) {
                            Image(nsImage: img)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: fitSize.width * zoomScale, height: fitSize.height * zoomScale)
                                .shadow(color: .black.opacity(0.5), radius: 16)
                                .offset(panOffset)
                                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        }
                        
                        ScrollWheelCatcher { delta in
                            let step = delta * 0.012
                            zoomScale = min(8.0, max(0.25, zoomScale + step))
                        }
                        .allowsHitTesting(false)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { val in
                                panOffset = CGSize(
                                    width: lastPanOffset.width + val.translation.width,
                                    height: lastPanOffset.height + val.translation.height
                                )
                            }
                            .onEnded { _ in
                                lastPanOffset = panOffset
                            }
                    )
                }
            }
            .frame(minWidth: 560, maxWidth: .infinity)
            
            // 우측: 14종 슬라이더
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
                    }
                    .padding(16)
                }
                Divider()
                HStack {
                    Button("전체 초기화") { resetAll() }
                    Spacer()
                    Button("원본 화질 저장") { saveFullRes() }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                }
                .padding(14)
                .background(.regularMaterial)
            }
            .frame(width: 340)
        }
        .onAppear {
            if let cg = FileProcessor.loadRawCGImage(from: fileURL) {
                pixelSize = CGSize(width: cg.width, height: cg.height)
                originalNSImage = NSImage(cgImage: cg, size: pixelSize)
            }
            updatePreview()
        }
    }
    
    func adjustZoom(by delta: CGFloat) {
        zoomScale = min(8.0, max(0.25, zoomScale + delta))
    }
    
    func calculateFitSize(in container: CGSize) -> CGSize {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return CGSize(width: 500, height: 400) }
        let availW = max(200, container.width - 48)
        let availH = max(200, container.height - 48)
        let ratio = min(availW / pixelSize.width, availH / pixelSize.height)
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
                Button(action: { val.wrappedValue = def; updatePreview() }) {
                    Image(systemName: "arrow.counterclockwise").font(.caption2)
                }.buttonStyle(.plain)
            }
            Slider(value: val, in: range).tint(.orange).onChange(of: val.wrappedValue) { _ in updatePreview() }
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
            FileProcessor.saveCGImage(cgImg, to: outURL, formatExt: ext, quality: 0.95)
            FileProcessor.showToast("원본 화질 보정 완료: \(outURL.lastPathComponent)")
            NSApp.keyWindow?.close()
        }
    }
}

// MARK: - 8. Redact & 8방향 핸들 Crop 스튜디오 (정중앙 배치 + 휠 줌 + 드래그 패닝 + 8방향 모서리/변 조절)
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
    @State var mode: Int // 0 = Redact, 1 = Crop, 2 = Pan(화면 이동)
    @State private var redactStyle: RedactStyle = .pixelate
    @State private var strength: Double = 30.0
    @State private var redactItems: [RedactItem] = []
    @State private var activeDragRect: CGRect? = nil
    
    // Crop 정규화 영역 (0.0 ~ 1.0)
    @State private var cropRect: CGRect = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
    @State private var initialCropOnDrag: CGRect? = nil
    @State private var activeCropHandle: CropHandle? = nil
    
    // Zoom & Pan (항상 정중앙 기준)
    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero
    @State private var isPanMode: Bool = false
    
    @State private var rawCGImage: CGImage? = nil
    let ciContext = CIContext()
    
    var body: some View {
        VStack(spacing: 0) {
            // 상단 컨트롤 바
            HStack(spacing: 14) {
                Picker("작업", selection: $mode) {
                    Text("👁️ 가리기 (Redact)").tag(0)
                    Text("✂️ 자르기 (Crop)").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
                
                Toggle("✋ 화면 이동(Pan)", isOn: $isPanMode)
                    .toggleStyle(.button)
                    .tint(isPanMode ? .orange : .secondary)
                
                Divider().frame(height: 18)
                
                if mode == 0 {
                    Picker("스타일", selection: $redactStyle) {
                        ForEach(RedactStyle.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
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
                
                // 확대/축소 및 중앙 정렬 버튼
                HStack(spacing: 6) {
                    Button(action: { zoomScale = max(0.25, zoomScale - 0.25) }) { Image(systemName: "minus.magnifyingglass") }
                    Text("\(Int(zoomScale * 100))%").font(.caption.monospacedDigit()).frame(width: 44)
                    Button(action: { zoomScale = min(8.0, zoomScale + 0.25) }) { Image(systemName: "plus.magnifyingglass") }
                    Button("중앙 맞춤") {
                        withAnimation(.easeOut(duration: 0.15)) {
                            zoomScale = 1.0; panOffset = .zero; lastPanOffset = .zero
                        }
                    }.font(.caption)
                }
            }
            .padding(10)
            .background(.regularMaterial)
            
            // 중앙 뷰포트 (확대/축소 시에도 항상 정중앙 유지)
            GeometryReader { outerGeo in
                let baseFitSize = calculateFitSize(in: outerGeo.size)
                let scaledSize = CGSize(width: baseFitSize.width * zoomScale, height: baseFitSize.height * zoomScale)
                
                ZStack {
                    Color(white: 0.12)
                    
                    // 이미지 & 오버레이 컨테이너 (정중앙 배치 + panOffset)
                    ZStack(alignment: .topLeading) {
                        if let cg = rawCGImage {
                            Image(nsImage: NSImage(cgImage: cg, size: scaledSize))
                                .resizable()
                                .interpolation(.high)
                                .frame(width: scaledSize.width, height: scaledSize.height)
                        }
                        
                        // Redact 항목들
                        ForEach(redactItems) { item in
                            let r = CGRect(
                                x: item.normalizedRect.origin.x * scaledSize.width,
                                y: item.normalizedRect.origin.y * scaledSize.height,
                                width: item.normalizedRect.width * scaledSize.width,
                                height: item.normalizedRect.height * scaledSize.height
                            )
                            redactOverlayView(rect: r, style: item.style)
                        }
                        
                        if mode == 0, let drag = activeDragRect {
                            redactOverlayView(rect: drag, style: redactStyle)
                        }
                        
                        // Crop 오버레이 + 8방향(모서리 4 + 상하좌우 변 4) 조절 핸들
                        if mode == 1 {
                            cropOverlayWith8Handles(canvasSize: scaledSize)
                        }
                    }
                    .frame(width: scaledSize.width, height: scaledSize.height)
                    .contentShape(Rectangle())
                    .gesture(canvasDragGesture(canvasSize: scaledSize))
                    .offset(panOffset)
                    .position(x: outerGeo.size.width / 2, y: outerGeo.size.height / 2)
                    
                    // 마우스 휠 확대/축소 수신기
                    ScrollWheelCatcher { delta in
                        let step = delta * 0.012
                        zoomScale = min(8.0, max(0.25, zoomScale + step))
                    }
                    .allowsHitTesting(false)
                }
                .frame(width: outerGeo.size.width, height: outerGeo.size.height)
                .clipped()
            }
            
            // 하단 상태 바
            HStack {
                if let cg = rawCGImage {
                    let outW = mode == 1 ? Int(CGFloat(cg.width) * cropRect.width) : cg.width
                    let outH = mode == 1 ? Int(CGFloat(cg.height) * cropRect.height) : cg.height
                    Text("출력 해상도: \(outW) × \(outH) px | 휠: 확대/축소 | '화면 이동' 버튼 활성 시 드래그로 위치 이동")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(mode == 1 ? "크롭 적용 및 원본 화질 저장" : "가리기 적용 및 원본 화질 저장") {
                    saveExactPixelImage()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(12)
            .background(.regularMaterial)
        }
        .onAppear {
            rawCGImage = FileProcessor.loadRawCGImage(from: fileURL)
        }
    }
    
    // MARK: 8방향 핸들(4 모서리 + 4 변)이 포함된 크롭 UI
    @ViewBuilder
    func cropOverlayWith8Handles(canvasSize: CGSize) -> some View {
        let cRect = CGRect(
            x: cropRect.origin.x * canvasSize.width,
            y: cropRect.origin.y * canvasSize.height,
            width: cropRect.width * canvasSize.width,
            height: cropRect.height * canvasSize.height
        )
        
        ZStack(alignment: .topLeading) {
            // 바깥 어두운 마스크 영역 (Even-Odd Fill)
            Path { path in
                path.addRect(CGRect(origin: .zero, size: canvasSize))
                path.addRect(cRect)
            }
            .fill(Color.black.opacity(0.58), style: FillStyle(eoFill: true))
            
            // 크롭 테두리 및 3분할 그리드
            ZStack {
                Rectangle()
                    .stroke(Color.yellow, lineWidth: 2)
                VStack { Spacer(); Divider().background(Color.white.opacity(0.6)); Spacer(); Divider().background(Color.white.opacity(0.6)); Spacer() }
                HStack { Spacer(); Divider().background(Color.white.opacity(0.6)); Spacer(); Divider().background(Color.white.opacity(0.6)); Spacer() }
            }
            .frame(width: cRect.width, height: cRect.height)
            .position(x: cRect.midX, y: cRect.midY)
            
            // 모서리 핸들 4개 (맞닿은 두 변을 동시에 조절)
            handleKnob(at: CGPoint(x: cRect.minX, y: cRect.minY), isCorner: true)
            handleKnob(at: CGPoint(x: cRect.maxX, y: cRect.minY), isCorner: true)
            handleKnob(at: CGPoint(x: cRect.minX, y: cRect.maxY), isCorner: true)
            handleKnob(at: CGPoint(x: cRect.maxX, y: cRect.maxY), isCorner: true)
            
            // 상·하·좌·우 변 핸들 4개 (해당 변만 단독 조절)
            handleBar(at: CGPoint(x: cRect.midX, y: cRect.minY), horizontal: true)
            handleBar(at: CGPoint(x: cRect.midX, y: cRect.maxY), horizontal: true)
            handleBar(at: CGPoint(x: cRect.minX, y: cRect.midY), horizontal: false)
            handleBar(at: CGPoint(x: cRect.maxX, y: cRect.midY), horizontal: false)
        }
    }
    
    func handleKnob(at pt: CGPoint, isCorner: Bool) -> some View {
        Circle()
            .fill(Color.yellow)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
            .shadow(radius: 2)
            .position(pt)
    }
    
    func handleBar(at pt: CGPoint, horizontal: Bool) -> some View {
        Capsule()
            .fill(Color.white)
            .frame(width: horizontal ? 28 : 7, height: horizontal ? 7 : 28)
            .overlay(Capsule().stroke(Color.black, lineWidth: 1))
            .shadow(radius: 2)
            .position(pt)
    }
    
    // 드래그 제스처 (화면 이동 / Redact / 8방향 Crop 핸들 판정)
    func canvasDragGesture(canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { val in
                // 1) 화면 이동(Pan) 모드이거나 Option 키를 누른 상태면 캔버스 이동
                if isPanMode || NSEvent.modifierFlags.contains(.option) {
                    panOffset = CGSize(
                        width: lastPanOffset.width + val.translation.width,
                        height: lastPanOffset.height + val.translation.height
                    )
                    return
                }
                
                // 2) 가리기(Redact) 모드
                if mode == 0 {
                    let s = CGPoint(x: max(0, min(canvasSize.width, val.startLocation.x)),
                                    y: max(0, min(canvasSize.height, val.startLocation.y)))
                    let c = CGPoint(x: max(0, min(canvasSize.width, val.location.x)),
                                    y: max(0, min(canvasSize.height, val.location.y)))
                    activeDragRect = CGRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(c.x - s.x), height: abs(c.y - s.y))
                    return
                }
                
                // 3) 자르기(Crop) 모드: 8방향 핸들 및 내부 이동 처리
                if initialCropOnDrag == nil {
                    initialCropOnDrag = cropRect
                    activeCropHandle = detectCropHandle(at: val.startLocation, canvasSize: canvasSize)
                }
                
                guard let initRect = initialCropOnDrag else { return }
                let dx = val.translation.width / max(1, canvasSize.width)
                let dy = val.translation.height / max(1, canvasSize.height)
                let minLen: CGFloat = 0.04
                
                var minX = initRect.minX
                var maxX = initRect.maxX
                var minY = initRect.minY
                var maxY = initRect.maxY
                
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
                case .top:
                    minY = min(maxY - minLen, max(0.0, initRect.minY + dy))
                case .bottom:
                    maxY = max(minY + minLen, min(1.0, initRect.maxY + dy))
                case .left:
                    minX = min(maxX - minLen, max(0.0, initRect.minX + dx))
                case .right:
                    maxX = max(minX + minLen, min(1.0, initRect.maxX + dx))
                case .moveInside:
                    let w = initRect.width
                    let h = initRect.height
                    minX = max(0.0, min(1.0 - w, initRect.minX + dx))
                    minY = max(0.0, min(1.0 - h, initRect.minY + dy))
                    maxX = minX + w
                    maxY = minY + h
                case .none:
                    // 바깥 빈 공간을 드래그하면 새 크롭 영역 지정
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
                if isPanMode || NSEvent.modifierFlags.contains(.option) {
                    lastPanOffset = panOffset
                    return
                }
                if mode == 0, let drag = activeDragRect, drag.width > 4, drag.height > 4 {
                    let norm = CGRect(
                        x: drag.origin.x / canvasSize.width,
                        y: drag.origin.y / canvasSize.height,
                        width: drag.width / canvasSize.width,
                        height: drag.height / canvasSize.height
                    )
                    redactItems.append(RedactItem(normalizedRect: norm, style: redactStyle))
                }
                activeDragRect = nil
                initialCropOnDrag = nil
                activeCropHandle = nil
            }
    }
    
    func detectCropHandle(at pt: CGPoint, canvasSize: CGSize) -> CropHandle? {
        let cRect = CGRect(
            x: cropRect.origin.x * canvasSize.width,
            y: cropRect.origin.y * canvasSize.height,
            width: cropRect.width * canvasSize.width,
            height: cropRect.height * canvasSize.height
        )
        let r: CGFloat = 22.0 // 핸들 감지 반경
        
        // 1. 모서리 4곳 우선 감지
        if hypot(pt.x - cRect.minX, pt.y - cRect.minY) <= r { return .topLeft }
        if hypot(pt.x - cRect.maxX, pt.y - cRect.minY) <= r { return .topRight }
        if hypot(pt.x - cRect.minX, pt.y - cRect.maxY) <= r { return .bottomLeft }
        if hypot(pt.x - cRect.maxX, pt.y - cRect.maxY) <= r { return .bottomRight }
        
        // 2. 상·하·좌·우 변 감지
        if abs(pt.y - cRect.minY) <= r && pt.x >= cRect.minX && pt.x <= cRect.maxX { return .top }
        if abs(pt.y - cRect.maxY) <= r && pt.x >= cRect.minX && pt.x <= cRect.maxX { return .bottom }
        if abs(pt.x - cRect.minX) <= r && pt.y >= cRect.minY && pt.y <= cRect.maxY { return .left }
        if abs(pt.x - cRect.maxX) <= r && pt.y >= cRect.minY && pt.y <= cRect.maxY { return .right }
        
        // 3. 크롭 영역 내부 드래그 -> 박스 이동
        if cRect.contains(pt) { return .moveInside }
        return nil
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
    
    func calculateFitSize(in container: CGSize) -> CGSize {
        guard let cg = rawCGImage, cg.width > 0, cg.height > 0 else {
            return CGSize(width: 600, height: 400)
        }
        let imgW = CGFloat(cg.width)
        let imgH = CGFloat(cg.height)
        let availW = max(240, container.width - 48)
        let availH = max(240, container.height - 48)
        let ratio = min(availW / imgW, availH / imgH)
        return CGSize(width: imgW * ratio, height: imgH * ratio)
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
    
    func saveExactPixelImage() {
        guard let cg = rawCGImage else { return }
        let fullW = CGFloat(cg.width)
        let fullH = CGFloat(cg.height)
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
            case .blackBox:
                patch = CIImage(color: .black).cropped(to: pxRect)
            case .pixelate:
                let f = CIFilter.pixellate()
                f.inputImage = ciImage
                f.scale = Float(max(12.0, (max(fullW, fullH) / 1000.0) * strength))
                patch = (f.outputImage ?? ciImage).cropped(to: pxRect)
            case .blur:
                let f = CIFilter.gaussianBlur()
                f.inputImage = ciImage.clampedToExtent()
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

// MARK: - 9. QuickTime 스타일 비디오 프리뷰 + 프레임(HH:MM:SS:FF) 트림 + 다중 채널(1ch~8ch+) 오디오 스튜디오
struct VideoPlayerPreview: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView()
        v.player = player
        v.controlsStyle = .none
        v.videoGravity = .resizeAspect
        return v
    }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
    }
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
    
    // 다중 오디오 채널 상태 (1ch ~ 16ch 자동 감지)
    @Published var channelCount: Int = 2
    @Published var channelEnabled: [Bool] = [true, true]
    @Published var soloChannel: Int? = nil
    
    private var timeObserver: Any?
    private var audioEngine: AVAudioEngine?
    private var audioPlayerNode: AVAudioPlayerNode?
    private var audioFile: AVAudioFile?
    private var useAudioEngineForMultiChannel: Bool = false
    
    init(url: URL) {
        self.fileURL = url
        let ext = url.pathExtension.lowercased()
        self.isVideo = ["mp4", "mov", "m4v", "mkv", "avi", "webm"].contains(ext)
        setupMedia()
    }
    
    func setupMedia() {
        let asset = AVURLAsset(url: fileURL)
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        
        let sec = CMTimeGetSeconds(asset.duration)
        if sec.isFinite && sec > 0 {
            duration = sec
            endTime = sec
        }
        
        // 비디오 FPS 및 오디오 채널 수 정밀 감지
        if let vTrack = asset.tracks(withMediaType: .video).first {
            isVideo = true
            let rate = Double(vTrack.nominalFrameRate)
            if rate > 0 { fps = rate }
        }
        
        var detectedChannels = 0
        let aTracks = asset.tracks(withMediaType: .audio)
        for track in aTracks {
            if let desc = track.formatDescriptions.first {
                let fmtDesc = desc as! CMAudioFormatDescription
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmtDesc) {
                    detectedChannels += Int(asbd.pointee.mChannelsPerFrame)
                }
            }
        }
        if detectedChannels == 0 { detectedChannels = 2 }
        channelCount = min(16, max(1, detectedChannels))
        channelEnabled = Array(repeating: true, count: channelCount)
        
        // 오디오 전용 파일인 경우 AVAudioEngine을 구성하여 개별 채널(Ch 1..N) 실시간 뮤트/솔로 청취 지원
        if !isVideo, let af = try? AVAudioFile(forReading: fileURL) {
            self.audioFile = af
            let ch = Int(af.processingFormat.channelCount)
            if ch > 0 {
                channelCount = ch
                channelEnabled = Array(repeating: true, count: ch)
            }
            useAudioEngineForMultiChannel = true
        }
        
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0 / 60.0, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self = self else { return }
            let sec = CMTimeGetSeconds(time)
            if sec.isFinite {
                self.currentTime = sec
                if self.isPlaying && sec >= self.endTime {
                    self.pause()
                    self.seek(to: self.startTime)
                }
            }
        }
    }
    
    func togglePlay() {
        if isPlaying {
            pause()
        } else {
            if currentTime < startTime || currentTime >= endTime {
                seek(to: startTime)
            }
            play()
        }
    }
    
    func play() {
        isPlaying = true
        if useAudioEngineForMultiChannel {
            playMultiChannelAudioEngine(from: currentTime)
        } else {
            applyPlayerChannelMix()
            player.play()
        }
    }
    
    func pause() {
        isPlaying = false
        player.pause()
        audioPlayerNode?.stop()
        audioEngine?.stop()
    }
    
    func seek(to sec: Double) {
        let clamped = max(0.0, min(duration, sec))
        currentTime = clamped
        let cm = CMTime(seconds: clamped, preferredTimescale: 6000)
        player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        if useAudioEngineForMultiChannel && isPlaying {
            playMultiChannelAudioEngine(from: clamped)
        }
    }
    
    func stepFrames(_ deltaFrames: Int) {
        pause()
        let frameDur = 1.0 / max(1.0, fps)
        seek(to: currentTime + Double(deltaFrames) * frameDur)
    }
    
    func isChannelActive(_ idx: Int) -> Bool {
        if let solo = soloChannel { return solo == idx }
        guard idx < channelEnabled.count else { return true }
        return channelEnabled[idx]
    }
    
    func updateChannelRouting() {
        if useAudioEngineForMultiChannel {
            if isPlaying { playMultiChannelAudioEngine(from: currentTime) }
        } else {
            applyPlayerChannelMix()
        }
    }
    
    // AVPlayer 비디오 재생 중 오디오 트랙 볼륨/채널 제어
    private func applyPlayerChannelMix() {
        guard let item = player.currentItem else { return }
        let anyActive = (0..<channelCount).contains { isChannelActive($0) }
        player.isMuted = !anyActive
        let tracks = item.asset.tracks(withMediaType: .audio)
        if tracks.count > 1 {
            let mix = AVMutableAudioMix()
            var params: [AVMutableAudioMixInputParameters] = []
            for (idx, trk) in tracks.enumerated() {
                let p = AVMutableAudioMixInputParameters(track: trk)
                let active = idx < channelCount ? isChannelActive(idx) : true
                p.setVolume(active ? 1.0 : 0.0, at: .zero)
                params.append(p)
            }
            mix.inputParameters = params
            item.audioMix = mix
        }
    }
    
    // 다중 채널(1~8ch+) 오디오 파일에서 원하는 채널만 끄고 켜서 실시간으로 듣는 커스텀 믹서
    private func playMultiChannelAudioEngine(from startSec: Double) {
        guard let af = audioFile else { return }
        audioPlayerNode?.stop()
        audioEngine?.stop()
        
        let fmt = af.processingFormat
        let sr = fmt.sampleRate
        let totalFrames = af.length
        let startFrame = AVAudioFramePosition(max(0, min(Double(totalFrames), startSec * sr)))
        let endFrame = AVAudioFramePosition(max(Double(startFrame), min(Double(totalFrames), endTime * sr)))
        let frameCount = AVAudioFrameCount(max(0, endFrame - startFrame))
        guard frameCount > 0 else { return }
        
        guard let readBuf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frameCount) else { return }
        af.framePosition = startFrame
        try? af.read(into: readBuf, frameCount: frameCount)
        
        // 출력용 스테레오 버퍼 생성 후 활성화된 채널만 믹싱
        guard let stereoFmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2),
              let outBuf = AVAudioPCMBuffer(pcmFormat: stereoFmt, frameCapacity: frameCount) else { return }
        outBuf.frameLength = readBuf.frameLength
        
        let inChCount = Int(fmt.channelCount)
        if let inData = readBuf.floatChannelData, let outData = outBuf.floatChannelData {
            let len = Int(readBuf.frameLength)
            for i in 0..<len {
                outData[0][i] = 0.0
                outData[1][i] = 0.0
            }
            
            var activeIndices: [Int] = []
            for c in 0..<inChCount {
                if isChannelActive(c) { activeIndices.append(c) }
            }
            
            let gain = activeIndices.isEmpty ? 0.0 : (1.0 / Float(max(1, activeIndices.count)))
            for c in activeIndices {
                let src = inData[c]
                // 솔로(Solo) 선택 시 양쪽 귀(L/R) 모두에 들려주고, 다중 선택 시 짝수 채널은 L, 홀수 채널은 R로 배분
                if soloChannel != nil || inChCount == 1 {
                    for i in 0..<len {
                        outData[0][i] += src[i]
                        outData[1][i] += src[i]
                    }
                } else {
                    let targetOut = c % 2
                    for i in 0..<len {
                        outData[targetOut][i] += src[i] * min(1.0, gain * 1.5)
                    }
                }
            }
        }
        
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: stereoFmt)
        try? engine.start()
        node.scheduleBuffer(outBuf, at: nil, options: []) { [weak self] in
            DispatchQueue.main.async { self?.isPlaying = false }
        }
        node.play()
        self.audioEngine = engine
        self.audioPlayerNode = node
    }
    
    // 시:분:초:프레임(HH:MM:SS:FF) 포맷 변환
    func formatTimecode(_ sec: Double) -> String {
        let safe = max(0.0, sec)
        let totalSecs = Int(safe)
        let h = totalSecs / 3600
        let m = (totalSecs % 3600) / 60
        let s = totalSecs % 60
        let f = Int(((safe - Double(totalSecs)) * fps).rounded()) % max(1, Int(fps.rounded()))
        return String(format: "%02d:%02d:%02d:%02d", h, m, s, f)
    }
    
    func splitTimecode(_ sec: Double) -> (h: Int, m: Int, s: Int, f: Int) {
        let safe = max(0.0, sec)
        let totalSecs = Int(safe)
        let h = totalSecs / 3600
        let m = (totalSecs % 3600) / 60
        let s = totalSecs % 60
        let f = Int(((safe - Double(totalSecs)) * fps).rounded()) % max(1, Int(fps.rounded()))
        return (h, m, s, f)
    }
    
    func composeSeconds(h: Int, m: Int, s: Int, f: Int) -> Double {
        let base = Double(max(0, h) * 3600 + max(0, m) * 60 + max(0, s))
        let frameSec = Double(max(0, f)) / max(1.0, fps)
        return min(duration, max(0.0, base + frameSec))
    }
    
    deinit {
        if let obs = timeObserver { player.removeTimeObserver(obs) }
        audioPlayerNode?.stop()
        audioEngine?.stop()
    }
}

struct ProMediaStudioView: View {
    let fileURL: URL
    let initialMode: String
    @StateObject private var ctrl: MultiChannelMediaController
    
    @State private var volumePercent: Double = 100.0
    @State private var trimSilence: Bool = false
    @State private var enableBleep: Bool = false
    @State private var bleepStartRatio: Double = 0.3
    @State private var bleepEndRatio: Double = 0.45
    
    // 정밀 시:분:초:프레임 입력 필드
    @State private var inH: Int = 0; @State private var inM: Int = 0; @State private var inS: Int = 0; @State private var inF: Int = 0
    @State private var outH: Int = 0; @State private var outM: Int = 0; @State private var outS: Int = 0; @State private var outF: Int = 0
    
    let sampleBars: [CGFloat] = (0..<90).map { i in
        let d = Double(i)
        return CGFloat(abs(sin(d * 0.31) * cos(d * 0.17)) * 0.78 + 0.18)
    }
    
    init(fileURL: URL, initialMode: String) {
        self.fileURL = fileURL
        self.initialMode = initialMode
        _ctrl = StateObject(wrappedValue: MultiChannelMediaController(url: fileURL))
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // 1. 비디오 실시간 모니터 화면 (오디오 파일일 경우 대형 파형 모니터 표시)
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.black)
                if ctrl.isVideo {
                    VideoPlayerPreview(player: ctrl.player)
                        .cornerRadius(10)
                        .padding(4)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform.circle.fill")
                            .font(.system(size: 46))
                            .foregroundColor(.orange)
                        Text(fileURL.lastPathComponent)
                            .font(.headline)
                            .foregroundColor(.white)
                        Text("Multi-Channel Audio (\(ctrl.channelCount) Channels Detected)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                // 우측 상단 실시간 타임코드 오버레이
                VStack {
                    HStack {
                        Spacer()
                        Text("재생 위치: \(ctrl.formatTimecode(ctrl.currentTime))  (\(String(format: "%.2f", ctrl.fps)) fps)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.75), in: Capsule())
                    }
                    .padding(10)
                    Spacer()
                }
            }
            .frame(height: ctrl.isVideo ? 320 : 140)
            
            // 2. QuickTime 스타일 타임라인 (마우스 클릭/드래그로 재생 위치 스크러빙 + 좌우 노란색 시작/끝 트림 핸들)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("QuickTime 타임라인 (타임라인 클릭/드래그: 장면 이동 | 양끝 노란색 바 드래그: 시작/끝점 조절)")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Spacer()
                    let selDur = max(0, ctrl.endTime - ctrl.startTime)
                    Text("선택 길이: \(ctrl.formatTimecode(selDur))")
                        .font(.caption.monospacedDigit().bold())
                        .foregroundColor(.orange)
                }
                
                GeometryReader { geo in
                    let w = max(100, geo.size.width)
                    let h = geo.size.height
                    let startX = CGFloat(ctrl.startTime / max(0.01, ctrl.duration)) * w
                    let endX = CGFloat(ctrl.endTime / max(0.01, ctrl.duration)) * w
                    let playX = CGFloat(ctrl.currentTime / max(0.01, ctrl.duration)) * w
                    
                    ZStack(alignment: .leading) {
                        // 배경 트랙
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(white: 0.16))
                        
                        // 파형 바
                        HStack(spacing: (w / CGFloat(sampleBars.count)) * 0.25) {
                            ForEach(0..<sampleBars.count, id: \.self) { idx in
                                let t = (Double(idx) / Double(sampleBars.count)) * ctrl.duration
                                let inTrim = (t >= ctrl.startTime && t <= ctrl.endTime)
                                Capsule()
                                    .fill(inTrim ? Color.orange.opacity(0.85) : Color.gray.opacity(0.28))
                                    .frame(width: max(2, (w / CGFloat(sampleBars.count)) * 0.65), height: (h - 16) * sampleBars[idx])
                            }
                        }
                        .padding(.horizontal, 6)
                        
                        // 트림 제외 구간 어둡게 처리
                        Rectangle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: max(0, startX), height: h)
                        
                        Rectangle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: max(0, w - endX), height: h)
                            .offset(x: endX)
                        
                        // QuickTime 스타일 노란색 트림 박스 테두리
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.yellow, lineWidth: 3)
                            .frame(width: max(10, endX - startX), height: h - 2)
                            .offset(x: startX)
                        
                        // 좌측 시작점(In) 노란색 핸들
                        ZStack {
                            RoundedRectangle(cornerRadius: 4).fill(Color.yellow).frame(width: 14, height: h)
                            Rectangle().fill(Color.black).frame(width: 2, height: 18)
                        }
                        .position(x: max(7, startX), y: h / 2)
                        .gesture(
                            DragGesture()
                                .onChanged { val in
                                    let sec = Double(val.location.x / w) * ctrl.duration
                                    ctrl.startTime = max(0.0, min(ctrl.endTime - (1.0 / ctrl.fps), sec))
                                    ctrl.seek(to: ctrl.startTime)
                                    syncTimecodeFields()
                                }
                        )
                        
                        // 우측 종료점(Out) 노란색 핸들
                        ZStack {
                            RoundedRectangle(cornerRadius: 4).fill(Color.yellow).frame(width: 14, height: h)
                            Rectangle().fill(Color.black).frame(width: 2, height: 18)
                        }
                        .position(x: min(w - 7, endX), y: h / 2)
                        .gesture(
                            DragGesture()
                                .onChanged { val in
                                    let sec = Double(val.location.x / w) * ctrl.duration
                                    ctrl.endTime = min(ctrl.duration, max(ctrl.startTime + (1.0 / ctrl.fps), sec))
                                    ctrl.seek(to: ctrl.endTime)
                                    syncTimecodeFields()
                                }
                        )
                        
                        // 빨간색 재생 헤드(Playhead)
                        ZStack {
                            Rectangle().fill(Color.red).frame(width: 2.5, height: h + 6)
                            Circle().fill(Color.red).frame(width: 11, height: 11).offset(y: -h / 2)
                        }
                        .position(x: playX, y: h / 2)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                let sec = Double(max(0, min(w, val.location.x)) / w) * ctrl.duration
                                ctrl.seek(to: sec)
                            }
                    )
                }
                .frame(height: 68)
            }
            
            // 3. 재생 컨트롤 및 시:분:초:프레임(HH:MM:SS:FF) 정밀 입력 패널
            HStack(spacing: 14) {
                // 재생 & 1프레임 이동 컨트롤
                HStack(spacing: 6) {
                    Button(action: { ctrl.stepFrames(-1) }) { Image(systemName: "backward.frame.fill") }
                        .help("1프레임 뒤로")
                    Button(action: { ctrl.togglePlay() }) {
                        Image(systemName: ctrl.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    Button(action: { ctrl.stepFrames(1) }) { Image(systemName: "forward.frame.fill") }
                        .help("1프레임 앞으로")
                    
                    Button("[ 현재 위치를 시작점으로") {
                        ctrl.startTime = min(ctrl.currentTime, ctrl.endTime - (1.0 / ctrl.fps))
                        syncTimecodeFields()
                    }.font(.caption)
                    
                    Button("현재 위치를 끝점으로 ]") {
                        ctrl.endTime = max(ctrl.currentTime, ctrl.startTime + (1.0 / ctrl.fps))
                        syncTimecodeFields()
                    }.font(.caption)
                }
                
                Divider().frame(height: 28)
                
                // 시작 지점 (시:분:초:프레임)
                timecodeStepperBox(
                    label: "시작(In)",
                    h: $inH, m: $inM, s: $inS, f: $inF,
                    onApply: {
                        let newSec = ctrl.composeSeconds(h: inH, m: inM, s: inS, f: inF)
                        ctrl.startTime = min(newSec, ctrl.endTime - (1.0 / ctrl.fps))
                        ctrl.seek(to: ctrl.startTime)
                        syncTimecodeFields()
                    },
                    onStepFrame: { df in
                        let frameDur = 1.0 / max(1.0, ctrl.fps)
                        ctrl.startTime = max(0, min(ctrl.endTime - frameDur, ctrl.startTime + Double(df) * frameDur))
                        ctrl.seek(to: ctrl.startTime)
                        syncTimecodeFields()
                    }
                )
                
                // 종료 지점 (시:분:초:프레임)
                timecodeStepperBox(
                    label: "종료(Out)",
                    h: $outH, m: $outM, s: $outS, f: $outF,
                    onApply: {
                        let newSec = ctrl.composeSeconds(h: outH, m: outM, s: outS, f: outF)
                        ctrl.endTime = max(newSec, ctrl.startTime + (1.0 / ctrl.fps))
                        ctrl.seek(to: ctrl.endTime)
                        syncTimecodeFields()
                    },
                    onStepFrame: { df in
                        let frameDur = 1.0 / max(1.0, ctrl.fps)
                        ctrl.endTime = min(ctrl.duration, max(ctrl.startTime + frameDur, ctrl.endTime + Double(df) * frameDur))
                        ctrl.seek(to: ctrl.endTime)
                        syncTimecodeFields()
                    }
                )
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            
            // 4. 다중 오디오 채널 (1ch ~ 8ch+) 개별 On/Off 및 Solo 청취 믹서
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("🎛️ 다중 오디오 채널 믹서 (총 \(ctrl.channelCount)채널 감지됨 — 원하는 채널만 켜서 듣거나 내보낼 수 있습니다)")
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                    Spacer()
                    Button("전체 채널 켜기") {
                        ctrl.soloChannel = nil
                        ctrl.channelEnabled = Array(repeating: true, count: ctrl.channelCount)
                        ctrl.updateChannelRouting()
                    }.font(.caption2)
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(0..<ctrl.channelCount, id: \.self) { chIdx in
                            let isOn = ctrl.isChannelActive(chIdx)
                            let isSolo = (ctrl.soloChannel == chIdx)
                            
                            VStack(spacing: 6) {
                                Text("CH \(chIdx + 1)")
                                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                                    .foregroundColor(isOn ? .primary : .secondary)
                                
                                HStack(spacing: 6) {
                                    // 채널 켜기/끄기 버튼
                                    Button(action: {
                                        ctrl.soloChannel = nil
                                        if chIdx < ctrl.channelEnabled.count {
                                            ctrl.channelEnabled[chIdx].toggle()
                                            ctrl.updateChannelRouting()
                                        }
                                    }) {
                                        Label(isOn ? "ON" : "MUTE", systemImage: isOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                            .font(.caption2.bold())
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(isOn ? .green : .gray)
                                    
                                    // 해당 채널만 단독으로 듣기 (Solo)
                                    Button(action: {
                                        if ctrl.soloChannel == chIdx {
                                            ctrl.soloChannel = nil
                                        } else {
                                            ctrl.soloChannel = chIdx
                                        }
                                        ctrl.updateChannelRouting()
                                    }) {
                                        Text("SOLO")
                                            .font(.system(size: 10, weight: .black))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(isSolo ? .yellow : .secondary)
                                }
                            }
                            .padding(8)
                            .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSolo ? Color.yellow : (isOn ? Color.green.opacity(0.6) : Color.clear), lineWidth: 1.5))
                        }
                    }
                }
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            
            // 5. 부가 옵션 및 내보내기 버튼
            HStack(spacing: 18) {
                HStack(spacing: 6) {
                    Text("볼륨").font(.caption)
                    Slider(value: $volumePercent, in: 20...200).frame(width: 110).tint(.orange)
                    Text("\(Int(volumePercent))%").font(.caption.monospacedDigit()).frame(width: 40)
                }
                
                Toggle("앞뒤 무음 제거", isOn: $trimSilence).font(.caption)
                Toggle("Bleep(삐- 소리)", isOn: $enableBleep).font(.caption)
                
                Spacer()
                
                Button("트림 및 채널 설정 적용하여 저장") {
                    exportEditedMedia()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding(16)
        .onAppear {
            if initialMode == "tool_audio_bleep" { enableBleep = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                syncTimecodeFields()
            }
        }
        .onDisappear {
            ctrl.pause()
        }
    }
    
    func syncTimecodeFields() {
        let s = ctrl.splitTimecode(ctrl.startTime)
        inH = s.h; inM = s.m; inS = s.s; inF = s.f
        let e = ctrl.splitTimecode(ctrl.endTime)
        outH = e.h; outM = e.m; outS = e.s; outF = e.f
    }
    
    @ViewBuilder
    func timecodeStepperBox(
        label: String,
        h: Binding<Int>, m: Binding<Int>, s: Binding<Int>, f: Binding<Int>,
        onApply: @escaping () -> Void,
        onStepFrame: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption.bold()).foregroundColor(.orange)
            
            Group {
                TextField("HH", value: h, format: .number).frame(width: 28)
                Text(":")
                TextField("MM", value: m, format: .number).frame(width: 28)
                Text(":")
                TextField("SS", value: s, format: .number).frame(width: 28)
                Text(":")
                TextField("FF", value: f, format: .number).frame(width: 28)
            }
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .onSubmit { onApply() }
            
            Button("-1F") { onStepFrame(-1) }.font(.caption2)
            Button("+1F") { onStepFrame(1) }.font(.caption2)
        }
    }
    
    func exportEditedMedia() {
        ctrl.pause()
        let startSec = min(ctrl.startTime, ctrl.endTime)
        let endSec = max(ctrl.startTime, ctrl.endTime)
        let clipDur = max(0.1, endSec - startSec)
        let outURL = FileProcessor.uniqueOutputURL(for: fileURL, newExt: fileURL.pathExtension, suffix: "_trimmed")
        let jobTitle = "트림 편집: \(fileURL.lastPathComponent)"
        
        // 활성화된 채널 목록 확인
        var activeChannels: [Int] = []
        for idx in 0..<ctrl.channelCount {
            if ctrl.isChannelActive(idx) { activeChannels.append(idx) }
        }
        
        if FileProcessor.ffmpegPath != nil {
            var filters: [String] = ["volume=\(volumePercent / 100.0)"]
            
            // 특정 채널만 켜진 경우 FFmpeg pan 필터로 선택된 채널만 추출/믹싱
            if activeChannels.count > 0 && activeChannels.count < ctrl.channelCount {
                if activeChannels.count == 1 {
                    let ch = activeChannels[0]
                    filters.append("pan=mono|c0=c\(ch)")
                } else {
                    let exprs = activeChannels.enumerated().map { "c\($0.offset)=c\($0.element)" }.joined(separator: "|")
                    filters.append("pan=\(activeChannels.count)c|\(exprs)")
                }
            } else if activeChannels.isEmpty {
                filters.append("volume=0")
            }
            
            if trimSilence {
                filters.append("silenceremove=start_periods=1:start_silence=0.2:start_threshold=-45dB")
            }
            
            var args = ["-y", "-ss", String(format: "%.4f", startSec), "-to", String(format: "%.4f", endSec), "-i", fileURL.path]
            if ctrl.isVideo {
                args += ["-c:v", "libx264", "-preset", "fast", "-crf", "20"]
            }
            args += ["-af", filters.joined(separator: ","), outURL.path]
            
            FileProcessor.runFFmpegWithProgress(args: args, totalDuration: clipDur, jobTitle: jobTitle) { ok in
                if ok && FileManager.default.fileExists(atPath: outURL.path) {
                    FileProcessor.showToast("편집 완료: \(outURL.lastPathComponent)")
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
        exporter.outputURL = finalURL
        exporter.outputFileType = ctrl.isVideo ? .mp4 : .m4a
        exporter.timeRange = CMTimeRange(
            start: CMTime(seconds: startSec, preferredTimescale: 6000),
            duration: CMTime(seconds: duration, preferredTimescale: 6000)
        )
        
        let jobID = JobProgressManager.shared.startJob(title: jobTitle)
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            JobProgressManager.shared.updateJob(id: jobID, progress: Double(exporter.progress))
        }
        
        exporter.exportAsynchronously {
            DispatchQueue.main.async {
                timer.invalidate()
                JobProgressManager.shared.finishJob(id: jobID)
                FileProcessor.showToast("트림 저장 완료: \(finalURL.lastPathComponent)")
                NSApp.keyWindow?.close()
            }
        }
    }
}

// MARK: - 10. 배경 추가 창 (Add BG)
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

// MARK: - 11. 압축 도구 창 (진행률 % 연동)
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
                    } else if FileProcessor.ffmpegPath != nil {
                        let out = FileProcessor.uniqueOutputURL(for: f, newExt: ext, suffix: "_compressed")
                        let crf = Int(40.0 - (quality / 100.0) * 20.0)
                        let dur = FileProcessor.mediaDurationSeconds(for: f)
                        FileProcessor.runFFmpegWithProgress(args: ["-y", "-i", f.path, "-vcodec", "libx264", "-crf", "\(crf)", out.path], totalDuration: dur, jobTitle: "압축: \(f.lastPathComponent)") { _ in
                            FileProcessor.showToast("미디어 압축 완료: \(out.lastPathComponent)")
                        }
                    } else {
                        let out = FileProcessor.uniqueOutputURL(for: f, newExt: "mp4", suffix: "_compressed")
                        FileProcessor.avAssetConvertWithProgress(file: f, to: "mp4", outURL: out, jobTitle: "압축: \(f.lastPathComponent)")
                    }
                }
                NSApp.keyWindow?.close()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }.padding(24)
    }
}

// MARK: - 12. 메타데이터 확인 및 삭제 창
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

// MARK: - 13. 앱 델리게이트 & 메뉴바 실시간 진행률(%) 표시기
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var wheelPanel: NSPanel!
    var wheelCenterPoint: NSPoint = .zero
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusBarMenu()
        
        JobProgressManager.shared.onUpdate = { [weak self] in
            self?.updateStatusBarMenu()
        }
        
        setupWheelPanel()
        startGlobalMonitors()
    }
    
    func updateStatusBarMenu() {
        let jobs = JobProgressManager.shared.jobs
        if let btn = statusItem.button {
            if let overall = JobProgressManager.shared.overallProgress {
                let pct = Int((overall * 100.0).rounded())
                btn.image = NSImage(systemSymbolName: "gearshape.arrow.triangle.2.circlepath", accessibilityDescription: "Processing")
                btn.title = " \(pct)%"
            } else {
                btn.image = NSImage(systemSymbolName: "circle.hexagongrid.fill", accessibilityDescription: "MyTangerine")
                btn.title = ""
            }
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "🍊 MyTangerine 3.0 Pro", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        if jobs.isEmpty {
            menu.addItem(NSMenuItem(title: "대기 중 (현재 진행 중인 변환 작업 없음)", action: nil, keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "⚡ 진행 중인 작업 (\(jobs.count)건):", action: nil, keyEquivalent: ""))
            for job in jobs {
                let pct = Int((job.progress * 100.0).rounded())
                let barCount = max(1, min(10, pct / 10))
                let bar = String(repeating: "█", count: barCount) + String(repeating: "░", count: 10 - barCount)
                let item = NSMenuItem(title: "[\(bar)] \(pct)% — \(job.title)", action: nil, keyEquivalent: "")
                menu.addItem(item)
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Shift+드래그: 변환 | Option+Shift+드래그: 도구 | Control+드래그: 액션", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "종료 (Quit)", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
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
