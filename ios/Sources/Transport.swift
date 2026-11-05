import Foundation
import Network
import CoreBluetooth
import Combine

@MainActor protocol ELMCommands:AnyObject {func command(_ command:String,timeout:Double,recoverTimeout:Bool) async throws ->String}
extension ELMCommands {
    func command(_ command:String,timeout:Double=5) async throws ->String {try await self.command(command,timeout:timeout,recoverTimeout:false)}
}
@MainActor final class ELMTransport: NSObject, ObservableObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate, ELMCommands {
    struct Device: Identifiable { var id: UUID; var name: String }
    @Published var devices:[Device]=[]
    @Published var bluetoothState="Bluetooth não iniciado"
    @Published var trace:[String]=[]
    @Published var exchanges=0; @Published var timeouts=0
    private var tcp:NWConnection?; private var central:CBCentralManager?; private var peripherals:[UUID:CBPeripheral]=[:]
    private var peripheral:CBPeripheral?; private var tx:CBCharacteristic?; private var rx:CBCharacteristic?
    private var connected:CheckedContinuation<Void,Error>?; private var pending:CheckedContinuation<String,Error>?
    private var recovering=false
    private var response=""; private var deadline:Task<Void,Never>?; private var connectionDeadline:Task<Void,Never>?
    private var generation=0
    var writeUUID="";var notifyUUID=""
    func note(_ text:String) { trace.append(Date().formatted(date:.omitted,time:.standard)+" "+text);if trace.count>2000{trace.removeFirst(trace.count-2000)} }
    func scan() { if central == nil {central=CBCentralManager(delegate:self,queue:.main)}else if central?.state == .poweredOn {central?.scanForPeripherals(withServices:nil)} }
    func stopScan(){central?.stopScan()}
    func centralManagerDidUpdateState(_ central:CBCentralManager) {
        bluetoothState=central.state == .poweredOn ? "Procurando adaptadores BLE…":"Bluetooth indisponível: \(central.state.rawValue)"
        if central.state == .poweredOn {central.scanForPeripherals(withServices:nil)}
    }
    func centralManager(_ central:CBCentralManager,didDiscover p:CBPeripheral,advertisementData:[String:Any],rssi RSSI:NSNumber) {
        peripherals[p.identifier]=p
        if !devices.contains(where:{$0.id==p.identifier}) {devices.append(Device(id:p.identifier,name:p.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Adaptador BLE"))}
    }
    private func armConnection() { connectionDeadline?.cancel();connectionDeadline=Task{try? await Task.sleep(nanoseconds:15_000_000_000);if !Task.isCancelled {self.fail(AppError("Tempo de conexão esgotado."));self.close()}} }
    func connectWiFi(host:String,port:UInt16) async throws {
        close();let c=NWConnection(host:NWEndpoint.Host(host),port:NWEndpoint.Port(rawValue:port)!,using:.tcp);tcp=c
        try await withCheckedThrowingContinuation { (cont:CheckedContinuation<Void,Error>) in
            connected=cont;armConnection()
            c.stateUpdateHandler={ [weak self] state in Task { @MainActor in guard let self=self,self.tcp === c else{return};switch state {case .ready:self.finishConnection();self.receiveTCP(c);case .failed(let error):self.fail(error);case .cancelled:self.fail(AppError("Conexão encerrada."));default:break} } }
            c.start(queue:.main)
        }
    }
    func connectBLE(_ id:UUID) async throws {
        close()
        if central==nil{central=CBCentralManager(delegate:self,queue:.main)}
        let started=Date()
        while central?.state != .poweredOn {
            try Task.checkCancellation()
            guard let state=central?.state,state == .unknown || state == .resetting else{throw AppError("Ative o Bluetooth e permita o acesso ao FrenchDiag.")}
            try require(Date().timeIntervalSince(started)<10,"O Bluetooth não ficou disponível a tempo.")
            try await Task.sleep(nanoseconds:100_000_000)
        }
        guard let central=central,let p=peripherals[id] ?? central.retrievePeripherals(withIdentifiers:[id]).first else{throw AppError("Adaptador BLE salvo não encontrado. Faça uma nova busca.")}
        peripherals[id]=p;peripheral=p;p.delegate=self;tx=nil;rx=nil;central.stopScan()
        try await withCheckedThrowingContinuation { (cont:CheckedContinuation<Void,Error>) in connected=cont;armConnection();central.connect(p) }
    }
    private func finishConnection(){connectionDeadline?.cancel();let c=connected;connected=nil;c?.resume()}
    func centralManager(_ central:CBCentralManager,didConnect p:CBPeripheral){guard p === peripheral else{return};p.discoverServices(nil)}
    func centralManager(_ central:CBCentralManager,didFailToConnect p:CBPeripheral,error:Error?){if p === peripheral{fail(error ?? AppError("Falha no BLE."))}}
    func centralManager(_ central:CBCentralManager,didDisconnectPeripheral p:CBPeripheral,error:Error?){if p === peripheral{fail(error ?? AppError("BLE desconectado."));tx=nil;rx=nil}}
    func peripheral(_ p:CBPeripheral,didDiscoverServices error:Error?){if let e=error{fail(e);return};for s in p.services ?? []{p.discoverCharacteristics(nil,for:s)}}
    func peripheral(_ p:CBPeripheral,didDiscoverCharacteristicsFor service:CBService,error:Error?){
        if let e=error{fail(e);return}
        // Match UART pairs within one service. User-entered UUIDs override detection.
        let chars=service.characteristics ?? []
        let write=chars.first { c in (writeUUID.isEmpty || c.uuid.uuidString.caseInsensitiveCompare(writeUUID) == .orderedSame) && (c.properties.contains(.write) || c.properties.contains(.writeWithoutResponse)) }
        let notify=chars.first { c in (notifyUUID.isEmpty || c.uuid.uuidString.caseInsensitiveCompare(notifyUUID) == .orderedSame) && (c.properties.contains(.notify) || c.properties.contains(.indicate)) }
        if tx == nil,let write=write,let notify=notify {tx=write;rx=notify;p.setNotifyValue(true,for:notify)}
    }
    func peripheral(_ p:CBPeripheral,didUpdateNotificationStateFor characteristic:CBCharacteristic,error:Error?){if let e=error{fail(e)}else if characteristic === rx && characteristic.isNotifying{finishConnection()}}
    func peripheral(_ p:CBPeripheral,didUpdateValueFor characteristic:CBCharacteristic,error:Error?){if let e=error{fail(e)}else if characteristic === rx,let data=characteristic.value{ingest(data)}}
    func peripheral(_ p:CBPeripheral,didWriteValueFor characteristic:CBCharacteristic,error:Error?){if let e=error{fail(e)}}
    private func receiveTCP(_ c:NWConnection){
        c.receive(minimumIncompleteLength:1,maximumLength:65536){[weak self]data,_,complete,error in Task{@MainActor in
            guard let self=self,self.tcp === c else{return};if let data=data{self.ingest(data)};if let e=error{self.fail(e)}else if complete{self.fail(AppError("Adaptador encerrou a conexão."))}else{self.receiveTCP(c)}
        }}
    }
    private func ingest(_ data:Data){
        guard pending != nil else{return};response+=String(decoding:data,as:UTF8.self)
        if response.utf8.count>131072{fail(AppError("Resposta do adaptador excedeu o limite."));return}
        if response.contains(">") {
            let messages=Decoder.messages(response)
            if !recovering,let last=messages.last,last.hasPrefix("7F"),last.hasSuffix("78") {response=response.replacingOccurrences(of:">",with:"\n");return}
            deadline?.cancel();let c=pending;pending=nil;note("RX "+response);c?.resume(returning:response+(recovering ? "\rSTOPPED":""))
        }
    }
    func command(_ command:String,timeout:Double=5,recoverTimeout:Bool=false) async throws -> String {
        try Task.checkCancellation();try require(pending == nil,"Há outra solicitação OBD em andamento.")
        try require(command.range(of:"^[A-Za-z0-9 ]+$",options:.regularExpression) != nil,"Comando inválido.")
        generation+=1;let token=generation;response="";recovering=false;note("TX "+command)
        return try await withCheckedThrowingContinuation { cont in
            pending=cont;exchanges+=1
            deadline=Task {
                try? await Task.sleep(nanoseconds:UInt64(timeout*1_000_000_000))
                if !Task.isCancelled && self.generation==token {
                    self.timeouts+=1
                    if recoverTimeout {
                        self.recovering=true;self.note("Timeout opcional; interrompendo consulta e aguardando novo prompt.");self.send(Data(" ".utf8))
                        self.deadline=Task {try? await Task.sleep(nanoseconds:1_000_000_000);if !Task.isCancelled && self.generation==token {self.fail(AppError("Não foi possível recuperar o prompt após \(command)."));self.close()}}
                    }else{self.fail(AppError("Tempo esgotado: \(command)"));self.close()}
                }
            }
            let data=Data((command+"\r").utf8)
            send(data)
        }
    }
    private func send(_ data:Data){
        if let c=tcp{c.send(content:data,completion:.contentProcessed{[weak self]error in if let error=error{Task{@MainActor in self?.fail(error)}}})}
        else if let p=peripheral,let tx=tx{let type:CBCharacteristicWriteType=tx.properties.contains(.write) ? .withResponse:.withoutResponse;let size=p.maximumWriteValueLength(for:type);if data.count>size{fail(AppError("Comando excede o MTU BLE; use Wi-Fi para esta rotina."))}else{p.writeValue(data,for:tx,type:type)}}else{fail(AppError("Adaptador desconectado."))}
    }
    func fail(_ error:Error){deadline?.cancel();connectionDeadline?.cancel();let c=connected;connected=nil;let p=pending;pending=nil;c?.resume(throwing:error);p?.resume(throwing:error)}
    func close(){generation+=1;fail(AppError("Conexão encerrada."));let c=tcp;tcp=nil;c?.stateUpdateHandler=nil;c?.cancel();if let p=peripheral{peripheral=nil;central?.cancelPeripheralConnection(p)};tx=nil;rx=nil}
}

@MainActor final class PSASession {
    let elm:any ELMCommands;let catalog:Catalog;var keepAlive="3E";var software:Int?;var last=Date.distantPast;var category=0;var protocolName="CAN";var tpmsReceive:String?
    static let addresses:[Int:(String,String)]=[0:("6A8","688"),1:("76D","66D"),2:("765","665"),3:("6AD","68D"),4:("6B5","695"),5:("6C1","601"),6:("75F","65F"),7:("760","660"),8:("6A9","689")]
    init(_ elm:any ELMCommands,_ catalog:Catalog){self.elm=elm;self.catalog=catalog}
    func ok(_ command:String) async throws {let raw=try await elm.command(command);try require(raw.uppercased().contains("OK"),"O adaptador rejeitou \(command).")}
    func setup(category:Int,protocolName:String) async throws {
        self.category=category;self.protocolName=protocolName;_ = try await elm.command("ATZ",timeout:8)
        for c in ["ATE0","ATL0","ATS0","ATH0"]{try await ok(c)}
        if category == 9 {
            try require(protocolName.hasPrefix("CAN"),"TPMS requer CAN.")
            for c in [protocolName=="CAN 250 kbps" ? "ATSP8":"ATSP6","ATCAF1","ATSH6AF","ATCRA","ATCF000","ATCM000","ATH1"]{try await ok(c)};keepAlive="";return
        }
        if protocolName.hasPrefix("CAN") {
            guard let address=Self.addresses[category] else{throw AppError("Categoria não suportada.")}
            _ = try await elm.command(protocolName=="CAN variável" ? "ATV1":"ATV0");_ = try await elm.command("ATAL")
            for c in [protocolName=="CAN 250 kbps" ? "ATSP8":"ATSP6","ATCAF1","ATSH"+address.0,"ATCRA"+address.1,"ATFCSH"+address.0,"ATFCSD300000","ATFCSM1"]{try await ok(c)}
        }else {
            try await ok(protocolName=="KWP rápido" ? "ATSP5":"ATSP4");try await ok("ATSH8110F1");try await ok("ATSW00");if protocolName=="KWP rápido"{_ = try await elm.command("ATFI",timeout:8)}
        }
        for c in ["81","1003","10C0"] + (protocolName.hasPrefix("CAN") ? []:["10A4"]) {let raw=try await elm.command(c,timeout:6);if Decoder.body(raw,c) != nil{keepAlive=c=="1003" ? "3E00":"3E"}}
        last=Date()
    }
    func request(_ cmd:String,timeout:Double=5) async throws -> String {
        if !keepAlive.isEmpty && cmd != keepAlive && Date().timeIntervalSince(last)>1.8{_ = try await elm.command(keepAlive,timeout:3.5)}
        let raw=try await elm.command(cmd,timeout:timeout);last=Date();return raw
    }
    func identify() async throws -> Profile? {
        var candidates:[String]=[]
        for cmd in ["2180","21FE","22F080","22F0FE","22F1A0"] {
            let raw=try await request(cmd);guard let canonical=Decoder.canonical(raw,cmd) else{continue}
            let ranges:[(Int,Int)]=cmd=="2180" ? [(20,30),(6,16)] : cmd=="21FE" ? [(48,54)] : cmd=="22F080" ? [(22,32),(8,18)] : cmd=="22F0FE" ? [(50,56)]:[(126,136)]
            for (a,b) in ranges where canonical.count>=b{candidates.append(canonical.slice(a,b))}
            if cmd=="2180" && canonical.count>=34{software=Int(canonical.slice(30,34),radix:16)}
            if let profile=try catalog.identify(candidates,category:category){return profile}
        }
        return try catalog.identify(candidates,category:category)
    }
    func restore(_ cat:Int) async throws {guard let address=Self.addresses[cat] else{throw AppError("Endereço indisponível.")};for c in ["ATH0","ATCAF1","ATSH"+address.0,"ATCRA"+address.1,"ATFCSH"+address.0,"ATFCSD300000","ATFCSM1"]{try await ok(c)}}
    func tpms(_ p:Param) async throws -> Reading? {
        try require(category==0 && protocolName.hasPrefix("CAN"),"TPMS simultâneo requer ECU motor em CAN.")
        _ = try await request(keepAlive,timeout:3.5)
        var result:Reading?;var failure:Error?
        do {
            try await ok("ATSH6AF");if let rx=tpmsReceive{try await ok("ATCRA"+rx)}else{try await ok("ATCF000");try await ok("ATCM000")};try await ok("ATH1")
            let raw=try await elm.command(p.command,timeout:1.2,recoverTimeout:true)
            let (payload,rx)=try Decoder.tpmsPayload(raw,p.command);if let rx=rx{tpmsReceive=rx};result=Decoder.canonical(payload,p.command).flatMap{Decoder.tpms(p,$0)}
        }catch{failure=error}
        // Restoration is mandatory even when the module reports NO DATA.
        try await restore(category);if let failure=failure{throw failure};return result
    }
    func maintain(_ seconds:Double,stop:()->Bool) async throws {
        let end=Date().addingTimeInterval(seconds)
        while Date()<end && !stop(){try await Task.sleep(nanoseconds:500_000_000);if Date().timeIntervalSince(last)>1.5{let raw=try await request(keepAlive);try require(Decoder.body(raw,keepAlive)?.hasPrefix("7E")==true,"Sessão diagnóstica não confirmada.")}}
    }
}
