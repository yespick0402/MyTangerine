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

// MARK: - 0. 직접 키보드를 눌러 설정하는 단축키 매니저 (오리지널 Tangerine 기본값)
class ShortcutSettings: ObservableObject {
    static let shared = ShortcutSettings()
    
    // CGEventFlags rawValue를 저장 (기본값: Convert = Shift, Tools = Option + Shift)
    @Published var convertFlagsRaw: UInt64 {
        didSet { UserDefaults.standard.set(convertFlagsRaw, forKey: "tangerine_sc_convert_v38") }
    }
    @Published var toolsFlagsRaw: UInt64 {
        didSet { UserDefaults.standard.set(toolsFlagsRaw, forKey: "tangerine_sc_tools_v38") }
    }
    
    static let defaultConvertRaw: UInt64 = NSEvent.ModifierFlags.shift.rawValue
    static let defaultToolsRaw: UInt64 = NSEvent.ModifierFlags([.option, .shift]).rawValue
    
    init() {
        let savedConv = UserDefaults.standard.object(forKey: "tangerine_sc_convert_v38") as? UInt64
        let savedTools = UserDefaults.standard.object(forKey: "tangerine_sc_tools_v38") as? UInt64
        self.convertFlagsRaw = (savedConv != nil && savedConv != 0) ? savedConv! : Self.defaultConvertRaw
        self.toolsFlagsRaw = (savedTools != nil && savedTools != 0) ? savedTools! : Self.defaultToolsRaw
    }
    
    var convertFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(convertFlagsRaw)).intersection([.shift, .option, .control, .command])
    }
    
    var toolsFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(toolsFlagsRaw)).intersection([.shift, .option, .control, .command])
    }
    
    func resetToTangerineDefaults() {
        convertFlagsRaw = Self.defaultConvertRaw
        toolsFlagsRaw = Self.defaultToolsRaw
    }
    
    static func formatFlags(_ flags: NSEvent.ModifierFlags) -> String {
        let clean = flags.intersection([.control, .option, .shift, .command])
        var parts: [String] = []
        if clean.contains(.control) { parts.append("⌃ Control") }
        if clean.contains(.option) { parts.append("⌥ Option") }
        if clean.contains(.shift) { parts.append("⇧ Shift") }
        if clean.contains(.command) { parts.append("⌘ Command") }
        return parts.isEmpty ? "키를 눌러주세요..." : parts.joined(separator: " + ")
    }
    
    func matchWheelMode(for flags: NSEvent.ModifierFlags) -> WheelMode? {
        let clean = flags.intersection([.shift, .option, .control, .command])
        guard !clean.isEmpty else { return nil }
        
        let tFlags = toolsFlags
        let cFlags = convertFlags
        
        // 정확히 일치하는 키 조합 우선 판정
        if clean == tFlags { return .tools }
        if clean == cFlags { return .convert }
        
        // 복합키(예: Option+Shift)가 단일키(예: Shift)보다 먼저 매칭되도록 비트 수 정렬
        let candidates: [(WheelMode, NSEvent.ModifierFlags)] = [
            (.tools, tFlags),
            (.convert, cFlags)
        ].sorted { $0.1.rawValue.nonzeroBitCount > $1.1.rawValue.nonzeroBitCount }
        
        for (mode, req) in candidates where !req.isEmpty {
            if clean.isSuperset(of: req) { return mode }
        }
        return nil
    }
}

// MARK: - 1. 작업 진행률(Progress) 매니저 (메뉴바 실시간 % 연동)
struct ActiveJob: Identifiable {
    let id: UUID
    let title: String
    var progress: Double
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
}

struct WheelItem: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let actionKey: String
    var estimatedSizeText: String? = nil
}

class AppState: ObservableObject {
    static let shared = AppState()
    @Published var isDragging = false
    @Published var wheelMode: WheelMode = .convert
    @Published var draggedFiles: [URL] = []
    @Published var totalBytes: Int64 = 0
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
        
        var baseItems: [WheelItem] = []
        
        switch wheelMode {
        case .convert:
            if imageExts.contains(ext) {
                baseItems = [
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
                baseItems = [
                    WheelItem(title: "MP4", icon: "film", actionKey: "conv_mp4"),
                    WheelItem(title: "MOV", icon: "video", actionKey: "conv_mov"),
                    WheelItem(title: "GIF", icon: "sparkles.tv", actionKey: "conv_gif"),
                    WheelItem(title: "M4A (음원)", icon: "music.quarternote.3", actionKey: "conv_m4a"),
                    WheelItem(title: "MP3 (음원)", icon: "music.note", actionKey: "conv_mp3"),
                    WheelItem(title: "WAV (음원)", icon: "waveform", actionKey: "conv_wav"),
                    WheelItem(title: "MKV", icon: "play.rectangle", actionKey: "conv_mkv")
                ]
            } else if audioExts.contains(ext) {
                baseItems = [
                    WheelItem(title: "M4A", icon: "music.quarternote.3", actionKey: "conv_m4a"),
                    WheelItem(title: "WAV", icon: "waveform", actionKey: "conv_wav"),
                    WheelItem(title: "MP3", icon: "music.note", actionKey: "conv_mp3"),
                    WheelItem(title: "FLAC", icon: "hifispeaker", actionKey: "conv_flac"),
                    WheelItem(title: "AIFF", icon: "opticaldisc", actionKey: "conv_aiff"),
                    WheelItem(title: "CAF", icon: "speaker.wave.2", actionKey: "conv_caf")
                ]
            } else {
                baseItems = [
                    WheelItem(title: "ZIP 압축", icon: "doc.zipper", actionKey: "conv_zip"),
                    WheelItem(title: "TAR.GZ", icon: "archivebox", actionKey: "conv_targz"),
                    WheelItem(title: "PDF 변환", icon: "doc.richtext", actionKey: "conv_pdf")
                ]
            }
            
            let files = draggedFiles
            let origTotal = totalBytes
            for i in 0..<baseItems.count {
                let targetExt = baseItems[i].actionKey.replacingOccurrences(of: "conv_", with: "")
                let estBytes = FileSizeEstimator.estimateConversionBytes(files: files, originalTotalBytes: origTotal, targetExt: targetExt)
                baseItems[i].estimatedSizeText = "~" + ByteCountFormatter.string(fromByteCount: estBytes, countStyle: .file)
            }
            items = baseItems
            
            if imageExts.contains(ext) {
                DispatchQueue.global(qos: .userInteractive).async {
                    var updated = baseItems
                    for i in 0..<updated.count {
                        let targetExt = updated[i].actionKey.replacingOccurrences(of: "conv_", with: "")
                        let exactBytes = FileSizeEstimator.exactImageConversionBytes(files: files, originalTotalBytes: origTotal, targetExt: targetExt)
                        updated[i].estimatedSizeText = "~" + ByteCountFormatter.string(fromByteCount: exactBytes, countStyle: .file)
                    }
                    DispatchQueue.main.async {
                        if self.isDragging && self.wheelMode == .convert {
                            self.items = updated
                        }
                    }
                }
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
                    WheelItem(title: "용량 압축", icon: "arrow.down.right.and.arrow.up.left", actionKey: "tool_compress"),
                    WheelItem(title: "경로 복사", icon: "doc.on.clipboard", actionKey: "act_copy_path")
                ]
            }
        }
    }
}

// MARK: - 3. 변환 및 압축 파일 예상 크기 계산 엔진
class FileSizeEstimator {
    static func estimateConversionBytes(files: [URL], originalTotalBytes: Int64, targetExt: String) -> Int64 {
        guard let first = files.first, originalTotalBytes > 0 else { return 0 }
        let srcExt = first.pathExtension.lowercased()
        let tgt = targetExt.lowercased()
        
        if srcExt == tgt { return originalTotalBytes }
        
        let videoExts = ["mp4", "mov", "mkv", "avi", "webm", "m4v"]
        let audioExts = ["mp3", "m4a", "wav", "flac", "ogg", "aac", "aiff", "caf"]
        
        if videoExts.contains(srcExt) || audioExts.contains(srcExt) {
            var totalDuration: Double = 0
            for f in files {
                totalDuration += FileProcessor.mediaDurationSeconds(for: f)
            }
            if totalDuration > 0 {
                switch tgt {
                case "mp3", "m4a", "aac", "caf", "ogg":
                    return max(4096, Int64(totalDuration * 24_000))
                case "wav", "aiff":
                    return max(8192, Int64(totalDuration * 176_400))
                case "flac":
                    return max(8192, Int64(totalDuration * 96_000))
                case "gif":
                    return max(10_240, Int64(totalDuration * 380_000))
                case "mp4", "mov", "mkv":
                    let ratio: Double = (srcExt == "mov") ? 0.68 : 0.88
                    return max(16_384, Int64(Double(originalTotalBytes) * ratio))
                default:
                    break
                }
            }
        }
        
        let weights: [String: Double] = [
            "bmp": 3.2, "tiff": 2.4, "png": 1.0, "pdf": 0.95,
            "jpg": 0.36, "jpeg": 0.36, "heic": 0.22, "webp": 0.25,
            "icns": 0.45, "zip": 0.72, "targz": 0.68
        ]
        
        let srcW = weights[srcExt] ?? 1.0
        let tgtW = weights[tgt] ?? 0.85
        let estimated = Double(originalTotalBytes) * (tgtW / srcW)
        return max(1024, Int64(estimated))
    }
    
    static func exactImageConversionBytes(files: [URL], originalTotalBytes: Int64, targetExt: String) -> Int64 {
        guard let first = files.first,
              let attrs = try? FileManager.default.attributesOfItem(atPath: first.path),
              let firstOrigSize = attrs[.size] as? Int64, firstOrigSize > 0,
              let cg = FileProcessor.loadRawCGImage(from: first) else {
            return estimateConversionBytes(files: files, originalTotalBytes: originalTotalBytes, targetExt: targetExt)
        }
        
        let rep = NSBitmapImageRep(cgImage: cg)
        let tgt = targetExt.lowercased()
        var sampleDataSize: Int64? = nil
        
        switch tgt {
        case "jpg", "jpeg":
            sampleDataSize = Int64(rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])?.count ?? 0)
        case "png":
            sampleDataSize = Int64(rep.representation(using: .png, properties: [:])?.count ?? 0)
        case "tiff":
            sampleDataSize = Int64(rep.representation(using: .tiff, properties: [:])?.count ?? 0)
        case "bmp":
            sampleDataSize = Int64(rep.representation(using: .bmp, properties: [:])?.count ?? 0)
        case "heic", "webp":
            if let jpgCount = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])?.count {
                sampleDataSize = Int64(Double(jpgCount) * 0.62)
            }
        case "pdf":
            if let jpgCount = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.90])?.count {
                sampleDataSize = Int64(jpgCount + 4096)
            }
        default:
            break
        }
        
        if let sSize = sampleDataSize, sSize > 0 {
            let scaleRatio = Double(sSize) / Double(firstOrigSize)
            return max(1024, Int64(Double(originalTotalBytes) * scaleRatio))
        }
        return estimateConversionBytes(files: files, originalTotalBytes: originalTotalBytes, targetExt: targetExt)
    }
    
    static func estimateCompressedBytes(files: [URL], quality: Double) -> (original: Int64, estimated: Int64) {
        var origTotal: Int64 = 0
        var estTotal: Int64 = 0
        
        for (index, f) in files.enumerated() {
            let fSize = (try? FileManager.default.attributesOfItem(atPath: f.path)[.size] as? Int64) ?? 0
            origTotal += fSize
            let ext = f.pathExtension.lowercased()
            
            if ["jpg", "jpeg", "png", "heic", "tiff", "bmp", "webp"].contains(ext) {
                if index == 0, let cg = FileProcessor.loadRawCGImage(from: f) {
                    let rep = NSBitmapImageRep(cgImage: cg)
                    if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: quality / 100.0]) {
                        estTotal += Int64(data.count)
                        continue
                    }
                }
                let ratio = pow(quality / 100.0, 1.35) * (ext == "png" || ext == "tiff" || ext == "bmp" ? 0.45 : 0.85)
                estTotal += max(1024, Int64(Double(fSize) * ratio))
            } else {
                let crf = 40.0 - (quality / 100.0) * 20.0
                let ratio = min(0.95, max(0.08, pow(2.0, (23.0 - crf) / 6.0) * 0.78))
                estTotal += max(4096, Int64(Double(fSize) * ratio))
            }
        }
        return (origTotal, estTotal)
    }
}

// MARK: - 4. 파일 처리 및 실시간 진행률(%) 파싱 엔진
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

// MARK: - 5. 마우스 휠 확대/축소 감지용 헬퍼 뷰
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

// MARK: - 6. 원형 다이얼 휠 UI
struct PieSliceShape: Shape {
    var startAngle: Angle
    var endAngle: Angle
    var innerRadiusRatio: CGFloat = 0.35
    
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
    let wheelSize: CGFloat = 324
    
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
        let labelRadius = (wheelSize / 2.0) * 0.68
        
        let fillGrad = isHovered ?
            LinearGradient(colors: [Color.orange, Color.red], startPoint: .topLeading, endPoint: .bottomTrailing) :
            LinearGradient(colors: [Color.white.opacity(0.78), Color.white.opacity(0.48)], startPoint: .top, endPoint: .bottom)
        
        return ZStack {
            PieSliceShape(startAngle: start, endAngle: end)
                .fill(fillGrad)
                .overlay(
                    PieSliceShape(startAngle: start, endAngle: end)
                        .stroke(isHovered ? Color.white : Color.black.opacity(0.08), lineWidth: 1.2)
                )
            
            VStack(spacing: 2) {
                Image(systemName: item.icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(item.title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(1)
                if let est = item.estimatedSizeText {
                    Text(est)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(isHovered ? .white.opacity(0.95) : .black.opacity(0.62))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(isHovered ? Color.black.opacity(0.22) : Color.black.opacity(0.06), in: Capsule())
                }
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
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            
            if let idx = state.hoveredIndex, idx < state.items.count, let est = state.items[idx].estimatedSizeText {
                Text("예상 \(est)")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(.orange)
            } else {
                Text("\(state.draggedFiles.count)개 파일")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
    }
}

// MARK: - 7. 도구 창 매니저
class ToolWindowManager {
    static let shared = ToolWindowManager()
    var activeWindows: [NSWindow] = []
    var bannerWindow: NSPanel?
    
    func openWindow<V: View>(title: String, view: V, size: NSSize, minSize: NSSize = NSSize(width: 680, height: 500)) {
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
    
    func showHelpAndSettingsWindow() {
        openWindow(
            title: "🍊 MyTangerine — 설명 및 단축키 설정",
            view: HelpAndSettingsView(),
            size: NSSize(width: 760, height: 600),
            minSize: NSSize(width: 680, height: 520)
        )
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
        openWindow(title: "Compress Files", view: CompressToolView(files: urls), size: NSSize(width: 480, height: 370), minSize: NSSize(width: 440, height: 340))
    }
    
    func showMetadataWindow(url: URL) {
        openWindow(title: "File Metadata", view: MetadataToolView(fileURL: url), size: NSSize(width: 560, height: 520))
    }
    
    func showMediaStudioWindow(url: URL, initialTab: String) {
        openWindow(title: "QuickTime & Multi-Channel Studio — \(url.lastPathComponent)", view: ProMediaStudioView(fileURL: url, initialMode: initialTab), size: NSSize(width: 1060, height: 800), minSize: NSSize(width: 900, height: 680))
    }
}

// MARK: - 7-B. 직접 키보드를 눌러 입력하고 [완료]를 누르는 단축키 설정 & 사용 설명서 창
struct HelpAndSettingsView: View {
    @ObservedObject var settings = ShortcutSettings.shared
    @State private var selectedTab: Int = 0
    
    // 현재 녹음 중인 대상 ("convert" 또는 "tools" 또는 nil)
    @State private var recordingTarget: String? = nil
    @State private var tempRecordedFlags: NSEvent.ModifierFlags = []
    @State private var localMonitor: Any? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MyTangerine 3.8 Pro")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                    Text("파인더에서 파일을 드래그하며 단축키를 눌러 즉시 변환·편집하는 맥 유틸리티")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Picker("", selection: $selectedTab) {
                    Text("⌨️ 단축키 설정").tag(0)
                    Text("📖 상세 사용 설명서").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }
            .padding(18)
            .background(.regularMaterial)
            
            Divider()
            
            if selectedTab == 0 {
                shortcutRecorderTab
            } else {
                usageGuideTab
            }
            
            Divider()
            
            HStack {
                Text("💡 오리지널 Tangerine 기본값: 변환 = ⇧ Shift  |  도구 = ⌥⇧ Option + Shift")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Tangerine 기본 단축키로 복원") {
                    stopRecording()
                    settings.resetToTangerineDefaults()
                    FileProcessor.showToast("Tangerine 기본 단축키(Shift / Option+Shift)로 복원되었습니다.")
                }
                Button("닫기") {
                    stopRecording()
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(14)
            .background(.regularMaterial)
        }
        .onDisappear {
            stopRecording()
        }
    }
    
    var shortcutRecorderTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("단축키 직접 입력 설정")
                        .font(.headline)
                        .foregroundColor(.orange)
                    Text("바꾸고 싶은 기능의 [단축키 입력하기] 버튼을 누른 뒤, 키보드에서 원하는 조합(예: Shift, Option+Shift, Control+Shift 등)을 누르고 마우스로 [완료] 버튼을 클릭하면 적용됩니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 16) {
                    recorderCard(
                        targetID: "convert",
                        title: "🔄 포맷 변환 휠 (CONVERT)",
                        subtitle: "파일을 드래그하면서 이 키를 누르면 JPG, PNG, WEBP, HEIC, PDF, MP4, MOV, GIF, MP3, WAV 등으로 즉시 변환합니다.",
                        currentFlags: settings.convertFlags,
                        onSave: { newFlags in
                            settings.convertFlagsRaw = UInt64(newFlags.rawValue)
                            FileProcessor.showToast("변환(CONVERT) 단축키가 저장되었습니다.")
                        }
                    )
                    
                    recorderCard(
                        targetID: "tools",
                        title: "🛠️ 전용 편집 도구 휠 (TOOLS)",
                        subtitle: "파일을 드래그하면서 이 키를 누르면 사진 보정(Edit), 크롭(Crop), 모자이크(Redact), 배경 추가(Add BG), 영상/오디오 트림, 압축 도구가 열립니다.",
                        currentFlags: settings.toolsFlags,
                        onSave: { newFlags in
                            settings.toolsFlagsRaw = UInt64(newFlags.rawValue)
                            FileProcessor.showToast("도구(TOOLS) 단축키가 저장되었습니다.")
                        }
                    )
                }
                
                if settings.convertFlags == settings.toolsFlags {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.yellow)
                        Text("변환 휠과 도구 휠의 단축키가 똑같습니다. 서로 다른 키 조합으로 설정해 주세요.")
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(24)
        }
    }
    
    @ViewBuilder
    func recorderCard(
        targetID: String,
        title: String,
        subtitle: String,
        currentFlags: NSEvent.ModifierFlags,
        onSave: @escaping (NSEvent.ModifierFlags) -> Void
    ) -> some View {
        let isRecordingThis = (recordingTarget == targetID)
        
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 15, weight: .bold))
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
            }
            
            HStack(spacing: 12) {
                // 현재 키 또는 입력 중인 키 표시창
                HStack {
                    Image(systemName: isRecordingThis ? "keyboard.badge.ellipsis" : "keyboard")
                        .foregroundColor(isRecordingThis ? .orange : .secondary)
                    
                    if isRecordingThis {
                        Text(tempRecordedFlags.isEmpty ? "원하는 키 조합(Shift, Option, Control, Command)을 누르세요..." : ShortcutSettings.formatFlags(tempRecordedFlags))
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundColor(.orange)
                    } else {
                        Text("파일 드래그 + " + ShortcutSettings.formatFlags(currentFlags))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.black.opacity(isRecordingThis ? 0.28 : 0.14), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isRecordingThis ? Color.orange : Color.white.opacity(0.2), lineWidth: isRecordingThis ? 2 : 1)
                )
                
                if isRecordingThis {
                    Button("완료") {
                        if !tempRecordedFlags.isEmpty {
                            onSave(tempRecordedFlags)
                        }
                        stopRecording()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(tempRecordedFlags.isEmpty)
                    
                    Button("취소") {
                        stopRecording()
                    }
                } else {
                    Button("단축키 입력하기") {
                        startRecording(for: targetID)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    func startRecording(for targetID: String) {
        stopRecording()
        recordingTarget = targetID
        tempRecordedFlags = []
        
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
            if !flags.isEmpty {
                // 사용자가 누른 키 조합을 기록하여 키를 떼고 마우스로 [완료]를 눌러도 유지되도록 함
                self.tempRecordedFlags = flags
            }
            return nil
        }
    }
    
    func stopRecording() {
        if let mon = localMonitor {
            NSEvent.removeMonitor(mon)
            localMonitor = nil
        }
        recordingTarget = nil
        tempRecordedFlags = []
    }
    
    var usageGuideTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                guideCard(
                    icon: "hand.draw.fill",
                    title: "1. 기본 작동법 (오리지널 Tangerine 방식)",
                    items: [
                        "Finder나 바탕화면에서 변환·편집할 파일을 마우스로 잡고 드래그를 시작합니다.",
                        "드래그 중 Shift 키를 누르면 변환(CONVERT) 휠이 나타나며, 각 포맷 조각에 예상 파일 크기가 함께 표시됩니다.",
                        "드래그 중 Option + Shift 키를 누르면 해당 파일 종류에 맞는 전용 편집 도구(TOOLS) 휠이 나타납니다.",
                        "원하는 조각 위에 마우스를 놓으면 작업이 실행되며, 아무것도 선택하지 않고 취소해도 파일이 복제되지 않습니다."
                    ]
                )
                
                guideCard(
                    icon: "photo.on.rectangle.angled",
                    title: "2. 사진 편집 도구 (Edit Photo / Crop / Redact / Add BG)",
                    items: [
                        "EDIT PHOTO: 노출, 휘도, 하이라이트, 그림자, 대비, 채도, 색온도 등 14가지 슬라이더로 원본 화질 그대로 보정합니다.",
                        "CROP (8방향 자르기): 노란색 모서리 핸들 4곳으로 두 변을 동시에 조절하거나, 상·하·좌·우 흰색 바 4곳으로 각 변을 개별 조절합니다.",
                        "REDACT (가리기): 원하는 영역을 드래그하여 픽셀 모자이크, 블러(흐림), 검은 박스로 민감한 정보를 가립니다.",
                        "확대/축소 및 이동: 마우스 스크롤 휠로 정중앙 기준 확대/축소가 가능하며, 드래그하여 이미지를 이동할 수 있습니다."
                    ]
                )
                
                guideCard(
                    icon: "film.stack",
                    title: "3. 영상/오디오 정밀 트림 & 다중 채널 스튜디오",
                    items: [
                        "타임라인 양끝의 노란색 트림 바(시작점 In ~ 종료점 Out) 안쪽 구간만 정확하게 보고 들을 수 있도록 재생 범위가 고정됩니다.",
                        "하단 입력칸에서 시:분:초:프레임(HH:MM:SS:FF) 단위로 입력하거나 -1F / +1F 버튼으로 1프레임씩 정밀하게 시작·끝점을 맞출 수 있습니다.",
                        "다중 채널 오디오 믹서: 2채널부터 4채널, 8채널 이상의 오디오 트랙을 자동 감지하여 원하는 채널만 켜고 끄거나(ON/MUTE) 단독 청취(SOLO)할 수 있습니다."
                    ]
                )
            }
            .padding(22)
        }
    }
    
    func guideCard(icon: String, title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundColor(.orange).font(.title3)
                Text(title).font(.headline)
            }
            ForEach(items, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").foregroundColor(.orange).bold()
                    Text(line).font(.system(size: 13)).foregroundColor(.primary.opacity(0.9))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 8. 전문가 사진 보정 창
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
            FileProcessor.saveCGImage(cgImg, to: outURL, formatExt: ext, quality: 0.95)
            FileProcessor.showToast("원본 화질 보정 완료: \(outURL.lastPathComponent)")
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
            
            GeometryReader { outerGeo in
                let baseFitSize = calculateFitSize(in: outerGeo.size)
                let scaledSize = CGSize(width: baseFitSize.width * zoomScale, height: baseFitSize.height * zoomScale)
                
                ZStack {
                    Color(white: 0.12)
                    
                    ZStack(alignment: .topLeading) {
                        if let cg = rawCGImage {
                            Image(nsImage: NSImage(cgImage: cg, size: scaledSize))
                                .resizable()
                                .interpolation(.high)
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
                        
                        if mode == 0, let drag = activeDragRect {
                            redactOverlayView(rect: drag, style: redactStyle)
                        }
                        
                        if mode == 1 {
                            cropOverlayWith8Handles(canvasSize: scaledSize)
                        }
                    }
                    .frame(width: scaledSize.width, height: scaledSize.height)
                    .contentShape(Rectangle())
                    .gesture(canvasDragGesture(canvasSize: scaledSize))
                    .offset(panOffset)
                    .position(x: outerGeo.size.width / 2, y: outerGeo.size.height / 2)
                    
                    ScrollWheelCatcher { delta in
                        let step = delta * 0.012
                        zoomScale = min(8.0, max(0.25, zoomScale + step))
                    }
                    .allowsHitTesting(false)
                }
                .frame(width: outerGeo.size.width, height: outerGeo.size.height)
                .clipped()
            }
            
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
            }
            .fill(Color.black.opacity(0.58), style: FillStyle(eoFill: true))
            
            ZStack {
                Rectangle()
                    .stroke(Color.yellow, lineWidth: 2)
                VStack { Spacer(); Divider().background(Color.white.opacity(0.6)); Spacer(); Divider().background(Color.white.opacity(0.6)); Spacer() }
                HStack { Spacer(); Divider().background(Color.white.opacity(0.6)); Spacer(); Divider().background(Color.white.opacity(0.6)); Spacer() }
            }
            .frame(width: cRect.width, height: cRect.height)
            .position(x: cRect.midX, y: cRect.midY)
            
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
    
    func canvasDragGesture(canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { val in
                if isPanMode || NSEvent.modifierFlags.contains(.option) {
                    panOffset = CGSize(
                        width: lastPanOffset.width + val.translation.width,
                        height: lastPanOffset.height + val.translation.height
                    )
                    return
                }
                
                if mode == 0 {
                    let s = CGPoint(x: max(0, min(canvasSize.width, val.startLocation.x)),
                                    y: max(0, min(canvasSize.height, val.startLocation.y)))
                    let c = CGPoint(x: max(0, min(canvasSize.width, val.location.x)),
                                    y: max(0, min(canvasSize.height, val.location.y)))
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

// MARK: - 10. QuickTime 비디오 프리뷰 + 트림 구간 외 재생 차단 + 사운드 완벽 보장 스튜디오
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
    
    // 모든 채널이 기본 ON 상태인지 확인 (기본 상태에서는 AVPlayer 순정 오디오를 사용하여 100% 소리 출력 보장)
    var isCustomChannelFilterActive: Bool {
        if soloChannel != nil { return true }
        return channelEnabled.contains(false)
    }
    
    func setupMedia() {
        let asset = AVURLAsset(url: fileURL)
        let item = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: item)
        player.isMuted = false
        player.volume = previewVolume
        
        let sec = CMTimeGetSeconds(asset.duration)
        if sec.isFinite && sec > 0 {
            duration = sec
            endTime = sec
        }
        
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
        
        if !isVideo, let af = try? AVAudioFile(forReading: fileURL) {
            self.audioFile = af
            let ch = Int(af.processingFormat.channelCount)
            if ch > 0 {
                channelCount = ch
                channelEnabled = Array(repeating: true, count: ch)
            }
        }
        
        // 60fps 주기로 현재 재생 위치를 감시하며 트림 구간(startTime ~ endTime)을 절대 벗어나지 못하게 강제 고정
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0 / 60.0, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self = self else { return }
            guard self.audioEngine == nil else { return }
            let sec = CMTimeGetSeconds(time)
            if sec.isFinite {
                if sec < self.startTime - 0.02 {
                    self.seek(to: self.startTime)
                } else if sec >= self.endTime {
                    self.pause()
                    self.seek(to: self.startTime)
                } else {
                    self.currentTime = sec
                }
            }
        }
    }
    
    func setPreviewVolume(_ vol: Float) {
        previewVolume = max(0.0, min(2.0, vol))
        player.volume = previewVolume
        audioEngine?.mainMixerNode.outputVolume = previewVolume
    }
    
    func togglePlay() {
        if isPlaying {
            pause()
        } else {
            // 재생 시작 시 현재 위치가 트림 시작점 이전이거나 끝점 이후면 무조건 트림 시작점(startTime)에서 출발!
            if currentTime < startTime || currentTime >= endTime - 0.02 {
                seek(to: startTime)
            }
            play()
        }
    }
    
    func play() {
        isPlaying = true
        // 오디오 전용 파일에서 특정 채널을 끄거나 솔로(Solo)를 켠 경우에만 커스텀 멀티채널 엔진 구동
        if !isVideo && isCustomChannelFilterActive && audioFile != nil {
            player.pause()
            playCustomMultiChannelAudio(from: currentTime)
        } else {
            stopAudioEngine()
            applyPlayerAudioState()
            // 재생할 구간의 끝점(forwardPlaybackEndTime)을 AVPlayerItem에도 지정하여 트림 밖 재생 원천 차단
            player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: endTime, preferredTimescale: 6000)
            player.play()
        }
    }
    
    func pause() {
        isPlaying = false
        player.pause()
        stopAudioEngine()
    }
    
    private func stopAudioEngine() {
        audioPlayTimer?.invalidate()
        audioPlayTimer = nil
        audioPlayerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        audioPlayerNode = nil
    }
    
    // 재생 위치를 이동할 때 무조건 [startTime ... endTime] 트림 구간 안으로만 제한(Clamp)!
    func seek(to sec: Double) {
        let clampedToTrim = max(startTime, min(endTime, sec))
        currentTime = clampedToTrim
        player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: endTime, preferredTimescale: 6000)
        let cm = CMTime(seconds: clampedToTrim, preferredTimescale: 6000)
        player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        
        if isPlaying && !isVideo && isCustomChannelFilterActive && audioFile != nil {
            playCustomMultiChannelAudio(from: clampedToTrim)
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
        if isPlaying {
            let resumeTime = currentTime
            pause()
            seek(to: resumeTime)
            play()
        } else {
            applyPlayerAudioState()
        }
    }
    
    private func applyPlayerAudioState() {
        let anyActive = (0..<channelCount).contains { isChannelActive($0) }
        player.isMuted = !anyActive
        player.volume = previewVolume
        
        guard let item = player.currentItem else { return }
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
        } else {
            item.audioMix = nil
        }
    }
    
    // 최대 15초 단위 청크로 안전하게 멀티채널을 라우팅하여 대용량 파일에서도 소리가 끊기지 않도록 보장
    private func playCustomMultiChannelAudio(from startSec: Double) {
        guard let af = audioFile else { return }
        stopAudioEngine()
        
        let fmt = af.processingFormat
        let sr = fmt.sampleRate
        let totalFrames = af.length
        let clampedStart = max(startTime, min(endTime, startSec))
        let startFrame = AVAudioFramePosition(max(0, min(Double(totalFrames), clampedStart * sr)))
        let endFrame = AVAudioFramePosition(max(Double(startFrame), min(Double(totalFrames), endTime * sr)))
        let requestedFrames = AVAudioFrameCount(max(0, endFrame - startFrame))
        guard requestedFrames > 0 else {
            isPlaying = false
            return
        }
        
        // 메모리 초과 방지를 위해 한 번에 최대 30초 분량만 버퍼링
        let maxBufferFrames = AVAudioFrameCount(sr * 30.0)
        let frameCount = min(requestedFrames, maxBufferFrames)
        
        guard let readBuf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frameCount) else { return }
        af.framePosition = startFrame
        try? af.read(into: readBuf, frameCount: frameCount)
        
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
        engine.mainMixerNode.outputVolume = previewVolume
        try? engine.start()
        
        audioSegmentStartTime = clampedStart
        node.scheduleBuffer(outBuf, at: nil, options: [])
        node.play()
        
        self.audioEngine = engine
        self.audioPlayerNode = node
        
        let startedAt = Date()
        audioPlayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            let elapsed = Date().timeIntervalSince(startedAt)
            let nowSec = self.audioSegmentStartTime + elapsed
            if nowSec >= self.endTime {
                self.pause()
                self.seek(to: self.startTime)
            } else {
                self.currentTime = nowSec
            }
        }
    }
    
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
                
                VStack {
                    HStack {
                        Text("🔒 트림 구간 내 재생 잠금 활성화됨 (트림 바깥 구간은 재생되지 않습니다)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.orange.opacity(0.85), in: Capsule())
                        Spacer()
                        Text("현재 위치: \(ctrl.formatTimecode(ctrl.currentTime))  (\(String(format: "%.2f", ctrl.fps)) fps)")
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
            
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("QuickTime 타임라인 (노란색 트림 구간 안에서만 재생 헤드가 이동하며 시작점과 끝점을 정확히 확인합니다)")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Spacer()
                    let selDur = max(0, ctrl.endTime - ctrl.startTime)
                    Text("트림 구간 길이: \(ctrl.formatTimecode(selDur))")
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
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(white: 0.16))
                        
                        HStack(spacing: (w / CGFloat(sampleBars.count)) * 0.25) {
                            ForEach(0..<sampleBars.count, id: \.self) { idx in
                                let t = (Double(idx) / Double(sampleBars.count)) * ctrl.duration
                                let inTrim = (t >= ctrl.startTime && t <= ctrl.endTime)
                                Capsule()
                                    .fill(inTrim ? Color.orange.opacity(0.88) : Color.gray.opacity(0.22))
                                    .frame(width: max(2, (w / CGFloat(sampleBars.count)) * 0.65), height: (h - 16) * sampleBars[idx])
                            }
                        }
                        .padding(.horizontal, 6)
                        
                        // 트림 제외 구간 어둡게 마스킹 (재생 불가 영역 표시)
                        Rectangle()
                            .fill(Color.black.opacity(0.72))
                            .frame(width: max(0, startX), height: h)
                        
                        Rectangle()
                            .fill(Color.black.opacity(0.72))
                            .frame(width: max(0, w - endX), height: h)
                            .offset(x: endX)
                        
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
                                    ctrl.pause()
                                    let sec = Double(val.location.x / w) * ctrl.duration
                                    ctrl.startTime = max(0.0, min(ctrl.endTime - (1.0 / ctrl.fps), sec))
                                    // 시작점을 조절할 때 즉시 시작점 장면을 보여줌
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
                                    ctrl.pause()
                                    let sec = Double(val.location.x / w) * ctrl.duration
                                    ctrl.endTime = min(ctrl.duration, max(ctrl.startTime + (1.0 / ctrl.fps), sec))
                                    // 끝점을 조절할 때 즉시 끝점 장면을 보여줌
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
                                let rawSec = Double(max(0, min(w, val.location.x)) / w) * ctrl.duration
                                // 마우스를 트림 바깥으로 끌어도 무조건 [startTime ... endTime] 안에서만 이동!
                                ctrl.seek(to: rawSec)
                            }
                    )
                }
                .frame(height: 68)
            }
            
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Button(action: { ctrl.stepFrames(-1) }) { Image(systemName: "backward.frame.fill") }
                        .help("1프레임 뒤로 (트림 구간 내)")
                    Button(action: { ctrl.togglePlay() }) {
                        Image(systemName: ctrl.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    Button(action: { ctrl.stepFrames(1) }) { Image(systemName: "forward.frame.fill") }
                        .help("1프레임 앞으로 (트림 구간 내)")
                    
                    Button("시작점 보기") {
                        ctrl.pause()
                        ctrl.seek(to: ctrl.startTime)
                    }.font(.caption)
                    
                    Button("끝점 보기") {
                        ctrl.pause()
                        ctrl.seek(to: ctrl.endTime)
                    }.font(.caption)
                }
                
                Divider().frame(height: 28)
                
                timecodeStepperBox(
                    label: "시작(In)",
                    h: $inH, m: $inM, s: $inS, f: $inF,
                    onApply: {
                        ctrl.pause()
                        let newSec = ctrl.composeSeconds(h: inH, m: inM, s: inS, f: inF)
                        ctrl.startTime = min(newSec, ctrl.endTime - (1.0 / ctrl.fps))
                        ctrl.seek(to: ctrl.startTime)
                        syncTimecodeFields()
                    },
                    onStepFrame: { df in
                        ctrl.pause()
                        let frameDur = 1.0 / max(1.0, ctrl.fps)
                        ctrl.startTime = max(0, min(ctrl.endTime - frameDur, ctrl.startTime + Double(df) * frameDur))
                        ctrl.seek(to: ctrl.startTime)
                        syncTimecodeFields()
                    }
                )
                
                timecodeStepperBox(
                    label: "종료(Out)",
                    h: $outH, m: $outM, s: $outS, f: $outF,
                    onApply: {
                        ctrl.pause()
                        let newSec = ctrl.composeSeconds(h: outH, m: outM, s: outS, f: outF)
                        ctrl.endTime = max(newSec, ctrl.startTime + (1.0 / ctrl.fps))
                        ctrl.seek(to: ctrl.endTime)
                        syncTimecodeFields()
                    },
                    onStepFrame: { df in
                        ctrl.pause()
                        let frameDur = 1.0 / max(1.0, ctrl.fps)
                        ctrl.endTime = min(ctrl.duration, max(ctrl.startTime + frameDur, ctrl.endTime + Double(df) * frameDur))
                        ctrl.seek(to: ctrl.endTime)
                        syncTimecodeFields()
                    }
                )
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            
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
            
            HStack(spacing: 18) {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.3.fill").foregroundColor(.orange)
                    Text("볼륨").font(.caption)
                    Slider(value: $volumePercent, in: 20...200)
                        .frame(width: 110)
                        .tint(.orange)
                        .onChange(of: volumePercent) {
                            ctrl.setPreviewVolume(Float(volumePercent / 100.0))
                        }
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
        
        var activeChannels: [Int] = []
        for idx in 0..<ctrl.channelCount {
            if ctrl.isChannelActive(idx) { activeChannels.append(idx) }
        }
        
        if FileProcessor.ffmpegPath != nil {
            var filters: [String] = ["volume=\(volumePercent / 100.0)"]
            
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

// MARK: - 11. 배경 추가 창 (Add BG)
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

// MARK: - 12. 압축 도구 창
struct CompressToolView: View {
    let files: [URL]
    @State private var quality: Double = 65.0
    @State private var origBytes: Int64 = 0
    @State private var estBytes: Int64 = 0
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Compress \(files.count) File(s)").font(.headline)
            
            HStack(spacing: 18) {
                VStack(spacing: 4) {
                    Text("원본 크기").font(.caption).foregroundColor(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: origBytes, countStyle: .file))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
                
                VStack(spacing: 4) {
                    Text("예상 저장 크기").font(.caption).foregroundColor(.orange)
                    Text("~" + ByteCountFormatter.string(fromByteCount: estBytes, countStyle: .file))
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.orange)
                }
                
                if origBytes > 0 {
                    let savedRatio = max(0, Int(((1.0 - Double(estBytes) / Double(origBytes)) * 100.0).rounded()))
                    Text("-\(savedRatio)% 절감")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green, in: Capsule())
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            
            VStack(spacing: 6) {
                HStack {
                    Text("압축 품질 설정: \(Int(quality))%")
                        .font(.caption.bold())
                    Spacer()
                    Text("낮을수록 파일 크기가 더 많이 줄어듭니다")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Slider(value: $quality, in: 10...95)
                    .tint(.orange)
                    .onChange(of: quality) { recalculateEstimate() }
            }
            .padding(.horizontal, 8)
            
            HStack {
                Button("취소") { NSApp.keyWindow?.close() }
                Spacer()
                Button("압축 실행 및 저장") {
                    runCompression()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(.horizontal, 8)
        }
        .padding(22)
        .onAppear { recalculateEstimate() }
    }
    
    func recalculateEstimate() {
        let q = quality
        let targetFiles = files
        DispatchQueue.global(qos: .userInteractive).async {
            let res = FileSizeEstimator.estimateCompressedBytes(files: targetFiles, quality: q)
            DispatchQueue.main.async {
                self.origBytes = res.original
                self.estBytes = res.estimated
            }
        }
    }
    
    func runCompression() {
        for f in files {
            let ext = f.pathExtension.lowercased()
            if ["jpg", "jpeg", "png", "heic", "tiff", "bmp", "webp"].contains(ext),
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
}

// MARK: - 13. 메타데이터 확인 및 삭제 창
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

// MARK: - 14. 앱 델리게이트 & 메뉴바 설정 연동
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var wheelPanel: NSPanel!
    var wheelCenterPoint: NSPoint = .zero
    
    var dragCountAtMouseDown: Int = -1
    var activeSessionDragCount: Int = -1
    var isCurrentMouseStrokeValidFileDrag: Bool = false
    var eventTap: CFMachPort?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusBarMenu()
        
        JobProgressManager.shared.onUpdate = { [weak self] in
            self?.updateStatusBarMenu()
        }
        
        setupWheelPanel()
        startGlobalMonitors()
        setupCGEventTapForOptionCancelFix()
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
        menu.addItem(NSMenuItem(title: "🍊 MyTangerine 3.8 Pro", action: nil, keyEquivalent: ""))
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
        let helpItem = NSMenuItem(title: "📖 설명 및 단축키 설정...", action: #selector(openHelpAndSettings), keyEquivalent: ",")
        helpItem.target = self
        menu.addItem(helpItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "종료 (Quit)", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }
    
    @objc func openHelpAndSettings() {
        ToolWindowManager.shared.showHelpAndSettingsWindow()
    }
    
    @objc func quitApp() {
        NSApp.terminate(nil)
    }
    
    func setupWheelPanel() {
        wheelPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 356, height: 356),
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
    
    func setupCGEventTapForOptionCancelFix() {
        let mask = (1 << CGEventType.leftMouseUp.rawValue) |
                   (1 << CGEventType.leftMouseDragged.rawValue)
        
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let mySelf = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
            
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = mySelf.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            
            if AppState.shared.isDragging {
                if type == .leftMouseDragged || type == .leftMouseUp {
                    event.flags.remove([.maskAlternate, .maskShift, .maskControl, .maskCommand])
                }
                
                if type == .leftMouseUp {
                    mySelf.sendEscapeToCancelFinderDrag()
                    DispatchQueue.main.async {
                        mySelf.handleMouseUp()
                    }
                }
            }
            return Unmanaged.passUnretained(event)
        }
        
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: selfPtr
        ) {
            self.eventTap = tap
            let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
    
    func sendEscapeToCancelFinderDrag() {
        let src = CGEventSource(stateID: .hidSystemState)
        if let escDown = CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: true),
           let escUp = CGEvent(keyboardEventSource: src, virtualKey: 53, keyDown: false) {
            escDown.flags = []
            escUp.flags = []
            escDown.post(tap: .cghidEventTap)
            escUp.post(tap: .cghidEventTap)
        }
    }
    
    func startGlobalMonitors() {
        let dragPboard = NSPasteboard(name: .drag)
        dragCountAtMouseDown = dragPboard.changeCount
        
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            self.dragCountAtMouseDown = NSPasteboard(name: .drag).changeCount
            self.isCurrentMouseStrokeValidFileDrag = false
        }
        
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .flagsChanged]) { [weak self] event in
            self?.handleDragOrFlags(event: event)
        }
        
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            guard let self = self else { return }
            if AppState.shared.isDragging {
                self.handleMouseUp()
            }
        }
    }
    
    func handleDragOrFlags(event: NSEvent) {
        let mousePressed = (NSEvent.pressedMouseButtons & 1) != 0
        guard mousePressed else {
            if AppState.shared.isDragging { hideWheel() }
            return
        }
        
        guard let matchedMode = ShortcutSettings.shared.matchWheelMode(for: NSEvent.modifierFlags) else {
            if AppState.shared.isDragging { hideWheel() }
            return
        }
        
        let dragPboard = NSPasteboard(name: .drag)
        let currentChangeCount = dragPboard.changeCount
        
        if !isCurrentMouseStrokeValidFileDrag {
            guard currentChangeCount != dragCountAtMouseDown,
                  currentChangeCount != activeSessionDragCount else {
                return
            }
            let files = readValidDraggedFiles(from: dragPboard)
            guard !files.isEmpty else { return }
            
            isCurrentMouseStrokeValidFileDrag = true
            activeSessionDragCount = currentChangeCount
            AppState.shared.draggedFiles = files
            let bytes = calculateTotalBytes(files: files)
            AppState.shared.totalBytes = bytes
            AppState.shared.totalSizeText = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
        
        if !AppState.shared.isDragging {
            guard isCurrentMouseStrokeValidFileDrag, !AppState.shared.draggedFiles.isEmpty else { return }
            AppState.shared.wheelMode = matchedMode
            AppState.shared.updateItems()
            showWheel(at: NSEvent.mouseLocation)
        } else if event.type == .flagsChanged && AppState.shared.wheelMode != matchedMode {
            AppState.shared.wheelMode = matchedMode
            AppState.shared.updateItems()
        }
        
        updateHoveredSlice(mouseLocation: NSEvent.mouseLocation)
    }
    
    func readValidDraggedFiles(from pboard: NSPasteboard) -> [URL] {
        guard let types = pboard.types,
              types.contains(.fileURL) || types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType")) else {
            return []
        }
        guard let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else {
            return []
        }
        return urls.filter { $0.isFileURL && FileManager.default.fileExists(atPath: $0.path) }
    }
    
    func calculateTotalBytes(files: [URL]) -> Int64 {
        var total: Int64 = 0
        for f in files {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: f.path),
               let sz = attrs[.size] as? Int64 {
                total += sz
            }
        }
        return total
    }
    
    func showWheel(at point: NSPoint) {
        wheelCenterPoint = point
        AppState.shared.isDragging = true
        AppState.shared.hoveredIndex = nil
        wheelPanel.setFrameOrigin(NSPoint(x: point.x - 178, y: point.y - 178))
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
        
        guard dist > 48 && dist < 195 else {
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
        isCurrentMouseStrokeValidFileDrag = false
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
