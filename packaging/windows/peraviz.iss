; Windows installer generated from a verified Godot export.
#ifndef AppVersion
  #error "Pass /DAppVersion=<version> from the repository VERSION file."
#endif
#ifndef SourceDir
  #define SourceDir "..\..\dist\Peraviz"
#endif
#ifndef IconFile
  #define IconFile "..\..\assets\icons\app\peraviz_app.ico"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

#define ProjectProgId "Peraviz.Project"
#define ProjectExt ".pvz"

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
WizardStyle=modern dynamic
DisableProgramGroupPage=yes
LicenseFile={#SourceDir}\LICENSE.txt
ChangesAssociations=yes
SetupLogging=yes
SetupIconFile={#IconFile}
UninstallDisplayIcon={app}\Peraviz.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Registry]
; Per-user association. Respect existing handlers and Windows UserChoice.
Root: HKCU; Subkey: "Software\Classes\{#ProjectProgId}"; ValueType: string; ValueName: ""; ValueData: "{cm:ProjectFileType}"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\{#ProjectProgId}\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\resources\peraviz_project.ico,0"
Root: HKCU; Subkey: "Software\Classes\{#ProjectProgId}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\Peraviz.exe"" -- --open-project ""%1"""
Root: HKCU; Subkey: "Software\Classes\{#ProjectExt}\OpenWithProgids"; ValueType: string; ValueName: "{#ProjectProgId}"; ValueData: ""; Flags: uninsdeletevalue
Root: HKCU; Subkey: "Software\Classes\{#ProjectExt}"; ValueType: string; ValueName: ""; ValueData: "{#ProjectProgId}"; Flags: createvalueifdoesntexist; Check: NoExistingProjectHandler
Root: HKCU; Subkey: "Software\Classes\Applications\Peraviz.exe"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\Applications\Peraviz.exe\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\Peraviz.exe"" -- --open-project ""%1"""
Root: HKCU; Subkey: "Software\Classes\Applications\Peraviz.exe\SupportedTypes"; ValueType: string; ValueName: "{#ProjectExt}"; ValueData: ""

[CustomMessages]
english.ProjectFileType=Peraviz Project
spanish.ProjectFileType=Proyecto de Peraviz

[Icons]
Name: "{userprograms}\Peraviz"; Filename: "{app}\Peraviz.exe"; WorkingDir: "{app}"
Name: "{userdesktop}\Peraviz"; Filename: "{app}\Peraviz.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\Peraviz.exe"; Description: "{cm:LaunchProgram,Peraviz}"; Flags: nowait postinstall skipifsilent

[Code]
function NoExistingProjectHandler: Boolean;
var
  Handler: String;
begin
  { HKCR is already the merged Classes root; use its extension directly. }
  Result := not RegQueryStringValue(HKCR, '{#ProjectExt}', '', Handler);
  if not Result then
    Result := Handler = '';
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Handler: String;
begin
  if CurUninstallStep = usUninstall then
    if RegQueryStringValue(HKCU, 'Software\Classes\{#ProjectExt}', '', Handler) then
      if CompareText(Handler, '{#ProjectProgId}') = 0 then
        RegDeleteValue(HKCU, 'Software\Classes\{#ProjectExt}', '');
end;
