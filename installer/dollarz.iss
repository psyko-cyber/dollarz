; Installer di Dollarz per Windows (Inno Setup 6)
; Compila con:  ISCC.exe installer\dollarz.iss   (dalla cartella del progetto)

#define AppName "Dollarz"
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#define AppExe "Dollarz.exe"
#define AppAumid "Dollarz.App"
#define BuildDir "..\build\windows\x64\runner\Release"
#ifndef VcRedistDir
  #define VcRedistDir "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\14.44.35112\x64\Microsoft.VC143.CRT"
#endif

[Setup]
AppId={{E3A1C6D2-58B4-4F1E-A9C7-2D6B0F83E415}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Dollarz
AppPublisherURL=https://github.com/psyko-cyber/dollarz
AppSupportURL=https://github.com/psyko-cyber/dollarz/issues
AppUpdatesURL=https://github.com/psyko-cyber/dollarz/releases
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=..\dist
OutputBaseFilename=Dollarz-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
WizardStyle=modern
WizardImageFile=wizard.bmp,wizard_250.bmp
WizardSmallImageFile=wizard_small.bmp,wizard_small_250.bmp
Compression=lzma2/max
SolidCompression=yes
CloseApplications=force
RestartApplications=no
UsedUserAreasWarning=no
VersionInfoVersion={#AppVersion}
VersionInfoProductName={#AppName}
VersionInfoDescription=Installazione di Dollarz

[Languages]
Name: "it"; MessagesFile: "compiler:Languages\Italian.isl"

[CustomMessages]
it.TaskDesktop=Crea un collegamento sul desktop
it.TaskAutostart=Avvia Dollarz con Windows (nascosto nell'area di notifica, per promemoria e sincronizzazione)
it.TaskFirewall=Consenti la sincronizzazione Wi-Fi con il telefono (solo reti private)
it.GroupOptions=Opzioni:
it.RunAfter=Avvia Dollarz
it.AskDeleteData=Vuoi eliminare anche i tuoi dati di Dollarz da questo PC (conti, movimenti, investimenti)?%n%nScegli No se pensi di reinstallarlo: ritroverai tutto com'era. I backup in Documenti restano comunque.

[Tasks]
Name: "desktopicon"; Description: "{cm:TaskDesktop}"; GroupDescription: "{cm:GroupOptions}"
Name: "autostart"; Description: "{cm:TaskAutostart}"; GroupDescription: "{cm:GroupOptions}"
Name: "firewall"; Description: "{cm:TaskFirewall}"; GroupDescription: "{cm:GroupOptions}"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; runtime Visual C++ accanto all'exe: Dollarz parte anche sui PC che non lo hanno
Source: "{#VcRedistDir}\msvcp140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#VcRedistDir}\vcruntime140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#VcRedistDir}\vcruntime140_1.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; AppUserModelID: "{#AppAumid}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; AppUserModelID: "{#AppAumid}"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#AppName}"; \
  ValueData: """{app}\{#AppExe}"" --tray"; Tasks: autostart; Flags: uninsdeletevalue

[Run]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""{#AppName}"""; Flags: runhidden; Tasks: firewall
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""{#AppName}"" dir=in action=allow program=""{app}\{#AppExe}"" enable=yes profile=private"; \
  Flags: runhidden; Tasks: firewall; StatusMsg: "Configuro il firewall per la sincronizzazione Wi-Fi..."
Filename: "{app}\{#AppExe}"; Description: "{cm:RunAfter}"; Flags: nowait postinstall skipifsilent runasoriginaluser
; riaperto tramite explorer: parte come utente normale anche se il setup gira come amministratore
Filename: "{win}\explorer.exe"; Parameters: """{app}\{#AppExe}"""; Flags: nowait; Check: RelaunchAfterUpdate

[UninstallRun]
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""{#AppName}"""; Flags: runhidden; RunOnceId: "DelFirewall"
Filename: "{sys}\reg.exe"; Parameters: "delete ""HKCU\Software\Microsoft\Windows\CurrentVersion\Run"" /v {#AppName} /f"; Flags: runhidden; RunOnceId: "DelAutostart"

[Code]
procedure KillDollarz();
var
  Code: Integer;
begin
  { Dollarz può essere aperto nell'area di notifica: lo chiudo prima di copiare i file }
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM {#AppExe}', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Sleep(400);
end;

{ aggiornamento avviato da Dollarz (/RELAUNCH=1): alla fine lo riapro }
function RelaunchAfterUpdate(): Boolean;
begin
  Result := WizardSilent() and (ExpandConstant('{param:RELAUNCH|0}') = '1');
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  KillDollarz();
  Result := '';
end;

function InitializeUninstall(): Boolean;
begin
  KillDollarz();
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataDir: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    DataDir := ExpandConstant('{userappdata}\Dollarz');
    if DirExists(DataDir) and not UninstallSilent() then
      if MsgBox(CustomMessage('AskDeleteData'), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
        DelTree(DataDir, True, True, True);
  end;
end;
