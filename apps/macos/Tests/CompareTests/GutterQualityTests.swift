import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CompareUI

@Suite(.serialized) struct GutterQualityTests {
    @Test @MainActor func largeDocumentGutterFitsEveryLineNumberDigit() throws {
        let source=String(repeating:"line\n",count:100_000)
        let host=NSHostingView(rootView:SourceEditor(text:.constant(source),editable:true).frame(width:600,height:240))
        host.frame=NSRect(x:0,y:0,width:600,height:240); host.layoutSubtreeIfNeeded()
        let editor=try #require(findEditor(host)),ruler=try #require(editor.enclosingScrollView?.verticalRulerView)
        let labelWidth=("100001" as NSString).size(withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:10,weight:.regular)]).width
        #expect(ruler.ruleThickness >= ceil(labelWidth)+16)
        #expect(editor.lineStarts.count == 100_001)
        editor.replaceSource("short")
        #expect(ruler.ruleThickness == 38)
        editor.replaceSource(source)
        #expect(ruler.ruleThickness >= ceil(labelWidth)+16)
    }

    @Test @MainActor func emptyAndNonemptyFirstLineNumbersShareAlignment() throws {
        var origins: [CGPoint] = []
        for source in ["", "first"] {
            let host=NSHostingView(rootView:SourceEditor(text:.constant(source),editable:true).frame(width:600,height:240))
            host.frame=NSRect(x:0,y:0,width:600,height:240);host.layoutSubtreeIfNeeded()
            let editor=try #require(findEditor(host)),ruler=try #require(editor.enclosingScrollView?.verticalRulerView)
            try #require(editor.layoutManager).ensureLayout(for:try #require(editor.textContainer))
            let rect=NSRect(x:0,y:0,width:ruler.bounds.width,height:40)
            let bitmap=try #require(ruler.bitmapImageRepForCachingDisplay(in:rect))
            ruler.cacheDisplay(in:rect,to:bitmap)
            let scaleX=CGFloat(bitmap.pixelsWide)/rect.width,scaleY=CGFloat(bitmap.pixelsHigh)/rect.height
            var minX=bitmap.pixelsWide,minY=bitmap.pixelsHigh
            for y in 0..<bitmap.pixelsHigh {
                for x in Int(10*scaleX)..<min(bitmap.pixelsWide,Int((ruler.ruleThickness-8)*scaleX)) {
                    if let color=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.sRGB),color.redComponent < 0.8 && color.greenComponent < 0.8 && color.blueComponent < 0.8 {
                        minX=min(minX,x);minY=min(minY,y)
                    }
                }
            }
            try #require(minX < bitmap.pixelsWide && minY < bitmap.pixelsHigh,"The first line number must contain actual ink.")
            origins.append(CGPoint(x:CGFloat(minX)/scaleX,y:CGFloat(minY)/scaleY))
        }
        #expect(abs(origins[0].x-origins[1].x) <= 0.5)
        #expect(abs(origins[0].y-origins[1].y) <= 0.5)
    }

    @Test @MainActor func trailingLineBreakRendersLastLogicalLineNumber() throws {
        for (mode,prefix) in [("import","first"),("native-edit","first"),("scrolled",String(repeating:"line\n",count:120)+"first")] {
          for ending in ["\n","\r","\r\n"] {
            let initial=mode == "native-edit" ? prefix : prefix+ending
            let host=NSHostingView(rootView:SourceEditor(text:.constant(initial),editable:true).frame(width:600,height:240))
            host.frame=NSRect(x:0,y:0,width:600,height:240); host.layoutSubtreeIfNeeded()
            let editor=try #require(findEditor(host)),ruler=try #require(editor.enclosingScrollView?.verticalRulerView)
            if mode == "native-edit" {
                editor.insertText(ending,replacementRange:NSRange(location:prefix.utf16.count,length:0))
                #expect(editor.lineStarts == [0,prefix.utf16.count+ending.utf16.count])
            }
            let layout=try #require(editor.layoutManager),container=try #require(editor.textContainer)
            layout.ensureLayout(for:container)
            if mode == "scrolled" {
                editor.scrollRangeToVisible(NSRange(location:editor.textStorage?.length ?? 0,length:0))
                try #require(editor.visibleRect.minY > 0)
            }
            let finalLineY=layout.extraLineFragmentRect.minY + editor.textContainerOrigin.y - editor.visibleRect.minY + 1
            let bitmap=try #require(ruler.bitmapImageRepForCachingDisplay(in:ruler.bounds))
            ruler.cacheDisplay(in:ruler.bounds,to:bitmap)
            let scaleX=CGFloat(bitmap.pixelsWide)/ruler.bounds.width,scaleY=CGFloat(bitmap.pixelsHigh)/ruler.bounds.height
            var ink=0
            for y in Int(finalLineY*scaleY)..<min(bitmap.pixelsHigh,Int((finalLineY+12)*scaleY)) {
                for x in Int(10*scaleX)..<min(bitmap.pixelsWide,Int((ruler.ruleThickness-8)*scaleX)) {
                    if let color=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.sRGB),color.redComponent < 0.8 && color.greenComponent < 0.8 && color.blueComponent < 0.8 { ink += 1 }
                }
            }
            #expect(ink > 0,"The empty final logical line needs a visible line number.")
            if let directory=ProcessInfo.processInfo.environment["CC_GUTTER_OUTPUT"] {
                let destination=URL(fileURLWithPath:directory);try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
                let suffix=ending == "\n" ? "lf" : (ending == "\r" ? "cr" : "crlf")
                try #require(bitmap.representation(using:.png,properties:[:])).write(to:destination.appendingPathComponent("gutter-"+mode+"-"+suffix+".png"))
            }
          }
        }
    }

    @MainActor private func findEditor(_ view:NSView)->SourceTextView? {
        if let editor=view as? SourceTextView{return editor}
        for child in view.subviews {if let editor=findEditor(child){return editor}}
        return nil
    }
}
