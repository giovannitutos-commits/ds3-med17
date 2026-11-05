import Foundation

@MainActor enum Operations {
    static func dateBlock(day:Int,month:Int,year:Int)->String {
        let bytes:[Int]=[0x34,0xCF,0,0,0,9,0,0,0,day,month,year-2000,0,0,0];var crc=0xffff
        for b in bytes{crc ^= b;for _ in 0..<8{crc=crc&1 != 0 ? (crc>>1)^0x8408:crc>>1}}
        crc ^= 0xffff;let swapped=((crc&255)<<8)|((crc>>8)&255)
        return bytes.map{String(format:"%02X",$0)}.joined()+String(format:"%04X",swapped)
    }
    static func clear(_ session:PSASession) async throws -> String {
        let uds=session.keepAlive=="3E00";let cmd=uds ? "14FFFFFF":"14FF00"
        if Decoder.body(try await session.request(cmd,timeout:15),cmd)?.hasPrefix("54")==true{return "A ECU confirmou o apagamento. Consulte novamente as falhas."}
        try require(!uds,"A ECU recusou o apagamento de falhas.")
        let date=Calendar.current.dateComponents([.day,.month,.year],from:Date());let block=dateBlock(day:date.day!,month:date.month!,year:date.year!)
        _ = try await session.request("81");if !session.protocolName.hasPrefix("CAN"){_ = try await session.request("10A4")}
        _ = try await session.elm.command("ATAL");_ = try await session.request("21CF00")
        if session.protocolName.hasPrefix("CAN") {
            try await session.ok("ATCAF0")
            do {
                let flow=try await session.elm.command("1011"+block.prefix(12),timeout:6)
                try require(Decoder.messages(flow).contains{$0.hasPrefix("30")},"A ECU não autorizou o bloco de data.")
                try await session.ok("ATR0");_ = try await session.elm.command("21"+block.slice(12,26));try await session.ok("ATR1")
                let response=try await session.elm.command("22"+block.dropFirst(26),timeout:6)
                try require(Decoder.messages(response).contains{$0.hasPrefix("74") || $0.dropFirst(2).hasPrefix("74")},"Bloco de data não confirmado.")
            }catch{try? await session.ok("ATR1");try? await session.ok("ATCAF1");throw error}
            try await session.ok("ATR1");try await session.ok("ATCAF1")
        }else{let raw=try await session.request(block,timeout:6);try require(Decoder.body(raw,block)?.hasPrefix("74")==true,"Bloco de data rejeitado.")}
        let raw=try await session.request(cmd,timeout:15);try require(Decoder.body(raw,cmd)?.hasPrefix("54")==true,"Apagamento não confirmado.")
        return "A ECU confirmou o apagamento. Algumas centrais exigem desligar a ignição antes de consultar novamente."
    }
    static func run(_ a:Routine,session:PSASession,oil:Int?,stop:()->Bool,progress:(String)->Void) async throws -> String {
        let first=try await session.request(a.start,timeout:6)
        if a.condition==3 {
            try require(Decoder.body(first,a.start,telemetry:true)?.hasPrefix(a.poll)==true,"Estados de aprendizado indisponíveis.")
            let raw=try await session.request(a.stop,timeout:8)
            try require(Decoder.body(raw,a.stop)?.hasPrefix(a.response)==true,"Reset de aprendizado não confirmado.")
            return "Reset solicitado e confirmado. Desligue a ignição por pelo menos 30 segundos, religue e releia os estados. Isso não comprova adaptação mecânica concluída."
        }
        func valid(_ payload:String?,command:String,stopping:Bool)->Bool {
            guard let p=payload,p.hasPrefix(a.response) else{return false}
            if command.hasPrefix("30"){return p.count>=6 && (!stopping || p.slice(4,6)==a.stopped)}
            if command.hasPrefix("2F"){return p.count>=8 && p.slice(2,8)==command.slice(2,8)}
            return !stopping
        }
        if a.poll=="GEAROILWRITE" {
            try require(valid(Decoder.body(first,a.start),command:a.start,stopping:false),"Início da rotina recusado.")
            guard let value=oil,(0...65535).contains(value) else{throw AppError("Contador AL4 deve estar entre 0 e 65535.")}
            let cmd="3BCB"+String(format:"%08llX",Int64(value)*65535)
            let raw=try await session.request(cmd,timeout:6);try require(Decoder.body(raw,cmd)?.hasPrefix("7B")==true,"Gravação do contador não confirmada.");return "ECU confirmou a gravação do contador AL4."
        }
        if a.poll=="GEAROILWRITEAM6" {
            try require(valid(Decoder.body(first,a.start),command:a.start,stopping:false),"Início da rotina recusado.")
            let raw=try await session.request("11FF",timeout:8);try require(Decoder.body(raw,"11FF")?.hasPrefix("51")==true,"Reset AM6 não confirmado.");return "ECU confirmou 11FF. Desligue e religue a ignição conforme o fabricante e reconecte."
        }
        var result="Teste encerrado.";var failure:Error?
        do {
            try require(valid(Decoder.body(first,a.start,telemetry:true),command:a.start,stopping:false),"A ECU rejeitou o início de \(a.name).")
            let timed=["--","-"].contains(a.poll);let end=Date().addingTimeInterval(a.poll=="--" ? 28:6);var iteration=0
            while !stop() {
                if timed && Date()>=end{result="Tempo programado encerrado.";break}
                iteration+=1;progress("\(a.name) · consulta \(iteration)");try await session.maintain(1,stop:stop)
                if stop(){break}
                if !timed && a.poll.hex {
                    let raw=try await session.request(a.poll,timeout:6)
                    guard let p=Decoder.body(raw,a.poll),p.hasPrefix(a.response),p.count>=6 else{throw AppError("Resposta de teste incompleta; conclusão não confirmada.")}
                    let status=p.slice(4,6)
                    if status==a.stopped{result="ECU informou teste parado.";break}
                    if status != a.running {
                        try require(status=="00" && p.count>=8,"Resultado de rotina desconhecido ou truncado.")
                        let code=Int(p.slice(6,8),radix:16) ?? -1
                        result="ECU informou término: "+(a.results.indices.contains(code) ? a.results[code]:"código \(code)");break
                    }
                }
            }
            if stop(){result="Parada solicitada pelo usuário."}
        }catch{failure=error}
        if a.stop.hex {
            let raw=try await session.request(a.stop,timeout:6)
            try require(valid(Decoder.body(raw,a.stop),command:a.stop,stopping:true),"Parada não confirmada. Desligue a ignição e confira o atuador.")
            result+=" Parada confirmada pela ECU."
        }
        if let error=failure{throw error};return result
    }
}
