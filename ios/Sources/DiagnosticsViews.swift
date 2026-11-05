import SwiftUI
import Charts
import MapKit
import UniformTypeIdentifiers

struct MotorView:View {
    @EnvironmentObject var m:Dashboard
    @State private var action:Routine?;@State private var confirm=false;@State private var oil="0";@State private var search=""
    var body:some View{List{
        Section("Central ativa"){LabeledContent("Perfil",value:m.profile.name);LabeledContent("Protocolo",value:m.prefs.protocolName);Text(m.status).font(.caption);NavigationLink("Gráficos ao vivo"){GraphsView()};NavigationLink("Centrais secundárias"){ModulesView()};NavigationLink("Viagens e mapa"){TripsView()};NavigationLink("Relatório de oficina"){WorkshopView()};NavigationLink("Ajuda técnica"){HelpView()}}
        if m.actionRunning{Section{ProgressView(m.status);Button("Parar teste",role:.destructive){m.stopAction()}}}
        if !m.routines.isEmpty{Section("Rotinas do perfil"){ForEach(m.routines){a in Button{action=a;confirm=true}label:{VStack(alignment:.leading,spacing:4){Text(a.name);Text(a.tip).font(.caption).foregroundStyle(.secondary)}}.disabled(!m.connected || m.busy)}}}
        if let learning=m.learning{Section("Acompanhamento de aprendizado"){Text(learning.action);Text("Estado: "+learning.phase).font(.caption);Button("Confirmar ignição desligada"){m.ignitionOff()}.disabled(m.connected);Button("Reler estados após reconectar"){m.enqueue(.learning)}.disabled(!m.connected || m.busy);ForEach(learning.before.keys.sorted(),id:\.self){k in LabeledContent(k,value:(learning.before[k] ?? "—")+" → "+(learning.after[k] ?? "—"))}}}
        Section("Todos os parâmetros disponíveis no perfil"){ForEach(m.params.filter{search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.label.localizedCaseInsensitiveContains(search)}){p in NavigationLink{ParameterDetail(p:p)}label:{HStack{VStack(alignment:.leading){Text(p.title);Text(p.command).font(.caption2).foregroundStyle(.secondary)};Spacer();Text(m.display(p,m.readings[p.label]).0+" "+m.display(p,m.readings[p.label]).1).monospacedDigit().foregroundStyle(m.fresh(p.label)==nil ? .secondary:.primary)}}}}
    }.searchable(text:$search,prompt:"Buscar leitura").sheet(isPresented:$confirm){NavigationStack{Form{if let a=action{Section(a.name){Text(a.tip);Text("Execute apenas com o veículo imobilizado, motor desligado e ignição ligada, conforme o procedimento do fabricante. O app verificará as leituras de parada antes de enviar comandos.").font(.callout);if a.poll=="GEAROILWRITE"{TextField("Novo contador AL4 · 0 a 65535",text:$oil).keyboardType(.numberPad)};Button("Executar rotina",role:.destructive){confirm=false;m.enqueue(.routine(a,Int(oil)))};Button("Cancelar",role:.cancel){confirm=false}}}}.navigationTitle("Confirmar operação").toolbar{ToolbarItem(placement:.cancellationAction){Button("Fechar"){confirm=false}}}}}}
}
struct FaultsView:View {
    @EnvironmentObject var m:Dashboard;@State private var clear=false
    var body:some View {List {
        Section{Button{m.enqueue(.faults)}label:{Label("Ler falhas",systemImage:"arrow.clockwise")}.disabled(!m.connected || m.busy);Button("Apagar falhas",role:.destructive){clear=true}.disabled(!m.connected || m.busy);if m.busy{ProgressView()};if let date=m.faultDate{Text("Última consulta: "+date.formatted()).font(.caption)}}
        Section("Resposta da central"){if !m.faultsRead{ContentUnavailableView("Falhas ainda não consultadas",systemImage:"questionmark.circle",description:Text("Conecte ao veículo e consulte os códigos."))}else if m.faults.isEmpty{Text("Nenhum código retornado nesta consulta.")}else{ForEach(m.faults){f in VStack(alignment:.leading,spacing:5){Text(f.fullCode).font(.headline.monospaced());Text(f.description);if !f.detail.isEmpty{Text(f.detail).font(.caption)};Text("Raw \(f.rawCode) · subtipo \(f.subtype.isEmpty ? "—":f.subtype) · status \(f.status)").font(.caption2).foregroundStyle(.secondary)}}}}
        Section{NavigationLink("Capturar freeze frame / relatório"){WorkshopView()};Toggle("Monitorar novas falhas",isOn:$m.prefs.dtcMonitor).onChange(of:m.prefs.dtcMonitor){_,_ in m.save()}}
    }.confirmationDialog("Apagar falhas da central?",isPresented:$clear,titleVisibility:.visible){Button("Confirmar apagamento",role:.destructive){m.enqueue(.clear)}}message:{Text("Imobilize o veículo, desligue o motor e mantenha a ignição ligada. O apagamento pode reiniciar monitores de emissões. Se a telemetria estiver indisponível, esta confirmação declara que você verificou essas condições.")}}
}
struct ParameterDetail:View {
    @EnvironmentObject var m:Dashboard;let p:Param
    var body:some View {List{Section{Text(p.description);LabeledContent("Comando",value:p.command);LabeledContent("Unidade da ECU",value:p.unit);LabeledContent("Valor",value:m.display(p,m.readings[p.label]).0);if let reading=m.readings[p.label]{LabeledContent("Aquisição",value:reading.at.formatted());LabeledContent("Qualidade",value:reading.fresh ? reading.value==nil ? "Texto":"Válida":"Vencida")}};Section{LiveGraph(key:p.label).frame(height:220);NavigationLink("Visual e alarme"){TileEditor(key:p.label,landscape:false)}}}.navigationTitle(p.title)}
}
struct LiveGraph:View {
    @EnvironmentObject var m:Dashboard;let key:String
    var points:[GraphPoint]{var segment=0;var last:Date?;return (m.series[key] ?? []).compactMap{p in guard let v=p.value else{segment+=1;last=nil;return nil};if let old=last,p.at.timeIntervalSince(old)>15{segment+=1};last=p.at;return GraphPoint(at:p.at,value:v,segment:segment)}}
    var body:some View{Chart(points){p in LineMark(x:.value("Hora",p.at),y:.value("Valor",p.value),series:.value("Trecho",p.segment)).foregroundStyle(Color(hex:m.prefs.accent))}.chartXAxis{AxisMarks(values:.automatic(desiredCount:3))}.overlay{if points.isEmpty{Text("Aguardando leituras válidas").font(.caption).foregroundStyle(.secondary)}}}
}
struct GraphPoint:Identifiable{var at:Date;var value:Double;var segment:Int;var id:Date{at}}
struct GraphsView:View {
    @EnvironmentObject var m:Dashboard;@State private var choosing=false
    var keys:[String]{m.prefs.graphs.isEmpty ? Array(m.params.filter{$0.numeric}.prefix(4).map{$0.label}):m.prefs.graphs}
    var body:some View{ScrollView{VStack{ForEach(keys,id:\.self){key in VStack(alignment:.leading){Text(m.params.first{$0.label==key}?.title ?? key).font(.headline);LiveGraph(key:key).frame(height:190)}.padding()}}}.navigationTitle("Gráficos").toolbar{Button("Selecionar"){choosing=true}}.sheet(isPresented:$choosing){NavigationStack{List(m.params.filter{$0.numeric}){p in Toggle(p.title,isOn:Binding(get:{keys.contains(p.label)},set:{on in var list=keys;if on && !list.contains(p.label) && list.count<4{list.append(p.label)}else if !on{list.removeAll{$0==p.label}};m.prefs.graphs=list;m.save()}))}.navigationTitle("Até quatro parâmetros").toolbar{Button("Concluir"){choosing=false}}}}}
}
struct ModulesView:View {
    @EnvironmentObject var m:Dashboard
    @State private var selected=""
    @State private var category=8
    var choices:[Profile]{m.profiles.filter{$0.category==category}}
    var body:some View{List{addSection;ForEach(m.moduleReadings.keys.sorted(),id:\.self){name in ModuleSection(name:name)}}.navigationTitle("Centrais secundárias")}
    var addSection:some View {
        Section("Adicionar central secundária") {
            Picker("Categoria",selection:$category){ForEach([1,2,4,8],id:\.self){cat in Text(moduleName(cat)).tag(cat)}}.onChange(of:category){_,_ in selected=""}
            Picker("Perfil exato da central",selection:$selected){Text("Selecione").tag("");ForEach(choices){p in Text(p.name).tag(p.name)}}
            Button("Ler e acompanhar"){m.enqueue(.module(category,selected))}.disabled(selected.isEmpty || !m.connected || m.busy)
            Text("Selecione o perfil correto da central. A leitura restaura o endereço do motor e mantém sua sessão ativa.").font(.caption)
        }
    }
}
struct ModuleSection:View {
    @EnvironmentObject var m:Dashboard
    let name:String
    var values:[String:Reading]{m.moduleReadings[name] ?? [:]}
    var codes:[Fault]{m.moduleFaults[name] ?? []}
    var body:some View {Section(name){
        Button("Parar acompanhamento",role:.destructive){m.moduleReadings.removeValue(forKey:name);m.moduleFaults.removeValue(forKey:name)}
        ForEach(codes){f in Text(f.fullCode+" · "+f.description).font(.caption).foregroundStyle(.orange)}
        ForEach(values.keys.sorted(),id:\.self){key in LabeledContent(Catalog.titles[key] ?? key,value:values[key]?.display ?? "—")}
    }}
}
struct WorkshopView:View {
    @EnvironmentObject var m:Dashboard;@State private var stage="Antes";@State private var beforeID=""
    var body:some View{List {
        Section("Nova captura"){TextField("Veículo",text:$m.prefs.vehicle);TextField("Etapa",text:$stage);Button("Capturar leituras e falhas atuais"){m.enqueue(.capture(stage,false))}.disabled(!m.connected || m.busy);Button("Capturar freeze frame OBD-II"){m.enqueue(.capture(stage,true))}.disabled(!m.connected || m.busy || m.profile.name != "OBD-II")}
        Section("Comparação"){Picker("Captura anterior",selection:$beforeID){Text("Sem comparação").tag("");ForEach(m.captures){c in Text(c.stage+" · "+c.at.formatted()).tag(c.id)}}}
        Section("Capturas salvas"){ForEach(m.captures){c in VStack(alignment:.leading,spacing:6){Text(c.vehicle+" · "+c.stage).font(.headline);Text(c.profile+" · "+c.source).font(.caption);Text(c.at.formatted()).font(.caption2);Button("Compartilhar PDF"){do{m.share=try Store.report(c,before:m.captures.first{$0.id==beforeID})}catch{m.error=error.localizedDescription}}}}.onDelete{offset in m.captures.remove(atOffsets:offset);do{try Store.save(m.captures,"captures.json")}catch{m.error=error.localizedDescription}}}
    }.navigationTitle("Oficina").onDisappear{m.save()}}
}
struct CommunicationView:View {
    @EnvironmentObject var m:Dashboard
    var body:some View{List{Section("Saúde da conexão"){LabeledContent("Consultas",value:String(m.elm.exchanges));LabeledContent("Timeouts",value:String(m.elm.timeouts));Text(m.tpmsNotice).font(.caption)};Section{Button("Exportar comunicação"){do{m.share=try Store.export(m.elm.trace.joined(separator:"\n"),"FrenchDiag-comunicacao.txt")}catch{m.error=error.localizedDescription}};ForEach(Array(m.elm.trace.suffix(300).enumerated()),id:\.offset){_,text in Text(text).font(.caption2.monospaced()).textSelection(.enabled)}}}.navigationTitle("Comunicação")}
}
struct TripsView:View {
    @EnvironmentObject var m:Dashboard;@State private var gps=true
    var body:some View {List{Section("Viagem atual"){Toggle("Registrar trajeto GPS",isOn:$gps);if let t=m.currentTrip{TripSummary(trip:t);Button("Encerrar viagem",role:.destructive){m.finishTrip()}}else{Button("Iniciar viagem"){m.startTrip(gps:gps)}.disabled(!m.connected)}};Section("Histórico"){ForEach(m.trips){t in NavigationLink{TripDetail(trip:t)}label:{VStack(alignment:.leading){Text(t.started.formatted());TripSummary(trip:t)}}}.onDelete{indices in m.trips.remove(atOffsets:indices);do{try Store.save(m.trips,"trips.json")}catch{m.error=error.localizedDescription}}}}.navigationTitle("Viagens")}
}
struct TripSummary:View {let trip:Trip;var body:some View{VStack(alignment:.leading){Text("\(number(trip.km,2)) km · \(number(trip.liters,2)) l");Text(trip.consumption.map{number($0,2)+" l/100 km"} ?? "Consumo médio indisponível: cobertura insuficiente.").font(.caption).foregroundStyle(.secondary);Text("Cobertura distância/combustível: \(number(trip.observed>0 ? trip.distanceSeconds/trip.observed*100:0,0))% / \(number(trip.observed>0 ? trip.fuelSeconds/trip.observed*100:0,0))%").font(.caption2)}}}
struct TripDetail:View {
    @EnvironmentObject var m:Dashboard;let trip:Trip
    var body:some View{ScrollView{VStack(alignment:.leading){TripSummary(trip:trip).padding();if !trip.route.isEmpty {Map{MapPolyline(coordinates:trip.route.map{CLLocationCoordinate2D(latitude:$0.lat,longitude:$0.lon)}).stroke(.blue,lineWidth:4)}.frame(height:350)};Button("Exportar trajeto GPX"){let points=trip.route.map{"<trkpt lat=\"\($0.lat)\" lon=\"\($0.lon)\"><time>\($0.at.ISO8601Format())</time></trkpt>"}.joined();do{m.share=try Store.export("<?xml version=\"1.0\" encoding=\"UTF-8\"?><gpx version=\"1.1\" creator=\"FrenchDiag\" xmlns=\"http://www.topografix.com/GPX/1/1\"><trk><trkseg>"+points+"</trkseg></trk></gpx>","FrenchDiag-viagem.gpx")}catch{m.error=error.localizedDescription}}.padding()}}.navigationTitle(trip.started.formatted(date:.abbreviated,time:.shortened))}
}
struct HelpEntry:Codable,Identifiable{var profile:String;var key:String;var text:String;var id:String{profile+key}}
struct HelpView:View {
    @EnvironmentObject var m:Dashboard;@State private var search=""
    var entries:[HelpEntry]{guard let url=Bundle.main.url(forResource:"help",withExtension:"json"),let data=try? Data(contentsOf:url),let a=try? JSONDecoder().decode([HelpEntry].self,from:data) else{return []};return a.filter{$0.profile==m.profile.name && (search.isEmpty || $0.text.localizedCaseInsensitiveContains(search) || $0.key.localizedCaseInsensitiveContains(search))}}
    var body:some View{List{Section("Conexão"){Text("Wi-Fi: conecte o iPhone à rede do adaptador e informe endereço e porta. Permita acesso à rede local.");Text("BLE: permita Bluetooth, selecione o adaptador e confira as características UART. Adaptadores SPP de Bluetooth clássico não funcionam por esta interface.");Text("Use apenas o perfil correspondente à central. Uma resposta inválida ou ausente não é valor zero.")};Section("Ajuda do perfil"){ForEach(entries){e in VStack(alignment:.leading){Text(Catalog.titles[e.key] ?? e.key).font(.headline);Text(e.text).font(.callout)}}}}.navigationTitle("Ajuda técnica").searchable(text:$search)}
}
