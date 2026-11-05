import AppKit
import Foundation
let root=URL(fileURLWithPath:CommandLine.arguments[1])
let folder=root.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
var images:[[String:String]]=[]
for (idiom,point,scale) in [("iphone",20,2),("iphone",20,3),("iphone",29,2),("iphone",29,3),("iphone",40,2),("iphone",40,3),("iphone",60,2),("iphone",60,3),("ipad",20,1),("ipad",20,2),("ipad",29,1),("ipad",29,2),("ipad",40,1),("ipad",40,2),("ipad",76,1),("ipad",76,2),("ios-marketing",1024,1)] {
 let n=point*scale
 let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:n,pixelsHigh:n,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
 let context=NSGraphicsContext(bitmapImageRep:bitmap)!
 NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
 let cg=context.cgContext;cg.scaleBy(x:CGFloat(n)/1024,y:CGFloat(n)/1024)
 NSColor(red:0.035,green:0.045,blue:0.045,alpha:1).setFill();NSBezierPath(rect:NSRect(x:0,y:0,width:1024,height:1024)).fill()
 let arc=NSBezierPath();arc.appendArc(withCenter:NSPoint(x:512,y:470),radius:310,startAngle:220,endAngle:-40,clockwise:true);arc.lineWidth=64;arc.lineCapStyle = .round
 NSColor(red:0.75,green:0.94,blue:0.47,alpha:1).setStroke();arc.stroke()
 let needle=NSBezierPath();needle.move(to:NSPoint(x:512,y:470));needle.line(to:NSPoint(x:680,y:650));needle.lineWidth=52;needle.lineCapStyle = .round;needle.stroke()
 NSBezierPath(ovalIn:NSRect(x:466,y:424,width:92,height:92)).fill()
 NSGraphicsContext.restoreGraphicsState()
 let filename="icon-\(idiom)-\(n).png";try bitmap.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent(filename))
 images.append(["idiom":idiom,"size":"\(point)x\(point)","scale":"\(scale)x","filename":filename])
}
let json:[String:Any]=["images":images,"info":["version":1,"author":"xcode"]]
try JSONSerialization.data(withJSONObject:json,options:.prettyPrinted).write(to:folder.appendingPathComponent("Contents.json"))
