import SwiftUI

struct SettingsView:View {
    @EnvironmentObject var m:Dashboard
    var body:some View {Form {
        Section("Conexão com o carro") {
            Picker("Tipo",selection:$m.prefs.transport){Text("Wi-Fi").tag("Wi-Fi");Text("Bluetooth LE").tag("BLE")}.disabled(m.connected || m.connecting)
            if m.prefs.transport=="Wi-Fi"{TextField("Endereço IP",text:$m.prefs.host).keyboardType(.URL).textInputAutocapitalization(.never);TextField("Porta",text:$m.prefs.port).keyboardType(.numberPad)}
            else{NavigationLink("Selecionar adaptador BLE"){BLEDevicesView()};Text("Bluetooth clássico SPP comum não é compatível com esta versão iOS.").font(.caption).foregroundStyle(.secondary)}
            Picker("Perfil / central",selection:Binding(get:{m.prefs.profile},set:{m.selectProfile($0)})) {Text("Detectar automaticamente").tag("AUTO");ForEach(m.profiles){p in Text(p.name).tag(p.name)}}.disabled(m.connected || m.connecting)
            if m.prefs.profile=="AUTO"{Picker("Categoria",selection:$m.prefs.category){ForEach([0,8,4,1,2],id:\.self){i in Text(moduleName(i)).tag(i)}}}
            Picker("Protocolo",selection:$m.prefs.protocolName){ForEach(["CAN","CAN variável","CAN 250 kbps","KWP rápido","KWP lento"],id:\.self){Text($0)}}.disabled(m.connected || m.connecting)
            Toggle("Conectar ao abrir",isOn:$m.prefs.autoConnect)
            if m.connected || m.connecting{Button("Desconectar",role:.destructive){m.disconnect()}}else{Button("Conectar"){m.save();m.connect()}}
            Text(m.status).font(.caption).foregroundStyle(.secondary)
        }
        Section("Leituras") {
            Toggle("ECU e TPMS juntos",isOn:$m.prefs.tpms).onChange(of:m.prefs.tpms){_,_ in m.updateTPMS()}
            Text("TPMS usa os oito PIDs do Android, endereço CAN 6AF, com restauração do endereço do motor entre consultas.").font(.caption)
            Stepper("Intervalo: \(number(m.prefs.interval)) s",value:$m.prefs.interval,in:0.2...10,step:0.2)
            Toggle("Monitorar falhas",isOn:$m.prefs.dtcMonitor)
            Toggle("Som de novas falhas",isOn:$m.prefs.dtcSound);Toggle("Vibração de novas falhas",isOn:$m.prefs.dtcVibration)
            NavigationLink("Som de falhas"){SoundChoiceView(tone:$m.prefs.dtcTone)}
            Slider(value:$m.prefs.volume,in:0...1){Text("Volume dos alertas")}
            Stepper("Consulta DTC: \(Int(m.prefs.dtcInterval)) s",value:$m.prefs.dtcInterval,in:15...300,step:15)
            Toggle("Gravar sessão CSV",isOn:$m.prefs.recording)
        }
        Section("Personalização") {
            NavigationLink("Painel em retrato"){PanelEditor(landscape:false)}
            NavigationLink("Painel em paisagem"){PanelEditor(landscape:true)}
            NavigationLink("Medidores, escalas e cores"){MeterEditor()}
            NavigationLink("Shiftlight"){ShiftSettingsView()}
            Picker("Tema",selection:$m.prefs.theme){ForEach(["Escuro","Claro","Sistema"],id:\.self){Text($0)}}
            ColorPicker("Cor de destaque",selection:Binding(get:{Color(hex:m.prefs.accent)},set:{m.prefs.accent=$0.hexValue}))
            Text("Liquid Glass nativo no iOS 26 ou posterior. Em versões anteriores, os controles usam o material translúcido do sistema.").font(.caption).foregroundStyle(.secondary)
        }
        Section("Unidades") {
            Toggle("Temperatura em Celsius",isOn:$m.prefs.celsius);Toggle("Distância em quilômetros",isOn:$m.prefs.km)
            Picker("Pressão",selection:$m.prefs.pressure){ForEach(["ECU","bar","mbar","kPa","MPa","Pa","psi"],id:\.self){Text($0)}}
        }
        Section("Oficina e viagens") {TextField("Nome / identificação do veículo",text:$m.prefs.vehicle);Stepper("Correção de combustível: \(number(m.prefs.fuelFactor,2))",value:$m.prefs.fuelFactor,in:0.5...2,step:0.05);NavigationLink("Capturas e relatórios PDF"){WorkshopView()};NavigationLink("Viagens"){TripsView()};NavigationLink("Ajuda técnica"){HelpView()};NavigationLink("Registro de comunicação"){CommunicationView()}}
        Section("Versão de teste") {Text("FrenchDiag iOS · migração do Android Teste 12");Text("Sem bloqueio por código e sem prazo de validade do aplicativo. A instalação com conta Apple gratuita precisa de renovação da assinatura pelo Sideloadly.").font(.caption);Text("Comunicação com veículo ainda depende de validação física no adaptador. CarPlay não está incluído: requer autorização específica da Apple.").font(.caption).foregroundStyle(.secondary)}
    }.navigationTitle("Configurações").onDisappear{m.save()}}
}
func moduleName(_ cat:Int)->String {switch cat{case 0:return "Motor";case 8:return "Câmbio";case 4:return "Direção";case 1:return "Climatização";case 2:return "Display";case 9:return "Pneus TPMS";default:return "Central \(cat)"}}

struct BLEDevicesView:View {
    @EnvironmentObject var m:Dashboard
    var body:some View {List{Section{Text(m.elm.bluetoothState).font(.caption);Button("Buscar adaptadores"){m.elm.scan()};ForEach(m.elm.devices){d in Button{m.prefs.bleID=d.id.uuidString;m.save()}label:{HStack{VStack(alignment:.leading){Text(d.name);Text(d.id.uuidString).font(.caption2).foregroundStyle(.secondary)};Spacer();if m.prefs.bleID==d.id.uuidString{Image(systemName:"checkmark")}}}}};Section("UUIDs opcionais do fabricante"){TextField("Característica de escrita",text:$m.prefs.bleWrite).textInputAutocapitalization(.characters).autocorrectionDisabled();TextField("Característica de notificação",text:$m.prefs.bleNotify).textInputAutocapitalization(.characters).autocorrectionDisabled();Text("Deixe vazio para detectar um par de características de escrita e notificação no mesmo serviço UART. Confira o manual do adaptador se a detecção não funcionar.").font(.caption)}}.navigationTitle("Bluetooth LE").onAppear{m.elm.scan()}.onDisappear{m.elm.stopScan();m.save()}}
}
struct ShiftSettingsView:View {
    @EnvironmentObject var m:Dashboard
    var body:some View{Form{Toggle("Ativar shiftlight",isOn:$m.prefs.shiftEnabled);Stepper("Troca: \(Int(m.prefs.shiftTarget)) rpm",value:$m.prefs.shiftTarget,in:1000...12000,step:100);Stepper("Antecipação: \(Int(m.prefs.shiftLead)) rpm",value:$m.prefs.shiftLead,in:100...3000,step:100);Toggle("Som na troca",isOn:$m.prefs.shiftSound);NavigationLink("Som do shiftlight"){SoundChoiceView(tone:$m.prefs.shiftTone)};Toggle("Vibração na troca",isOn:$m.prefs.shiftVibration);NavigationLink("Cores da tela cheia"){FullShiftColorEditor()};Text("Usa sempre a rotação real e recente do motor. Cada medidor tem suas próprias faixas de cor em Personalizar medidores.").font(.caption)}.navigationTitle("Shiftlight").onDisappear{m.save()}}
}
struct PanelEditor:View {
    @EnvironmentObject var m:Dashboard;let landscape:Bool
    @State private var search="";@State private var reset=false
    var config:Binding<LayoutConfig>{Binding(get:{m.layout(landscape)},set:{m.setLayout($0,landscape)})}
    var body:some View {List {
        Section("Organização") {Stepper("Colunas: \(config.wrappedValue.columns)",value:config.columns,in:2...12);Toggle("Compacto",isOn:config.dense);Toggle("Exibir unidades",isOn:config.showUnits);Toggle("Rótulos curtos",isOn:config.shortLabels);Picker("Shiftlight",selection:config.shiftPosition){Text("No início").tag(0);Text("No fim").tag(1)};Button("Redefinir para o padrão",role:.destructive){reset=true}}
        Section("Parâmetros selecionados · arraste para ordenar") {
            ForEach(config.wrappedValue.selected,id:\.self){key in if let p=m.params.first(where:{$0.label==key}){NavigationLink{TileEditor(key:key,landscape:landscape)}label:{VStack(alignment:.leading){Text(p.title);Text(p.unit+" · "+(config.wrappedValue.tiles[key]?.style ?? "card")).font(.caption).foregroundStyle(.secondary)}}}}
                .onMove{from,to in var c=config.wrappedValue;c.selected.move(fromOffsets:from,toOffset:to);config.wrappedValue=c}
                .onDelete{indices in var c=config.wrappedValue;c.selected.remove(atOffsets:indices);config.wrappedValue=c}
        }
        Section("Adicionar leituras") {ForEach(m.params.filter{!config.wrappedValue.selected.contains($0.label) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search))}){p in Button{var c=config.wrappedValue;c.selected.append(p.label);if c.tiles[p.label]==nil{c.tiles[p.label]=Tile(maximum:Double(max(1,p.limit)))};config.wrappedValue=c}label:{Label(p.title,systemImage:"plus.circle")}}}
    }.navigationTitle(landscape ? "Painel · paisagem":"Painel · retrato").searchable(text:$search,prompt:"Buscar parâmetros").toolbar{EditButton()}.confirmationDialog("Restaurar seleção, ordem, tamanhos e formatos? Alarmes serão preservados.",isPresented:$reset){Button("Redefinir para o padrão",role:.destructive){let old=config.wrappedValue;var c=Dashboard.defaults(m.params,landscape);for (key,value) in old.tiles{if c.tiles[key] != nil{c.tiles[key]?.alarm=value.alarm}};config.wrappedValue=c}}}
}
struct TileEditor:View {
    @EnvironmentObject var m:Dashboard;let key:String;let landscape:Bool
    var tile:Binding<Tile>{Binding(get:{m.layout(landscape).tiles[key] ?? Tile()},set:{v in var c=m.layout(landscape);c.tiles[key]=v;m.setLayout(c,landscape)})}
    var body:some View {Form {
        Section("Exibição"){Picker("Formato",selection:tile.style){Text("Cartão").tag("card");Text("Barra").tag("bar");Text("Texto").tag("text")};Stepper("Largura: \(tile.wrappedValue.span)",value:tile.span,in:1...m.layout(landscape).columns);Stepper("Texto: \(Int(tile.wrappedValue.fontSize))",value:tile.fontSize,in:10...40,step:1);Toggle("Mínimo e máximo",isOn:tile.showExtrema);ColorPicker("Cor",selection:Binding(get:{Color(hex:tile.wrappedValue.color)},set:{tile.wrappedValue.color=$0.hexValue}));TextField("Escala mínima",value:tile.minimum,format:.number).keyboardType(.numbersAndPunctuation);TextField("Escala máxima",value:tile.maximum,format:.number).keyboardType(.numbersAndPunctuation)}
        Section("Alarme · unidades originais da ECU"){Toggle("Ativar",isOn:tile.alarm.enabled);TextField("Limite",value:tile.alarm.limit,format:.number).keyboardType(.numbersAndPunctuation);Toggle("Abaixo do limite",isOn:tile.alarm.below);TextField("Histerese",value:tile.alarm.hysteresis,format:.number).keyboardType(.decimalPad);Toggle("Som",isOn:tile.alarm.sound);NavigationLink("Selecionar som"){SoundChoiceView(tone:tile.alarm.tone)};Toggle("Vibração",isOn:tile.alarm.vibration);Stepper("Repetir: \(Int(tile.wrappedValue.alarm.repeatSeconds)) s",value:tile.alarm.repeatSeconds,in:3...60,step:1);Text("Os alarmes usam o valor original da ECU e leituras recentes. A conversão de unidades é apenas visual.").font(.caption)}
        Button("Redefinir este parâmetro",role:.destructive){let alarm=tile.wrappedValue.alarm;let def=Dashboard.defaults(m.params,landscape).tiles[key] ?? Tile();tile.wrappedValue=def;tile.wrappedValue.alarm=alarm}
    }.navigationTitle(m.params.first{$0.label==key}?.title ?? key)}
}
struct MeterEditor:View {
    @EnvironmentObject var m:Dashboard
    var body:some View {Form{ForEach(0..<3,id:\.self){i in Section(i==0 ? "Medidor principal":"Medidor \(i+1)"){NavigationLink{MeterSlotEditor(index:i)}label:{Text(m.params.first{$0.label==m.meters()[i].key}?.title ?? m.meters()[i].key)}}};Button("Restaurar medidores padrão",role:.destructive){m.prefs.meters.removeValue(forKey:m.profile.name);m.save()};Text("Em paisagem, os três medidores ficam lado a lado. Cada posição permite parâmetro, escala e faixas de cor independentes.").font(.caption)}.navigationTitle("Personalizar medidores")}
}
struct MeterSlotEditor:View {
    @EnvironmentObject var m:Dashboard;let index:Int
    var meter:Binding<Meter>{Binding(get:{m.meters()[index]},set:{v in var a=m.meters();a[index]=v;m.prefs.meters[m.profile.name]=a;m.save()})}
    var body:some View {Form {
        Picker("Parâmetro",selection:meter.key){ForEach(m.params.filter{$0.numeric}){p in Text(p.title+" · "+p.unit).tag(p.label)}}
        TextField("Mínimo",value:meter.minimum,format:.number).keyboardType(.numbersAndPunctuation);TextField("Máximo",value:meter.maximum,format:.number).keyboardType(.numbersAndPunctuation)
        Section("Faixas de cor · unidades originais da ECU") {
            ForEach(Array(meter.wrappedValue.bands.indices),id:\.self){i in HStack{TextField("A partir de",value:Binding(get:{meter.wrappedValue.bands[i].start},set:{meter.wrappedValue.bands[i].start=$0}),format:.number).keyboardType(.numbersAndPunctuation);ColorPicker("Cor",selection:Binding(get:{Color(hex:meter.wrappedValue.bands[i].hex)},set:{meter.wrappedValue.bands[i].hex=$0.hexValue})).labelsHidden()}}.onDelete{indices in var v=meter.wrappedValue;if v.bands.count>indices.count{v.bands.remove(atOffsets:indices);meter.wrappedValue=v}}
            if meter.wrappedValue.bands.count<8{Button("Adicionar faixa"){var v=meter.wrappedValue;v.bands.append(ColorBand(start:(v.bands.last?.start ?? v.minimum)+(v.maximum-v.minimum)/4,hex:"#FFAA00"));meter.wrappedValue=v}}
            ColorPicker("Cor no máximo",selection:Binding(get:{Color(hex:meter.wrappedValue.maxHex)},set:{meter.wrappedValue.maxHex=$0.hexValue}))
        }
        if meter.wrappedValue.maximum<=meter.wrappedValue.minimum{Text("O máximo deve ser maior que o mínimo.").foregroundStyle(.red)}
    }.navigationTitle("Medidor \(index+1)").onDisappear{var v=meter.wrappedValue;v.bands.sort{$0.start<$1.start};if v.maximum<=v.minimum{v.maximum=v.minimum+1};if !v.bands.isEmpty{v.bands[0].start=v.minimum};meter.wrappedValue=v}}
}

struct FullShiftColorEditor:View {
    @EnvironmentObject var m:Dashboard
    var body:some View {Form{ForEach(Array(m.prefs.shiftBands.indices),id:\.self){i in HStack{TextField("A partir de rpm",value:$m.prefs.shiftBands[i].start,format:.number).keyboardType(.numberPad);ColorPicker("Cor",selection:Binding(get:{Color(hex:m.prefs.shiftBands[i].hex)},set:{m.prefs.shiftBands[i].hex=$0.hexValue})).labelsHidden()}}.onDelete{indices in if m.prefs.shiftBands.count>indices.count{m.prefs.shiftBands.remove(atOffsets:indices)}};if m.prefs.shiftBands.count<8{Button("Adicionar faixa"){m.prefs.shiftBands.append(ColorBand(start:max(0,m.prefs.shiftTarget-1000),hex:"#EF6C00"))}};ColorPicker("Cor na troca",selection:Binding(get:{Color(hex:m.prefs.shiftMaxHex)},set:{m.prefs.shiftMaxHex=$0.hexValue}))}.navigationTitle("Cores do shiftlight").onDisappear{m.prefs.shiftBands.sort{$0.start<$1.start};if !m.prefs.shiftBands.isEmpty{m.prefs.shiftBands[0].start=0};m.save()}}
}
