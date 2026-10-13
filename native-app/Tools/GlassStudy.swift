// Native, current-process-only visual study. Does not read preferences or capture other apps.
import AppKit
import SwiftUI
import ScreenCaptureKit

struct StudySurface: View {
    let rich: Bool
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red:0.04,green:0.09,blue:0.20),Color(red:0.20,green:0.29,blue:0.44)], startPoint:.bottomLeading,endPoint:.topTrailing)
            if rich {
                ForEach(0..<15) { index in
                    RoundedRectangle(cornerRadius: 14).fill([Color.cyan,.purple,.orange,.white][index % 4].opacity(0.65))
                        .frame(width:70,height:95).rotationEffect(.degrees(Double(index)*13))
                        .position(x:CGFloat(index)*63,y:CGFloat(index%3)*110+60)
                }
            }
            GlassEffectContainer(spacing: 0) {
                HStack(spacing: 24) {
                    content("SwiftUI · Regular").glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
                    content("SwiftUI · Clear").glassEffect(.clear, in: RoundedRectangle(cornerRadius: 22))
                }.padding(28)
            }
        }
    }
    private func content(_ title: String) -> some View {
        VStack(alignment:.leading,spacing:18) {
            Text(title).font(.headline)
            HStack { Text("CPU"); Spacer(); Text("42%").font(.title2) }
            ProgressView(value:0.42).tint(.cyan)
            Text("Native material · no custom rim or blur").font(.caption)
        }.foregroundStyle(.white).padding(22).frame(maxWidth:.infinity,minHeight:170)
    }
}
final class Pattern: NSView {
    var rich = true
    override func draw(_ dirtyRect: NSRect) {
        NSGradient(starting: NSColor(red:0.04,green:0.09,blue:0.20,alpha:1), ending: NSColor(red:0.20,green:0.29,blue:0.44,alpha:1))!.draw(in:bounds,angle:30)
        if rich {
            let colors: [NSColor] = [.cyan,.purple,.orange,.white]
            for i in 0..<15 {
                colors[i%4].withAlphaComponent(0.65).setFill()
                NSBezierPath(roundedRect:NSRect(x:i*63,y:(i%3)*75,width:70,height:95),xRadius:14,yRadius:14).fill()
            }
        }
    }
}
@main struct GlassStudy {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let previous = NSWorkspace.shared.frontmostApplication
        let root = NSView(frame:NSRect(x:0,y:0,width:900,height:650))
        let backdrop = Pattern(frame:root.bounds); root.addSubview(backdrop)
        let hosting = NSHostingView(rootView: StudySurface(rich:true))
        hosting.frame = NSRect(x:0,y:320,width:900,height:330); root.addSubview(hosting)
        let group = NSGlassEffectContainerView(frame:NSRect(x:0,y:0,width:900,height:320))
        let groupContent = NSView(frame:group.bounds)
        groupContent.translatesAutoresizingMaskIntoConstraints=false
        NSLayoutConstraint.activate([groupContent.widthAnchor.constraint(equalToConstant:900),groupContent.heightAnchor.constraint(equalToConstant:320)])
        group.contentView=groupContent; group.spacing=0; root.addSubview(group)
        for (index,style) in [NSGlassEffectView.Style.regular,.clear].enumerated() {
            let glass = NSGlassEffectView(frame:NSRect(x:28+index*438,y:45,width:410,height:225))
            glass.style=style; glass.cornerRadius=22
            let content = NSView(frame:NSRect(x:0,y:0,width:410,height:225))
            content.translatesAutoresizingMaskIntoConstraints=false
            NSLayoutConstraint.activate([content.widthAnchor.constraint(equalToConstant:410),content.heightAnchor.constraint(equalToConstant:225)])
            for (text,y,size) in [("AppKit · \(index == 0 ? "Regular" : "Clear")",170,18),("CPU                                  42%",110,20),("Native NSTextField content",50,13)] {
                let field=NSTextField(labelWithString:text);field.frame=NSRect(x:22,y:y,width:365,height:30)
                field.font=NSFont.systemFont(ofSize:CGFloat(size));field.textColor = .white;content.addSubview(field)
            }
            glass.contentView=content;groupContent.addSubview(glass)
        }
        for (index, style) in [NSGlassEffectView.Style.regular, .clear].enumerated() {
            let pill = NSGlassEffectView(frame: NSRect(x:28+index*220,y:4,width:190,height:36))
            pill.style=style; pill.cornerRadius=18
            let label=NSTextField(labelWithString:index == 0 ? "Small · Regular" : "Small · Clear")
            label.font=NSFont.systemFont(ofSize:13,weight:.semibold); label.textColor = .white
            label.alignment = .center; label.translatesAutoresizingMaskIntoConstraints=false
            NSLayoutConstraint.activate([label.widthAnchor.constraint(equalToConstant:190), label.heightAnchor.constraint(equalToConstant:36)])
            pill.contentView=label; groupContent.addSubview(pill)
        }
        let window=NSWindow(contentRect:root.bounds,styleMask:[.titled],backing:.buffered,defer:false)
        window.title="Sorayura · native glass study";window.contentView=root;window.isReleasedWhenClosed=false
        window.center();window.makeKeyAndOrderFront(nil);app.activate(ignoringOtherApps:true)
        let focus=NSWindow(contentRect:NSRect(x:0,y:0,width:180,height:60),styleMask:[.titled],backing:.buffered,defer:false)
        focus.title="Inactive comparison";focus.isReleasedWhenClosed=false
        Task { @MainActor in
            do {
                let directory=URL(fileURLWithPath:CommandLine.arguments.dropFirst().first ?? "/private/tmp/glass-study",isDirectory:true)
                try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
                for rich in [true,false] {
                    backdrop.rich=rich;backdrop.needsDisplay=true;hosting.rootView=StudySurface(rich:rich)
                    for active in [true,false] {
                        if active { focus.orderOut(nil);window.makeKeyAndOrderFront(nil) }
                        else { focus.setFrameOrigin(NSPoint(x:window.frame.maxX+15,y:window.frame.minY));focus.makeKeyAndOrderFront(nil) }
                        try await Task.sleep(for:.milliseconds(800))
                        let shareable=try await SCShareableContent.currentProcess
                        guard let own=shareable.windows.first(where:{$0.windowID==CGWindowID(window.windowNumber)}) else { throw NSError(domain:"Own window unavailable",code:1) }
                        let config=SCStreamConfiguration();config.width=1800;config.height=1300;config.showsCursor=false;config.scalesToFit=true
                        let filter=SCContentFilter(desktopIndependentWindow:own)
                        let image=try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
                        let rep=NSBitmapImageRep(cgImage:image)
                        let name="\(rich ? "rich" : "uniform")-\(active ? "active" : "inactive").png"
                        try rep.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent(name))
                        print("\(name): key=\(window.isKeyWindow), appActive=\(app.isActive)")
                    }
                }
            } catch { fputs("Study failed: \(error)\n",stderr) }
            focus.orderOut(nil);window.orderOut(nil);previous?.activate(options:[]);app.terminate(nil)
        }
        app.run()
    }
}
