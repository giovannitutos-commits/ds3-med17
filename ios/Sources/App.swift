import SwiftUI

@main struct FrenchDiagApp:App {
    @StateObject private var model=Dashboard()
    @Environment(\.scenePhase) private var phase
    var body:some Scene {WindowGroup {RootView().environmentObject(model).preferredColorScheme(model.prefs.theme=="Sistema" ? nil:model.prefs.theme=="Claro" ? .light:.dark).tint(Color(hex:model.prefs.accent)).onChange(of:phase){_,p in if p == .active{model.enterForeground()}else if p == .background{model.enterBackground()}}}}
}
extension Color {
    init(hex:String){let text=hex.replacingOccurrences(of:"#",with:"");let n=UInt32(text,radix:16) ?? 0xBFF078;self.init(.sRGB,red:Double((n>>16)&255)/255,green:Double((n>>8)&255)/255,blue:Double(n&255)/255,opacity:1)}
    var hexValue:String {let c=UIColor(self);var r:CGFloat=0,g:CGFloat=0,b:CGFloat=0,a:CGFloat=0;c.getRed(&r,green:&g,blue:&b,alpha:&a);return String(format:"#%02X%02X%02X",Int(r*255),Int(g*255),Int(b*255))}
}
struct GlassControl:ViewModifier {
    func body(content:Content)->some View {if #available(iOS 26.0,*) {content.glassEffect(.regular,in:.capsule)}else{content.background(.ultraThinMaterial,in:Capsule())}}
}
struct RootView:View {
    @EnvironmentObject var m:Dashboard
    @State private var settings=false;@State private var tab=0
    var body:some View {
        TabView(selection:$tab){
            shell("FrenchDiag"){PanelView()}.tabItem{Label("Painel",systemImage:"square.grid.2x2.fill")}.tag(0)
            shell("Motor"){MotorView()}.tabItem{Label("Motor",systemImage:"engine.combustion")}.tag(1)
            shell("Falhas"){FaultsView()}.tabItem{Label("Falhas",systemImage:"exclamationmark.triangle")}.tag(2)
            shell("Registros"){HistoryView()}.tabItem{Label("Registros",systemImage:"list.bullet.rectangle")}.tag(3)
            shell("Medidores"){MetersView()}.tabItem{Label("Medidores",systemImage:"gauge.with.dots.needle.67percent")}.tag(4)
        }
        .sheet(isPresented:$settings){NavigationStack{SettingsView().toolbar{ToolbarItem(placement:.confirmationAction){Button("Concluir"){m.save();settings=false}}}}}
        .background(ShareBridge(url:m.share){m.share=nil}.frame(width:0,height:0))
        .alert(m.error == nil ? "Resultado":"FrenchDiag",isPresented:Binding(get:{m.error != nil || m.message != nil},set:{if !$0{m.error=nil;m.message=nil}})){Button("OK"){m.error=nil;m.message=nil}}message:{Text(m.error ?? m.message ?? "")}
        .task{m.autoConnect()}
    }
    func shell<V:View>(_ title:String,@ViewBuilder content:()->V)->some View {
        NavigationStack{content().navigationTitle(title).navigationBarTitleDisplayMode(.inline).toolbar{
            ToolbarItem(placement:.topBarLeading){HStack(spacing:4){Circle().fill(m.connected ? .green:m.connecting ? .orange:.gray).frame(width:7,height:7);Text(m.profile.name).font(.caption2).lineLimit(1)}.accessibilityLabel(m.status)}
            ToolbarItem(placement:.topBarTrailing){Button{settings=true}label:{Image(systemName:"gearshape")}.accessibilityLabel("Configurações")}
        }}
    }
}
struct ShareSheet:UIViewControllerRepresentable {let url:URL;func makeUIViewController(context:Context)->UIActivityViewController{UIActivityViewController(activityItems:[url],applicationActivities:nil)};func updateUIViewController(_ controller:UIActivityViewController,context:Context){}}
struct ShiftStrip:View {
    @EnvironmentObject var m:Dashboard
    var body:some View {VStack(spacing:7){HStack{Text("Shiftlight").font(.caption.bold());Spacer();Text(number(m.prefs.shiftTarget,0)+" rpm").font(.caption)};HStack(spacing:4){ForEach(0..<10){i in let threshold=m.prefs.shiftTarget-m.prefs.shiftLead+Double(i)*m.prefs.shiftLead/9;let lit=m.connected && (m.rpm?.value ?? -1)>=threshold;Capsule().fill((i<6 ? Color(hex:m.prefs.accent):i<8 ? .orange:.red).opacity(lit ? 1:0.15)).frame(height:7)}}}.padding(10).background(.thinMaterial,in:RoundedRectangle(cornerRadius:16)).accessibilityElement(children:.combine)}
}
struct SpanKey:LayoutValueKey {static let defaultValue=1}
struct SpanLayout:Layout {
    var columns:Int;var spacing:CGFloat=4
    func plan(_ proposal:ProposedViewSize,_ subviews:Subviews)->([CGRect],CGSize){
        let width=proposal.width ?? 360;let c=max(1,columns);let cell=max(1,(width-spacing*CGFloat(c-1))/CGFloat(c));var x=0;var y:CGFloat=0;var rowHeight:CGFloat=0;var frames:[CGRect]=[]
        for view in subviews {let span=min(c,max(1,view[SpanKey.self]));if x+span>c{x=0;y+=rowHeight+spacing;rowHeight=0};let w=cell*CGFloat(span)+spacing*CGFloat(span-1);let size=view.sizeThatFits(ProposedViewSize(width:w,height:nil));frames.append(CGRect(x:CGFloat(x)*(cell+spacing),y:y,width:w,height:size.height));rowHeight=max(rowHeight,size.height);x+=span;if x==c{x=0;y+=rowHeight+spacing;rowHeight=0}}
        return(frames,CGSize(width:width,height:y+rowHeight))
    }
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize{plan(proposal,subviews).1}
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()){let frames=plan(ProposedViewSize(width:bounds.width,height:nil),subviews).0;for (i,frame) in frames.enumerated(){subviews[i].place(at:CGPoint(x:bounds.minX+frame.minX,y:bounds.minY+frame.minY),proposal:ProposedViewSize(frame.size))}}
}
struct PanelView:View {
    @EnvironmentObject var m:Dashboard
    @State private var edit=false
    var body:some View {GeometryReader{g in let landscape=g.size.width>g.size.height;let config=m.layout(landscape)
        ScrollView{VStack(spacing:5){
            if m.connecting{ProgressView(m.status).padding()}
            if !m.connected && !m.connecting {HStack{Text(m.status).font(.caption).foregroundStyle(.secondary);Spacer();Button("Conectar"){m.connect()}.buttonStyle(.bordered)}.padding(.vertical,4)}
            if m.prefs.shiftEnabled && config.shiftPosition==0{ShiftStrip()}
            SpanLayout(columns:config.columns,spacing:config.dense ? 3:8){
                ForEach(config.selected,id:\.self){key in if let p=m.params.first(where:{$0.label==key}){let tile=config.tiles[key] ?? Tile();ParameterTile(p:p,tile:tile,units:config.showUnits).layoutValue(key:SpanKey.self,value:tile.style=="card" ? tile.span:config.columns)}}
            }
            if m.prefs.shiftEnabled && config.shiftPosition>0{ShiftStrip()}
            if !m.tpmsNotice.isEmpty{Text(m.tpmsNotice).font(.caption).foregroundStyle(.orange).padding(6)}
        }.padding(.horizontal,8).padding(.bottom,12)}
        .toolbar{ToolbarItem(placement:.topBarTrailing){Button{edit=true}label:{Image(systemName:"slider.horizontal.3")}.accessibilityLabel("Personalizar painel")}}
        .sheet(isPresented:$edit){NavigationStack{PanelEditor(landscape:landscape).toolbar{ToolbarItem(placement:.confirmationAction){Button("Concluir"){edit=false}}}}}
    }}
}
struct ParameterTile:View {
    @EnvironmentObject var m:Dashboard
    let p:Param;let tile:Tile;let units:Bool
    var body:some View {
        let data=m.display(p,m.readings[p.label]);let alarm=m.alarmOn(p)
        Group {
            if tile.style=="card" {VStack(alignment:.leading,spacing:4){Text(p.title).font(.system(size:max(9,tile.fontSize-4))).foregroundStyle(.secondary).lineLimit(2).minimumScaleFactor(0.7);HStack(alignment:.firstTextBaseline,spacing:2){Text(data.0).font(.system(size:tile.fontSize,weight:.semibold,design:.rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5);if units{Text(data.1).font(.system(size:max(8,tile.fontSize-5))).lineLimit(1).minimumScaleFactor(0.5)}}.foregroundStyle(Color(hex:tile.color));extrema.font(.system(size:9)).foregroundStyle(.secondary)}.frame(maxWidth:.infinity,alignment:.leading).padding(6).frame(minHeight:68)}
            else {VStack(spacing:2){HStack{Text(p.title).font(.system(size:tile.fontSize)).lineLimit(2);Spacer(minLength:4);extrema.font(.system(size:9)).foregroundStyle(.secondary);Text(data.0+(units ? " "+data.1:"")).font(.system(size:tile.fontSize,weight:.semibold)).monospacedDigit().foregroundStyle(Color(hex:tile.color)).lineLimit(1).minimumScaleFactor(0.5)};if tile.style=="bar"{GeometryReader{g in let value=m.fresh(p.label)?.value;let ratio=value.map{min(1,max(0,($0-tile.minimum)/max(0.001,tile.maximum-tile.minimum)))} ?? 0;ZStack(alignment:.leading){Capsule().fill(.gray.opacity(0.2));Capsule().fill(Color(hex:tile.color)).frame(width:g.size.width*ratio)}}.frame(height:4)}}.padding(7)}
        }.background(alarm ? Color.red.opacity(0.35):Color(uiColor:.secondarySystemBackground),in:RoundedRectangle(cornerRadius:10)).overlay{RoundedRectangle(cornerRadius:10).stroke(alarm ? .red:Color.primary.opacity(0.08),lineWidth:1)}.contextMenu{NavigationLink("Ajustar parâmetro"){TileEditor(key:p.label,landscape:false)}}
    }
    @ViewBuilder var extrema:some View {if tile.showExtrema,let e=m.extrema[p.label]{Text("↓ \(number(e.0,0))  ↑ \(number(e.1,0))").lineLimit(1).minimumScaleFactor(0.5)}}
}
struct MetersView:View {
    @EnvironmentObject var m:Dashboard
    @State private var edit=false;@State private var fullShift=false
    var body:some View {GeometryReader{g in let wide=g.size.width>g.size.height
        ScrollView{VStack(spacing:12){
            if m.prefs.shiftEnabled{ShiftStrip().onTapGesture{fullShift=true}}
            if wide{HStack(alignment:.center,spacing:8){ForEach(0..<3,id:\.self){i in DialView(meter:m.meters()[i]).frame(width:(g.size.width-40)/3)}}}
            else{DialView(meter:m.meters()[0]).frame(height:min(g.size.width-24,360));HStack(spacing:8){ForEach(1..<3,id:\.self){i in DialView(meter:m.meters()[i])}}.frame(height:(g.size.width-24)/2+35)}
            Button{edit=true}label:{Label("Personalizar",systemImage:"slider.horizontal.3").padding(.horizontal,16).padding(.vertical,10)}.modifier(GlassControl())
            Button("Shiftlight em tela cheia"){fullShift=true}.font(.caption)
        }.padding(12)}
    }.sheet(isPresented:$edit){NavigationStack{MeterEditor().toolbar{ToolbarItem(placement:.confirmationAction){Button("Concluir"){edit=false}}}}}
        .fullScreenCover(isPresented:$fullShift){FullShiftView{fullShift=false}}
    }
}
struct DialView:View {
    @EnvironmentObject var m:Dashboard;let meter:Meter
    func axis(_ raw:Double)->String {
        guard let p=m.params.first(where:{$0.label==meter.key}) else{return number(raw,0)}
        return m.display(p,Reading(value:raw,display:number(raw,0))).0
    }
    var body:some View {
        let p=m.params.first{$0.label==meter.key};let r=m.fresh(meter.key);let value=r?.value;let ratio=value.map{min(1,max(0,($0-meter.minimum)/max(0.001,meter.maximum-meter.minimum)))} ?? 0
        let band=(value.flatMap{v in meter.bands.last(where:{v >= $0.start})?.hex}) ?? meter.bands.first?.hex ?? m.prefs.accent
        VStack(spacing:0){Text(p?.title ?? meter.key).font(.headline).lineLimit(2).minimumScaleFactor(0.6);GeometryReader{g in let side=min(g.size.width,g.size.height);ZStack{
            Circle().trim(from:0,to:0.75).stroke(Color.gray.opacity(0.22),style:StrokeStyle(lineWidth:max(7,side*0.045),lineCap:.round)).rotationEffect(.degrees(135))
            if let v=value{Circle().trim(from:0,to:0.75*ratio).stroke(Color(hex:v>=meter.maximum ? meter.maxHex:band),style:StrokeStyle(lineWidth:max(7,side*0.045),lineCap:.round)).rotationEffect(.degrees(135))}
            VStack(spacing:3){Text(p.map{m.display($0,r).0} ?? "—").font(.system(size:max(24,side*0.19),weight:.semibold,design:.rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5);Text(p.map{m.display($0,r).1} ?? "").font(.system(size:max(12,side*0.065))).foregroundStyle(.secondary)}.padding(side*0.1)
        }.frame(width:side,height:side).frame(maxWidth:.infinity,maxHeight:.infinity)};HStack{Text(axis(meter.minimum));Spacer();Text(axis(meter.maximum))}.font(.caption2).foregroundStyle(.secondary).padding(.horizontal,12)}.padding(8)
    }
}
struct FullShiftView:View {
    @EnvironmentObject var m:Dashboard;let close:()->Void
    @State private var latched=false
    var background:Color{guard let rpm=m.rpm?.value else{return .black};if rpm>=m.prefs.shiftTarget || latched && rpm>=m.prefs.shiftTarget-100{return Color(hex:m.prefs.shiftMaxHex)};return Color(hex:m.prefs.shiftBands.sorted{$0.start<$1.start}.last(where:{rpm >= $0.start})?.hex ?? "#000000")}
    var body:some View {ZStack{background.ignoresSafeArea();VStack{HStack{Spacer();Button("Fechar",action:close).padding().modifier(GlassControl())};Spacer();Text(m.rpm?.value.map{number($0,0)} ?? "—").font(.system(size:110,weight:.bold,design:.rounded)).minimumScaleFactor(0.3).foregroundStyle(.white);Text("rpm").foregroundStyle(.white);ShiftStrip();Spacer()}.padding()}.onAppear{m.fullShiftVisible=true}.onDisappear{m.fullShiftVisible=false}.onChange(of:m.rpm?.value){_,rpm in latched=rpm.map{$0>=m.prefs.shiftTarget || latched && $0>=m.prefs.shiftTarget-100} ?? false}}
}

struct ShareBridge:UIViewControllerRepresentable {
    let url:URL?;let clear:()->Void
    class Coordinator {var showing:URL?}
    func makeCoordinator()->Coordinator{Coordinator()}
    func makeUIViewController(context:Context)->UIViewController{UIViewController()}
    func updateUIViewController(_ controller:UIViewController,context:Context){
        guard let url=url else{context.coordinator.showing=nil;return}
        guard context.coordinator.showing != url else{return}
        context.coordinator.showing=url
        DispatchQueue.main.async {
            guard var top=controller.view.window?.rootViewController else{context.coordinator.showing=nil;return}
            while let presented=top.presentedViewController{top=presented}
            guard !(top is UIActivityViewController) else{return}
            let activity=UIActivityViewController(activityItems:[url],applicationActivities:nil)
            activity.completionWithItemsHandler={_,_,_,_ in DispatchQueue.main.async{clear()}}
            activity.popoverPresentationController?.sourceView=top.view
            activity.popoverPresentationController?.sourceRect=CGRect(x:top.view.bounds.midX,y:top.view.bounds.midY,width:1,height:1)
            top.present(activity,animated:true)
        }
    }
}
