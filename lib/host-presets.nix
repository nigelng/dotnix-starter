# machineType presets for networking and power settings.
{ lib }:

{
  laptop = {
    knownNetworkServices = [
      "Wi-Fi"
      "Thunderbolt Bridge"
    ];
    restartAfterPowerFailure = false;
  };

  macmini = {
    knownNetworkServices = [
      "Wi-Fi"
      "USB 10/100/1000 LAN"
      "Thunderbolt Ethernet Slot 1"
      "Thunderbolt Bridge"
    ];
    restartAfterPowerFailure = true;
  };
}
