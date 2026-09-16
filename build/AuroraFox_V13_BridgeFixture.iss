#define MyAppName "AuroraFox"
#define MyAppVersion "1.3.0.0"
#define MyAppPublisher "AuroraFox"

[Setup]
AppId={{8C21F024-53DE-4FA3-A150-78C80829B6BF}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\AuroraFox
PrivilegesRequired=lowest
OutputDir=release
OutputBaseFilename=AuroraFox_V13_BridgeFixture
Compression=lzma2/max
SolidCompression=yes
Uninstallable=yes

[Files]
Source: "bridge_fixture\AuroraFox.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "bridge_fixture\v1.3-marker.txt"; DestDir: "{app}"; Flags: ignoreversion
