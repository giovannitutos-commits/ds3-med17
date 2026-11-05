import Foundation
import SwiftUI
import Combine
import CoreLocation
import AudioToolbox

@MainActor final class Dashboard: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var prefs=Store.load("preferences.json",Preferences())
    @Published var connected=false;@Published var connecting=false;@Published var busy=false;@Published var actionRunning=false
    @Published var status="Pronto para conectar";@Published var message:String?;@Published var error:String?
    @Published var readings:[String:Reading]=[:];@Published var extrema:[String:(Double,Double)]=[:];@Published var series:[String:[TracePoint]]=[:]
    @Published var faults:[Fault]=[];@Published var faultsRead=false;@Published var faultDate:Date?;@Published var tpmsNotice=""
    @Published var sessions=Store.load("sessions.json",[SessionInfo]());@Published var events=Store.load("alarms.json",[Event]())
    @Published var captures=Store.load("captures.json",[Capture]());@Published var trips=Store.load("trips.json",[Trip]());@Published var currentTrip:Trip?
    @Published var learning:LearningState?=Store.load("learning.json",Optional<LearningState>.none)
    @Published var profile:Profile=Catalog.generic;@Published var share:URL?;@Published var samples=0
    @Published var moduleReadings:[String:[String:Reading]]=[:]
    let elm=ELMTransport();var catalog:Catalog?;var session:PSASession?
    private var worker:Task<Void,Never>?;private var pending:[Operation]=[];private var stopRequested=false;private var disconnectRequested=false
    private var canGeneric=true
    private var recordingSession:SessionInfo?;private var lastRecord=Date.distantPast;private var lastFault=Date.distantPast;private var lastModule=Date.distantPast
    private var activeAlarm:[String:String]=[:];private var lastAlarm:[String:Date]=[:];private var lastShift=false
    private var backgroundTask:UIBackgroundTaskIdentifier = .invalid
    private var previousTripAt:Date?;private var previousSpeed:Double?;private var previousFuel:Double?;private var location=CLLocationManager()
    private var cancellable:AnyCancellable?
    enum Operation {case faults,clear,capture(String,Bool),routine(Routine,Int?),learning, module(Int,String)}
    override init(){super.init();location.delegate=self;do{let c=try Catalog();catalog=c;profile=c.profiles.first{$0.name==prefs.profile} ?? Catalog.generic;ensureDefaults()}catch{self.error="Catálogo indisponível: "+error.localizedDescription};cancellable=elm.objectWillChange.sink{[weak self] _ in self?.objectWillChange.send()}
        // Persisted active alarms are closed after an interrupted process.
        for i in events.indices where events[i].end==nil{events[i].end=Date();events[i].reason="Aplicativo interrompido"}
    }
    var profiles:[Profile]{catalog?.profiles ?? [Catalog.generic]}
    var params:[Param]{profile.usable + (prefs.tpms && profile.category==0 && profile.name != "OBD-II" ? Catalog.tpms.usable:[])}
    var routines:[Routine]{catalog?.actions[profile.name] ?? []}
    var rpm:Reading? {readings[profile.name=="OBD-II" ? "0C":"Revs"].flatMap{Date().timeIntervalSince($0.at)<2 ? $0:nil}}
    func fresh(_ key:String)->Reading?{readings[key].flatMap{$0.fresh ? $0:nil}}
    func save(){do{try Store.save(prefs,"preferences.json")}catch{self.error="Não foi possível salvar as configurações: "+error.localizedDescription}}
    func selectProfile(_ name:String){guard !connected && !connecting else{return};prefs.profile=name;profile=profiles.first{$0.name==name} ?? Catalog.generic;readings=[:];faults=[];faultsRead=false;ensureDefaults();save()}
    func layout(_ landscape:Bool)->LayoutConfig{prefs.layouts[profile.name+(landscape ? ":landscape":":portrait")] ?? Self.defaults(params,landscape)}
    func setLayout(_ config:LayoutConfig,_ landscape:Bool){prefs.layouts[profile.name+(landscape ? ":landscape":":portrait")]=config;save()}
    func meters()->[Meter]{prefs.meters[profile.name] ?? [Meter(key:profile.name=="OBD-II" ? "0C":"Revs",maximum:6000),Meter(key:profile.name=="OBD-II" ? "05":"Coolant",maximum:140),Meter(key:profile.name=="OBD-II" ? "0B":"TurboPress",maximum:profile.name=="OBD-II" ? 255:3000)]}
    func updateTPMS(){
        if prefs.tpms && profile.category==0 && profile.name != "OBD-II" {for landscape in [false,true]{var config=layout(landscape);for p in Catalog.tpms.usable where !config.selected.contains(p.label){config.selected.append(p.label);config.tiles[p.label]=Tile(span:landscape ? 2:1,maximum:Double(p.limit))};setLayout(config,landscape)}}
        save()
    }
    func ensureDefaults(){for landscape in [false,true]{let key=profile.name+(landscape ? ":landscape":":portrait");if prefs.layouts[key]==nil{prefs.layouts[key]=Self.defaults(params,landscape)}}}
    static let cardRows=[["Gear","FuelLevel","ExternalTemp","IntakeAirPressInstr","IntakeAirPress"],["FuelPressInstr","FuelPress","FuelPressReg","AlternatorTemp","AlternatorCurrent","ECUtemp"],["UpO2Volt","DownO2Volt","UpO2Heat","DownO2Heat","UpMixCorr","DownMixCorr"]]
    static let pressureBars=["Revs","TurboInstr","TurboPress","OilPressInstr","OilPress"]
    static let textRows=["AirFlowInstr","AirFlow","ThrottleAngleInstr","ThrottleAngle","InCamDephaserInstr","InCamDephaser","InCamDephaserValve","TorqIgnAdvInstr","TorqIgnAdv","TorqAirFlowInstr","TorqAirFlow","TorqLost","TurboWastegate","TurboBlowOff"]
    static let lowerBars=["AccelPedalPos","AlternatorCharge","OilPumpValve"]
    static let lowerText=["KnockSensor","KnockSensorThr","Errors"]
    static func defaults(_ params:[Param],_ landscape:Bool)->LayoutConfig {
        let reference=params.contains{$0.label=="Revs"};let order=cardRows.flatMap{$0}+pressureBars+textRows+lowerBars+lowerText
        let selected=reference ? order.filter{k in params.contains{$0.label==k}}+params.filter{$0.label.hasPrefix("P_")}.map{$0.label}:params.map{$0.label}
        let columns=landscape ? 12:6;var result=LayoutConfig(columns:columns,selected:selected)
        for p in params {
            let card = !reference || cardRows.flatMap{$0}.contains(p.label) || p.label.hasPrefix("P_")
            let style=card ? "card" : pressureBars.contains(p.label) || lowerBars.contains(p.label) ? "bar":"text"
            let span=style != "card" ? columns : landscape ? (["IntakeAirPressInstr","IntakeAirPress"].contains(p.label) ? 3:2) : p.label=="IntakeAirPress" ? 2:1
            result.tiles[p.label]=Tile(style:style,span:span,minimum:0,maximum:Double(max(1,p.limit)),fontSize:landscape ? 12:16)
        }
        return result
    }
    func display(_ p:Param,_ reading:Reading?)->(String,String,Double?) {
        guard let reading=reading,reading.fresh else{return("—",p.unit,nil)}
        guard var value=reading.value else{return(reading.display,p.unit,nil)};var unit=p.unit
        if ["°C","℃"].contains(unit) && !prefs.celsius {value=value*1.8+32;unit="°F"}
        if unit=="km/h" && !prefs.km{value*=0.621371;unit="mph"}
        let factors:[String:Double]=["Pa":1,"kPa":1000,"MPa":1_000_000,"bar":100_000,"mbar":100,"psi":6894.757]
        if prefs.pressure != "ECU",let factor=factors[unit],let target=factors[prefs.pressure]{value=value*factor/target;unit=prefs.pressure}
        let changed=unit != p.unit
        return(changed ? number(value,unit=="psi" || unit=="bar" ? 2:1):reading.display,unit,value)
    }
    func enterBackground(){
        save()
        guard connected || connecting else{return}
        if actionRunning{stopRequested=true;disconnectRequested=true}
        if backgroundTask == .invalid {backgroundTask=UIApplication.shared.beginBackgroundTask(withName:"FrenchDiag finish connection"){[weak self] in self?.disconnect()}}
    }
    func enterForeground(){if backgroundTask != .invalid{UIApplication.shared.endBackgroundTask(backgroundTask);backgroundTask = .invalid};autoConnect()}
    func autoConnect(){if prefs.autoConnect && !connected && !connecting{connect()}}
    func connect(){
        guard !connected && !connecting,let catalog=catalog else{return};error=nil;message=nil;connecting=true;status="Conectando ao ELM327…";stopRequested=false;disconnectRequested=false
        worker=Task {
            do {
                elm.writeUUID=prefs.bleWrite;elm.notifyUUID=prefs.bleNotify
                if prefs.transport=="Wi-Fi"{guard let port=UInt16(prefs.port),port>0,!prefs.host.isEmpty else{throw AppError("Endereço ou porta inválidos.")};try await elm.connectWiFi(host:prefs.host,port:port)}
                else{guard let id=UUID(uuidString:prefs.bleID) else{throw AppError("Selecione um adaptador BLE.")};try await elm.connectBLE(id)}
                if prefs.profile=="OBD-II" {
                    _ = try await elm.command("ATZ",timeout:8)
                    for cmd in ["ATE0","ATL0","ATS0","ATH0","ATSP0"]{let response=try await elm.command(cmd);try require(response.uppercased().contains("OK"),"O adaptador rejeitou \(cmd).")}
                    let raw=try await elm.command("0100",timeout:12);try require(Decoder.messages(raw).contains{$0.hasPrefix("4100")},"O adaptador não retornou dados OBD-II válidos.")
                    guard var supported=Decoder.supported(raw,base:0) else{throw AppError("Tabela OBD-II incompleta.")}
                    if supported.contains("20"),let next=Decoder.supported(try await elm.command("0120",timeout:6),base:0x20){supported.formUnion(next)}
                    if supported.contains("40"),let next=Decoder.supported(try await elm.command("0140",timeout:6),base:0x40){supported.formUnion(next)}
                    let proto=try await elm.command("ATDPN");let compact=proto.replacingOccurrences(of:">",with:"").trimmingCharacters(in:.whitespacesAndNewlines).uppercased();let value=compact.hasPrefix("A") ? String(compact.dropFirst()):compact
                    try require(value.count==1 && "123456789ABC".contains(value),"Protocolo OBD-II não identificado pelo ELM.")
                    canGeneric="6789ABC".contains(value);profile=Catalog.generic;profile.parameters=profile.parameters.filter{supported.contains($0.label)};session=nil
                }else {
                    let selected=profiles.first{$0.name==prefs.profile};let cat=selected?.category ?? prefs.category
                    let psa=PSASession(elm,catalog);session=psa;status="Preparando protocolo PSA…";try await psa.setup(category:cat,protocolName:prefs.protocolName)
                    let detected:Profile?
                    if cat==9{detected=nil}else{detected=try await psa.identify()}
                    try require(selected==nil || detected==nil || selected?.name==detected?.name,"A ECU identificada difere do perfil selecionado. Confira a configuração.")
                    guard let active=selected ?? detected else{throw AppError("ECU não identificada. Selecione o perfil correto manualmente.")};profile=active
                }
                ensureDefaults();readings=[:];extrema=[:];series=[:];faults=[];faultsRead=false;moduleReadings=[:];samples=0
                let commands=Array(Set(profile.usable.filter{!$0.command.hasPrefix("17") && !$0.command.hasPrefix("19")}.map{$0.command})).sorted()
                let rpmCommand=profile.usable.first{$0.label=="Revs" || $0.label=="0C"}?.command
                for cmd in ([rpmCommand].compactMap{$0}+commands).prefix(profile.category==9 ? 8:3){try await readGroup(cmd);if readings.values.contains(where:{$0.value != nil}){break}}
                try require(readings.values.contains{$0.value != nil},"O adaptador respondeu, mas não retornou parâmetros válidos deste perfil.")
                connected=true;connecting=false;status=profile.name+" · leituras ao vivo";UIApplication.shared.isIdleTimerDisabled=true
                var index=0;var priorityIndex=0;var tpmsIndex=0;var tpmsAt=Date.distantPast;var misses=0;var tpmsWasEnabled=prefs.tpms;var lastSlow=Date.distantPast
                while !Task.isCancelled && !disconnectRequested {
                    if !pending.isEmpty {let op=pending.removeFirst();do{try await execute(op)}catch{self.error=error.localizedDescription};busy=false;actionRunning=false;stopRequested=false;if disconnectRequested{break}}
                    if let cmd=rpmCommand{try await readGroup(cmd)}
                    if Date().timeIntervalSince(lastSlow)>=max(0.1,prefs.interval/2),!commands.isEmpty{let keys=Set(layout(false).selected+layout(true).selected+meters().map{$0.key}+prefs.graphs)
                        let priority=commands.filter{cmd in profile.usable.contains{$0.command==cmd && keys.contains($0.label)}}
                        let cmd:String
                        if index%4 != 3 && !priority.isEmpty {cmd=priority[priorityIndex%priority.count];priorityIndex+=1}else{cmd=commands[(index/4)%commands.count]}
                        index+=1;if cmd != rpmCommand{try await readGroup(cmd)};lastSlow=Date()}
                    if prefs.tpms != tpmsWasEnabled{misses=0;tpmsWasEnabled=prefs.tpms;tpmsNotice=""}
                    if prefs.tpms && profile.category==0 && session != nil && prefs.protocolName=="CAN" && misses<8 && Date().timeIntervalSince(tpmsAt)>0.75 {
                        let p=Catalog.tpms.usable[tpmsIndex%8];tpmsIndex+=1
                        do{let r=try await session!.tpms(p);publish(p,r);misses=r==nil ? misses+1:0;tpmsNotice=misses>=8 ? "TPMS sem resposta. ECU continua ativa. Desative e reative TPMS para tentar novamente.":r==nil ? "Sem resposta para "+p.title:""}catch{tpmsNotice="TPMS pausado: "+error.localizedDescription;misses=8};tpmsAt=Date()
                    }
                    if prefs.dtcMonitor && profile.category != 9 && Date().timeIntervalSince(lastFault)>=max(15,prefs.dtcInterval){do{try await readFaults()}catch{self.error="Monitor de falhas: "+error.localizedDescription};lastFault=Date()}
                    if !moduleReadings.isEmpty && session != nil && profile.category==0 && Date().timeIntervalSince(lastModule)>5 {
                        for name in moduleReadings.keys.sorted(){if let p=profiles.first(where:{$0.name==name}){try await readModule(p)}};lastModule=Date()
                    }
                    recordIfNeeded();sampleTrip();evaluateAlarms();try await Task.sleep(nanoseconds:100_000_000)
                }
            }catch{if !Task.isCancelled{self.error=error.localizedDescription}}
            finishConnection()
        }
    }
    func readGroup(_ cmd:String) async throws {
        let list=profile.usable.filter{$0.command==cmd};let raw:String
        if let session=session{raw=try await session.request(cmd)}else{raw=try await elm.command(cmd)}
        for p in list {
            let result:Reading?
            if profile.name=="OBD-II" {result=Decoder.pid(raw,p.label).map{Reading(value:$0,display:number($0,p.label=="42" ? 2:1))}}
            else if profile.category==9 {let (payload,_)=try Decoder.tpmsPayload(raw,cmd);result=Decoder.canonical(payload,cmd).flatMap{Decoder.tpms(p,$0)}}
            else if let canonical=Decoder.canonical(raw,cmd,telemetry:true) {
                var param=p
                if p.label=="AutoSelector",canonical.hasPrefix("0562D4E7"),canonical.count==12{param.end=12}
                // No transform 16 values are shown until the ECU software version is known.
                let decoded=Decoder.decode(param,canonical,software:session?.software)
                result=param.label=="AutoSelector" && ![0.0,1.0,2.0,3.0,6.0].contains(decoded?.value ?? -1) ? nil:decoded
            }else{result=nil}
            publish(p,result)
        }
    }
    func publish(_ p:Param,_ reading:Reading?){
        let r=reading ?? Reading(value:nil,display:"—");readings[p.label]=r
        if let value=r.value,value.isFinite{let old=extrema[p.label];extrema[p.label]=(min(old?.0 ?? value,value),max(old?.1 ?? value,value))}
        var points=series[p.label] ?? [];points.append(TracePoint(at:r.at,value:r.value));series[p.label]=Array(points.suffix(600))
    }
    func enqueue(_ op:Operation){guard connected && !busy else{error="Conecte ao veículo e aguarde a operação atual.";return};busy=true;stopRequested=false;pending.append(op)}
    func readFaults() async throws {
        let result:[Fault]?
        if let s=session {
            try require(profile.category != 9,"O perfil TPMS contém apenas leituras.")
            let cmd=s.keepAlive=="3E00" ? "1902FF":"17FF00";let raw=try await s.request(cmd,timeout:10)
            result=Decoder.faults(raw,cmd,definitions:catalog?.faults(profile.name) ?? [:])
        }else{result=Decoder.genericFaults(try await elm.command("03",timeout:10),can:canGeneric)}
        guard let result=result else{throw AppError("Resposta de falhas inválida. Ausência de resposta não significa ausência de DTCs.")}
        let previous=Set(faults.map{$0.fullCode});faults=result;faultsRead=true;faultDate=Date()
        if prefs.dtcMonitor && !Set(result.map{$0.fullCode}).subtracting(previous).isEmpty{message="Novas falhas: "+Set(result.map{$0.fullCode}).subtracting(previous).sorted().joined(separator:", ");AudioServicesPlayAlertSound(1005)}
    }
    func stationary(allowUnknown:Bool=false) async throws {
        let rpmParam=profile.usable.first{$0.label=="Revs" || $0.label=="0C"};let speedParam=profile.usable.first{["Speed","AvgFrontWheels","0D"].contains($0.label)}
        for cmd in Set([rpmParam,speedParam].compactMap{$0?.command}){try await readGroup(cmd)}
        for (param,label) in [(rpmParam,"Rotação"),(speedParam,"Velocidade")] {
            guard let p=param else{continue};guard let value=fresh(p.label)?.value else{if allowUnknown{continue};throw AppError(label+" indisponível. Não foi possível confirmar veículo e motor parados.")}
            try require(value==0,label+" diferente de zero. Imobilize o veículo, desligue o motor e mantenha a ignição ligada.")
        }
    }
    func learningValues() async throws->[String:String] {
        let list=profile.usable.filter{$0.style=="learning"};try require(!list.isEmpty,"Este perfil não declara estados LEARN.")
        for cmd in Set(list.map{$0.command}){try await readGroup(cmd)}
        let values=Dictionary(uniqueKeysWithValues:list.map{($0.label,fresh($0.label)?.display ?? "—")});try require(values.values.contains{$0 != "—"},"Estados de aprendizado indisponíveis.");return values
    }
    func execute(_ op:Operation) async throws {
        switch op {
        case .faults:try await readFaults()
        case .clear:
            try await stationary(allowUnknown:true)
            if let s=session{message=try await Operations.clear(s)}else{let raw=try await elm.command("04",timeout:15);try require(Decoder.messages(raw).contains{$0.hasPrefix("44")},"ECU não confirmou o apagamento.");message="ECU confirmou o apagamento OBD-II; monitores de emissões podem ter sido reiniciados."}
            faults=[];faultsRead=false;lastFault=Date()
        case .capture(let stage,let freeze):try await capture(stage,freeze:freeze)
        case .routine(let action,let oil):
            guard let s=session,routines.contains(action) else{throw AppError("Rotina não pertence ao perfil ativo.")}
            try await stationary();actionRunning=true
            if action.condition==3{learning=LearningState(profile:profile.name,action:action.name,before:try await learningValues());try Store.save(learning,"learning.json")}
            message=try await Operations.run(action,session:s,oil:oil,stop:{self.stopRequested},progress:{self.status=$0})
            if action.condition==3{learning?.phase="reset_acknowledged";try Store.save(learning,"learning.json");disconnectRequested=true}
            if action.poll=="GEAROILWRITEAM6"{disconnectRequested=true}
            status=profile.name+" · leituras ao vivo"
        case .learning:
            guard let state=learning,state.profile==profile.name,let off=state.ignitionOffAt,Date().timeIntervalSince(off)>=30 else{throw AppError("Confirme ignição desligada por 30 segundos, religue e reconecte à mesma ECU.")}
            learning?.after=try await learningValues();learning?.phase="reread_confirmed";try Store.save(learning,"learning.json");message="Estados LEARN relidos. Isso não comprova adaptação mecânica concluída."
        case .module(_,let name):guard let p=profiles.first(where:{$0.name==name}) else{throw AppError("Perfil de central inexistente.")};try await readModule(p)
        }
    }
    func ignitionOff(){guard !connected && !connecting,learning?.phase=="reset_acknowledged" else{error="Desconecte antes de confirmar a ignição desligada.";return};learning?.phase="ignition_off";learning?.ignitionOffAt=Date();do{try Store.save(learning,"learning.json")}catch{self.error=error.localizedDescription}}
    func readModule(_ target:Profile) async throws {
        guard let s=session,profile.category==0,prefs.protocolName.hasPrefix("CAN"),[1,2,4,8].contains(target.category) else{throw AppError("Leitura de central secundária requer motor PSA em CAN.")}
        var result:[String:Reading]=[:];var failure:Error?
        do {
            _ = try await s.request(s.keepAlive);try await s.restore(target.category)
            let child=PSASession(elm,catalog!);child.category=target.category
            for cmd in ["81","1003","10C0"]{let raw=try await child.request(cmd);if Decoder.body(raw,cmd) != nil{child.keepAlive=cmd=="1003" ? "3E00":"3E"}}
            // Restore host between groups to avoid letting its diagnostic session expire.
            for cmd in Set(target.usable.map{$0.command}).sorted(){
                if Date().timeIntervalSince(s.last)>1{try await s.restore(0);_ = try await s.request(s.keepAlive);try await s.restore(target.category)}
                let raw=try await child.request(cmd);if let canonical=Decoder.canonical(raw,cmd,telemetry:true){for p in target.usable where p.command==cmd {if let r=Decoder.decode(p,canonical,software:child.software){result[p.label]=r}}}
            }
        }catch{failure=error}
        try await s.restore(0);if let failure=failure{throw failure};moduleReadings[target.name]=result
    }
    func capture(_ stage:String,freeze:Bool) async throws {
        var values:[String:Reading]=[:];var codes:[Fault]=[]
        if freeze {
            try require(profile.name=="OBD-II","Freeze frame padrão exige o perfil OBD-II.")
            let raw=try await elm.command("020200",timeout:6)
            guard let msg=Decoder.messages(raw).first(where:{$0.hasPrefix("420200")}),msg.count>=10,let value=Int(msg.slice(6,10),radix:16),value != 0 else{throw AppError("ECU não informou freeze frame válido associado a uma falha.")}
            codes=[Fault(code:Decoder.code(value),status:"",description:"Freeze frame OBD-II",detail:"",rawCode:msg.slice(6,10),subtype:"")]
            for p in Catalog.generic.usable where (Int(p.label,radix:16) ?? 256)<=0x20 {
                let raw=try await elm.command("02"+p.label+"00",timeout:6)
                if let msg=Decoder.messages(raw).first(where:{$0.hasPrefix("42"+p.label+"00")}),let value=Decoder.pid("41"+p.label+msg.dropFirst(6),p.label){values[p.label]=Reading(value:value,display:number(value))}
            }
        }else{try await readFaults();codes=faults;for cmd in Set(profile.usable.filter{["Revs","Speed","Coolant","Battery","TurboPress","0C","05","0D","42"].contains($0.label)}.map{$0.command}){try await readGroup(cmd)};values=readings.filter{$0.value.fresh && $0.value.value != nil}}
        let capture=Capture(vehicle:prefs.vehicle,profile:profile.name,stage:stage,source:freeze ? "Freeze frame OBD-II · quadro 0":"Leituras ao vivo",faults:codes,readings:values,units:Dictionary(uniqueKeysWithValues:params.map{($0.label,$0.unit)}))
        captures.insert(capture,at:0);captures=Array(captures.prefix(100));try Store.save(captures,"captures.json");message="Captura de oficina salva."
    }
    func recordIfNeeded(){
        guard prefs.recording,Date().timeIntervalSince(lastRecord)>=max(0.2,prefs.interval) else{if !prefs.recording{recordingSession=nil};return}
        do {
            if recordingSession==nil {let id=UUID().uuidString;let s=SessionInfo(id:id,profile:profile.name,filename:"session-\(id).csv");try Store.csv(["timestamp","mode","profile","parameter","value","unit","display","acquired_at","sample_time","age_ms","quality"]).write(to:Store.url(s.filename),atomically:true,encoding:.utf8);recordingSession=s;sessions.insert(s,at:0)}
            guard var current=recordingSession else{return};let at=ISO8601DateFormatter().string(from:Date())
            var text=""
            for p in params {guard let r=fresh(p.label) else{continue};text+=Store.csv([String(Int64(Date().timeIntervalSince1970*1000)),"real",profile.name,p.label,r.value.map{String($0)} ?? "",p.unit,r.display,String(Int64(r.at.timeIntervalSince1970*1000)),"",String(Int(max(0,Date().timeIntervalSince(r.at)*1000))),r.value==nil ? "text":"valid"])}
            for (module,values) in moduleReadings {for (key,r) in values where r.fresh {text+=Store.csv([at,"real",module,key,r.value.map{String($0)} ?? "","",r.display,r.at.ISO8601Format(),"","",r.value==nil ? "text":"valid"])}}
            if !text.isEmpty{let file=try FileHandle(forWritingTo:Store.url(current.filename));defer{try? file.close()};try file.seekToEnd();try file.write(contentsOf:Data(text.utf8));current.rows+=text.components(separatedBy:"\n").count-1;recordingSession=current;if let i=sessions.firstIndex(where:{$0.id==current.id}){sessions[i]=current};try Store.save(sessions,"sessions.json");samples+=1}
            lastRecord=Date()
        }catch{self.error="Erro ao gravar sessão: "+error.localizedDescription;prefs.recording=false;save()}
    }
    func exportAlarms(){do{let header=Store.csv(["id","profile","parameter","unit","limit","direction","started","ended","extreme","last","reason"]);let rows=events.map{e in Store.csv([e.id,e.profile,e.parameter,e.unit,String(e.limit),e.below ? "below":"above",e.at.ISO8601Format(),e.end?.ISO8601Format() ?? "",String(e.extreme),String(e.last),e.reason])}.joined();share=try Store.export(header+rows,"FrenchDiag-alarmes.csv")}catch{self.error=error.localizedDescription}}
    func evaluateAlarms(){
        let config=layout(false);var changed=false
        for p in params {
            let rule=config.tiles[p.label]?.alarm ?? AlarmRule();let r=fresh(p.label);let value=r?.value;let active=activeAlarm[p.label] != nil
            let on:Bool
            if let v=value,rule.enabled,connected {on=rule.below ? v<rule.limit+(active ? rule.hysteresis:0):v>rule.limit-(active ? rule.hysteresis:0)}else{on=false}
            if on,let v=value {
                if let id=activeAlarm[p.label],let index=events.firstIndex(where:{$0.id==id}){events[index].last=v;events[index].extreme=rule.below ? min(events[index].extreme,v):max(events[index].extreme,v)}
                else{let e=Event(profile:profile.name,parameter:p.label,unit:p.unit,limit:rule.limit,extreme:v,last:v,below:rule.below);events.append(e);activeAlarm[p.label]=e.id;changed=true}
                if Date().timeIntervalSince(lastAlarm[p.label] ?? .distantPast)>=max(3,rule.repeatSeconds){if rule.sound{AudioServicesPlayAlertSound(1005)};if rule.vibration{UIImpactFeedbackGenerator(style:.heavy).impactOccurred()};lastAlarm[p.label]=Date()}
            }else if let id=activeAlarm.removeValue(forKey:p.label),let i=events.firstIndex(where:{$0.id==id}){events[i].end=Date();events[i].reason=connected ? "Rearmado ou leitura indisponível":"Desconectado";changed=true}
        }
        let shift=prefs.shiftEnabled && (rpm?.value ?? -1)>=prefs.shiftTarget
        if shift && !lastShift{if prefs.shiftSound{AudioServicesPlayAlertSound(1005)};if prefs.shiftVibration{UIImpactFeedbackGenerator(style:.heavy).impactOccurred()}}
        lastShift=shift
        if changed{events=Array(events.suffix(500));do{try Store.save(events,"alarms.json")}catch{self.error=error.localizedDescription}}
    }
    func alarmOn(_ p:Param)->Bool{activeAlarm[p.label] != nil}
    func startTrip(gps:Bool){guard connected,currentTrip==nil else{error="Conecte antes de iniciar a viagem.";return};currentTrip=Trip(profile:profile.name,factor:prefs.fuelFactor);previousTripAt=nil;previousSpeed=nil;previousFuel=nil;if gps{location.requestWhenInUseAuthorization();location.desiredAccuracy=kCLLocationAccuracyBest;location.distanceFilter=5;location.startUpdatingLocation()}}
    func sampleTrip(){guard var t=currentTrip else{return};let now=Date();let dt=previousTripAt.map{now.timeIntervalSince($0)} ?? 0;if dt>0 && dt<1{return};let speed=fresh(profile.name=="OBD-II" ? "0D":"Speed")?.value;let fuel=params.first{$0.unit.lowercased()=="l/h"}.flatMap{fresh($0.label)?.value}
        if dt>0 && dt<=5{t.observed+=dt;if let s=speed,let old=previousSpeed,(0...400).contains(s){t.km+=(s+old)/2*dt/3600;t.distanceSeconds+=dt};if let f=fuel,let old=previousFuel,(0...500).contains(f){t.liters+=(f+old)/2*dt/3600*t.factor;t.fuelSeconds+=dt}}else if dt>5{t.observed+=dt}
        previousTripAt=now;previousSpeed=speed;previousFuel=fuel;currentTrip=t
    }
    func finishTrip(){guard var t=currentTrip else{return};t.ended=Date();trips.insert(t,at:0);trips=Array(trips.prefix(100));currentTrip=nil;location.stopUpdatingLocation();do{try Store.save(trips,"trips.json")}catch{self.error=error.localizedDescription}}
    func locationManager(_ manager:CLLocationManager,didUpdateLocations locations:[CLLocation]){guard var t=currentTrip,let l=locations.last,l.horizontalAccuracy>=0,l.horizontalAccuracy<=50,Date().timeIntervalSince(t.route.last?.at ?? .distantPast)>=5 else{return};t.route.append(RoutePoint(lat:l.coordinate.latitude,lon:l.coordinate.longitude,at:Date()));t.route=Array(t.route.suffix(20000));currentTrip=t}
    func locationManager(_ manager:CLLocationManager,didFailWithError error:Error){self.error="GPS: "+error.localizedDescription}
    func stopAction(){stopRequested=true}
    func disconnect(){if actionRunning{stopRequested=true;disconnectRequested=true;status="Encerrando rotina antes de desconectar…"}else{worker?.cancel();elm.close()}}
    func finishConnection(){if backgroundTask != .invalid{UIApplication.shared.endBackgroundTask(backgroundTask);backgroundTask = .invalid};finishTrip();elm.close();connected=false;connecting=false;busy=false;actionRunning=false;session=nil;pending=[];recordingSession=nil;status="Pronto para conectar";readings=[:];UIApplication.shared.isIdleTimerDisabled=false;for id in activeAlarm.values{if let i=events.firstIndex(where:{$0.id==id}){events[i].end=Date();events[i].reason="Desconectado"}};activeAlarm=[:];try? Store.save(events,"alarms.json")}
}
