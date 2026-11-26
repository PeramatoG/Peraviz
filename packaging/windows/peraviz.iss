; Windows installer generated from a verified Godot export.
#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef SourceDir
  #define SourceDir "dist\Peraviz"
#endif
#ifndef OutputDir
  #define OutputDir "dist"
#endif

[Setup]
AppId={{EFA28DAB-73B8-5E82-B798-9947A32D7B16}
AppName=Peraviz
AppVersion={#AppVersion}
AppVerName=Peraviz {#AppVersion}
AppPublisher=Peraviz contributors
AppPublisherURL=https://github.com/PeramatoG/Peraviz
AppSupportURL=https://github.com/PeramatoG/Peraviz/issues
AppUpdatesURL=https://github.com/PeramatoG/Peraviz/releases
DefaultDirName={localappdata}\Programs\Peraviz
DefaultGroupName=Peraviz
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
OutputBaseFilename=Peraviz-Setup-{#AppVersion}-windows-x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
UninstallDisplayIcon={app}\Peraviz.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\Peraviz"; Filename: "{app}\Peraviz.exe"; WorkingDir: "{app}"
Name: "{userdesktop}\Peraviz"; Filename: "{app}\Peraviz.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\Peraviz.exe"; Description: "{cm:LaunchProgram,Peraviz}"; Flags: nowait postinstall skipifsilent
