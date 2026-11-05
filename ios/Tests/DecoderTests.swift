import XCTest
@testable import FrenchDiag

final class DecoderTests:XCTestCase {
    let rpm="017\r0:61FF032A9251\r1:76774D64646465\r2:FFFF60606060FF\r3:FF765F\r>"
    func param(_ label:String="Revs",_ start:Int=6,_ end:Int=10,_ scale:Double=1,_ transform:Int=0)->Param{Param(label:label,description:label,command:"21C18001",unit:"",start:start,end:end,kind:"double",style:"text",scale:scale,limit:6000,offset:0,transform:transform,enums:[:],shift:0,mask:0,frequency:1)}
    func testRecordedMED17Trace()throws {
        let c=try XCTUnwrap(Decoder.canonical(rpm,"21C18001",telemetry:true))
        XCTAssertEqual(c,"1761FF032A925176774D64646465FFFF60606060FFFF765F")
        XCTAssertEqual(try XCTUnwrap(Decoder.decode(param(),c)?.value),810,accuracy:0.001)
        XCTAssertEqual(try XCTUnwrap(Decoder.decode(param("Battery",10,12,0.1),c)?.value),14.6,accuracy:0.001)
    }
    func testFFExceptionCannotIdentifyWrongECU(){for cmd in ["2180","21FE","22D400"]{XCTAssertNil(Decoder.canonical(rpm,cmd,telemetry:true))};XCTAssertNil(Decoder.canonical(rpm,"21C18001"));XCTAssertNil(Decoder.canonical("61C20001","21C18001",telemetry:true));XCTAssertNil(Decoder.canonical("7F2131","21C18001",telemetry:true))}
    func testRecordedTurboOffsets()throws {let raw="026\r0:61FF03229200\r1:595B2D00000031\r2:FF18C060C060C0\r3:60C060FFFFFF2F\r4:005903F252FF0A\r5:00000000\r>";let c=try XCTUnwrap(Decoder.canonical(raw,"21C58001",telemetry:true));XCTAssertEqual(try XCTUnwrap(Decoder.decode(param("TurboInstr",12,16,10),c)?.value),890,accuracy:0.001);XCTAssertEqual(try XCTUnwrap(Decoder.decode(param("TurboPress",56,60,10),c)?.value),890,accuracy:0.001)}
    func testRejectsTruncatedOrOutOfOrderFrames(){XCTAssertEqual(Decoder.messages("017\r0:61FF032A9251\r2:76774D64646465\r3:FFFF60606060FF\r4:FF765F>"),[]);XCTAssertEqual(Decoder.messages("017\r0:61FF032A9251\r1:76774D64646465>"),[])}
    func testSignedValuesAndUnavailable(){XCTAssertNil(Decoder.decode(param("X",6,10),"0461AAFFFF"));XCTAssertEqual(Decoder.decode(param("X",6,10,1,12),"0461AAFFFF")?.value,-1);XCTAssertEqual(Decoder.decode(param("X",6,10,1,22),"0461AA00FF")?.value,-256)}
    func testGenericPIDs(){XCTAssertEqual(Decoder.pid("410C2710>","0C"),2500);XCTAssertEqual(Decoder.pid("41058C>","05"),100);XCTAssertEqual(Decoder.pid("41423778>","42"),14.2);XCTAssertNil(Decoder.pid("NO DATA>","0C"));XCTAssertNil(Decoder.pid("410C27>","0C"))}
    func testTPMSMatchesUserFormula()throws {let p=Catalog.tpms.usable[0];let (payload,id)=try Decoder.tpmsPayload("70004410C0C80000000\r6C70562D61008660000\r>",p.command);XCTAssertEqual(id,"6C7");XCTAssertEqual(payload,"62D6100866");let c=try XCTUnwrap(Decoder.canonical(payload,p.command));XCTAssertEqual(try XCTUnwrap(Decoder.tpms(p,c)?.value),Double(8*255+102)/69,accuracy:1e-9);XCTAssertThrowsError(try Decoder.tpmsPayload("6C70562D61008660000\r6C80562D61008660000>",p.command))}
    func testDTCValidation()throws {let faults=try XCTUnwrap(Decoder.faults("5902FF107A002F>","1902FF",definitions:[:]));XCTAssertEqual(faults.first?.fullCode,"P107A-00");XCTAssertEqual(faults.first?.status,"2F");XCTAssertNil(Decoder.faults("5701107A>","17FF00",definitions:[:]));XCTAssertEqual(Decoder.genericFaults("4301C305>")?.first?.code,"U0305");XCTAssertNil(Decoder.genericFaults("NO DATA>"))}
    func testCatalogAndCommandsPreserved()throws {let catalog=try Catalog();XCTAssertEqual(catalog.profiles.count,82);XCTAssertEqual(catalog.actions.values.reduce(0){$0+$1.count},356);XCTAssertEqual(catalog.profiles.first{$0.name=="MED17_4_2"}?.parameters.count,62);XCTAssertEqual(Catalog.tpms.usable.map{$0.command},["22D610","22D60F","22D612","22D611","22D60E","22D60D","22D60C","22D60B"]);XCTAssertFalse(catalog.faults("MED17_4_2").isEmpty)}
    @MainActor func testReferenceDefaultLayout()async throws {let catalog=try Catalog();let p=try XCTUnwrap(catalog.profiles.first{$0.name=="MED17_4_2"});let config=Dashboard.defaults(p.usable,false);let order=Dashboard.cardRows.flatMap{$0}+Dashboard.pressureBars+Dashboard.textRows+Dashboard.lowerBars+Dashboard.lowerText;XCTAssertEqual(config.selected,order.filter{k in p.usable.contains{$0.label==k}});XCTAssertEqual(config.columns,6);XCTAssertEqual(config.tiles["Revs"]?.style,"bar");XCTAssertEqual(config.tiles["AirFlow"]?.style,"text")}
    func testCSVQuotedCommasAndNewlines(){let rows=CSV.parse("a,b,c\r\n\"x,y\",\"a\"\"b\",\"line1\nline2\"\r\n");XCTAssertEqual(rows,[["a","b","c"],["x,y","a\"b","line1\nline2"]])}
    func testUnavailableQualityAndCRLF(){XCTAssertEqual(Reading(value:nil,display:"—").quality,"unavailable");XCTAssertEqual(CSV.parse("a,b\r\n1,2\r\n"),[["a","b"],["1","2"]])}
    @MainActor func testGenericRotationIsABar()async {let config=Dashboard.defaults(Catalog.generic.usable,false);XCTAssertEqual(config.tiles["0C"]?.style,"bar")}
    func testUnitConversionKeepsGaugeScaleAndValuesConsistent(){
        XCTAssertEqual(Units.convert(3000,unit:"mbar",celsius:true,km:true,pressure:"bar").0,3,accuracy:0.0001)
        XCTAssertEqual(Units.convert(140,unit:"°C",celsius:false,km:true,pressure:"ECU").0,284,accuracy:0.0001)
        XCTAssertEqual(Units.convert(0,unit:"°C",celsius:false,km:true,pressure:"ECU").0,32,accuracy:0.0001)
        XCTAssertEqual(Units.convert(100,unit:"km/h",celsius:true,km:false,pressure:"ECU").0,62.1371,accuracy:0.0001)
    }
    func testStatsIgnoreUnavailableAndStale(){let rows=CSV.parse("parameter,value,unit,quality\nX,10,V,valid\nX,20,V,valid\nX,999,V,stale\nX,,V,unavailable\n");let stat=CSV.stats(rows).first;XCTAssertEqual(stat?.count,2);XCTAssertEqual(stat?.mean,15)}
    @MainActor func testDateBlock()async{let block=Operations.dateBlock(day:31,month:10,year:2026);XCTAssertEqual(block.count,34);XCTAssertTrue(block.hasPrefix("34CF000000090000001F0A1A000000"))}
}

@MainActor final class FixtureLink:ELMCommands {
    var commands:[String]=[];var failTPMS=false
    func command(_ command:String,timeout:Double,recoverTimeout:Bool)async throws->String {
        commands.append(command)
        if command.hasPrefix("AT"){return "OK>"}
        if command=="22D610" {if failTPMS{throw AppError("TPMS fixture error")};return "6C70562D61008660000>"}
        if command=="3E" || command=="3E00"{return "7E00>"}
        return "NO DATA>"
    }
}
final class SessionRoutingTests:XCTestCase {
    @MainActor func testRestoresEngineAfterTPMS()async throws {
        let link=FixtureLink();let session=PSASession(link,try Catalog());session.category=0;session.protocolName="CAN"
        let reading=try await session.tpms(Catalog.tpms.usable[0])
        XCTAssertEqual(try XCTUnwrap(reading?.value),Double(8*255+102)/69,accuracy:1e-9)
        XCTAssertTrue(link.commands.contains("ATSH6AF"));XCTAssertEqual(Array(link.commands.suffix(7)),["ATH0","ATCAF1","ATSH6A8","ATCRA688","ATFCSH6A8","ATFCSD300000","ATFCSM1"])
    }
    @MainActor func testRestoresEngineWhenTPMSFails()async throws {
        let link=FixtureLink();link.failTPMS=true;let session=PSASession(link,try Catalog());session.category=0;session.protocolName="CAN"
        do{_ = try await session.tpms(Catalog.tpms.usable[0]);XCTFail("Expected failure")}catch{}
        XCTAssertEqual(Array(link.commands.suffix(7)),["ATH0","ATCAF1","ATSH6A8","ATCRA688","ATFCSH6A8","ATFCSD300000","ATFCSM1"])
    }
    func testSupportedBitmapsAndLegacyFaults(){XCTAssertTrue(Decoder.supported("410008180000>",base:0)?.contains("0C")==true);XCTAssertFalse(Decoder.supported("410008180000>",base:0)?.contains("42")==true);XCTAssertEqual(Decoder.genericFaults("43C3050000>",can:false)?.first?.code,"U0305")}
}
