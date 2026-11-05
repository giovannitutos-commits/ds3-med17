import XCTest
final class SmokeTests:XCTestCase {
    func testNavigationAndScreenshots(){
        let app=XCUIApplication();app.launchArguments=["-ui-testing"];app.launch()
        for label in ["Painel","Motor","Falhas","Registros","Medidores"] {
            let button=app.tabBars.buttons[label];XCTAssertTrue(button.waitForExistence(timeout:10));button.tap()
            let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name=label;attachment.lifetime = .keepAlways;add(attachment)
        }
        let settings=app.buttons["Configurações"];XCTAssertTrue(settings.waitForExistence(timeout:5));settings.tap();XCTAssertTrue(app.navigationBars["Configurações"].waitForExistence(timeout:5))
    }
}
