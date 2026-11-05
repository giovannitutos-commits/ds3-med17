import Foundation

enum Units {
    static func convert(_ raw:Double,unit:String,celsius:Bool,km:Bool,pressure:String)->(Double,String){
        var value=raw;var displayUnit=unit
        if ["°C","℃"].contains(unit) && !celsius{value=value*1.8+32;displayUnit="°F"}
        if unit=="km/h" && !km{value*=0.621371;displayUnit="mph"}
        let factors:[String:Double]=["Pa":1,"kPa":1000,"MPa":1_000_000,"bar":100_000,"mbar":100,"psi":6894.757]
        if pressure != "ECU",let from=factors[unit],let to=factors[pressure]{value=raw*from/to;displayUnit=pressure}
        return(value,displayUnit)
    }
}
