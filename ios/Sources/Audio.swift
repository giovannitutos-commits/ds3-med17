import Foundation
import AVFoundation
import AudioToolbox
import SwiftUI
import UniformTypeIdentifiers

@MainActor final class SoundPlayer {
    private var player:AVAudioPlayer?
    static let choices=[("builtin:double","Bip duplo"),("builtin:triple","Bip triplo"),("builtin:soft","Bip suave"),("builtin:c4_service","SERVICE C4"),("builtin:ds3_double","Bip DS3"),("system","Som do sistema")]
    func play(_ tone:String,volume:Double=0.7){
        if tone=="system"{AudioServicesPlayAlertSound(1005);return}
        let url:URL?
        if tone.hasPrefix("custom:"){url=Store.url(String(tone.dropFirst(7)))}else{let name="alarm_"+tone.replacingOccurrences(of:"builtin:",with:"");url=Bundle.main.url(forResource:name,withExtension:tone=="builtin:ds3_double" ? "wav":"mp3")}
        guard let url=url else{AudioServicesPlayAlertSound(1005);return}
        do{try AVAudioSession.sharedInstance().setCategory(.playback,options:.mixWithOthers);try AVAudioSession.sharedInstance().setActive(true);player=try AVAudioPlayer(contentsOf:url);player?.volume=Float(min(1,max(0,volume)));player?.prepareToPlay();player?.play()}catch{AudioServicesPlayAlertSound(1005)}
    }
}
struct SoundChoiceView:View {
    @EnvironmentObject var m:Dashboard
    @Binding var tone:String
    @State private var importing=false
    var body:some View{List{ForEach(SoundPlayer.choices,id:\.0){value,title in Button{tone=value;m.save();m.sound.play(value,volume:m.prefs.volume)}label:{HStack{Text(title);Spacer();if tone==value{Image(systemName:"checkmark")}}}};if tone.hasPrefix("custom:"){Text("Som personalizado selecionado")};Button("Importar áudio personalizado"){importing=true};Button("Ouvir selecionado"){m.sound.play(tone,volume:m.prefs.volume)}}.navigationTitle("Som de alerta").fileImporter(isPresented:$importing,allowedContentTypes:[.audio]){result in do{let source=try result.get();let scoped=source.startAccessingSecurityScopedResource();defer{if scoped{source.stopAccessingSecurityScopedResource()}};let data=try Data(contentsOf:source);try require(data.count<=10_000_000,"Escolha um áudio de até 10 MB.");let name="alert-"+UUID().uuidString+"."+source.pathExtension;try data.write(to:Store.url(name),options:.atomic);tone="custom:"+name;m.save();m.sound.play(tone,volume:m.prefs.volume)}catch{m.error=error.localizedDescription}}}
}
