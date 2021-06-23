# ReverbG2ConfigManager
An AutoHotKey script that can be used to maintain separate SteamVR configurations for the Reverb G2 and a Native Steam VR HMD in a MixedVR environment

Created by reddit user /u/TeTitanAtoll

This script mangages the ability to keep portions of the SteamVR configuration
separate for the Reverb G2 and other HMDs.  It currently supports the following
features:

  * Switches config files between G2 and non-G2 versions based on the G2 HMD
    being added/removed from the system (i.e. powered on/off)
      - Allows settings such as Force Bounds, etc. to be completely eliminated
         when using an HMD other than G2.
      - Allows Room Bounds and space offsets for G2 and non-G2 HMDs to be kept
        seperate. These settings are maintained between sessions for each
        respective HMD.
      - Allows super-sampling and reprojection settings to be maintained
        separately for G2 and other HMDs
      - Provides fading pop-up notifications to the user when configurations
        are auto switched between G2 configs and Default configs
  * Auto manages settings for "Force Steam VR Bounds" for the G2 configs based
    on whether G2 controllers are detected or not.
      - When using G2 controllers instead of Index controllers, disables force
        bounds while maintaining all other G2 settings.
      - If Index controllers are used (G2 controllers not detected), enables
        force bounds for proper mixed VR support.
      - Can be enabled/disabled via ENABLE_FORCEBOUNDS_AUTOCONFIG setting.
  * Manages auto-killing of Room Setup Wizard when force bounds is enabled
      - A fading popup when the HMD is first detected gives the option to
        disabled auto-kill for any given session, in case room setup is
        actually required/desired.
      - When the G2 HMD is not present, background monitoring is disabled,
        so no cycles are spent looking for Room Setup to start when it isn't 
        expected to start.

 The functionality in this script is entirely event driven and relies on
 detecting when the G2 HMD are powered on or off.  As such, in order for
 this script to work properly, it must be running in the background before
 the G2 is powered on, as well as when the the G2 is powered off.  It is
 recommended that this ahk script be compiled into an executable and run at boot.
 As the script is primarily event driven, it will be idle except when hardware
 is added or removed from the system.
 
 The script also needs to have time to make changes to the config files before
 SteamVR launches.  Once the G2 is powered on, you will want to wait for the
 WMR portal to start and the "config change" pop-ups from this script to be
 dispalyed before launching Steam VR (which should be only 10 to 15 seconds
 after the G2 becomes active).  At this point, Steam VR may be launched
 either from the desktop, or by powering on an Index controller.  It is also
 recommended that you exit SteamVR before powering down the G2 (thought the 
 scripts should work regardless)

 I have attempted to make all of the hardware detection strings generic enough
 that they should work on any system without needing to be modified.  However,
 it is possible some adjustments may be needed for your specfic installation. 
 For example, if you have installed SteamVR anywhere other than the default
 location, you may need to update some of the paths in the configuration 
 section below to match your own setup.  Likewise, the ini file for OVR
 Advanced Settings is stored in your user directory, and that path will 
 need to be updated (below) to reflect the user folder on your VR PC.

 Faded Popup functionality leverages code from: 
    https://autohotkey.com/board/topic/21510-toaster-popups/

 Hardware monitoring support leverages code from:
    https://autohotkey.com/board/topic/70334-detecting-hardware-changes-for-example-new-usb-devices/
