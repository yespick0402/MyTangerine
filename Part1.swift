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

// MARK: - 0. 3종 휠 단축키 매니저 (오리지널 Tangerine 기본값: Shift / Option+Shift / Control)
class ShortcutSettings: ObservableObject {
    static let shared = ShortcutSettings()
    
    @Published var convertFlagsRaw: UInt {
        didSet { UserDefaults.standard.set(Int(convertFlagsRaw), forKey: "tangerine_sc_convert_v39") }
    }
    @Published var toolsFlagsRaw: UInt {
        didSet { UserDefaults.standard.set(Int(toolsFlagsRaw), forKey: "tangerine_sc_tools_v39") }
    }
    @Published var actionsFlagsRaw: UInt {
        didSet { UserDefaults.standard.set(Int(actionsFlagsRaw), forKey: "tangerine_sc_actions_v39") }
    }
    
    static let defaultConvertRaw: UInt = NSEvent.ModifierFlags.shift.rawValue
    static let defaultToolsRaw: UInt = NSEvent.ModifierFlags([.option, .shift]).rawValue
    static let defaultActionsRaw: UInt = NSEvent.ModifierFlags.control.rawValue
    
    init() {
        let savedConv = UserDefaults.standard.integer(forKey: "tangerine_sc_convert_v39")
        let savedTools = UserDefaults.standard.integer(forKey: "tangerine_sc_tools_v39")
        let savedActions = UserDefaults.standard.integer(forKey: "tangerine_sc_actions_v39")
        self.convertFlagsRaw = (savedConv != 0) ? UInt(savedConv) : Self.defaultConvertRaw
        self.toolsFlagsRaw = (savedTools != 0) ? UInt(savedTools) : Self.defaultToolsRaw
        self.actionsFlagsRaw = (savedActions != 0) ? UInt(savedActions) : Self.defaultActionsRaw
    }
    
    var convertFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: convertFlagsRaw).intersection([.shift, .option, .control, .command])
    }
    var toolsFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: toolsFlagsRaw).intersection([.shift, .option, .control, .command])
    }
    var actionsFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: actionsFlagsRaw).intersection([.shift, .option, .control, .command])
    }
    
    func resetToTangerineDefaults() {
        convertFlagsRaw = Self.defaultConvertRaw
        toolsFlagsRaw = Self.defaultToolsRaw
        actionsFlagsRaw = Self.defaultActionsRaw
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
        let tFlags = toolsFlags; let aFlags = actionsFlags; let cFlags = convertFlags
        if clean == tFlags { return .tools }
        if clean == aFlags { return .actions }
        if clean == cFlags { return .convert }
        
        let candidates: [(WheelMode, NSEvent.ModifierFlags)] = [
            (.tools, tFlags), (.actions, aFlags), (.convert, cFlags)
        ].sorted { $0.1.rawValue.nonzeroBitCount > $1.1.rawValue.nonzeroBitCount }
        
        for (mode, req) in candidates where !req.isEmpty {
            if clean.isSuperset(of: req) { return mode }
        }
        return nil
    }
}

// MARK: - 1. 작업 진행률 매니저
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
        return jobs.reduce(0.0) { $0 + $1.progress } / Double(jobs.count)
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

// MARK: - 2. 글로벌 상태 및 3종 휠 모델
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
            let files = draggedFiles; let origTotal = totalBytes
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
                        if self.isDragging && self.wheelMode == .convert { self.items = updated }
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
            let totalDuration = files.reduce(0.0) { $0 + FileProcessor.mediaDurationSeconds(for: $1) }
            if totalDuration > 0 {
                switch tgt {
                case "mp3", "m4a", "aac", "caf", "ogg": return max(4096, Int64(totalDuration * 24_000))
                case "wav", "aiff": return max(8192, Int64(totalDuration * 176_400))
                case "flac": return max(8192, Int64(totalDuration * 96_000))
                case "gif": return max(10_240, Int64(totalDuration * 380_000))
                case "mp4", "mov", "mkv":
                    let ratio: Double = (srcExt == "mov") ? 0.68 : 0.88
                    return max(16_384, Int64(Double(originalTotalBytes) * ratio))
                default: break
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
        return max(1024, Int64(Double(originalTotalBytes) * (tgtW / srcW)))
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
        case "jpg", "jpeg": sampleDataSize = Int64(rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])?.count ?? 0)
        case "png": sampleDataSize = Int64(rep.representation(using: .png, properties: [:])?.count ?? 0)
        case "tiff": sampleDataSize = Int64(rep.representation(using: .tiff, properties: [:])?.count ?? 0)
        case "bmp": sampleDataSize = Int64(rep.representation(using: .bmp, properties: [:])?.count ?? 0)
        case "heic", "webp":
            if let jpgCount = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])?.count {
                sampleDataSize = Int64(Double(jpgCount) * 0.62)
            }
        case "pdf":
            if let jpgCount = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.90])?.count {
                sampleDataSize = Int64(jpgCount + 4096)
            }
        default: break
        }
        if let sSize = sampleDataSize, sSize > 0 {
            return max(1024, Int64(Double(originalTotalBytes) * (Double(sSize) / Double(firstOrigSize))))
        }
        return estimateConversionBytes(files: files, originalTotalBytes: originalTotalBytes, targetExt: targetExt)
    }
    
    static func estimateCompressedBytes(files: [URL], quality: Double) -> (original: Int64, estimated: Int64) {
        var origTotal: Int64 = 0; var estTotal: Int64 = 0
        for (index, f) in files.enumerated() {
            let fSize = (try? FileManager.default.attributesOfItem(atPath: f.path)[.size] as? Int64) ?? 0
            origTotal += fSize
            let ext = f.pathExtension.lowercased()
            if ["jpg", "jpeg", "png", "heic", "tiff", "bmp", "webp"].contains(ext) {
                if index == 0, let cg = FileProcessor.loadRawCGImage(from: f) {
                    let rep = NSBitmapImageRep(cgImage: cg)
                    if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: quality / 100.0]) {
                        estTotal += Int64(data.count); continue
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

// MARK: - 4. 파일 처리 및 변환 엔진
class FileProcessor {
    static var ffmpegPath: String? {
        let candidates = [
            Bundle.main.path(forResource: "ffmpeg", ofType: nil),
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg"
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
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
        var result: Double = 0
        let sem = DispatchSemaphore(value: 0)
        let asset = AVURLAsset(url: url)
        Task {
            if let dur = try? await asset.load(.duration) {
                let sec = CMTimeGetSeconds(dur)
                if sec.isFinite && sec > 0 { result = sec }
            }
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 1.5)
        return result
    }
    
    static func runFFmpegWithProgress(args: [String], totalDuration: Double, jobTitle: String, completion: @escaping (Bool) -> Void) {
        guard let ffmpeg = ffmpegPath else { completion(false); return }
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
                    JobProgressManager.shared.updateJob(id: jobID, progress: min(0.99, max(0.01, currentSec / totalDuration)))
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
        let timeStr = String(log[range.upperBound...].prefix(11))
        let parts = timeStr.split(separator: ":")
        guard parts.count == 3,
              let h = Double(parts[0]), let m = Double(parts[1]),
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
        if actionKey == "tool_edit_photo", let first = files.first { ToolWindowManager.shared.showEditPhotoWindow(url: first); return }
        if actionKey == "tool_crop", let first = files.first { ToolWindowManager.shared.showRedactCropWindow(url: first, initialTab: 1); return }
        if actionKey == "tool_redact", let first = files.first { ToolWindowManager.shared.showRedactCropWindow(url: first, initialTab: 0); return }
        if actionKey == "tool_add_bg", let first = files.first { ToolWindowManager.shared.showAddBGWindow(url: first); return }
        if actionKey == "tool_compress" { ToolWindowManager.shared.showCompressWindow(urls: files); return }
        if actionKey == "tool_metadata", let first = files.first { ToolWindowManager.shared.showMetadataWindow(url: first); return }
        if ["tool_audio_video_trim", "tool_audio_channels", "tool_audio_bleep"].contains(actionKey), let first = files.first {
            ToolWindowManager.shared.showMediaStudioWindow(url: first, initialTab: actionKey); return
        }
        if actionKey == "tool_qr", let first = files.first { readQRCode(from: first); return }
        if actionKey == "tool_merge_pdf" { mergeToPDF(files: files); return }
        
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
        if actionKey == "act_finder" { NSWorkspace.shared.activateFileViewerSelecting(files); return }
        if actionKey == "act_airdrop" {
            if let service = NSSharingService(named: .sendViaAirDrop) { service.perform(withItems: files) }
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
                convertFile(file, to: actionKey.replacingOccurrences(of: "conv_", with: ""))
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
                if ok { showToast("\(ext.uppercased()) 변환 완료!") } else { convertMediaHybrid(file, to: ext) }
            }
            return
        }
        if ext == "pdf", let img = NSImage(contentsOf: file) {
            let out = uniqueOutputURL(for: file, newExt: "pdf")
            let pdf = PDFDocument()
            if let page = PDFPage(image: img) {
                pdf.insert(page, at: 0); pdf.write(to: out)
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
            if ext == "mp4" { args += ["-c:v", "libx264", "-preset", "fast", "-crf", "22", "-c:a", "aac", "-pix_fmt", "yuv420p", out.path] }
            else if ext == "mov" { args += ["-c:v", "libx264", "-c:a", "aac", out.path] }
            else if ext == "gif" { args += ["-vf", "fps=12,scale=640:-1:flags=lanczos", out.path] }
            else if ext == "mp3" { args += ["-vn", "-c:a", "libmp3lame", "-q:a", "2", out.path] }
            else if ext == "m4a" { args += ["-vn", "-c:a", "aac", "-b:a", "192k", out.path] }
            else if ext == "wav" { args += ["-vn", "-c:a", "pcm_s16le", out.path] }
            else if ext == "flac" { args += ["-vn", "-c:a", "flac", out.path] }
            else { args.append(out.path) }
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
            showToast("변환기를 초기화할 수 없습니다."); return
        }
        var targetURL = outURL
        if isAudioOnly { targetURL = uniqueOutputURL(for: file, newExt: "m4a"); exporter.outputFileType = .m4a }
        else if ext == "mp4" { exporter.outputFileType = .mp4 }
        else { exporter.outputFileType = .mov }
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
        if ext == "png" { data = rep.representation(using: .png, properties: [:]) }
        else if ext == "tiff" { data = rep.representation(using: .tiff, properties: [:]) }
        else if ext == "bmp" { data = rep.representation(using: .bmp, properties: [:]) }
        else { data = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) }
        try? data?.write(to: url)
    }
    
    static func readQRCode(from url: URL) {
        guard let ciImage = CIImage(contentsOf: url) else { return }
        let request = VNDetectBarcodesRequest { req, _ in
            if let results = req.results as? [VNBarcodeObservation], let payload = results.first?.payloadStringValue {
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
                for i in 0..<sub.pageCount { if let page = sub.page(at: i) { pdf.insert(page, at: pdf.pageCount) } }
            } else if let img = NSImage(contentsOf: f), let page = PDFPage(image: img) {
                pdf.insert(page, at: pdf.pageCount)
            }
        }
        let out = uniqueOutputURL(for: first, newExt: "pdf", suffix: "_merged")
        pdf.write(to: out)
        showToast("PDF 병합 완료: \(out.lastPathComponent)")
    }
    
    static func showToast(_ message: String) {
        DispatchQueue.main.async { ToolWindowManager.shared.showBanner(message: message) }
    }
}

// MARK: - 5. 마우스 휠 확대/축소 감지 뷰 및 원형 다이얼 휠 UI
struct ScrollWheelCatcher: NSViewRepresentable {
    var onScroll: (CGFloat) -> Void
    func makeNSView(context: Context) -> ScrollWheelNSView {
        let v = ScrollWheelNSView(); v.onScroll = onScroll; return v
    }
    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) { nsView.onScroll = onScroll }
    class ScrollWheelNSView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        override func scrollWheel(with event: NSEvent) {
            if abs(event.scrollingDeltaY) > 0.01 { onScroll?(event.scrollingDeltaY) }
        }
    }
}

struct PieSliceShape: Shape {
    var startAngle: Angle; var endAngle: Angle; var innerRadiusRatio: CGFloat = 0.35
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
            Circle().fill(.ultraThinMaterial).frame(width: wheelSize + 16, height: wheelSize + 16)
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.32), radius: 18, x: 0, y: 8)
            slicesView
            centerBadgeView
        }.frame(width: wheelSize + 30, height: wheelSize + 30)
    }
    var slicesView: some View {
        let count = max(state.items.count, 1)
        let angleStep = 360.0 / Double(count)
        return ForEach(0..<state.items.count, id: \.self) { index in sliceItemView(index: index, angleStep: angleStep) }
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
            PieSliceShape(startAngle: start, endAngle: end).fill(fillGrad)
                .overlay(PieSliceShape(startAngle: start, endAngle: end).stroke(isHovered ? Color.white : Color.black.opacity(0.08), lineWidth: 1.2))
            VStack(spacing: 2) {
                Image(systemName: item.icon).font(.system(size: 15, weight: .semibold))
                Text(item.title).font(.system(size: 11, weight: .bold, design: .rounded)).lineLimit(1)
                if let est = item.estimatedSizeText {
                    Text(est).font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(isHovered ? .white.opacity(0.95) : .black.opacity(0.62))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(isHovered ? Color.black.opacity(0.22) : Color.black.opacity(0.06), in: Capsule())
                }
            }
            .foregroundColor(isHovered ? .white : .black.opacity(0.85))
            .position(x: wheelSize / 2.0 + CGFloat(cos(midAngle)) * labelRadius, y: wheelSize / 2.0 + CGFloat(sin(midAngle)) * labelRadius)
        }.frame(width: wheelSize, height: wheelSize)
    }
    var centerBadgeView: some View {
        VStack(spacing: 2) {
            Text(state.wheelMode.rawValue).font(.system(size: 9, weight: .heavy, design: .rounded)).foregroundColor(.orange)
            Text(state.totalSizeText).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(.primary)
            if let idx = state.hoveredIndex, idx < state.items.count, let est = state.items[idx].estimatedSizeText {
                Text("예상 \(est)").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.orange)
            } else {
                Text("\(state.draggedFiles.count)개 파일").font(.system(size: 9.5, weight: .medium)).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
    }
}

// MARK: - 6. 도구 창 매니저 및 3종 단축키 설정 창
class ToolWindowManager {
    static let shared = ToolWindowManager()
    var activeWindows: [NSWindow] = []
    var bannerWindow: NSPanel?
    
    func openWindow<V: View>(title: String, view: V, size: NSSize, minSize: NSSize = NSSize(width: 680, height: 500)) {
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        win.title = title; win.minSize = minSize; win.isReleasedWhenClosed = false
        win.center(); win.contentView = NSHostingView(rootView: view)
        win.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        activeWindows.append(win)
    }
    
    func showBanner(message: String) {
        bannerWindow?.close()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 52), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.level = .statusBar
        if let screen = NSScreen.main { panel.setFrameOrigin(NSPoint(x: screen.frame.midX - 200, y: screen.frame.maxY - 90)) }
        panel.contentView = NSHostingView(rootView:
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.orange).font(.title2)
                Text(message).font(.system(size: 13, weight: .semibold)).foregroundColor(.primary)
            }
            .padding(.horizontal, 18).padding(.vertical, 12).background(.regularMaterial, in: Capsule()).shadow(radius: 10)
        )
        panel.orderFrontRegardless(); bannerWindow = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { panel.close() }
    }
    
    func showHelpAndSettingsWindow() {
        openWindow(title: "🍊 MyTangerine — 설명 및 단축키 설정", view: HelpAndSettingsView(), size: NSSize(width: 780, height: 660), minSize: NSSize(width: 700, height: 560))
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

struct HelpAndSettingsView: View {
    @ObservedObject var settings = ShortcutSettings.shared
    @State private var selectedTab: Int = 0
    @State private var recordingTarget: String? = nil
    @State private var tempRecordedFlags: NSEvent.ModifierFlags = []
    @State private var localMonitor: Any? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "circle.hexagongrid.fill").font(.system(size: 36)).foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MyTangerine 3.9 Pro").font(.system(size: 20, weight: .heavy, design: .rounded))
                    Text("파인더에서 파일을 드래그하며 단축키를 눌러 즉시 변환·편집·액션을 실행하는 맥 유틸리티").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Picker("", selection: $selectedTab) {
                    Text("⌨️ 단축키 설정").tag(0)
                    Text("📖 상세 사용 설명서").tag(1)
                }.pickerStyle(.segmented).frame(width: 280)
            }
            .padding(18).background(.regularMaterial)
            Divider()
            if selectedTab == 0 { shortcutRecorderTab } else { usageGuideTab }
            Divider()
            HStack {
                Text("💡 Tangerine 기본값: 변환 = ⇧ Shift  |  도구 = ⌥⇧ Option + Shift  |  액션 = ⌃ Control")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("Tangerine 기본 단축키로 복원") {
                    stopRecording(); settings.resetToTangerineDefaults()
                    FileProcessor.showToast("Tangerine 기본 단축키(Shift / Option+Shift / Control)로 복원되었습니다.")
                }
                Button("닫기") { stopRecording(); NSApp.keyWindow?.close() }
                    .buttonStyle(.borderedProminent).tint(.orange)
            }
            .padding(14).background(.regularMaterial)
        }.onDisappear { stopRecording() }
    }
    
    var shortcutRecorderTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("3가지 원형 휠 단축키 직접 입력 설정").font(.headline).foregroundColor(.orange)
                    Text("바꾸고 싶은 기능의 [단축키 입력하기] 버튼을 누른 뒤, 키보드에서 원하는 조합(예: Shift, Option+Shift, Control 등)을 누르고 마우스로 [완료] 버튼을 클릭하면 적용됩니다.")
                        .font(.caption).foregroundColor(.secondary)
                }
                VStack(spacing: 14) {
                    recorderCard(
                        targetID: "convert", title: "🔄 포맷 변환 휠 (CONVERT)",
                        subtitle: "파일을 드래그하면서 이 키를 누르면 JPG, PNG, WEBP, HEIC, PDF, MP4, MOV, GIF, MP3, WAV 등으로 즉시 변환합니다.",
                        currentFlags: settings.convertFlags,
                        onSave: { newFlags in settings.convertFlagsRaw = newFlags.rawValue; FileProcessor.showToast("변환(CONVERT) 단축키가 저장되었습니다.") }
                    )
                    recorderCard(
                        targetID: "tools", title: "🛠️ 전용 편집 도구 휠 (TOOLS)",
                        subtitle: "파일을 드래그하면서 이 키를 누르면 사진 보정(Edit), 크롭(Crop), 모자이크(Redact), 배경 추가(Add BG), 영상/오디오 트림, 압축 도구가 열립니다.",
                        currentFlags: settings.toolsFlags,
                        onSave: { newFlags in settings.toolsFlagsRaw = newFlags.rawValue; FileProcessor.showToast("도구(TOOLS) 단축키가 저장되었습니다.") }
                    )
                    recorderCard(
                        targetID: "actions", title: "⚡ 빠른 액션 휠 (ACTIONS)",
                        subtitle: "파일을 드래그하면서 이 키를 누르면 경로 복사, 터미널 열기, AirDrop 전송, Finder 표시, 사본 만들기 휠이 열립니다.",
                        currentFlags: settings.actionsFlags,
                        onSave: { newFlags in settings.actionsFlagsRaw = newFlags.rawValue; FileProcessor.showToast("빠른 액션(ACTIONS) 단축키가 저장되었습니다.") }
                    )
                }
            }.padding(22)
        }
    }
    
    @ViewBuilder
    func recorderCard(targetID: String, title: String, subtitle: String, currentFlags: NSEvent.ModifierFlags, onSave: @escaping (NSEvent.ModifierFlags) -> Void) -> some View {
        let isRecordingThis = (recordingTarget == targetID)
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .bold))
                Text(subtitle).font(.caption).foregroundColor(.secondary)
            }
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: isRecordingThis ? "keyboard.badge.ellipsis" : "keyboard").foregroundColor(isRecordingThis ? .orange : .secondary)
                    if isRecordingThis {
                        Text(tempRecordedFlags.isEmpty ? "원하는 키 조합(Shift, Option, Control, Command)을 누르세요..." : ShortcutSettings.formatFlags(tempRecordedFlags))
                            .font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundColor(.orange)
                    } else {
                        Text("파일 드래그 + " + ShortcutSettings.formatFlags(currentFlags))
                            .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(.primary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Color.black.opacity(isRecordingThis ? 0.28 : 0.14), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(isRecordingThis ? Color.orange : Color.white.opacity(0.2), lineWidth: isRecordingThis ? 2 : 1))
                
                if isRecordingThis {
                    Button("완료") {
                        if !tempRecordedFlags.isEmpty { onSave(tempRecordedFlags) }
                        stopRecording()
                    }.buttonStyle(.borderedProminent).tint(.green).disabled(tempRecordedFlags.isEmpty)
                    Button("취소") { stopRecording() }
                } else {
                    Button("단축키 입력하기") { startRecording(for: targetID) }.buttonStyle(.borderedProminent).tint(.orange)
                }
            }
        }.padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    func startRecording(for targetID: String) {
        stopRecording(); recordingTarget = targetID; tempRecordedFlags = []
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
            if !flags.isEmpty { self.tempRecordedFlags = flags }
            return nil
        }
    }
    func stopRecording() {
        if let mon = localMonitor { NSEvent.removeMonitor(mon); localMonitor = nil }
        recordingTarget = nil; tempRecordedFlags = []
    }
    
    var usageGuideTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                guideCard(icon: "hand.draw.fill", title: "1. 3가지 원형 휠 작동법 (Tangerine 방식)", items: [
                    "🔄 Shift + 드래그 (CONVERT): 각 포맷 조각에 예상 파일 크기(~1.2 MB)가 표시되며, 드롭 즉시 원본 옆에 변환 저장됩니다.",
                    "🛠️ Option + Shift + 드래그 (TOOLS): 해당 파일 종류에 맞는 전용 편집 도구(Edit, Crop, Redact, Add BG, Trim, Compress 등)가 열립니다.",
                    "⚡ Control + 드래그 (ACTIONS): 파일 경로 복사, 해당 폴더에서 터미널 열기, AirDrop 공유, 사본 생성 등 빠른 액션이 실행됩니다."
                ])
                guideCard(icon: "photo.on.rectangle.angled", title: "2. 사진 편집 도구 (Edit Photo / Crop / Redact / Add BG)", items: [
                    "EDIT PHOTO: 노출, 휘도, 하이라이트, 그림자, 대비, 채도, 색온도 등 14가지 슬라이더로 원본 화질 그대로 보정합니다.",
                    "CROP (8방향 자르기): 노란색 모서리 핸들 4곳으로 두 변을 동시에 조절하거나, 상·하·좌·우 흰색 바 4곳으로 각 변을 개별 조절합니다.",
                    "확대/축소 및 이동: 마우스 스크롤 휠로 정중앙 기준 확대/축소가 가능하며, 드래그하여 이미지를 이동할 수 있습니다."
                ])
                guideCard(icon: "film.stack", title: "3. 영상/오디오 정밀 트림 & 다중 채널 스튜디오", items: [
                    "타임라인 양끝의 노란색 트림 바(시작점 In ~ 종료점 Out) 안쪽 구간만 정확하게 보고 들을 수 있도록 재생 범위가 고정됩니다.",
                    "다중 채널 오디오 믹서: 2채널부터 4채널, 8채널 이상의 오디오 트랙을 자동 감지하여 원하는 채널만 켜고 끄거나(ON/MUTE) 단독 청취(SOLO)할 수 있습니다."
                ])
            }.padding(22)
        }
    }
    func guideCard(icon: String, title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) { Image(systemName: icon).foregroundColor(.orange).font(.title3); Text(title).font(.headline) }
            ForEach(items, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) { Text("•").foregroundColor(.orange).bold(); Text(line).font(.system(size: 13)) }
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
