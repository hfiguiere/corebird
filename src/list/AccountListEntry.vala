/*  This file is part of corebird.
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


[GtkTemplate (ui = "/org/baedert/corebird/ui/account-list-entry.ui")]
class AccountListEntry : Gtk.ListBoxRow {
  [GtkChild]
  private Gtk.Label screen_name_label;
  [GtkChild]
  private AvatarWidget avatar_image;

  public string screen_name{
    get { return screen_name_label.label; }
  }

  private ulong avatar_change_id;
  public unowned Account account {public get; private set;}

  public AccountListEntry (Account account) {
    this.account = account;
    screen_name_label.label = account.screen_name;
    avatar_image.pixbuf = account.avatar_small;

    avatar_change_id = account.notify["avatar_small"].connect(() => {
      avatar_image.pixbuf = account.avatar_small;
    });
  }

}
