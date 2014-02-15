
/*
 * Copyright (C) 2014 Jonathan Hudson <jh+mwptools@daria.co.uk>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 */
using Gtk;
using Clutter;
using Champlain;
using GtkChamplain;

public class Craft : GLib.Object
{
    private Champlain.View view;
    private Champlain.Label icon;
    private Champlain.MarkerLayer layer;
    private bool dorotate;

    private static string[] icons =
    {
        "QuadX.png",
        "Tri.png",
        "QuadP.png",
        "QuadX.png",
        "Bi.png",
        "QuadX.png",
        "Y6.png",
        "Hex6P.png",
        "Flying_Wing.png",
        "Y4.png",
        "Hex6X.png",
        "OctoX8.png",
        "OctoFlatP.png",
        "OctoFlatX.png",
        "Airplane.png",
        "Heli.png",
        "Heli.png",
        "V-Tail4.png",
        "Hex6P.png"
    };

    public Craft(Champlain.View _view, uint id, bool _dorotate = true)
    {
        view = _view;
        dorotate = _dorotate;

        if (id == icons.length)
        {
            id = 0;
        }

        var iconfile = MWPUtils.find_conf_file(icons[id], "pixmaps");
        try {
            icon = new Champlain.Label.from_file (iconfile);
        } catch (GLib.Error e) {
            GLib.warning ("ICON: %s", e.message);
            Clutter.Color colour = {0xff, 0xb7, 0x22, 0xff};
            Clutter.Color black = { 0,0,0, 0xff };
            icon = new Champlain.Label.with_text ("⌖","Sans 24",null,null);
            icon.set_alignment (Pango.Alignment.RIGHT);
            icon.set_color (colour);
            icon.set_text_color(black);
        }
        layer = new Champlain.MarkerLayer();
        view.add_layer (layer);
        Clutter.Point p = Clutter.Point.alloc();
        p.init(0.5f,0.5f);
        icon.set_property("pivot-point", p);
        icon.set_draw_background (false);
        park();
        layer.add_marker (icon);
        icon.animate_in();
    }

    ~Craft()
    {
        layer.remove_marker(icon);
    }

    public void remove_marker()
    {
        park();
    }

    public void park()
    {
        set_pix_pos(40,40);
        if (dorotate)
            icon.set_rotation_angle(Clutter.RotateAxis.Z_AXIS, 0);
    }

    public void get_pos(out double lat, out double lon)
    {
        lat = icon.get_latitude();
        lon = icon.get_longitude();
    }


    public void set_lat_lon (double lat, double lon, double cse)
    {
        icon.set_location (lat, lon);
        if (dorotate)
            icon.set_rotation_angle(Clutter.RotateAxis.Z_AXIS, cse);
    }

    public void set_pix_pos (int x, int y)
    {
        var lat = view.y_to_latitude(y);
        var lon = view.x_to_longitude(x);
        icon.set_location (lat, lon);
    }
}
