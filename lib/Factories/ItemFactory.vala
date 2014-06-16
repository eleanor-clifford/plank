//
//  Copyright (C) 2011 Robert Dyer
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

using Plank.Items;
using Plank.Services;

namespace Plank.Factories
{
	/**
	 * An item factory.  Creates {@link Items.DockItem}s based on .dockitem files.
	 */
	public class ItemFactory : GLib.Object
	{
		/**
		 * The directory containing .dockitem files.
		 */
		public File launchers_dir;
		
		/**
		 * Creates a new {@link Items.DockElement} from a .dockitem.
		 *
		 * @param file the {@link GLib.File} of .dockitem file to parse
		 * @return the new {@link Items.DockElement} created
		 */
		public virtual DockElement make_element (GLib.File file)
		{
			return default_make_element (file, get_launcher_from_dockitem (file));
		}
		
		/**
		 * Creates a new {@link Items.DockElement} for a launcher parsed from a .dockitem.
		 *
		 * @param file the {@link GLib.File} of .dockitem file that was parsed
		 * @param launcher the launcher name from the .dockitem
		 * @return the new {@link Items.DockElement} created
		 */
		protected DockElement default_make_element (GLib.File file, string launcher)
		{
			if (Factory.main.is_launcher_for_dock (launcher))
				return new PlankDockItem.with_dockitem_file (file);
			if (launcher.has_suffix (".desktop"))
				return new ApplicationDockItem.with_dockitem_file (file);
			return new FileDockItem.with_dockitem_file (file);
		}
		
		/**
		 * Parses a .dockitem to get the launcher from it.
		 *
		 * @param file the {@link GLib.File} of .dockitem to parse
		 * @return the launcher from the .dockitem
		 */
		protected string get_launcher_from_dockitem (GLib.File file)
		{
			try {
				var keyfile = new KeyFile ();
				keyfile.load_from_file (file.get_path (), KeyFileFlags.NONE);
				
				return keyfile.get_string (typeof (Items.DockItemPreferences).name (), "Launcher");
			} catch {
				return "";
			}
		}
			
		/**
		 * Creates a list of Dockitems based on .dockitem files found in the given source_dir.
		 *
		 * @param source_dir the folder where to load .dockitem from
		 * @param ordering a ";;"-separated string to be used to order the loaded DockItems
		 * @return the new List of DockItems
		 */
		public Gee.ArrayList<DockItem> load_items (GLib.File source_dir, string? ordering = null)
		{
			var result = new Gee.ArrayList<DockItem> ();
			
			if (!source_dir.query_exists ()) {
				critical ("Given folder '%s' does not exist.", source_dir.get_path ());
				return result;
			}

			debug ("Loading dock items from '%s'", source_dir.get_path ());
			
			try {
				var enumerator = source_dir.enumerate_children (FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_IS_HIDDEN, 0);
				FileInfo info;
				while ((info = enumerator.next_file ()) != null) {
					if (info.get_is_hidden () || !info.get_name ().has_suffix (".dockitem"))
						continue;
					
					var file = source_dir.get_child (info.get_name ());
					var element = make_element (file);
					var item = (element as DockItem);
					if (item == null)
						continue;
					
					if (!item.is_valid ()) {
						warning ("The launcher '%s' in dock item '%s' does not exist", item.Launcher, file.get_path ());
						continue;
					}
					
					result.add (item);
				}
			} catch (Error e) {
				critical ("Error loading dock items from '%s'. (%s)", source_dir.get_path () ?? "", e.message);
			}
			
			if (ordering == null)
				return result;
			
			var existing_items = new Gee.ArrayList<DockItem> ();
			var new_items = new Gee.ArrayList<DockItem> ();
			
			foreach (var item in result) {
				if (ordering.contains (item.DockItemFilename))
					existing_items.add (item);
				else
					new_items.add (item);
			}
			
			result.clear ();
			
			// add saved dockitems based on their serialized order
			var dockitems = ordering.split (";;");
			foreach (unowned string dockitem in dockitems)
				foreach (var item in existing_items)
					if (dockitem == item.DockItemFilename) {
						result.add (item);
						break;
					}
			
			// add new dockitems
			foreach (var item in new_items)
				result.add (item);
			
			return result;
		}
		
		bool make_default_gnome_items ()
		{
			var browser = AppInfo.get_default_for_type ("text/html", false);
			// FIXME dont know how to get terminal...
			var terminal = AppInfo.get_default_for_uri_scheme ("ssh");
			var calendar = AppInfo.get_default_for_type ("text/calendar", false);
			var media = AppInfo.get_default_for_type ("video/mpeg", false);
			
			if (browser == null && terminal == null && calendar == null && media == null)
				return false;
			
			if (browser != null)
				try {
					make_dock_item (Filename.to_uri (new DesktopAppInfo (browser.get_id ()).get_filename ()));
				} catch (ConvertError e) {
					warning (e.message);
				}
			if (terminal != null)
				try {
					make_dock_item (Filename.to_uri (new DesktopAppInfo (terminal.get_id ()).get_filename ()));
				} catch (ConvertError e) {
					warning (e.message);
				}
			if (calendar != null)
				try {
					make_dock_item (Filename.to_uri (new DesktopAppInfo (calendar.get_id ()).get_filename ()));
				} catch (ConvertError e) {
					warning (e.message);
				}
			if (media != null)
				try {
					make_dock_item (Filename.to_uri (new DesktopAppInfo (media.get_id ()).get_filename ()));
				} catch (ConvertError e) {
					warning (e.message);
				}
			
			return true;
		}
		
		/**
		 * Creates a bunch of default .dockitem's.
		 */
		public void make_default_items ()
		{
			// add plank item!
			make_dock_item (Paths.DataFolder.get_parent ().get_child ("applications").get_child (Factory.main.app_launcher).get_uri ());
			
			if (make_default_gnome_items ())
				return;
			
			// add browser
			if (make_dock_item ("file:///usr/share/applications/chromium-browser.desktop") == null)
				if (make_dock_item ("file:///usr/share/applications/google-chrome.desktop") == null)
					if (make_dock_item ("file:///usr/share/applications/firefox.desktop") == null)
						if (make_dock_item ("file:///usr/share/applications/epiphany.desktop") == null)
							make_dock_item ("file:///usr/share/applications/kde4/konqbrowser.desktop");
			
			// add terminal
			if (make_dock_item ("file:///usr/share/applications/terminator.desktop") == null)
				if (make_dock_item ("file:///usr/share/applications/gnome-terminal.desktop") == null)
					make_dock_item ("file:///usr/share/applications/kde4/konsole.desktop");
			
			// add music player
			if (make_dock_item ("file:///usr/share/applications/exaile.desktop") == null)
				if (make_dock_item ("file:///usr/share/applications/songbird.desktop") == null)
					if (make_dock_item ("file:///usr/share/applications/rhythmbox.desktop") == null)
						if (make_dock_item ("file:///usr/share/applications/banshee-1.desktop") == null)
							make_dock_item ("file:///usr/share/applications/kde4/amarok.desktop");
			
			// add IM client
			if (make_dock_item ("file:///usr/share/applications/pidgin.desktop") == null)
				make_dock_item ("file:///usr/share/applications/empathy.desktop");
		}
		
		/**
		 * Creates a new .dockitem for a uri.
		 *
		 * @param uri the uri or path to create a .dockitem for
		 * @param target_dir the folder where to put the newly created .dockitem (defaults to launchers_dir)
		 * @return the new {@link GLib.File} of the new .dockitem created
		 */
		public GLib.File? make_dock_item (string uri, File? target_dir = null)
		{
			if (target_dir == null)
				target_dir = launchers_dir;
			
			var launcher_file = File.new_for_uri (uri);
			
			if (launcher_file.query_exists ()) {
				var file = new KeyFile ();
				
				file.set_string (typeof (Items.DockItemPreferences).name (), "Launcher", uri);
				
				try {
					// find a unique file name, based on the name of the launcher
					var launcher_base = (launcher_file.get_basename () ?? "unknown").split (".") [0];
					var dockitem = launcher_base + ".dockitem";
					var dockitem_file = target_dir.get_child (dockitem);
					var counter = 1;
					
					while (dockitem_file.query_exists ()) {
						dockitem = "%s-%d.dockitem".printf (launcher_base, counter++);
						dockitem_file = target_dir.get_child (dockitem);
					}
					
					// save the key file
					var stream = new DataOutputStream (dockitem_file.create (FileCreateFlags.NONE));
					stream.put_string (file.to_data ());
					stream.close ();
					
					debug ("Created dock item '%s' for launcher '%s'", dockitem_file.get_path (), uri);
					return dockitem_file;
				} catch { }
			}
			
			return null;
		}
	}
}
