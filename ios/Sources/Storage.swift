import Foundation
import CoreLocation
import UIKit

struct ColorBand:Codable,Hashable {var start:Double=0;var hex:String="#BFF078"}
struct Meter:Codable,Hashable {var key:String;var minimum:Double=0;var maximum:Double=100;var bands:[ColorBand]=[ColorBand()];var maxHex:String="#FF4545"}
struct AlarmRule:Codable {var enabled=false;var limit:Double=100;var below=false;var hysteresis:Double=2;var sound=true;var vibration=false;var repeatSeconds:Double=10;var tone="builtin:double"}
struct Tile:Codable {var style="card";var span=1;var minimum:Double=0;var maximum:Double=100;var fontSize:Double=16;var showExtrema=true;var color="#BFF078";var alarm=AlarmRule()}
struct LayoutConfig:Codable {var columns=3;var selected:[String]=[];var tiles:[String:Tile]=[:];var showUnits=true;var shortLabels=true;var dense=true;var shiftPosition=0}
struct Preferences:Codable {
    var profile="OBD-II";var category=0;var protocolName="CAN";var host="192.168.0.10";var port="35000";var transport="Wi-Fi"
    var bleID="";var bleWrite="";var bleNotify="";var autoConnect=false;var tpms=false;var interval:Double=1
    var shiftEnabled=false;var shiftTarget:Double=6000;var shiftLead:Double=500;var shiftSound=true;var shiftVibration=false;var shiftBands:[ColorBand]=[ColorBand(start:0,hex:"#00695C"),ColorBand(start:3000,hex:"#1565C0"),ColorBand(start:4500,hex:"#F9A825"),ColorBand(start:5500,hex:"#EF6C00")];var shiftMaxHex="#C62828"
    var celsius=true;var km=true;var pressure="ECU";var theme="Escuro";var accent="#BFF078";var fontScale:Double=1
    var layouts:[String:LayoutConfig]=[:];var meters:[String:[Meter]]=[:];var graphs:[String]=[];var dtcMonitor=true;var dtcInterval:Double=60
    var dtcSound=true;var dtcVibration=false;var dtcTone="builtin:double";var shiftTone="builtin:double";var volume:Double=0.7
    var recording=false;var fuelFactor:Double=1;var vehicle="Meu veículo";var language="pt-BR"
}
struct Event:Codable,Identifiable {var id=UUID().uuidString;var at=Date();var end:Date?;var profile:String;var parameter:String;var unit:String;var limit:Double;var extreme:Double;var last:Double;var below:Bool;var reason="";var context:[String:Double]=[:];var contextUnits:[String:String]=[:];var duration:Double=0}
struct TracePoint:Codable,Identifiable {var at=Date();var value:Double?;var id:Date{at}}
struct SessionInfo:Codable,Identifiable {var id=UUID().uuidString;var at=Date();var profile:String;var filename:String;var rows=0}
struct Capture:Codable,Identifiable {var id=UUID().uuidString;var at=Date();var vehicle:String;var profile:String;var stage:String;var source:String;var faults:[Fault];var readings:[String:Reading];var units:[String:String]}
struct RoutePoint:Codable {var lat:Double;var lon:Double;var at:Date}
struct Trip:Codable,Identifiable {var id=UUID().uuidString;var started=Date();var ended:Date?;var profile:String;var km:Double=0;var liters:Double=0;var observed:Double=0;var distanceSeconds:Double=0;var fuelSeconds:Double=0;var factor:Double=1;var route:[RoutePoint]=[];var consumption:Double?{km>=0.1 && observed>0 && distanceSeconds>=observed*0.9 && fuelSeconds>=observed*0.9 ? liters*100/km:nil}}
struct LearningState:Codable {var profile:String;var action:String;var phase="before";var before:[String:String];var after:[String:String]=[:];var ignitionOffAt:Date?}

enum Store {
    static var root:URL { FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0] }
    static func url(_ name:String)->URL {root.appendingPathComponent(name)}
    static func load<T:Decodable>(_ name:String,_ fallback:T)->T {(try? JSONDecoder().decode(T.self,from:Data(contentsOf:url(name)))) ?? fallback}
    static func save<T:Encodable>(_ value:T,_ name:String)throws {try JSONEncoder().encode(value).write(to:url(name),options:.atomic)}
    static func csv(_ a:[String])->String {a.map{"\""+$0.replacingOccurrences(of:"\"",with:"\"\"")+"\""}.joined(separator:",")+"\n"}
    static func export(_ data:String,_ name:String)throws->URL {let url=FileManager.default.temporaryDirectory.appendingPathComponent(name);try data.write(to:url,atomically:true,encoding:.utf8);return url}
    static func report(_ capture:Capture,before:Capture?=nil)throws->URL {
        if let before=before {try require(before.vehicle==capture.vehicle && before.profile==capture.profile && before.source==capture.source && before.at<=capture.at && before.id != capture.id,"Selecione capturas do mesmo veículo, perfil e origem, na ordem de data.")}
        var lines=["FrenchDiag · Relatório de oficina","Veículo: "+capture.vehicle,"Central: "+capture.profile,"Etapa: "+capture.stage,"Origem: "+capture.source,"Consulta: "+capture.at.formatted(),"","Falhas retornadas nesta consulta:"]
        lines+=capture.faults.map{$0.fullCode+" · "+$0.description+" · status "+$0.status}
        if capture.faults.isEmpty{lines.append("Nenhuma nesta consulta.")}
        if let b=before {
            let old:Set<String>=Set(b.faults.map{$0.fullCode})
            let current:Set<String>=Set(capture.faults.map{$0.fullCode})
            let added:String=current.subtracting(old).sorted().joined(separator:", ")
            let removed:String=old.subtracting(current).sorted().joined(separator:", ")
            let persistent:String=old.intersection(current).sorted().joined(separator:", ")
            lines.append("");lines.append("Comparação com "+b.at.formatted())
            lines.append("Novos: "+added);lines.append("Não retornaram: "+removed);lines.append("Persistentes: "+persistent)
        }
        lines.append("");lines.append("Leituras disponíveis (unidades da ECU):")
        for key in capture.readings.keys.sorted(){let r=capture.readings[key]!;let old=before?.readings[key];lines.append("\(Catalog.titles[key] ?? key): \(r.display) \(capture.units[key] ?? "") · aquisição \(r.at.formatted())"+(old.map{" · antes: "+$0.display} ?? ""))}
        lines += ["","Ausente não equivale a zero. Não retornar um DTC não comprova reparo.","Freeze frame: a data é a consulta; instante da falha não é informado.","Leituras ao vivo não representam o estado gravado no instante da falha."]
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("FrenchDiag-oficina-\(capture.id).pdf")
        let renderer=UIGraphicsPDFRenderer(bounds:CGRect(x:0,y:0,width:595,height:842))
        try renderer.writePDF(to:url){ctx in
            ctx.beginPage();var y:CGFloat=45
            for line in lines {
                let attr:[NSAttributedString.Key:Any]=[.font:UIFont.systemFont(ofSize:11),.foregroundColor:UIColor.black]
                let text=line as NSString;let rect=text.boundingRect(with:CGSize(width:505,height:10000),options:[.usesLineFragmentOrigin],attributes:attr,context:nil)
                if y+rect.height>795{ctx.beginPage();y=45}
                text.draw(in:CGRect(x:45,y:y,width:505,height:rect.height+4),withAttributes:attr);y+=max(17,rect.height+6)
            }
        }
        return url
    }
}
