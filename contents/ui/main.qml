/*
 * Copyright 2021 Martin Krcma <martin.krcma1@gmail.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as
 * published by the Free Software Foundation; either version 2 of
 * the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http: //www.gnu.org/licenses/>.
 *
 */
import QtQuick 2.15
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as Controls
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: main
    preferredRepresentation: compactRepresentation
    Layout.preferredWidth: 800 * Kirigami.Units.devicePixelRatio
    Layout.minimumWidth: 400 * Kirigami.Units.devicePixelRatio
    Layout.preferredHeight: 300 * Kirigami.Units.devicePixelRatio

    // Battery state management - moved to main item
    property var batteryList: []
    property bool batteriesDiscovered: false
    property double currentPower: 0.0
    property bool debug: false  // Set to true when debugging
    
    // Moving average and battery status
    property var powerHistory: []
    property int powerHistorySize: 30  // 60 seconds at 2s intervals
    property double averagePower: 0.0
    property double batteryPercentage: -1.0  // -1 means unavailable
    property string timeRemaining: "--:--"
    property bool previousBatteryState: false  // Track previous charging state

    // Power management data source - moved to main item
    property QtObject pmSource: P5Support.DataSource {
        id: pmSource
        engine: "powermanagement"
        connectedSources: ["Battery", "AC Adapter"]
        interval: 1000
    }

    property bool isOnBattery: pmSource.data["AC Adapter"] &&
                               pmSource.data["AC Adapter"]["Plugged in"] === false

    // DataEngine for executing shell commands
    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: {
            var stdout = data["stdout"]

            if (sourceName.indexOf("battery_discover") !== -1) {
                handleBatteryDiscovery(stdout)
            } else if (sourceName.indexOf("battery_power") !== -1) {
                handleBatteryPower(stdout)
            }

            disconnectSource(sourceName)
        }

        function exec(cmd) {
            connectSource(cmd)
        }
    }

    // Update timer - moved to main item
    Timer {
        id: updateTimer
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: false  // Don't trigger immediately
        onTriggered: {
            main.updatePowerUsage()
        }
    }

    // Discover batteries on startup
    Component.onCompleted: {
        discoverBatteries()
    }

    function discoverBatteries() {
        var cmd = "battery_discover|"
        for (var i = 0; i < 4; i++) {
            cmd += "if [ -f /sys/class/power_supply/BAT" + i + "/present ]; then "
            cmd += "present=$(cat /sys/class/power_supply/BAT" + i + "/present 2>/dev/null); "
            cmd += "if [ \"$present\" = \"1\" ]; then "
            cmd += "echo -n 'BAT" + i + "'; "
            cmd += "if [ -f /sys/class/power_supply/BAT" + i + "/power_now ]; then "
            cmd += "echo ':power_now'; "
            cmd += "else echo ':current_voltage'; fi; "
            cmd += "fi; fi; "
        }
        executable.exec(cmd)
    }

    function handleBatteryDiscovery(stdout) {
        batteryList = []
        var lines = stdout.trim().split('\n')

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (line === "") continue

            var parts = line.split(':')
            if (parts.length === 2) {
                var battery = {
                    name: parts[0],
                    url: "/sys/class/power_supply/" + parts[0],
                    powerNowExists: parts[1] === "power_now"
                }
                batteryList.push(battery)
            }
        }

        batteriesDiscovered = true
        if (debug) console.log("Batteries discovered:", batteryList.length)

        // Initialize battery state
        previousBatteryState = isOnBattery

        // Start updating power after discovery
        if (batteryList.length > 0) {
            updatePowerUsage()
            updateTimer.start()
        }
    }

    function updatePowerUsage() {
        if (!batteriesDiscovered || batteryList.length === 0) {
            currentPower = 0.0
            return
        }

        var cmd = "battery_power|"
        for (var i = 0; i < batteryList.length; i++) {
            var battery = batteryList[i]
            if (battery.powerNowExists) {
                cmd += "power=$(cat " + battery.url + "/power_now 2>/dev/null || echo '0'); "
                cmd += "energy_now=$(cat " + battery.url + "/energy_now 2>/dev/null || echo '0'); "
                cmd += "energy_full=$(cat " + battery.url + "/energy_full 2>/dev/null || echo '0'); "
                cmd += "echo \"" + battery.name + ":$power:$energy_now:$energy_full\"; "
            } else {
                // Use command substitution directly in echo
                cmd += "echo \"" + battery.name + ":$(cat " + battery.url + "/current_now 2>/dev/null || echo '0'):$(cat " + battery.url + "/voltage_now 2>/dev/null || echo '0'):$(cat " + battery.url + "/charge_now 2>/dev/null || echo '0'):$(cat " + battery.url + "/charge_full 2>/dev/null || echo '0')\"; "
            }
        }
        executable.exec(cmd)
    }

    function safeParseInt(value) {
        if (!value || value === "" || value === "0") {
            return 0
        }
        var parsed = parseInt(value)
        return isNaN(parsed) ? 0 : parsed
    }

    function handleBatteryPower(stdout) {
        var totalPower = 0.0
        var totalEnergyNow = 0.0
        var totalEnergyFull = 0.0
        var lines = stdout.trim().split('\n')

        if (debug) console.log("Battery power output:", stdout)

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (line === "") continue

            var parts = line.split(':')
            if (parts.length === 4) {
                // power_now format: name:power:energy_now:energy_full
                if (debug) console.log("power=", parts[1], "energy_now=", parts[2], "energy_full=", parts[3])
                var powerValue = safeParseInt(parts[1])
                var energyNow = safeParseInt(parts[2])
                var energyFull = safeParseInt(parts[3])
                
                if (powerValue > 0) {
                    var power = powerValue / 1000000.0
                    totalPower += Math.round(power * 10) / 10
                }
                
                totalEnergyNow += energyNow
                totalEnergyFull += energyFull
                
            } else if (parts.length === 5) {
                // current:voltage format: name:current:voltage:charge_now:charge_full
                if (debug) console.log("current='", parts[1], "' voltage='", parts[2], "' charge_now='", parts[3], "' charge_full='", parts[4], "'")
                var current = safeParseInt(parts[1])
                var voltage = safeParseInt(parts[2])
                var chargeNow = safeParseInt(parts[3])
                var chargeFull = safeParseInt(parts[4])
                
                if (current > 0 && voltage > 0) {
                    var power = (current * voltage) / 1000000000000.0
                    totalPower += Math.round(power * 10) / 10
                }
                
                // Convert charge to energy: charge (µAh) * voltage (µV) / 1000000 = energy (µWh)
                if (voltage > 0) {
                    totalEnergyNow += (chargeNow * voltage) / 1000000
                    totalEnergyFull += (chargeFull * voltage) / 1000000
                }
            }
        }

        if (debug) console.log("Total power calculated:", totalPower)
        currentPower = totalPower
        
        // Detect state change (charging/discharging) and reset history
        if (isOnBattery !== previousBatteryState) {
            if (debug) console.log("Battery state changed, resetting power history")
            powerHistory = []
            previousBatteryState = isOnBattery
        }
        
        // Update moving average
        powerHistory.push(totalPower)
        if (powerHistory.length > powerHistorySize) {
            powerHistory.shift()
        }
        
        // Calculate average power (using actual number of samples recorded)
        var sum = 0.0
        for (var j = 0; j < powerHistory.length; j++) {
            sum += powerHistory[j]
        }
        averagePower = powerHistory.length > 0 ? sum / powerHistory.length : 0.0
        
        // Calculate battery percentage
        if (totalEnergyFull > 0) {
            batteryPercentage = (totalEnergyNow / totalEnergyFull) * 100.0
        } else {
            batteryPercentage = -1.0
        }
        
        // Calculate time remaining
        calculateTimeRemaining(totalEnergyNow, totalEnergyFull)
    }
    
    function calculateTimeRemaining(energyNow, energyFull) {
        // If power is too low, don't calculate time
        if (averagePower < 0.5) {
            timeRemaining = "--:--"
            return
        }
        
        var hours = 0.0
        
        if (isOnBattery) {
            // Discharging: time to 0%
            if (energyNow > 0 && averagePower > 0) {
                // energyNow is in µWh, averagePower is in W
                hours = (energyNow / 1000000.0) / averagePower
            } else {
                timeRemaining = "--:--"
                return
            }
        } else {
            // Charging: time to 100%
            var energyRemaining = energyFull - energyNow
            if (energyRemaining > 0 && averagePower > 0) {
                hours = (energyRemaining / 1000000.0) / averagePower
            } else {
                timeRemaining = "--:--"
                return
            }
        }
        
        // Format time
        if (hours < 0 || hours > 99) {
            timeRemaining = "--:--"
        } else {
            var h = Math.floor(hours)
            var m = Math.floor((hours - h) * 60)
            timeRemaining = h + ":" + (m < 10 ? "0" : "") + m
        }
    }

    // compact representation
    compactRepresentation: Item {
        Layout.minimumWidth: 90
        Layout.preferredWidth: 110
        Layout.fillHeight: true
        
        PlasmaComponents3.Label {
            id: label1
            anchors {
                fill: parent
                margins: Math.round(parent.width * 0.01)
            }
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter

            text: {
                var powerStr = isNaN(main.currentPower) ? "--" : main.currentPower.toFixed(1)
                var avgStr = isNaN(main.averagePower) ? "--" : main.averagePower.toFixed(1)
                var percentStr = (main.batteryPercentage < 0) ? "--" : Math.round(main.batteryPercentage).toString()
                return powerStr + "W (" + avgStr + ")\n" + percentStr + "% | " + main.timeRemaining
            }
            color: main.isOnBattery ? "#FFFFFF" : "#80FF80"

            font.pixelSize: parent.height * 0.45
            fontSizeMode: Text.FixedSize
            font.bold: false
            lineHeight: 0.75
            lineHeightMode: Text.ProportionalHeight

            MouseArea {
                id: mouseArea
                anchors.fill: parent
                onClicked: plasmoid.expanded = !plasmoid.expanded
                hoverEnabled: true

                Controls.ToolTip {
                    visible: parent.containsMouse
                    text: {
                        var powerStr = isNaN(main.currentPower) ? "--" : main.currentPower.toFixed(1)
                        var percentStr = (main.batteryPercentage < 0) ? "--" : main.batteryPercentage.toFixed(1)
                        var avgStr = isNaN(main.averagePower) ? "--" : main.averagePower.toFixed(1)
                        return "Energy monitor\n" + powerStr + "W (avg: " + avgStr + "W) | " + percentStr + "% | " + main.timeRemaining
                    }
                }
            }
        }
    }

    // full representation - simple placeholder
    fullRepresentation: Item {
        Layout.preferredWidth: 400 * Kirigami.Units.devicePixelRatio
        Layout.preferredHeight: 300 * Kirigami.Units.devicePixelRatio

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10

            PlasmaComponents3.Label {
                text: "Energy Monitor"
                font.bold: true
                font.pointSize: 14
            }

            PlasmaComponents3.Label {
                text: "Current Power Usage:"
                font.pointSize: 12
            }

            PlasmaComponents3.Label {
                text: {
                    if (isNaN(main.currentPower)) {
                        return "-- W"
                    }
                    return main.currentPower.toFixed(1) + " W"
                }
                font.pointSize: 24
                font.bold: true
                color: main.isOnBattery ? "#FFFFFF" : "#80FF80"
            }

            PlasmaComponents3.Label {
                text: "Average Power (60s):"
                font.pointSize: 12
            }

            PlasmaComponents3.Label {
                text: {
                    if (isNaN(main.averagePower)) {
                        return "-- W"
                    }
                    return main.averagePower.toFixed(1) + " W"
                }
                font.pointSize: 16
                font.bold: true
            }

            PlasmaComponents3.Label {
                text: "Battery Level:"
                font.pointSize: 12
            }

            PlasmaComponents3.Label {
                text: {
                    if (main.batteryPercentage < 0) {
                        return "--%"
                    }
                    return main.batteryPercentage.toFixed(1) + "%"
                }
                font.pointSize: 16
                font.bold: true
            }

            PlasmaComponents3.Label {
                text: "Time Remaining:"
                font.pointSize: 12
            }

            PlasmaComponents3.Label {
                text: {
                    var status = main.isOnBattery ? "to 0%" : "to 100%"
                    return main.timeRemaining + " " + status
                }
                font.pointSize: 16
                font.bold: true
            }

            PlasmaComponents3.Label {
                text: main.isOnBattery ? "On Battery" : "Plugged In"
                font.pointSize: 12
            }

            PlasmaComponents3.Label {
                text: "Batteries detected: " + main.batteryList.length
                font.pointSize: 10
            }

            Item {
                Layout.fillHeight: true
            }
        }
    }
}
