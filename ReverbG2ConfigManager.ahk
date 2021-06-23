; Created by reddit user /u/TeTitanAtoll
;
; This script mangages the ability to keep portions of the SteamVR configuration
; separate for the Reverb G2 and other HMDs.  It currently supports the following
; features:
;
;  * Switches config files between G2 and non-G2 versions based on the G2 HMD
;    being added/removed from the system (i.e. powered on/off)
;      - Allows settings such as Force Bounds, etc. to be completely eliminated
;         when using an HMD other than G2.
;      - Allows Room Bounds and space offsets for G2 and non-G2 HMDs to be kept
;        seperate. These settings are maintained between sessions for each
;        respective HMD.
;      - Allows super-sampling and reprojection settings to be maintained
;        separately for G2 and other HMDs
;      - Provides fading pop-up notifications to the user when configurations
;        are auto switched between G2 configs and Default configs
;  * Auto manages settings for "Force Steam VR Bounds" for the G2 configs based
;    on whether G2 controllers are detected or not.
;      - When using G2 controllers instead of Index controllers, disables force
;        bounds while maintaining all other G2 settings.
;      - If Index controllers are used (G2 controllers not detected), enables
;        force bounds for proper mixed VR support.
;      - Can be enabled/disabled via ENABLE_FORCEBOUNDS_AUTOCONFIG setting.
;  * Manages auto-killing of Room Setup Wizard when force bounds is enabled
;      - A fading popup when the HMD is first detected gives the option to
;        disabled auto-kill for any given session, in case room setup is
;        actually required/desired.
;      - When the G2 HMD is not present, background monitoring is disabled,
;        so no cycles are spent looking for Room Setup to start when it isn't 
;        expected to start.
;
; The functionality in this script is entirely event driven and relies on
; detecting when the G2 HMD are powered on or off.  As such, in order for
; this script to work properly, it must be running in the background before
; the G2 is powered on, as well as when the the G2 is powered off.  It is
; recommended that this ahk script be compiled into an executable and run at boot.
; As the script is primarily event driven, it will be idle except when hardware
; is added or removed from the system.
; 
; The script also needs to have time to make changes to the config files before
; SteamVR launches.  Once the G2 is powered on, you will want to wait for the
; WMR portal to start and the "config change" pop-ups from this script to be
; dispalyed before launching Steam VR (which should be only 10 to 15 seconds
; after the G2 becomes active).  At this point, Steam VR may be launched
; either from the desktop, or by powering on an Index controller.  It is also
; recommended that you exit SteamVR before powering down the G2 (thought the 
; scripts should work regardless)
;
; I have attempted to make all of the hardware detection strings generic enough
; that they should work on any system without needing to be modified.  However,
; it is possible some adjustments may be needed for your specfic installation. 
; For example, if you have installed SteamVR anywhere other than the default
; location, you may need to update some of the paths in the configuration 
; section below to match your own setup.  Likewise, the ini file for OVR
; Advanced Settings is stored in your user directory, and that path will 
; need to be updated (below) to reflect the user folder on your VR PC.
;
; Faded Popup functionality leverages code from: 
;    https://autohotkey.com/board/topic/21510-toaster-popups/
;
; Hardware monitoring support leverages code from:
;    https://autohotkey.com/board/topic/70334-detecting-hardware-changes-for-example-new-usb-devices/
;
;

#SingleInstance force

;-------------------------- BEGIN CONFIGURABLE SETTINGS --------------------------------------------------

global ENABLE_ROOMSETUP_AUTOKILL = 1
global ENABLE_FORCEBOUNDS_AUTOCONFIG = 1
global INITIAL_FORCE_BOUNDS_CHECK_TIMER = -5000 ; in millseconds, must be negative for one-shot timer
global G2_HMD_REGEX := "VID_045E&PID_0659.*HolographicDisplay"
global G2_CONTROLLER_REGEX := "VID_045E&PID_066A"
global STEAMVR_HMDMODEL_G2 := """HMDModel"" : ""HP Reverb Virtual Reality Headset G20"""
global STEAMVR_FORCE_BOUNDS := """enableDriverBoundsImport"" : false"
Global STEAMVR_PROCESS := "steamvr_room_setup.exe"
global VR_SETTINGS_FILE := "C:\Program Files (x86)\Steam\config\steamvr.vrsettings"
global CONFIG_FILE_ARRAY := [VR_SETTINGS_FILE, "C:\Program Files (x86)\Steam\config\chaperone_info.vrchap", "C:\Users\bryce\AppData\Roaming\AdvancedSettings-Team\OVR Advanced Settings.ini"]
;--------------------------- END CONFIGURABLE SETTINGS -----------------------------------------------------

; Strings below are the full hardware IDs from TeTitanAtoll's system.  Used to derive regular expressions above.
;G2_R_CONTROLLER_ID := "\\?\HID#VID_045E&PID_066A&MI_01#9&1fb0dfed&0&0000#{4d1e55b2-f16f-11cf-88cb-001111000030}"
;G2_L_CONTROLLER_ID := "\\?\HID#VID_045E&PID_066A&MI_01#9&15b2803b&0&0000#{4d1e55b2-f16f-11cf-88cb-001111000030}"
;G2_HMD_FULL_ID := "\\?\USB#VID_045E&PID_0659&MI_04#7&149e593&0&0004#{deac60ab-66e2-42a4-ad9b-557ee33ae2d5}\HolographicDisplay"

global DBT_DEVICEREMOVECOMPLETE   := 0x8004
global DBT_DEVICEARRIVAL          := 0x8000
global DBT_DEVTYP_DEVICEINTERFACE := 0x00000005
DEVICE_NOTIFY_WINDOW_HANDLE := 0x0 
DBT_DEVTYP_DEVICEINTERFACE  := 5
DEVICE_NOTIFY_ALL_INTERFACE_CLASSES := 0x00000004

hWnd := GetAHKWin()

VarSetCapacity(DevHdr, 32, 0) ; Actual size is 29, but the function will fail with less than 32
NumPut(32, DevHdr, 0, "UInt") ; sizeof(_DEV_BROADCAST_DEVICEINTERFACE) (should be 29)
NumPut(DBT_DEVTYP_DEVICEINTERFACE, DevHdr, 4, "UInt") ; DBT_DEVTYP_DEVICEINTERFACE
Addr := &DevHdr
Flags := DEVICE_NOTIFY_WINDOW_HANDLE|DEVICE_NOTIFY_ALL_INTERFACE_CLASSES
Msg = %Msg%RegisterDeviceNotification(%hWnd%, %Addr%, %Flags%)`r`n
Ret := DllCall("RegisterDeviceNotification", "UInt", hWnd, "UInt", Addr, "UInt", Flags)
if (!Ret)
{
   ErrMsg := FormatMessageFromSystem(A_LastError)
   Msg = %Msg%Ret %Ret% ErrorLevel %ErrorLevel% %A_LastError% %ErrMsg%
   Toast(Msg)
}

global controller_count := 0
global killtimer_aborted := 0

; Monitor for WM_DEVICECHANGE 
OnMessage(0x219, "MsgMonitor")

MsgMonitor(wParam, lParam, msg)
{
   
   if ((wParam == DBT_DEVICEREMOVECOMPLETE) || (wParam == DBT_DEVICEARRIVAL))
   {
 	; lParam points to a DEV_BROADCAST_HDR structure
      dbch_size       := NumGet(lParam+0, 0, "UInt")
      dbch_devicetype := NumGet(lParam+0, 4, "UInt")
      if (dbch_devicetype == DBT_DEVTYP_DEVICEINTERFACE)
      {
         ; lParam points to a DEV_BROADCAST_DEVICEINTERFACE structure
         dbcc_name := GetString(lParam+28)

		 if(RegExMatch(dbcc_name, G2_HMD_REGEX))
		 {
			if (wParam == DBT_DEVICEARRIVAL)
            {	
			   
			  ; Lots of activity while the HMD comes up...sleep a bit to let all the drivers settle.
			
  			  Toast("G2 HMD Added", "Switching to Reverb G2 Steam VR configuration", 3500)
              Toast_Wait()
		      ; Never backup a default configuration if the last HMD was the G2.  This implies
			  ; the G2 was used when the script was not running, and the state of the current file
			  ; is unknown.  Instead, save it off for reference, but it won't ever be restored automatically.
			  if (IsStringInFile(STEAMVR_HMDMODEL_G2, VR_SETTINGS_FILE))
			     BackupExt = Default_Saved
			  else 
			     BackupExt = Default

			  RestoreExt = G2
			  
			  for idx, configfile in CONFIG_FILE_ARRAY
			  {
			     BackupRestoreFile(configfile, BackupExt, RestoreExt)
              }
			  
			  killtimer_aborted = 0
			  
			  SetTimer, InitialForceBoundsCheck, %INITIAL_FORCE_BOUNDS_CHECK_TIMER%
			    
			}
            else if (wParam == DBT_DEVICEREMOVECOMPLETE)
			{
			  Toast("G2 HMD Removed", "Switching to Default Steam VR configuration", 3500)

		      ; Never backup a G2 configuration if the last HMD was not the G2.  Not entirely sure
			  ; Instead, save it off for reference, but it won't ever be restored automatically.
			  if (!IsStringInFile(STEAMVR_HMDMODEL_G2, VR_SETTINGS_FILE))
			     BackupExt = G2_Saved
			  else 
			     BackupExt = G2
			 
			  RestoreExt = Default
			  
			  for idx, configfile in CONFIG_FILE_ARRAY
			  {
			     BackupRestoreFile(configfile, BackupExt, RestoreExt)
              }
			  controller_count = 0;
			  EnableForceBounds()
			}				
		}
		else if ((ENABLE_FORCEBOUNDS_AUTOCONFIG) && RegExMatch(dbcc_name, G2_CONTROLLER_REGEX)) 
		{
		
		    if (wParam == DBT_DEVICEARRIVAL)
			{
			   controller_count += 1
			   if(controller_count == 1)
			   {
			      Toast("G2 Controller Added", "Disabling Force Bounds",3500)
				  DisableForceBounds()
			   }				  
            }
			else if (wParam == DBT_DEVICEREMOVECOMPLETE)
            {			
			   controller_count -= 1
			   if (controller_count < 0) controller_count = 0
			   
			   if (controller_count == 0)
			   {
			      Toast("G2 Controllers Removed", "Re-enabling Force Bounds", 3500)
				  EnableForceBounds()
			   }
			}
		}
		
      }
   }
}

InitialForceBoundsCheck()
{
   CheckForceBounds(1)
}

CheckForceBounds(Toast=0)
{
   ; Check to see if force bounds is on, and if so, begin monitoring to auto-close Room Setup 
   ; Otherwise, stop any ongoing monitoring.			
   if ((ENABLE_ROOMSETUP_AUTOKILL) && (IsStringInFile(STEAMVR_FORCE_BOUNDS, VR_SETTINGS_FILE)))
   {
      if (Toast)
	  {
	     Toast("Force Bounds is Enabled", "Click to disable Room Setup auto-kill", 5000, "AbortLabel")
	     Toast_Wait()
      }
	  SetTimer, KillRoomSetup, 1000
   }
}


EnableForceBounds()
{
   CollisionBoundsStartStr := """collisionBounds"" : {"  
   CollisionBoundsEndStr := "[\r\n]\s*},"
   ForceBoundsEndStr := ",`r`n      ""enableDriverBoundsImport"" : false`r`n   },"

   FileRead, FileStr, %VR_SETTINGS_FILE%
   if(InStr(FileStr, STEAMVR_FORCE_BOUNDS))
   {
      ; Force bounds already enabled
	  return
   }
   
   FoundPos := InStr(FileStr, CollisionBoundsStartStr)
   NewStr := RegExReplace(FileStr, CollisionBoundsEndStr, ForceBoundsEndStr, Count, 1, FoundPos)

   if (Count)
   {
	  FileDelete, %VR_SETTINGS_FILE%.tmp
	  FileAppend, %NewStr%, %VR_SETTINGS_FILE%.tmp
      FileMove, %VR_SETTINGS_FILE%.tmp, %VR_SETTINGS_FILE%, 1
	  CheckForceBounds()
   }
}

DisableForceBounds()
{
   ForceBoundsRegex := "m),[\r\n]\s*""enableDriverBoundsImport"" : false"

   FileRead, FileStr, %VR_SETTINGS_FILE%
   NewStr := RegExReplace(FileStr, ForceBoundsRegex,"", Count, 1)

   if (Count)
   {
      ; Shouldn't be there, but delete just in case
	  FileDelete, %VR_SETTINGS_FILE%.tmp
	  FileAppend, %NewStr%, %VR_SETTINGS_FILE%.tmp
      FileMove, %VR_SETTINGS_FILE%.tmp, %VR_SETTINGS_FILE%, 1
      CheckForceBounds()
   }
}
		
KillRoomSetup()
{
   if (killtimer_aborted)
   {
      SetTimer, KillRoomSetup, Delete
      return
   }
	  
   Process, Exist, %STEAMVR_PROCESS% ; check to see if process is running
   If (ErrorLevel) ; If it is running
   {
	   Process, Close, %STEAMVR_PROCESS%    
   }
}

IsStringInFile(SearchString, FilePath)
{
    Loop, Read, %FilePath%
    {
        if (InStr(A_LoopReadLine, SearchString))
            return 1
    }
    return 0
}

; Make a backup of FilePath using BackupToExt, and then overwrite
; FilePath using the file with RestoreFromExt.
BackupRestoreFile(FilePath, BackupToExt, RestoreFromExt)
{

   BackupPath = %FilePath%.%BackupToExt%
   RestorePath = %FilePath%.%RestoreFromExt%

   FileCopy, %FilePath%, %BackupPath%, 1
   IfExist, %RestorePath%
      FileCopy, %RestorePath%, %FilePath%, 1
}

FormatMessageFromSystem(ErrorCode)
{
   VarSetCapacity(Buffer, 2000, 32 )
   DllCall("FormatMessage"
      , "UInt", 0x1000      ; FORMAT_MESSAGE_FROM_SYSTEM
      , "UInt", 0
      , "UInt", ErrorCode
      , "UInt", 0x800 ;LANG_SYSTEM_DEFAULT (LANG_USER_DEFAULT=0x400)
      , "UInt", &Buffer
      , "UInt", 500
      , "UInt", 0)
      
   ; Strip any newlines
   Buffer := RegExReplace(Buffer, "\r\n", " ")

   Return Buffer
}

GetHex(Num)
{
    Old := A_FormatInteger 
    SetFormat, IntegerFast, Hex
    Num += 0 
    Num .= ""
    SetFormat, IntegerFast, %Old%
    return Num
}

GetAHKWin()
{
    Gui +LastFound  
    hwnd := WinExist() 
    return hwnd
}

GetString(Addr)
{
   OutString := ""
   VarSetCapacity(OutString, 1024, 0)
   Loop {
      Char := *Addr+0
      ;MsgBox, %Char%
      if (Char == 0)
         break
      OutString .= Chr(Char)
      Addr +=2
   }
   return OutString
}

Toast(TP_Title="", TP_Message="", TP_Lifespan=0, TP_CallBack="", TP_Speed="10", TP_TitleSize="9", TP_FontSize="8", TP_FontColor="0x00437e", TP_BGColor="0xE3F2FE",  TP_FontFace="")
{
   Global TP_GuiEvent
   Static TP_CallBackTarget, TP_GUI_ID
   TP_CallBackTarget := TP_CallBack
   
   DetectHiddenWindows, On
   SysGet, Workspace, MonitorWorkArea
   Gui, 89:Destroy
   Gui, 89:-Caption +ToolWindow +LastFound +AlwaysOnTop +Border
   Gui, 89:Color, %TP_BGColor%
   If (TP_Title) {
      TP_TitleSize := TP_FontSize + 1
      Gui, 89:Font, s%TP_TitleSize% c%TP_FontColor% w700, %TP_FontFace%
      Gui, 89:Add, Text, r1 gToast_Fade x5 y5, %TP_Title%
      Gui, 89:Margin, 0, 0
   }
   Gui, 89:Font, s%TP_FontSize% c%TP_FontColor% w400, %TP_FontFace%
   Gui, 89:Add, Text, gToast_Fade x5, %TP_Message%
   IfNotEqual, TP_Title,, Gui, 89:Margin, 5, 5
   Gui, 89:Show, Hide, TP_Gui
   TP_GUI_ID := WinExist("TP_Gui")
   WinGetPos, , , GUIWidth, GUIHeight, ahk_id %TP_GUI_ID%
   NewX := WorkSpaceRight-GUIWidth-5
   NewY := WorkspaceBottom-GUIHeight-5
   Gui, 89:Show, Hide x%NewX% y%NewY%
   WinGetPos,,,Width
   GuiControl, 89:Move, Static1, % "w" . GuiWidth-7
   GuiControl, 89:Move, Static2, % "w" . GuiWidth-7
   DllCall("AnimateWindow","UInt", TP_GUI_ID,"Int", GuiHeight*TP_Speed,"UInt", 0x40008)
   If (TP_Lifespan)
      SetTimer, Toast_Fade, -%TP_Lifespan%
Return TP_GUI_ID

Toast_Fade:
   If (A_GuiEvent and TP_CallBackTarget)
   {
      TP_GuiEvent := A_GuiEvent
      If IsLabel(TP_CallBackTarget)
         Gosub, %TP_CallBackTarget%
      else
      {
         If InStr(TP_CallBackTarget, "(")
         Msgbox Cannot yet callback a function
         else
         Msgbox, not a valid CallBack
      }
   }
   DllCall("AnimateWindow","UInt", TP_GUI_ID,"Int", 600,"UInt", 0x90000)
   Gui, 89:Destroy
Return
}

Toast_Wait(TP_GUI_ID="") {
  If not (TP_GUI_ID)
   TP_GUI_ID := WinExist("TP_Gui")
  WinWaitClose, ahk_id %TP_GUI_ID%
}

return

AbortLabel:
   killtimer_aborted = 1
   Toast("Room Setup Auto Kill" , "Disabled for this session", 3500)

