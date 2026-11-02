; Windows installer for Liquiflux (Inno Setup 6).
; The release workflow runs:
;   ISCC /DAppVersion=1.0.0 /DAppSource=<flutter Release folder> /DOutputDir=<dist> tools\installer\liquiflux.iss
; It installs for the current user only, so it needs no administrator rights.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef AppSource
  #define AppSource "..\..\app\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

[Setup]
; Keep this AppId forever: it is how Windows knows a new installer is an update.
AppId={{F88427EC-1DFB-4761-8BBF-05C8FA253AB7}
AppName=Liquiflux
AppVersion={#AppVersion}
AppVerName=Liquiflux {#AppVersion}
AppPublisher=Liquiflux
AppPublisherURL=https://github.com/Foehammer1987/Liquiflux
AppSupportURL=https://github.com/Foehammer1987/Liquiflux/issues
DefaultDirName={autopf}\Liquiflux
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=Liquiflux-Setup-x64
SetupIconFile=..\..\app\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Liquiflux.exe
UninstallDisplayName=Liquiflux
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#AppSource}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Liquiflux"; Filename: "{app}\Liquiflux.exe"
Name: "{autodesktop}\Liquiflux"; Filename: "{app}\Liquiflux.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Liquiflux.exe"; Description: "{cm:LaunchProgram,Liquiflux}"; Flags: nowait postinstall skipifsilent
; The in-app updater runs this installer with /SILENT /RELAUNCH=1, and gets Liquiflux back afterwards.
Filename: "{app}\Liquiflux.exe"; Flags: nowait runasoriginaluser; Check: Relaunch

[Code]
function Relaunch: Boolean;
begin
  Result := WizardSilent and (ExpandConstant('{param:RELAUNCH|0}') = '1');
end;
