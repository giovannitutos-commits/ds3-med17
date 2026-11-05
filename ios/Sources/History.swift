import SwiftUI
import UniformTypeIdentifiers
import Charts

struct CSVRow:Identifiable {var index:Int;var fields:[String];var id:Int{index}}
struct CSVStat:Identifiable {var key:String;var unit:String;var count:Int;var min:Double;var max:Double;var sum:Double;var id:String{key+unit};var mean:Double{sum/Double(count)}}
enum CSV {
    static func parse(_ text:String,separator:Character=",")->[[String]] {
        var rows:[[String]]=[];var row:[String]=[];var field="";var quoted=false;let chars=Array(text);var i=0
        while i<chars.count {let c=chars[i];if c=="\""{if quoted && i+1<chars.count && chars[i+1]=="\""{field.append("\"");i+=1}else{quoted.toggle()}}else if c==separator && !quoted{row.append(field);field=""}else if (c=="\n" || c=="\r") && !quoted{if c=="\r" && i+1<chars.count && chars[i+1]=="\n"{i+=1};row.append(field);if row.contains(where:{!$0.isEmpty}){rows.append(row)};row=[];field=""}else{field.append(c)};i+=1}
        if !field.isEmpty || !row.isEmpty{row.append(field);rows.append(row)};return rows
    }
    static func stats(_ rows:[[String]])->[CSVStat] {
        guard let header=rows.first,let ki=header.firstIndex(of:"parameter"),let vi=header.firstIndex(of:"value") else{return []};let ui=header.firstIndex(of:"unit");let qi=header.firstIndex(of:"quality");var result:[String:CSVStat]=[:]
        for row in rows.dropFirst(){guard row.count>max(ki,vi),let value=Double(row[vi]),value.isFinite else{continue};if let i=qi,row.count>i,["invalid","unavailable","stale"].contains(row[i]){continue};let unit=ui.flatMap{row.indices.contains($0) ? row[$0]:nil} ?? "";let id=row[ki]+unit;if var s=result[id]{s.count+=1;s.min=min(s.min,value);s.max=max(s.max,value);s.sum+=value;result[id]=s}else{result[id]=CSVStat(key:row[ki],unit:unit,count:1,min:value,max:value,sum:value)}}
        return result.values.sorted{$0.key<$1.key}
    }
    static func importFile(_ source:URL)throws->SessionInfo {
        let scoped=source.startAccessingSecurityScopedResource();defer{if scoped{source.stopAccessingSecurityScopedResource()}}
        let data=try Data(contentsOf:source);try require(data.count<50_000_000,"Importe arquivos menores que 50 MB.")
        guard let text=String(data:data,encoding:.utf8) ?? String(data:data,encoding:.isoLatin1) else{throw AppError("Codificação do CSV não reconhecida.")}
        let separator:Character=(text.components(separatedBy:.newlines).first ?? "").filter{$0==";"}.count > (text.components(separatedBy:.newlines).first ?? "").filter{$0==","}.count ? ";":","
        var rows=parse(text.replacingOccurrences(of:"\u{feff}",with:""),separator:separator);try require(rows.count>1,"Arquivo vazio ou sem amostras.")
        let header=rows.removeFirst();let id=UUID().uuidString;let filename="session-\(id).csv";let standard=["timestamp","mode","profile","parameter","value","unit","display","acquired_at","sample_time","age_ms","quality"]
        var output=Store.csv(standard);var count=0
        if header.contains("parameter") && header.contains("value") {
            let indexes=standard.map{header.firstIndex(of:$0)}
            for row in rows{var fields=indexes.map{$0.flatMap{row.indices.contains($0) ? row[$0]:nil} ?? ""};if fields[3].isEmpty{continue};if fields[6].isEmpty{fields[6]=fields[4]};if fields[10].isEmpty{fields[10]=Double(fields[4])==nil ? "text":"legacy"};output+=Store.csv(fields);count+=1}
        }else{
            try require(header.count>1,"Formato não reconhecido.")
            let dateTime=header.prefix(2).map{$0.lowercased()}==["date","time"]
            for row in rows {for i in (dateTime ? 2:1)..<min(row.count,header.count){let value=Double(row[i].replacingOccurrences(of:",",with:"."));if row[i].isEmpty || row[i]=="—"{continue};output+=Store.csv([dateTime ? row.prefix(2).joined(separator:" "):(row.first ?? ""),"importado","legado",header[i],value.map{String($0)} ?? "","",row[i],"","","",value==nil ? "text":"legacy"]);count+=1}}
        }
        try require(count>0,"Nenhuma leitura reconhecida.");try data.write(to:Store.url(filename+".original"),options:.atomic);try output.write(to:Store.url(filename),atomically:true,encoding:.utf8)
        return SessionInfo(id:id,profile:"Importado · "+source.lastPathComponent,filename:filename,rows:count)
    }
}
struct HistoryView:View {
    @EnvironmentObject var m:Dashboard;@State private var importing=false
    var body:some View{List{
        Section {Toggle("Gravar leituras",isOn:$m.prefs.recording).onChange(of:m.prefs.recording){_,_ in m.save()};Text("Amostras gravadas nesta conexão: \(m.samples)").font(.caption);Button("Importar CSV do Android / outro aplicativo"){importing=true};NavigationLink("Histórico de alarmes"){AlarmHistoryView()};NavigationLink("Capturas de oficina"){WorkshopView()}}
        Section("Sessões"){ForEach(m.sessions){s in NavigationLink{SessionDetail(session:s)}label:{VStack(alignment:.leading){Text(s.profile);Text(s.at.formatted()+" · \(s.rows) leituras").font(.caption).foregroundStyle(.secondary)}}}.onDelete{indices in guard !m.prefs.recording else{m.error="Encerre a gravação antes de excluir sessões.";return};for i in indices{try? FileManager.default.removeItem(at:Store.url(m.sessions[i].filename));try? FileManager.default.removeItem(at:Store.url(m.sessions[i].filename+".original"))};m.sessions.remove(atOffsets:indices);do{try Store.save(m.sessions,"sessions.json")}catch{m.error=error.localizedDescription}}}
    }.fileImporter(isPresented:$importing,allowedContentTypes:[.commaSeparatedText,.plainText,.data]){result in do{let url=try result.get();let info=try CSV.importFile(url);m.sessions.insert(info,at:0);try Store.save(m.sessions,"sessions.json")}catch{m.error=error.localizedDescription}}}
}
struct SessionDetail:View {
    @EnvironmentObject var m:Dashboard;let session:SessionInfo
    @State private var rows:[[String]]=[];@State private var comparing="";@State private var comparison:[CSVStat]=[];@State private var limit=200
    var stats:[CSVStat]{CSV.stats(rows)}
    var body:some View{List{
        Section("Exportar"){Button("Compartilhar CSV"){snapshot(session.filename)};if FileManager.default.fileExists(atPath:Store.url(session.filename+".original").path){Button("Compartilhar original importado"){snapshot(session.filename+".original")}}}
        Section("Comparar sessões"){Picker("Comparar com",selection:$comparing){Text("Sem comparação").tag("");ForEach(m.sessions.filter{$0.id != session.id}){s in Text(s.profile+" · "+s.at.formatted()).tag(s.filename)}}.onChange(of:comparing){_,name in comparison=CSV.stats((try? String(contentsOf:Store.url(name),encoding:.utf8)).map{CSV.parse($0)} ?? [])}}
        Section("Estatísticas · valores válidos"){ForEach(stats){s in VStack(alignment:.leading){Text(Catalog.titles[s.key] ?? s.key).font(.headline);Text("Mín \(number(s.min,2)) · Máx \(number(s.max,2)) · Média \(number(s.mean,2)) \(s.unit)").font(.caption);Text("\(s.count) amostras").font(.caption2).foregroundStyle(.secondary);if let other=comparison.first(where:{$0.key==s.key && $0.unit==s.unit}){Text("Comparação: mín \(number(other.min,2)), máx \(number(other.max,2)), média \(number(other.mean,2))").font(.caption)}}}}
        Section("Leituras · primeiras \(min(limit,max(0,rows.count-1))) de \(max(0,rows.count-1))"){ForEach(Array(rows.dropFirst().prefix(limit).enumerated()),id:\.offset){_,r in Text(r.joined(separator:" · ")).font(.caption2).textSelection(.enabled)};if rows.count>limit+1{Button("Carregar mais 200"){limit+=200}}}
    }.navigationTitle(session.at.formatted(date:.abbreviated,time:.shortened)).task{do{rows=CSV.parse(try String(contentsOf:Store.url(session.filename),encoding:.utf8))}catch{m.error=error.localizedDescription}}}
    func snapshot(_ filename:String){do{let data=try Data(contentsOf:Store.url(filename));let u=FileManager.default.temporaryDirectory.appendingPathComponent(filename.hasSuffix(".original") ? "FrenchDiag-original.csv":filename);try data.write(to:u,options:.atomic);m.share=u}catch{m.error=error.localizedDescription}}
}
struct AlarmHistoryView:View {
    @EnvironmentObject var m:Dashboard
    var body:some View{List{Section{Button("Exportar alarmes CSV"){m.exportAlarms()};Button("Excluir alarmes encerrados",role:.destructive){m.events.removeAll{$0.end != nil};do{try Store.save(m.events,"alarms.json")}catch{m.error=error.localizedDescription}}};ForEach(m.events.reversed()){e in VStack(alignment:.leading){Text(Catalog.titles[e.parameter] ?? e.parameter).font(.headline);Text("\(e.below ? "Abaixo":"Acima") de \(number(e.limit)) \(e.unit) · extremo \(number(e.extreme))");Text(e.at.formatted()+" · "+(e.end==nil ? "Ativo":e.reason)).font(.caption).foregroundStyle(e.end==nil ? .red:.secondary)}}}.navigationTitle("Alarmes")}
}
