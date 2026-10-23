class SWRCFixExtension extends Object;

/*
 * SWRCFixExtension
 * Base class for optional add-ons that are loaded by SWRCFix at startup.
 * The class names are listed in SWRCFix.ExtensionClasses. Missing packages are silently skipped so the list can contain mods that are not installed.
 * An extension lives as long as the game is running (it is referenced by the SWRCFix instance which is never garbage collected).
 */

function Init(SWRCFix Fix);

// Called by SWRCFix whenever a menu is opened via CallMenuClass, OverlayMenuClass or GotoMenuClass. Return a different class name to replace the menu.
function string RedirectMenuClass(string MenuClassName)
{
	return MenuClassName;
}
