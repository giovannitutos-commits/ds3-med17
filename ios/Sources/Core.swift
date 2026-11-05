import Foundation

struct Param: Codable, Identifiable, Hashable {
    var label: String; var description: String; var command: String; var unit: String
    var start: Int; var end: Int; var kind: String; var style: String; var scale: Double
    var limit: Int; var offset: Int; var transform: Int; var enums: [String:String]
    var shift: Int; var mask: Int; var frequency: Int
    var id: String { label }
    enum CodingKeys: String, CodingKey { case label, description, command, unit, start, end, kind, style, scale, limit, offset, transform, shift, mask, frequency; case enums = "enum" }
    var title: String { Catalog.titles[label] ?? label }
    var numeric: Bool { kind != "text" && enums.isEmpty && !["indicator","learning"].contains(style) }
}
struct Profile: Codable, Identifiable, Hashable {
    var name: String; var category: Int; var parameters: [Param]
    var id: String { name }
    var usable: [Param] { parameters.filter { $0.label != "ECU" } }
}
struct Routine: Codable, Identifiable, Hashable {
    var name: String; var tip: String; var start: String; var stop: String; var poll: String
    var response: String; var running: String; var stopped: String; var results: [String]; var condition: Int
    var id: String { name + start }
}
struct ActionGroup: Codable { var profile: String; var actions: [Routine] }
struct Reading: Codable { var value: Double?; var display: String; var at: Date = Date(); var fresh: Bool { Date().timeIntervalSince(at) < 15 } }
struct Fault: Codable, Identifiable { var code: String; var status: String; var description: String; var detail: String; var rawCode: String; var subtype: String
    var id: String { rawCode + status }; var fullCode: String { code + (subtype.isEmpty ? "" : "-" + subtype) }
}
struct AppError: LocalizedError { var message: String; var errorDescription: String? { message }; init(_ message: String) { self.message = message } }
extension String {
    func slice(_ start: Int, _ end: Int) -> String { guard start >= 0, end >= start, end <= count else { return "" }; return String(dropFirst(start).prefix(end-start)) }
    var hex: Bool { !isEmpty && allSatisfy { "0123456789ABCDEF".contains($0) } }
}
func require(_ condition: Bool, _ text: String) throws { if !condition { throw AppError(text) } }
func number(_ value: Double, _ decimals: Int = 1) -> String { String(format: "%.*f", locale: Locale(identifier:"pt_BR"), decimals, value) }

final class Catalog {
    let profiles: [Profile]; let actions: [String:[Routine]]; let learning: [Param]; let identification: [[String]]
    init(bundle: Bundle = .main) throws {
        func load<T:Decodable>(_ name: String, as type: T.Type) throws -> T {
            guard let url = bundle.url(forResource:name, withExtension:"json") else { throw AppError("Recurso ausente: \(name)") }
            return try JSONDecoder().decode(type, from:Data(contentsOf:url))
        }
        let data = try load("profiles",as:[Profile].self)
        let learned = try load("learning",as:[Param].self)
        learning = learned
        identification = try load("identification",as:[[String]].self)
        let groups = try load("actions",as:[ActionGroup].self)
        actions = Dictionary(groups.map { ($0.profile,$0.actions) }, uniquingKeysWith: { _,b in b })
        profiles = [Self.generic] + data.map { item in
            var p = item
            if p.name == "EDC17C10_BR2" { p.parameters += learned }
            if ["MED17_4_4","MED17_4_4v2","MEVD17_4_4"].contains(p.name) && !p.parameters.contains(where:{$0.label == "AutoSelector"}) {
                p.parameters.append(Param(label:"AutoSelector", description:"Seletor automático opcional",command:"22D4E7",unit:"",start:8,end:10,kind:"integer",style:"text",scale:1,limit:7,offset:0,transform:0,enums:["0":"P","1":"R","2":"N","3":"D","6":"M"],shift:0,mask:0,frequency:1))
            }
            return p
        } + [Self.tpms]
    }
    func identify(_ candidates: [String], category: Int) throws -> Profile? {
        let ids = Set(candidates.filter{!$0.isEmpty && $0.contains(where:{$0 != "F"})}.map { let v = $0.uppercased().drop(while:{$0 == "0"}); return v.isEmpty ? "0" : String(v) })
        let names = Set(identification.filter{$0.count > 1 && ids.contains($0[0])}.map{$0[1]})
        let matches = profiles.filter{$0.category == category && names.contains($0.name)}
        try require(matches.count <= 1,"Identificação ambígua. Selecione o perfil correto manualmente.")
        return matches.first
    }
    func faults(_ profile: String) -> [Int:[String]] {
        guard let u = Bundle.main.url(forResource:profile + ".dtc",withExtension:"txt"), let text = try? String(contentsOf:u,encoding:.utf8) else { return [:] }
        var result: [Int:[String]] = [:]
        for line in text.components(separatedBy:.newlines) { let a = line.components(separatedBy:";"); if a.count >= 4, let code = Int(a[1].trimmingCharacters(in:.whitespaces),radix:16) { result[code] = [a[2],a[3]] } }
        return result
    }
    static func genericParam(_ id:String,_ title:String,_ unit:String,_ limit:Int) -> Param { Param(label:id,description:title,command:"01"+id,unit:unit,start:0,end:0,kind:"double",style:"text",scale:1,limit:limit,offset:0,transform:0,enums:[:],shift:0,mask:0,frequency:1) }
    static let generic = Profile(name:"OBD-II",category:0,parameters:[genericParam("0C","Rotação","rpm",6000),genericParam("05","Arrefecimento","°C",140),genericParam("0D","Velocidade","km/h",240),genericParam("04","Carga do motor","%",100),genericParam("42","Tensão da ECU","V",16),genericParam("0F","Temperatura da admissão","°C",100),genericParam("0B","Pressão MAP","kPa",255),genericParam("10","Fluxo de ar","g/s",100),genericParam("11","Borboleta","%",100),genericParam("2F","Combustível","%",100),genericParam("5E","Vazão combustível","l/h",50)])
    static let tpms = Profile(name:"TPMS_6AF",category:9,parameters:zip(["P_FLpressure","P_FRpressure","P_RLpressure","P_RRpressure","P_FLtemperature","P_FRtemperature","P_RLtemperature","P_RRtemperature"],["22D610","22D60F","22D612","22D611","22D60E","22D60D","22D60C","22D60B"]).map { key,cmd in Param(label:key,description:"TPMS CAN 6AF · " + cmd,command:cmd,unit:key.contains("pressure") ? "psi" : "°C",start:8,end:key.contains("pressure") ? 12 : 10,kind:"double",style:"card",scale:1,limit:key.contains("pressure") ? 50 : 100,offset:0,transform:0,enums:[:],shift:0,mask:0,frequency:1) })
    static let titles: [String:String] = {
        guard let url=Bundle.main.url(forResource:"titles",withExtension:"json"),let data=try? Data(contentsOf:url) else{return [:]}
        return (try? JSONDecoder().decode([String:String].self,from:data)) ?? [:]
    }()
}

enum Decoder {
    static func messages(_ raw:String) -> [String] {
        var result:[String] = []; var advertised:Int?; var next=0; var bad=false; var chunks:[String] = []
        func finish() {
            let payload=chunks.joined()
            let shape=chunks.dropLast().enumerated().allSatisfy{$0.element.count == ($0.offset == 0 ? 12 : 14)}
            if !chunks.isEmpty, !bad, let n=advertised, payload.count == n*2, (chunks.count == 1 || shape) { result.append(payload) }
            chunks=[];next=0;bad=false;advertised=nil
        }
        for line in raw.uppercased().replacingOccurrences(of:">",with:"\n").components(separatedBy:.newlines) {
            let text=line.trimmingCharacters(in:.whitespaces)
            if text.isEmpty { continue }
            let a=text.components(separatedBy:":")
            if a.count == 2, let index=Int(a[0],radix:16) {
                let data=a[1].replacingOccurrences(of:" ",with:"")
                if index != next || !(2...14).contains(data.count) || data.count%2 != 0 || !data.hex { bad=true }
                chunks.append(data);next+=1
            } else {
                let compact=text.replacingOccurrences(of:" ",with:"")
                if compact.count == 3 && compact.hex { finish();advertised=Int(compact,radix:16) }
                else { finish();if compact.count>=2 && compact.count%2 == 0 && compact.hex { result.append(compact) } }
            }
        }
        finish();return result
    }
    static func body(_ raw:String,_ command:String, telemetry:Bool=false) -> String? {
        guard let service=Int(command.prefix(2),radix:16) else { return nil }
        let prefix=String(format:"%02X",service+0x40)+(command.hasPrefix("21") ? command.slice(2,4) : command.hasPrefix("22") ? command.slice(2,6) : command.hasPrefix("19") ? command.slice(2,4) : "")
        let masked=telemetry && service == 0x21 && command.range(of:"^21[0-9A-F]{2}8001$",options:.regularExpression) != nil && !["80","FE"].contains(command.slice(2,4))
        func matches(_ x:String)->Bool { x.hasPrefix(prefix) || (masked && x.hasPrefix("61FF")) }
        for line in messages(raw) {
            if matches(line) { return line }
            if line.count > 2 && Int(line.prefix(2),radix:16) == line.count/2-1 && matches(String(line.dropFirst(2))) { return String(line.dropFirst(2)) }
        }
        return nil
    }
    static func canonical(_ raw:String,_ cmd:String,telemetry:Bool=false)->String? { body(raw,cmd,telemetry:telemetry).map{String(format:"%02X",($0.count/2)&255)+$0} }
    static func interpolate(_ v:Double,_ x:[Double],_ y:[Double])->Double {
        let i = v <= x[0] ? 0 : v >= x.last! ? x.count-2 : (0..<x.count-1).first{v <= x[$0+1]}!
        return y[i]+(v-x[i])*(y[i+1]-y[i])/(x[i+1]-x[i])
    }
    static func decode(_ p:Param,_ canonical:String,software:Int?=nil)->Reading? {
        guard p.start>=0,p.end>p.start,p.end<=canonical.count else { return nil }
        let text=canonical.slice(p.start,p.end)
        if p.kind == "text" { return Reading(value:nil,display:text) }
        if text.isEmpty || (text.count>=2 && text.allSatisfy{$0 == "F"} && ![12,14,22].contains(p.transform)) { return nil }
        guard let raw=UInt64(text,radix:16) else { return nil }
        var value=Double(raw)*p.scale+Double(p.offset)
        if p.kind == "integer" { value=floor(value+0.5) }
        let swapped=((raw&255)<<8)+((raw&65280)>>8)
        switch p.transform {
        case 0,23: break
        case 1: value=interpolate(value,[200,259,444,591,786,1045,1387,1587,1807,3398,3645,4092,4272,4429,4561,4746],[120,110,90,80,70,60,50,45,40,10,5,-5,-10,-15,-20,-30])
        case 2: value=interpolate(value,[112,181,234,308,410,547,737,986,1318,1519,1738,2793,3350,3848,4248,4570],[120,100,90,80,70,60,49,40,29,25,19,7,-4,-16,-30,-40])
        case 3: value-=0.2
        case 4: value=Double(swapped)*p.scale+Double(p.offset)
        case 5: value-=0.25
        case 6: value=Double((Int(value)>>p.shift)&p.mask)
        case 7: value=Double(stride(from:8,to:canonical.count,by:8).filter{let t=canonical.slice($0,min($0+8,canonical.count));return t.count>=6 && t.prefix(6) != "FFFFFF"}.count)
        case 8: value=value>0 ? 1:0
        case 11: guard let n=Double(text) else{return nil};value=n*p.scale+Double(p.offset)
        case 12: value=Double(Int16(truncatingIfNeeded:raw))*p.scale+Double(p.offset)
        case 14: value=Double(Int8(truncatingIfNeeded:raw))*p.scale+Double(p.offset)
        case 16: guard let sw=software else{return nil};if sw>33280 {value*=0.1}
        case 17: value=value == 1 ? 1:0
        case 18: value-=12.8
        case 19: value-=3276.8
        case 20: value-=19.58
        case 21: value=value == 0 ? 1:0
        case 22: value=Double(Int16(truncatingIfNeeded:swapped))*p.scale+Double(p.offset)
        default: return nil
        }
        if p.style == "learning" { let on=Int(truncatingIfNeeded:raw)&p.limit != 0;return Reading(value:on ? 1:0,display:on ? "Aprendido":"Não aprendido") }
        guard value.isFinite else{return nil}
        if p.kind == "integer" {value=floor(value+0.5)}
        if p.style == "indicator" {value=Double(Int(value)&p.limit)}
        let display=p.enums[String(Int(value))] ?? (p.style == "indicator" ? (value != 0 ? "Ativo":"Inativo") : number(value,p.kind == "integer" ? 0 : p.scale == 0.001 ? 3 : p.scale == 0.1 ? 1:2))
        return Reading(value:value,display:display)
    }
    static func pid(_ raw:String,_ pid:String)->Double? {
        guard let msg=messages(raw).first(where:{$0.hasPrefix("41"+pid)}) else{return nil}
        let data=String(msg.dropFirst(4));let b=stride(from:0,to:data.count,by:2).compactMap{Int(data.slice($0,min($0+2,data.count)),radix:16)}
        guard let a=b.first else{return nil};let pair=b.count>=2 ? Double(a*256+b[1]):nil
        switch pid {case "0C":return pair.map{$0/4};case "0D","0B":return Double(a);case "05","0F":return Double(a-40);case "04","11","2F":return Double(a)*100/255;case "10":return pair.map{$0/100};case "5E":return pair.map{$0*0.05};case "42":return pair.map{$0/1000};default:return nil}
    }
    static func code(_ n:Int)->String { String(Array("PCBU")[(n>>14)&3])+String((n>>12)&3)+String(format:"%03X",n&0xfff) }
    static func faults(_ raw:String,_ cmd:String,definitions:[Int:[String]])->[Fault]? {
        guard let body=body(raw,cmd) else{return nil}
        var data:String;let width:Int
        if cmd.hasPrefix("19") {guard body.count>=6 else{return nil};data=String(body.dropFirst(6));width=8}
        else {guard body.count>=4,let n=Int(body.slice(2,4),radix:16),body.count>=4+n*6 else{return nil};data=body.slice(4,4+n*6);width=6}
        guard data.count%width == 0 else{return nil}
        var result:[Fault]=[]
        while !data.isEmpty {let item=String(data.prefix(width));data=String(data.dropFirst(width));if item.prefix(6)=="FFFFFF" || item.prefix(4)=="0000" {continue};guard let code=Int(item.prefix(4),radix:16) else{return nil};let d=definitions[code] ?? ["Definição não encontrada para este perfil",""];result.append(Fault(code:Self.code(code),status:String(item.suffix(2)),description:d[0],detail:d[1],rawCode:String(item.prefix(width==8 ? 6:4)),subtype:width==8 ? item.slice(4,6):""))}
        return result
    }
    static func supported(_ raw:String,base:Int)->Set<String>? {
        let prefix="41"+String(format:"%02X",base)
        guard let message=messages(raw).first(where:{$0.hasPrefix(prefix)}),message.count>=12 else{return nil}
        let bytes=stride(from:4,to:12,by:2).compactMap{Int(message.slice($0,$0+2),radix:16)}
        guard bytes.count==4 else{return nil}
        return Set((1...32).filter{offset in ((bytes[(offset-1)/8]>>(7-(offset-1)%8))&1)==1}.map{String(format:"%02X",base+$0)})
    }
    static func genericFaults(_ raw:String,can:Bool=true)->[Fault]? {
        let messages=messages(raw).filter{$0.hasPrefix("43")};guard !messages.isEmpty else{return nil};var result:[Fault]=[]
        for msg in messages {let data=String(msg.dropFirst(2));let count:Int;let start:Int;if can{guard data.count>=2,let n=Int(data.prefix(2),radix:16),data.count>=2+n*4 else{return nil};count=n;start=2}else{guard data.count%4==0 else{return nil};count=data.count/4;start=0};for i in 0..<count {let item=data.slice(start+i*4,start+4+i*4);guard let code=Int(item,radix:16) else{return nil};if code != 0 {result.append(Fault(code:Self.code(code),status:"",description:"DTC OBD-II",detail:"",rawCode:item,subtype:""))}}}
        return result
    }
    static func tpmsPayload(_ raw:String,_ cmd:String)throws->(String,String?) {
        let prefix="62"+cmd.dropFirst(2);let count=["22D610","22D60F","22D612","22D611"].contains(cmd) ? 5:4
        var values=Set<String>();var ids=Set<String>()
        for line in raw.uppercased().replacingOccurrences(of:">",with:"\n").components(separatedBy:.newlines) {
            var text=line.filter{!$0.isWhitespace};guard text.hex else{continue};var header:String?
            if text.count%2==1 && text.count>=11,let id=Int(text.prefix(3),radix:16),id<=0x7ff {header=String(text.prefix(3));text=String(text.dropFirst(3))}
            let payload:String
            if text.count==count*2 && text.hasPrefix(String(prefix)) {payload=text}
            else if text.count>=2+count*2 && text.count<=16 && Int(text.prefix(2),radix:16)==count {payload=text.slice(2,2+count*2)}else{continue}
            if payload.hasPrefix(String(prefix)) {values.insert(payload);if let h=header{ids.insert(h)}}
        }
        try require(values.count<=1 && ids.count<=1,"Mais de uma resposta TPMS para o mesmo PID.")
        return (values.first ?? "",ids.first)
    }
    static func tpms(_ p:Param,_ raw:String)->Reading? {
        let pressure=p.unit=="psi";guard raw.count==(pressure ? 12:10),raw.hasPrefix((pressure ? "05":"04")+"62"+p.command.dropFirst(2)) else{return nil}
        let text=String(raw.dropFirst(8));guard !text.allSatisfy({$0=="F"}),let a=Int(text.prefix(2),radix:16) else{return nil}
        let v:Double
        if pressure {guard let b=Int(text.dropFirst(2),radix:16) else{return nil};v=Double(a*255+b)/69}else{v=Double(a-50)}
        return Reading(value:v,display:number(v,pressure ? 2:0))
    }
}
