// Opt-in reference capture for a Mac. No network access and no event injection.
// Build in Swift 5 language mode; macOS 13+ and Apple frameworks are required.
import AppKit
import AVFoundation
import CoreGraphics
import CoreImage
import ScreenCaptureKit
import Darwin

func hostTicks() -> UInt64 { mach_absolute_time() }
var timebase = mach_timebase_info_data_t()

final class Journal {
    private let file: FileHandle
    private let lock = NSLock()
    private var closed = false
    init(_ url: URL) throws {
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        file = try FileHandle(forWritingTo: url)
    }
    func append(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return }
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        file.write(data); file.write(Data([10]))
    }
    func finish() {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        closed = true; file.synchronizeFile(); file.closeFile()
    }
}

struct ProbeError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

final class Probe: NSObject, SCStreamOutput, SCStreamDelegate {
    let folder: URL
    let seconds: Double
    let fps: Int32
    let journal: Journal
    let videoQueue = DispatchQueue(label: "OmarchyLight.reference.frames")
    let context = CIContext(options: [.cacheIntermediates: false])
    var stream: SCStream?
    var writer: AVAssetWriter?
    var input: AVAssetWriterInput?
    var tap: CFMachPort?
    var tapSource: CFRunLoopSource?
    var interrupt: DispatchSourceSignal?
    var startedSession = false
    var stopping = false
    var exitStatus: Int32 = 0
    var frameIndex = 0
    var eventIndex = 0
    var lastMouseTime: UInt64 = 0
    let snapshotLock = NSLock()
    var snapshotRequested = false

    init(folder: URL, seconds: Double, fps: Int32) throws {
        self.folder = folder; self.seconds = seconds; self.fps = fps
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        journal = try Journal(folder.appendingPathComponent("timeline.jsonl"))
        super.init()
    }

    func recordEvent(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            journal.append(["type":"event_tap_gap", "hostMachTicks":hostTicks()])
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        var value: [String: Any] = ["type":"input", "eventIndex":eventIndex,
            "eventTimestampNs":event.timestamp, "callbackMachTicks":hostTicks()]
        if type == .keyDown || type == .keyUp {
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            let names: [Int64:String] = [53:"escape", 51:"backspace", 117:"delete", 126:"up", 125:"down",
                123:"left", 124:"right", 48:"tab", 36:"return", 76:"return", 100:"snapshot"]
            // Never read Unicode text or retain arbitrary letter/digit keycodes.
            value["action"] = key == 49 && event.flags.contains(.maskCommand) ? "spotlight" : names[key] ?? "typing"
            value["edge"] = type == .keyDown ? "down" : "up"
            value["repeat"] = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if key == 100 && type == .keyDown {
                snapshotLock.lock(); snapshotRequested = true; snapshotLock.unlock()
            }
        } else {
            let moved = type == .mouseMoved || type == .leftMouseDragged || type == .rightMouseDragged
            if moved && event.timestamp >= lastMouseTime && event.timestamp-lastMouseTime < 16_666_667 { return }
            lastMouseTime = event.timestamp
            value["action"] = moved ? "pointer_move" : type == .leftMouseDown ? "left_down" :
                type == .leftMouseUp ? "left_up" : type == .rightMouseDown ? "right_down" : "right_up"
            value["x"] = event.location.x; value["y"] = event.location.y
        }
        eventIndex += 1
        journal.append(value)
    }

    func installEventTap() throws {
        let types: [CGEventType] = [.keyDown, .keyUp, .mouseMoved, .leftMouseDragged, .rightMouseDragged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, info in
            if let info { Unmanaged<Probe>.fromOpaque(info).takeUnretainedValue().recordEvent(type, event) }
            return Unmanaged.passUnretained(event)
        }
        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            throw ProbeError("Input Monitoring permission is required for this executable/terminal. Grant it in System Settings, then rerun.")
        }
        tap = created
        tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
    }

    @MainActor func start() async throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw ProbeError("Screen Recording permission is required. Grant it to this executable/terminal in System Settings, then rerun.")
        }
        try installEventTap()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }),
              let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID }) else {
            throw ProbeError("The main display could not be resolved.")
        }
        let scale = screen.backingScaleFactor
        let width = min(720.0, screen.frame.width), height = min(580.0, screen.frame.height)
        let region = CGRect(x:(screen.frame.width-width)/2, y:min(70,screen.frame.height-height), width:width, height:height)
        let config = SCStreamConfiguration()
        config.sourceRect = region
        config.width = Int(width*scale); config.height = Int(height*scale)
        config.minimumFrameInterval = CMTime(value:1, timescale:fps)
        config.queueDepth = 8; config.showsCursor = true; config.capturesAudio = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        let filter = SCContentFilter(display:display, excludingApplications:[], exceptingWindows:[])
        let video = try AVAssetWriter(outputURL:folder.appendingPathComponent("reference.mov"), fileType:.mov)
        let track = AVAssetWriterInput(mediaType:.video, outputSettings:[
            AVVideoCodecKey:AVVideoCodecType.proRes4444, AVVideoWidthKey:config.width, AVVideoHeightKey:config.height])
        track.expectsMediaDataInRealTime = true
        guard video.canAdd(track) else { throw ProbeError("ProRes 4444 output is unavailable.") }
        video.add(track)
        guard video.startWriting() else { throw video.error ?? ProbeError("Video writer could not start.") }
        writer = video; input = track
        journal.append(["type":"metadata", "schema":1, "hostMachTicks":hostTicks(),
            "machTimebaseNumer":timebase.numer, "machTimebaseDenom":timebase.denom,
            "os":ProcessInfo.processInfo.operatingSystemVersionString, "requestedFPS":fps,
            "displayID":display.displayID, "displayScale":scale,
            "regionPoints":[region.minX,region.minY,region.width,region.height],
            "outputPixels":[config.width,config.height], "durationSeconds":seconds,
            "eventClock":"CGEvent timestamp: nanoseconds since startup",
            "displayClock":"SCStreamFrameInfo.displayTime: raw mach absolute ticks",
            "inputScope":"shortcut names, generic typing edges, pointer coordinates; no typed text",
            "font":NSFont.systemFont(ofSize:26).fontName])
        let capture = SCStream(filter:filter, configuration:config, delegate:self)
        try capture.addStreamOutput(self, type:.screen, sampleHandlerQueue:videoQueue)
        stream = capture
        try await capture.startCapture()
        print("Recording \(seconds)s into \(folder.path). F8 saves a lossless still. Ctrl+C stops. No audio is captured.")
        DispatchQueue.main.asyncAfter(deadline:.now()+seconds) { Task { @MainActor in await self.stop() } }
        signal(SIGINT, SIG_IGN)
        let signalSource = DispatchSource.makeSignalSource(signal:SIGINT, queue:.main)
        signalSource.setEventHandler { Task { @MainActor in await self.stop() } }
        signalSource.resume(); interrupt = signalSource
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sample.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary:false) as? [[SCStreamFrameInfo:Any]],
              let info = attachments.first, let status = info[.status] as? Int,
              status == SCFrameStatus.complete.rawValue, let writer, let input else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        if !startedSession { writer.startSession(atSourceTime:pts); startedSession = true }
        let accepted = input.isReadyForMoreMediaData && input.append(sample)
        var row: [String:Any] = ["type":"frame", "frameIndex":frameIndex,
            "sourcePTSValue":pts.value, "sourcePTSTimescale":pts.timescale,
            "callbackMachTicks":hostTicks(), "written":accepted]
        if let displayTime = info[.displayTime] as? NSNumber { row["displayMachTicks"] = displayTime.uint64Value }
        if !accepted { row["writerStatus"] = writer.status.rawValue }
        snapshotLock.lock(); let snapshot = snapshotRequested; snapshotRequested = false; snapshotLock.unlock()
        if snapshot, let buffer = CMSampleBufferGetImageBuffer(sample),
           let image = context.createCGImage(CIImage(cvPixelBuffer:buffer), from:CGRect(x:0,y:0,
               width:CGFloat(CVPixelBufferGetWidth(buffer)),height:CGFloat(CVPixelBufferGetHeight(buffer)))),
           let png = NSBitmapImageRep(cgImage:image).representation(using:.png, properties:[:]) {
            let name = String(format:"still-%06d.png",frameIndex)
            do { try png.write(to:folder.appendingPathComponent(name)); row["still"] = name }
            catch { row["stillError"] = error.localizedDescription }
        }
        journal.append(row); frameIndex += 1
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        journal.append(["type":"capture_error", "message":error.localizedDescription, "hostMachTicks":hostTicks()])
        Task { @MainActor in self.exitStatus = 1; await self.stop() }
    }

    @MainActor func stop() async {
        guard !stopping else { return }; stopping = true
        if let tap { CGEvent.tapEnable(tap:tap, enable:false) }
        if let source = tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(),source,.commonModes) }
        if let stream { try? await stream.stopCapture() }
        // Drain outstanding sample callbacks before finalizing the movie.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void,Never>) in
            videoQueue.async { continuation.resume() }
        }
        if let writer, let input {
            if startedSession {
                input.markAsFinished()
                await writer.finishWriting()
                journal.append(["type":"writer_end", "status":writer.status.rawValue,
                    "error":writer.error?.localizedDescription ?? ""])
                if writer.status != .completed { exitStatus = 1 }
            } else { writer.cancelWriting(); exitStatus = 1 }
        }
        journal.append(["type":"end", "hostMachTicks":hostTicks(), "frames":frameIndex, "exitStatus":exitStatus]); journal.finish()
        Darwin.exit(exitStatus)
    }
}

@main struct Main {
    static var retainedProbe: Probe?
    @MainActor static func main() {
        mach_timebase_info(&timebase)
        let args = CommandLine.arguments
        guard args.count >= 2, args.count <= 4 else {
            fputs("Usage: reference-probe NEW_OUTPUT_DIRECTORY [seconds=30] [fps=60]\n",stderr); exit(2)
        }
        let seconds = args.count>2 ? Double(args[2]) ?? 0 : 30
        let fps = args.count>3 ? Int32(args[3]) ?? 0 : 60
        guard seconds>=5, seconds<=120, fps>=30, fps<=120 else {
            fputs("Duration must be 5–120 seconds; FPS must be 30–120.\n",stderr); exit(2)
        }
        do {
            let probe = try Probe(folder:URL(fileURLWithPath:args[1],isDirectory:true), seconds:seconds, fps:fps)
            retainedProbe = probe
            let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
            Task { @MainActor in
                do { try await probe.start() }
                catch {
                    fputs("\(error)\n",stderr)
                    probe.exitStatus = 1
                    probe.journal.append(["type":"capture_error", "message":String(describing:error), "hostMachTicks":hostTicks()])
                    await probe.stop()
                }
            }
            app.run()
        } catch { fputs("\(error)\n",stderr); exit(1) }
    }
}
