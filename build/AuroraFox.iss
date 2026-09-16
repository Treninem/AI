#define MyAppName "AuroraFox"
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0.0"
#endif
#define MyAppPublisher "AuroraFox"
#define MyAppExeName "AuroraFox.exe"

[Setup]
AppId={{8C21F024-53DE-4FA3-A150-78C80829B6BF}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\AuroraFox
DefaultGroupName=AuroraFox
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=release
OutputBaseFilename=AuroraFox_Setup_Windows
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#MyAppExeName}
SetupLogging=yes
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Ярлыки:"; Flags: checkedonce

[Files]
Source: "windows\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\AuroraFox"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\AuroraFox"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Запустить AuroraFox"; Flags: nowait postinstall skipifsilent

[InstallDelete]
; Only known installation-directory leftovers are removed. Godot user:// data lives
; outside {app} and is deliberately never touched by the bridge installer.
Type: files; Name: "{app}\v1.2-marker.txt"
Type: filesandordirs; Name: "{app}.__new_*"
Type: filesandordirs; Name: "{app}.__old_*"

[UninstallDelete]
Type: filesandordirs; Name: "{app}.__new_*"
Type: filesandordirs; Name: "{app}.__old_*"

[Code]
var
  PreviousVersion: String;

function InstalledVersion(): String;
var
  Key: String;
begin
  Key := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{8C21F024-53DE-4FA3-A150-78C80829B6BF}_is1';
  if not RegQueryStringValue(HKCU, Key, 'DisplayVersion', Result) then
    Result := '';
end;

function InitializeSetup(): Boolean;
begin
  PreviousVersion := InstalledVersion();
  Result := True;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  MarkerDir: String;
  MarkerPath: String;
  MarkerText: String;
begin
  if CurStep <> ssPostInstall then
    Exit;
  if PreviousVersion = '' then
    Exit;

  MarkerDir := ExpandConstant('{app}\update');
  ForceDirectories(MarkerDir);
  MarkerPath := MarkerDir + '\bridge_repair.txt';
  MarkerText := 'previous=' + PreviousVersion + #13#10 +
    'current={#MyAppVersion}' + #13#10 +
    'mode=in-place-update-chain-repair' + #13#10;
  SaveStringToFile(MarkerPath, MarkerText, False);
end;
