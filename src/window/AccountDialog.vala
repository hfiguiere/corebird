/*  This file is part of corebird, a Gtk+ linux Twitter client.
 *  Copyright (C) 2013 Timm Bäder
 *
 *  corebird is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  corebird is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with corebird.  If not, see <http://www.gnu.org/licenses/>.
 */
[GtkTemplate (ui = "/org/baedert/corebird/ui/account-dialog.ui")]
class AccountDialog : Gtk.Dialog {
  private static const int RESPONSE_CLOSE  = 0;
  private static const int RESPONSE_DELETE = 1;
  private static const int RESPONSE_CANCEL = 2;
  private static const string PAGE_NORMAL = "normal";
  private static const string PAGE_DELETE = "delete";
  [GtkChild]
  private Gtk.Label screen_name_label;
  [GtkChild]
  private Gtk.Entry name_entry;
  [GtkChild]
  private AvatarBannerWidget avatar_banner_widget;
  [GtkChild]
  private Gtk.Stack delete_stack;
  [GtkChild]
  private Gtk.Button delete_button;
  [GtkChild]
  private Gtk.Switch autostart_switch;
  [GtkChild]
  private Gtk.Entry website_entry;
  [GtkChild]
  private Gtk.TextView description_text_view;

  private unowned Account account;
  private string old_user_name;
  private string old_description;
  private string old_website;



  public AccountDialog (Account account) {
    this.account = account;
    screen_name_label.label = account.screen_name;
    name_entry.text = account.name;
    avatar_banner_widget.set_account (account);
    website_entry.text = account.website ?? "";
    old_user_name = account.name;
    old_website = account.website ?? "";
    old_description = account.description ?? "";
    if (account.description != null) {
      description_text_view.get_buffer ().set_text (account.description);
    }


    autostart_switch.freeze_notify ();
    string[] startup_accounts = Settings.get ().get_strv ("startup-accounts");
    foreach (string acc in startup_accounts) {
      if (acc == this.account.screen_name) {
        autostart_switch.active = true;
        break;
      }
    }
    autostart_switch.thaw_notify ();
    this.set_default_size (350, 450);
  }

  public override void response (int response_id) {
    if (response_id == RESPONSE_CLOSE) {
      save_data ();
      this.destroy ();
    } else if (response_id == RESPONSE_DELETE) {
      delete_stack.visible_child_name = PAGE_DELETE;
      delete_button.hide ();
    } else if (response_id == RESPONSE_CANCEL) {
      this.destroy ();
    }
  }

  private void save_data () {
    bool needs_save = (old_user_name != name_entry.text) ||
                      (old_description != description_text_view.buffer.text) ||
                      (old_website != website_entry.text);

    if (!needs_save)
      return;

    debug ("Saving data...");

    var call = account.proxy.new_call ();
    call.set_function ("1.1/account/update_profile.json");
    call.set_method ("POST");
    call.add_param ("url", website_entry.text);
    call.add_param ("name", name_entry.text);
    call.add_param ("description", description_text_view.buffer.text);
    call.invoke_async.begin (null, (obj, res) => {
      try {
        call.invoke_async.end (res);
      } catch (GLib.Error e) {
        warning (e.message);
        Utils.show_error_object (call.get_payload (), "Could not update profile",
                                 GLib.Log.LINE, GLib.Log.FILE);
      }
    });

    /* Update local user data */
    account.name = name_entry.text;
    account.description = description_text_view.buffer.text;
    account.website = website_entry.text;
  }

  [GtkCallback]
  private void delete_confirm_button_clicked_cb () {
    /*
       - Close open window of that account
       - Remove the account from the db, disk, etc.
       - Remove the account from the app menu
       - If this would close the last opened window,
         set the account of that window to NULL
     */
    var acc_menu = (GLib.Menu) Corebird.account_menu;
    int64 acc_id = account.id;
    FileUtils.remove (Dirs.config (@"accounts/$(acc_id).db"));
    FileUtils.remove (Dirs.config (@"accounts/$(acc_id).png"));
    FileUtils.remove (Dirs.config (@"accounts/$(acc_id)_small.png"));
    Corebird.db.exec (@"DELETE FROM `accounts` WHERE `id`='$(acc_id)';");

    /* Remove account from startup accounts, if it's in there */
    string[] startup_accounts = Settings.get ().get_strv ("startup-accounts");
    for (int i = 0; i < startup_accounts.length; i++)
      if (startup_accounts[i] == account.screen_name) {
        string[] sa_new = new string[startup_accounts.length - 1];
        for (int x = 0; x < i; i++)
          sa_new[x] = startup_accounts[x];
        for (int x = i+1; x < startup_accounts.length; x++)
          sa_new[x] = startup_accounts[x];
        Settings.get ().set_strv ("startup-accounts", sa_new);
      }

    /* Remove account from account app menu */
    for (int i = 0; i < acc_menu.get_n_items (); i++){
      Variant item_name = acc_menu.get_item_attribute_value (i,
                                       "label", VariantType.STRING);
      if (item_name.get_string () == "@"+account.screen_name) {
        acc_menu.remove (i);
        break;
      }
    }


    Corebird cb = (Corebird) GLib.Application.get_default ();

    /* Handle windows, i.e. if this MainWindow is the last open one,
       we want to use it to show the "new account" UI, otherwise we
       just close it. */
    unowned GLib.List<Gtk.Window> windows = cb.get_windows ();
    Gtk.Window? account_window = null;
    int n_main_windows = 0;
    foreach (Gtk.Window win in windows) {
      if (win is MainWindow) {
        n_main_windows ++;
        if (((MainWindow)win).account.id == this.account.id) {
          account_window = win;
        }
      }
    }
    debug ("Open main windows: %d", n_main_windows);

    if (account_window != null) {
      if (n_main_windows > 1)
        account_window.destroy ();
      else
        ((MainWindow)account_window).change_account (null);
    }


    /* Remove the account from the global list of accounts */
    Account acc_to_remove = Account.query_account (account.screen_name);
    cb.account_removed (acc_to_remove);
    Account.remove_account (account.screen_name);


    /* Close this dialog */
    this.destroy ();
  }

  [GtkCallback]
  private void delete_cancel_button_clicked_cb () {
    delete_stack.visible_child_name = PAGE_NORMAL;
    delete_button.show ();
  }

  [GtkCallback]
  private void autostart_switch_activate_cb () {
    bool active = autostart_switch.active;
    string[] startup_accounts = Settings.get ().get_strv ("startup-accounts");
    if (active) {
      foreach (string acc in startup_accounts) {
        if (acc == this.account.screen_name) {
          return;
        }
      }

      string[] new_startup_accounts = new string[startup_accounts.length + 1];
      int i = 0;
      foreach (string s in startup_accounts) {
        new_startup_accounts[i] = s;
      }
      new_startup_accounts[new_startup_accounts.length - 1] = this.account.screen_name;
      Settings.get ().set_strv ("startup-accounts", new_startup_accounts);
    } else {
      string[] new_startup_accounts = new string[startup_accounts.length - 1];
      int i = 0;
      foreach (string acc in startup_accounts) {
        if (acc != this.account.screen_name) {
          new_startup_accounts[i] = acc;
          i ++;
        }
      }
      Settings.get ().set_strv ("startup-accounts", new_startup_accounts);
    }
  }
}
