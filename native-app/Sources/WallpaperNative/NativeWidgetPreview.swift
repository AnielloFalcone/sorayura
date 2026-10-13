import AppKit
import SwiftUI
import ScreenCaptureKit

/// Explicit developer preview of the real AI widget using fixture data only.
@available(macOS 26, *)
enum NativeWidgetPreview {
    @MainActor static func run(directory: String) {
        let app = NSApplication.shared; app.setActivationPolicy(.accessory)
        let previous = NSWorkspace.shared.frontmostApplication
        var prefs = Prefs(); prefs.widgetTheme="glass"; prefs.agentUsageEnabled=true; prefs.codexAccountEnabled=true; prefs.agentDensity="compact"
        let model=Model.isolated(preferences:prefs)
        let now=Date()
        model.agentUsage.updated=now
        model.agentUsage.periods["all"] = AgentPeriodSummary(tokens: 12_000_000, cached: 9_000_000)
        let fixture: [String:Any] = ["version":2,"samples":[["t":now.addingTimeInterval(-60).timeIntervalSince1970*1000,"u":["fh":21,"sd":62]]]]
        model.agentUsage.claudeDesktop=ClaudeDesktopLimits.decode(try! JSONSerialization.data(withJSONObject:fixture),now:now)
        model.codexAccount.quota=AgentQuota(date:now,plan:"plus",session:AgentLimit(used:9,reset:now.addingTimeInterval(3600),minutes:300),week:AgentLimit(used:1,reset:now.addingTimeInterval(86400),minutes:10080))
        let root=ZStack {
            LinearGradient(colors:[Color(red:0.04,green:0.09,blue:0.20),Color(red:0.20,green:0.29,blue:0.44)],startPoint:.bottomLeading,endPoint:.topTrailing)
            WidgetView(id:"agents").environment(model).frame(width:560,height:340)
        }.frame(width:660,height:440)
        let window=DesktopSurfaceWindow(contentRect:NSRect(x:0,y:0,width:660,height:440),styleMask:[.borderless],backing:.buffered,defer:false)
        window.editingEnabled=true;window.title="Sorayura · AI layout preview (sample data)";window.isReleasedWhenClosed=false
        window.contentView=NSHostingView(rootView:root);window.center();window.makeKeyAndOrderFront(nil);app.activate(ignoringOtherApps:true)
        Task { @MainActor in
            do {
                let folder=URL(fileURLWithPath:directory,isDirectory:true)
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                for active in [true,false] {
                    if !active { window.editingEnabled=false; previous?.activate(options:[]) }
                    try await Task.sleep(for:.milliseconds(800))
                    let content=try await SCShareableContent.currentProcess
                    guard let own=content.windows.first(where:{$0.windowID==CGWindowID(window.windowNumber)}) else { throw SettingsError.invalid("Preview window unavailable") }
                    let config=SCStreamConfiguration();config.width=1320;config.height=940;config.scalesToFit=true;config.showsCursor=false
                    let image=try await SCScreenshotManager.captureImage(contentFilter:SCContentFilter(desktopIndependentWindow:own),configuration:config)
                    try NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("ai-\(active ? "active" : "inactive").png"))
                    print("AI preview saved: key=\(window.isKeyWindow), active=\(app.isActive)")
                }
            } catch { fputs("AI preview failed: \(error)\n",stderr) }
            window.orderOut(nil);previous?.activate(options:[]);app.terminate(nil)
        }
        app.run()
    }
    @MainActor static func runSpotify(directory:String) {
        let app=NSApplication.shared;app.setActivationPolicy(.accessory)
        let previous=NSWorkspace.shared.frontmostApplication
        var prefs=Prefs();prefs.widgetTheme="glass";prefs.spotifyEnabled=true;prefs.spotifyDisplay="expanded"
        prefs.spotifyShortcuts=[SpotifyShortcut(name:"Focus",link:"spotify:playlist:0123456789ABCDEFGHIJKL"),SpotifyShortcut(name:"Evening",link:"spotify:album:0123456789ABCDEFGHIJKL"),SpotifyShortcut(name:"Favorites",link:"spotify:track:0123456789ABCDEFGHIJKL")]
        let model=Model.isolated(preferences:prefs)
        let art=NSImage(size:NSSize(width:256,height:256));art.lockFocus()
        NSGradient(starting:NSColor.systemIndigo,ending:NSColor.systemTeal)!.draw(in:NSRect(x:0,y:0,width:256,height:256),angle:45)
        NSColor.white.withAlphaComponent(0.45).setStroke();let path=NSBezierPath(ovalIn:NSRect(x:55,y:55,width:146,height:146));path.lineWidth=3;path.stroke();art.unlockFocus()
        model.spotify=SpotifySnapshot(title:"Moonlit Horizons",artist:"Sample Artist",album:"Night Drive",playing:true,available:true,artwork:art.tiffRepresentation,volume:65,shuffle:true)
        let window=DesktopSurfaceWindow(contentRect:NSRect(x:0,y:0,width:540,height:460),styleMask:[.borderless],backing:.buffered,defer:false)
        window.isReleasedWhenClosed=false;window.editingEnabled=true;window.title="Sorayura · Spotify preview (sample data)"
        Task { @MainActor in
            do {
                let folder=URL(fileURLWithPath:directory,isDirectory:true);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                for (name,w,h,mode) in [("expanded",440.0,380.0,"expanded"),("compact",440.0,180.0,"compact"),("small",260.0,180.0,"expanded")] {
                    model.prefs.spotifyDisplay=mode
                    model.spotifyHover["preview"] = name == "expanded" ? "playpause":nil
                    window.setContentSize(NSSize(width:w+80,height:h+80))
                    let root=ZStack { LinearGradient(colors:[Color(red:0.04,green:0.09,blue:0.20),Color(red:0.20,green:0.29,blue:0.44)],startPoint:.bottomLeading,endPoint:.topTrailing);WidgetView(id:"spotify").environment(model).frame(width:w,height:h) }.frame(width:w+80,height:h+80)
                    window.contentView=NSHostingView(rootView:root);window.center();window.makeKeyAndOrderFront(nil);app.activate(ignoringOtherApps:true)
                    try await Task.sleep(for:.milliseconds(700))
                    let content=try await SCShareableContent.currentProcess
                    guard let own=content.windows.first(where:{$0.windowID==CGWindowID(window.windowNumber)}) else { throw SettingsError.invalid("Preview window unavailable") }
                    let config=SCStreamConfiguration();config.width=Int((w+80)*2);config.height=Int((h+80)*2);config.scalesToFit=true;config.showsCursor=false
                    let image=try await SCScreenshotManager.captureImage(contentFilter:SCContentFilter(desktopIndependentWindow:own),configuration:config)
                    try NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("spotify-\(name).png"))
                }
                print("Spotify previews saved: expanded, compact, small fallback")
            } catch { fputs("Spotify preview failed: \(error)\n",stderr) }
            window.orderOut(nil);previous?.activate(options:[]);app.terminate(nil)
        }
        app.run()
    }

}
