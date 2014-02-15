
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

public class MWPlanner : GLib.Object {

    public Builder builder;
    public Gtk.Window window;
    public  Champlain.View view;
    public MWPMarkers markers;
    private string last_file;
    private ListBox ls;
    private Gtk.SpinButton zoomer;
    private Gtk.Label poslabel;
    public Gtk.Label stslabel;
    private double lx;
    private double ly;
    private int ht_map = 600;
    private int wd_map = 800;
    private Gtk.MenuItem menuup;
    private Gtk.MenuItem menudown;
    private Gtk.MenuItem menunav;
    private Gtk.MenuItem menuncfg;
    public MWPSettings conf;
    private MWSerial msp;
    private Gtk.Button conbutton;
    private Gtk.Label verlab;
    private Gtk.Label typlab;
    private Gtk.Label labelvbat;
    private bool have_vers;
    private bool have_misc;
    private bool have_wp;
    private bool have_nc;
    private uint8 mrtype;
    private uint gpstid;
    private uint cmdtid;
    private Craft craft;
    private bool follow = false;
    private bool centreon = false;
    private bool navcap = false;
    private GtkChamplain.Embed embed;
    private PrefsDialog prefs;
    private Gtk.AboutDialog about;
    private NavStatus navstatus;
    private NavConfig navconf;
    private GPSInfo gpsinfo;
    private WPMGR wpmgr;
    private MissionItem[] wp_resp;
    private static string mission;
    private static string serial;
    private static bool mkcon;
    private static bool ignore_sz;
    private static bool dorotate = false; // workaround for Ubuntu & old champlain
    private uint8 vwarn1;
    private uint8 vwarn2;
    private uint8 vcrit;
    private uint8 livbat;

    private enum MS_Column {
        ID,
        NAME,
        N_COLUMNS
    }

    private enum WPDL {
        IDLE=0,
        VALIDATE,
        REPLACE
    }

    private struct WPMGR
    {
        MSP_WP[] wps;
        WPDL wp_flag;
        uint8 npts;
        uint8 wpidx;
    }


    private enum WPFAIL {
        OK=0,
        NO = (1<<0),
        ACT = (1<<1),
        LAT = (1<<2),
        LON = (1<<3),
        ALT = (1<<4),
        P1 = (1<<5),
        P2 = (1<<6),
        P3 = (1<<7),
        FLAG = (1<<8)
    }

    private static const string[] failnames =
        {"","WPNO","LAT","LON","ALT","P1","P2","P3","FLAG"};

    const OptionEntry[] options = {
        { "mission", 'm', 0, OptionArg.STRING, out mission, "Mission file", null},
        { "serial-device", 's', 0, OptionArg.STRING, out serial, "Serial device", null},
        { "connect", 'c', 0, OptionArg.NONE, out mkcon, "connect to first device", null},
        { "ignore-sizing", 0, 0, OptionArg.NONE, out ignore_sz, "ignore minimum size constraint", null},
        { "force-rotation", 0, 0, OptionArg.NONE, out dorotate, "Force rotation on old libchamplain", null},
        {null}
    };

    public MWPlanner ()
    {
        wpmgr = WPMGR();

        builder = new Builder ();
        conf = new MWPSettings();
        conf.read_settings();

        var fn = MWPUtils.find_conf_file("mwp.ui");
        if (fn == null)
        {
            stderr.printf ("No UI definition file\n");
            Posix.exit(255);
        }
        else
        {
            try
            {
                builder.add_from_file (fn);
            } catch (Error e) {
                stderr.printf ("Builder: %s\n", e.message);
                Posix.exit(255);
            }
        }

        builder.connect_signals (null);
        window = builder.get_object ("window1") as Gtk.Window;
        window.destroy.connect (Gtk.main_quit);

        string icon=null;

        try {
            icon = MWPUtils.find_conf_file("mwp_icon.svg");
            window.set_icon_from_file(icon);
        } catch {};

        zoomer = builder.get_object ("spinbutton1") as Gtk.SpinButton;

        var menuop = builder.get_object ("file_open") as Gtk.MenuItem;
        menuop.activate.connect (() => {
                on_file_open();
            });

        menuop = builder.get_object ("menu_save") as Gtk.MenuItem;
        menuop.activate.connect (() => {
                on_file_save();
            });

        menuop = builder.get_object ("menu_save_as") as Gtk.MenuItem;
        menuop.activate.connect (() => {
                on_file_save_as();
            });

        menuop = builder.get_object ("menu_prefs") as Gtk.MenuItem;
        menuop.activate.connect(() =>
            {
                prefs.run_prefs(ref conf);
            });

        menuop = builder.get_object ("menu_quit") as Gtk.MenuItem;
        menuop.activate.connect (() => {
                Gtk.main_quit();
            });

        menuop= builder.get_object ("menu_about") as Gtk.MenuItem;
        menuop.activate.connect (() => {
                about.show_all();
                about.run();
                about.hide();
            });

        menuup = builder.get_object ("upload_quad") as Gtk.MenuItem;
        menuup.sensitive = false;
        menuup.activate.connect (() => {
                upload_quad();
            });

        menudown = builder.get_object ("download_quad") as Gtk.MenuItem;
        menudown.sensitive =false;
        menudown.activate.connect (() => {
                download_quad();
            });

        menunav = builder.get_object ("nav_status_menu") as Gtk.MenuItem;
        menunav.sensitive =false;
        navstatus = new NavStatus(window,builder);
        menunav.activate.connect (() => {
                navstatus.show();
            });

        menuncfg = builder.get_object ("nav_config_menu") as Gtk.MenuItem;
        menuncfg.sensitive =false;
        navconf = new NavConfig(window,builder);
        menuncfg.activate.connect (() => {
                navconf.show();
            });

        var cvers = Champlain.VERSION_HEX;
        if(cvers > 0xc0300)
        {
            dorotate = true;
        }

        embed = new GtkChamplain.Embed();
        view = embed.get_view();
        view.set_reactive(true);
        view.set_property("kinetic-mode", true);
        zoomer.adjustment.value_changed.connect (() =>
            {
                int  zval = (int)zoomer.adjustment.value;
                var val = view.get_zoom_level();
                if (val != zval)
                {
                    view.set_property("zoom-level", zval);
                }
            });


        var ent = builder.get_object ("entry1") as Gtk.Entry;
        ent.set_text(conf.altitude.to_string());

        ent = builder.get_object ("entry2") as Gtk.Entry;
        ent.set_text(conf.loiter.to_string());

        var scale = new Champlain.Scale();
        scale.connect_view(view);
        view.add_child(scale);
        var lm = view.get_layout_manager();
        lm.child_set(view,scale,"x-align", Clutter.ActorAlign.START);
        lm.child_set(view,scale,"y-align", Clutter.ActorAlign.END);
        view.set_keep_center_on_resize(true);

        if(ignore_sz != true)
        {
            var s = window.get_screen();
            var m = s.get_monitor_at_window(s.get_active_window());
            Gdk.Rectangle monitor;
            s.get_monitor_geometry(m, out monitor);
            var tmp = monitor.width - 320;
            if (wd_map > tmp)
                wd_map = tmp;
            tmp = monitor.height - 180;
            if (ht_map > tmp)
                ht_map = tmp;
            embed.set_size_request(wd_map, ht_map);
        }

        var pane = builder.get_object ("paned1") as Gtk.Paned;
        add_source_combo(conf.defmap);
        pane.pack1 (embed,true,false);

        ls = new ListBox();
        ls.create_view(this);

        var scroll = new Gtk.ScrolledWindow (null, null);
        scroll.set_policy (Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        scroll.set_min_content_width(400);
        scroll.add (ls.view);

        var pane2 = new Gtk.Paned(Gtk.Orientation.VERTICAL);
        pane.pack2 (pane2,false,true);
        pane2.pack1(scroll,true,false);

        var grid =  builder.get_object ("grid1") as Gtk.Grid;
        grid.set_column_homogeneous(true);

        gpsinfo = new GPSInfo(grid);

        pane2.pack2(grid,false,true);
        pane2.set_position(ht_map-20);

        view.notify["zoom-level"].connect(() => {
                var val = view.get_zoom_level();
                var zval = (int)zoomer.adjustment.value;
                if (val != zval)
                    zoomer.adjustment.value = (int)val;
            });

        markers = new MWPMarkers();
        view.add_layer (markers.path);
        view.add_layer (markers.markers);
        view.button_release_event.connect((evt) => {
                if(evt.button == 3)
                {
                    var lon = view.x_to_longitude (evt.x);
                    var lat = view.y_to_latitude (evt.y);
                    ls.insert_item(MSP.Action.WAYPOINT, lat,lon);
                    ls.calc_mission();
                    return true;
                }
                else
                    return false;
            });

        poslabel = builder.get_object ("poslabel") as Gtk.Label;
        stslabel = builder.get_object ("label5") as Gtk.Label;

        var logb = builder.get_object ("logger_cb") as Gtk.CheckButton;
        logb.toggled.connect (() => {
                if (logb.active)
                    Logger.start();
                else
                    Logger.stop();
            });

        var centreonb = builder.get_object ("checkbutton1") as Gtk.CheckButton;
        centreonb.toggled.connect (() => {
                centreon = centreonb.active;
            });

        var followb = builder.get_object ("checkbutton2") as Gtk.CheckButton;
        followb.toggled.connect (() => {
                follow = followb.active;
                if (follow == false && craft != null)
                {
                    craft.park();
                }
            });

        prefs = new PrefsDialog(builder);
        about = builder.get_object ("aboutdialog1") as Gtk.AboutDialog;
        Gdk.Pixbuf pix = null;
        try  {
            pix = new Gdk.Pixbuf.from_file_at_size (icon, 200,200);
        } catch  {};
        about.logo = pix;
        Timeout.add(500, () => { anim_cb(); return true;});

        if (mission == null)
        {
            view.center_on(conf.latitude,conf.longitude);
            view.set_property("zoom-level", conf.zoom);
            zoomer.adjustment.value = conf.zoom;
        }
        else
        {
            load_file(mission);
        }

        var dentry = builder.get_object ("comboboxtext1") as Gtk.ComboBoxText;
        foreach(string a in conf.devices)
        {
            dentry.append_text(a);
        }
        var te = dentry.get_child() as Gtk.Entry;
        te.can_focus = true;
        dentry.active = 0;
        conbutton = builder.get_object ("button1") as Gtk.Button;

        verlab = builder.get_object ("verlab") as Gtk.Label;
        typlab = builder.get_object ("typlab") as Gtk.Label;
        labelvbat = builder.get_object ("labelvbat") as Gtk.Label;
        conbutton.clicked.connect(() => {
                connect_serial(conbutton, dentry);
            });

        msp = new MWSerial();
        msp.serial_lost.connect(() => {
                serial_doom(conbutton);
            });

        msp.serial_event.connect((s,cmd,raw,len,errs) => {
                handle_serial(s,cmd,raw,len,errs);
            });

        if(serial != null)
        {
            dentry.prepend_text(serial);
            dentry.active = 0;
        }

        if(mkcon)
        {
            connect_serial(conbutton, dentry);
        }

        window.show_all();
    }

    private void handle_serial(MWSerial sd,  MSP.Cmds cmd, uint8[] raw, uint len, bool errs)
    {
        if(errs == true)
        {
            stderr.printf("Error on cmd %c (%d)\n", cmd,cmd);
            remove_tid(ref cmdtid);
            return;
        }
        switch(cmd)
        {
            case MSP.Cmds.IDENT:
                remove_tid(ref cmdtid);
                have_vers = true;
                mrtype = raw[1];
                navcap = ((raw[3] & 16) == 16);
                var vers="v%03d".printf(raw[0]);
                verlab.set_label(vers);
                typlab.set_label(MSP.get_mrtype(mrtype));
                add_cmd(MSP.Cmds.MISC,null,0, &have_misc,1000);
                break;

            case MSP.Cmds.MISC:
                remove_tid(ref cmdtid);
                have_misc = true;
                MSP_MISC *m = (MSP_MISC *)raw;
                vwarn1 = m.conf_vbatlevel_warn1;
                vwarn2 = m.conf_vbatlevel_warn2;
                vcrit =  m.conf_vbatlevel_crit;
                add_cmd(MSP.Cmds.STATUS,null,0,&have_misc,1000);
                break;

            case MSP.Cmds.STATUS:
                remove_tid(ref cmdtid);
                have_misc = true;
                uint16 sensor;
                MSP_STATUS *s = (MSP_STATUS *)raw;
                sensor=uint16.from_little_endian(s.sensor);
                if((sensor & 8) == 8)
                {
                    add_cmd(MSP.Cmds.NAV_CONFIG,null,0,&have_nc,1000);
                    if(craft == null)
                        craft = new Craft(view, mrtype,dorotate);
                    craft.park();

                    var timadj = builder.get_object ("spinbutton2") as Gtk.SpinButton;
                    var  val = timadj.adjustment.value;
                    int timeout = (int)(val*1000 / 6);
                    int tcycle = 0;
                    gpstid = Timeout.add(timeout, () =>
                        {
                            switch (tcycle)
                            {
                                case 0:
                                    send_cmd(MSP.Cmds.RAW_GPS, null, 0);
                                    break;
                                case 1:
                                    send_cmd(MSP.Cmds.NAV_STATUS, null, 0);
                                    break;
                                case 2:
                                    send_cmd(MSP.Cmds.COMP_GPS, null, 0);
                                    break;
                                case 3:
                                    send_cmd(MSP.Cmds.ALTITUDE, null, 0);
                                    break;
                                case 4:
                                    send_cmd(MSP.Cmds.ATTITUDE, null, 0);
                                    break;
                                case 5:
                                    send_cmd(MSP.Cmds.ANALOG, null, 0);
                                    break;
                            }
                            tcycle += 1;
                            tcycle %= 6;
                            return true;
                        }
                    );
                }
                else
                {
                    gpstid = Timeout.add(1000, () =>
                        {
                            send_cmd(MSP.Cmds.ANALOG, null, 0);
                            return true;
                        }
                    );
                }
                break;

            case MSP.Cmds.NAV_STATUS:
                navstatus.update(*(MSP_NAV_STATUS*)raw);
                break;

            case MSP.Cmds.NAV_CONFIG:
                have_nc = true;
                navconf.update(*(MSP_NAV_CONFIG*)raw);
                break;

            case MSP.Cmds.COMP_GPS:
                navstatus.comp_gps(*(MSP_COMP_GPS*)raw);
                break;

            case MSP.Cmds.ATTITUDE:
                navstatus.set_attitude(*(MSP_ATTITUDE*)raw);
                break;

            case MSP.Cmds.ALTITUDE:
                navstatus.set_altitude(*(MSP_ALTITUDE*)raw);
                break;

            case MSP.Cmds.ANALOG:
                if(Logger.is_logging)
                {
                    Logger.analog(*(MSP_ANALOG*)raw);
                }
                var ivbat = ((MSP_ANALOG*)raw).vbat;
                set_bat_stat(ivbat);
                break;

            case MSP.Cmds.RAW_GPS:
                var fix = gpsinfo.update(*(MSP_RAW_GPS*)raw, conf.dms);

                if (fix != 0)
                {
                    if(craft != null)
                    {
                        if(follow == true)
                            craft.set_lat_lon(gpsinfo.lat,gpsinfo.lon,gpsinfo.cse);
                        if (centreon == true)
                            view.center_on(gpsinfo.lat,gpsinfo.lon);
                    }
                }
                break;
            case MSP.Cmds.SET_WP:
                var no = wpmgr.wps[wpmgr.wpidx].wp_no;
                request_wp(no);
                break;

            case MSP.Cmds.WP:
                MSP_WP *w = (MSP_WP *)raw;
                remove_tid(ref cmdtid);
                have_wp = true;

//                print("Got WP %d\n", w.wp_no);
                if (wpmgr.wp_flag == WPDL.VALIDATE)
                {
                    WPFAIL fail = WPFAIL.OK;
                    if(w.wp_no != wpmgr.wps[wpmgr.wpidx].wp_no)
                        fail |= WPFAIL.NO;
                    else if(w.action != wpmgr.wps[wpmgr.wpidx].action)
                        fail |= WPFAIL.ACT;
                    else if (w.lat != wpmgr.wps[wpmgr.wpidx].lat)
                        fail |= WPFAIL.LAT;
                    else if (w.lon != wpmgr.wps[wpmgr.wpidx].lon)
                        fail |= WPFAIL.LON;
                    else if(w.altitude != wpmgr.wps[wpmgr.wpidx].altitude)
                        fail |= WPFAIL.ALT;
                    else if (w.p1 != wpmgr.wps[wpmgr.wpidx].p1)
                        fail |= WPFAIL.P1;
                    else if (w.p2 != wpmgr.wps[wpmgr.wpidx].p2)
                        fail |= WPFAIL.P2;
                    else if (w.p3 != wpmgr.wps[wpmgr.wpidx].p3)
                        fail |= WPFAIL.P3;
                    else if (w.flag != wpmgr.wps[wpmgr.wpidx].flag)
                        fail |= WPFAIL.FLAG;

                    if (fail != WPFAIL.OK)
                    {
                        string[] arry = {};
                        for(var i = WPFAIL.OK; i <= WPFAIL.FLAG; i += 1)
                        {
                            if ((fail & i) == i)
                            {
                                arry += failnames[i];
                            }
                        }
                        var fmsg = string.join("|",arry);
                        var mtxt = "Validation for wp %d fails for %s".printf(w.wp_no, fmsg);
                        mwp_warning_box(mtxt, Gtk.MessageType.ERROR);
                    }
                    else if(w.flag != 0xa5)
                    {
                        wpmgr.wpidx++;
                        send_cmd(MSP.Cmds.SET_WP, &wpmgr.wps[wpmgr.wpidx], sizeof(MSP_WP));
                    }
                    else
                    {
                        mwp_warning_box("Mission validated", Gtk.MessageType.INFO);
                    }

                }
                else if (wpmgr.wp_flag == WPDL.REPLACE)
                {
                    MissionItem m = MissionItem();
                    m.no= w.wp_no;
                    m.action = (MSP.Action)w.action;
                    m.lat = (int32.from_little_endian(w.lat))/10000000.0;
                    m.lon = (int32.from_little_endian(w.lon))/10000000.0;
                    m.alt = (uint32.from_little_endian(w.altitude))/100;
                    m.param1 = (uint16.from_little_endian(w.p1));
                    m.param2 = (uint16.from_little_endian(w.p2));
                    m.param3 = (uint16.from_little_endian(w.p3));

//                    print("wp %d act %d %.5f %.5f %d %02x\n",
//                          m.no, m.action, m.lat, m.lon, (int)m.alt, w.flag);

                    wp_resp += m;
                    if(w.flag == 0xa5 || w.wp_no == 255)
                    {
                        var ms = new Mission();
                        ms.set_ways(wp_resp);
                        ls.import_mission(ms);
                        foreach(MissionItem mi in wp_resp)
                        {
                            if(mi.action != MSP.Action.RTH &&
                               mi.action != MSP.Action.JUMP)
                            {
                                if (mi.lat > ms.maxy)
                                    ms.maxy = mi.lat;
                                if (mi.lon > ms.maxx)
                                    ms.maxx = mi.lon;
                                if (mi.lat <  ms.miny)
                                    ms.miny = mi.lat;
                                if (mi.lon <  ms.minx)
                                    ms.minx = mi.lon;
                            }
                            }
                            ms.zoom = 16;
                            ms.cy = (ms.maxy + ms.miny) / 2.0;
                            ms.cx = (ms.maxx + ms.minx) / 2.0;
                            if (centreon == false)
                            {
                                var mmax = view.get_max_zoom_level();
                                view.center_on(ms.cy, ms.cx);
                                view.set_property("zoom-level", mmax-1);
                            }
                            markers.add_list_store(ls);
                            wp_resp={};
                    }
                    else if(w.flag == 0xfe)
                    {
                        stderr.printf("Error flag on wp #%d\n", w.wp_no);
                    }
                    else
                    {
                        request_wp(w.wp_no+1);
                    }
                }
                else
                {
                    stderr.printf("unsolicited WP #%d\n", w.wp_no);
                }
                break;

            default:
                stderr.printf ("** Unknown response %d\n", cmd);
                break;
        }
    }

    private void set_bat_stat(uint8 ivbat)
    {
        string vbatlab;
        if(ivbat != livbat)
        {
            if(ivbat < vcrit /2 || ivbat == 0)
                vbatlab="<span background=\"white\" weight=\"normal\">~0v</span>";
            else
            {
                string vbatcol;
                if (ivbat <= vcrit)
                    vbatcol = "red";
                else if (ivbat <= vwarn2)
                    vbatcol = "orange";
                else if (ivbat <= vwarn1)
                    vbatcol = "yellow" ;
                else
                vbatcol = "green";
                vbatlab="<span background=\"%s\" weight=\"bold\">%.1fv</span>".printf(vbatcol, (double)ivbat/10.0);
            }
            labelvbat.set_markup(vbatlab);
            livbat = ivbat;
        }
    }

    private void upload_quad()
    {
        bool ok = true;

        if(conf.scary_warn == true)
        {
            ok = scary_warning();

        }
        if (ok == true)
        {
            var wps = ls.to_wps();
            if(wps.length == 0)
            {
                MSP_WP w0 = MSP_WP();
                w0.wp_no = 1;
                w0.action =  MSP.Action.RTH;
                w0.lat = w0.lon = 0;
                w0.altitude = 25;
                w0.p1 = w0.p2 = w0.p3 = 0;
                w0.flag = 0xa5;
                wps += w0;
            }
            wpmgr.npts = (uint8)wps.length;
            wpmgr.wpidx = 0;
            wpmgr.wps = wps;
            wpmgr.wp_flag = WPDL.VALIDATE;
            send_cmd(MSP.Cmds.SET_WP, &wpmgr.wps[wpmgr.wpidx], sizeof(MSP_WP));
        }
    }

    public void request_wp(uint8 wp)
    {
        uint8 buf[2];
        have_wp = false;
        buf[0] = wp;
        add_cmd(MSP.Cmds.WP,buf,1,&have_wp,1000);
    }

    private void send_cmd(MSP.Cmds cmd, void* buf, size_t len)
    {
        if(msp.available == true)
        {
            msp.send_command(cmd,buf,len);
        }
    }

    private void add_cmd(MSP.Cmds cmd, void* buf, size_t len,
                         bool *flag, int wait=1000)
    {
        if(flag != null)
        {
            cmdtid = Timeout.add(wait, () => {
                    if (*flag == false)
                    {
                        send_cmd(cmd,buf,len);
                        return true;
                    }
                    else
                    {
                        return false;
                    }
                });
        }
        send_cmd(cmd,buf,len);
    }

    private void remove_tid(ref uint tid)
    {
        if(tid > 0)
            Source.remove(tid);
        tid = 0;
    }

    private void serial_doom(Gtk.Button c)
    {
        remove_tid(ref gpstid);
        remove_tid(ref cmdtid);
        msp.close();
        gpsinfo.annul();
        set_bat_stat(0);
        have_vers = have_misc = false;
        c.set_label("gtk-connect");
        menunav.sensitive = menuncfg.sensitive =
        menuup.sensitive = menudown.sensitive = false;
        navstatus.hide();
        navconf.hide();
        if(craft != null)
        {
            craft.remove_marker();
        }
    }

    private void connect_serial(Gtk.Button c, Gtk.ComboBoxText d)
    {
        if(msp.available)
        {
            verlab.set_label("");
            typlab.set_label("");
            serial_doom(c);
        }
        else
        {
            var serdev = d.get_active_text();
            if (msp.open(serdev,115200) == true)
            {
                c.set_label("gtk-disconnect");
                add_cmd(MSP.Cmds.IDENT,null,0,&have_vers,1000);
                menuup.sensitive = menudown.sensitive = menunav.sensitive =
                menuncfg.sensitive = true;
            }
            else
                mwp_warning_box("Unable to open serial device %s".printf(serdev));
        }
    }

    private void anim_cb()
    {
        var x = view.get_center_longitude();
        var y = view.get_center_latitude();

        if (lx !=  x && ly != y)
        {
            poslabel.set_text(PosFormat.pos(y,x,conf.dms));
            lx = x;
            ly = y;
            if (follow == false && craft != null)
            {
                double plat,plon;
                craft.get_pos(out plat, out plon);
                    /*
                     * Older Champlain versions don't have full bbox
                     * work around it
                     */
#if NOBB
                double vypix = view.latitude_to_y(plat);
                double vxpix = view.longitude_to_x(plon);
                bool outofview = ((int)vypix < 0 || (int)vxpix < 0);
                if(outofview == false)
                {
                    var ww = embed.get_window();
                    var wd = ww.get_width();
                    var ht = ww.get_height();
                    outofview = ((int)vypix > ht || (int)vxpix > wd);
                }
                if (outofview == true)
                {
                    craft.park();
                }
#else
                var bbox = view.get_bounding_box();
                if (bbox.covers(plat, plon) == false)
                {
                    craft.park();
                }
#endif
            }
        }
    }

    private void add_source_combo(string? defmap)
    {
        var combo  = builder.get_object ("combobox1") as Gtk.ComboBox;
        var map_source_factory = Champlain.MapSourceFactory.dup_default();

        var liststore = new ListStore (MS_Column.N_COLUMNS, typeof (string), typeof (string));

        if(conf.map_sources != null)
        {
            var fn = MWPUtils.find_conf_file(conf.map_sources);
            if (fn != null)
            {
                var msources =   JsonMapDef.read_json_sources(fn);
                foreach (unowned MapSource s0 in msources)
                {
                    s0.desc = new  MwpMapSource(
                        s0.id,
                        s0.name,
                        s0.licence,
                        s0.licence_uri,
                        s0.min_zoom,
                        s0.max_zoom,
                        s0.tile_size,
                        Champlain.MapProjection.MAP_PROJECTION_MERCATOR,
                        s0.uri_format);
                    map_source_factory.register((Champlain.MapSourceDesc)s0.desc);
                }
            }
        }
        var sources =  map_source_factory.get_registered();
        int i = 0;
        int defval = 0;
        string? defsource = null;

        foreach (Champlain.MapSourceDesc s in sources)
        {
            TreeIter iter;
            liststore.append(out iter);
            var id = s.get_id();
            liststore.set (iter, MS_Column.ID, id);
            var name = s.get_name();
            liststore.set (iter, MS_Column.NAME, name);
            if (defmap != null && name == defmap)
            {
                defval = i;
                defsource = id;
            }
            i++;
        }
        combo.set_model(liststore);
        if(defsource != null)
        {
            var src = map_source_factory.create_cached_source(defsource);
            view.set_property("map-source", src);
        }

        var cell = new Gtk.CellRendererText();
        combo.pack_start(cell, false);
        combo.add_attribute(cell, "text", 1);
        combo.set_active(defval);
        combo.changed.connect (() => {
                GLib.Value val1;
                TreeIter iter;
                combo.get_active_iter (out iter);
                liststore.get_value (iter, 0, out val1);
                var source = map_source_factory.create_cached_source((string)val1);
                var zval = zoomer.adjustment.value;
                var cx = lx;
                var cy = ly;
                view.set_property("map-source", source);

                    /* Stop oob zooms messing up the map */
                var mmax = view.get_max_zoom_level();
                var mmin = view.get_min_zoom_level();
                var chg = false;
                if (zval > mmax)
                {
                    chg = true;
                    view.set_property("zoom-level", mmax);
                }
                if (zval < mmin)
                {
                    chg = true;
                    view.set_property("zoom-level", mmin);
                }
                if (chg == true)
                {
                    view.center_on(cy, cx);
                }
            });

    }

    public void on_file_save()
    {
        if (last_file == null)
        {
            on_file_save_as ();
        }
        else
        {
            Mission m = ls.to_mission();
            if (conf.compat_vers != null)
                m.version = conf.compat_vers;
            m.to_xml_file(last_file);
        }
    }

    public void on_file_save_as ()
    {
        Mission m = ls.to_mission();
        Gtk.FileChooserDialog chooser = new Gtk.FileChooserDialog (
            "Select a mission file", null, Gtk.FileChooserAction.SAVE,
            "_Cancel",
            Gtk.ResponseType.CANCEL,
            "_Save",
            Gtk.ResponseType.ACCEPT);
        chooser.select_multiple = false;
        Gtk.FileFilter filter = new Gtk.FileFilter ();
        filter.set_filter_name ("Mission");
        filter.add_pattern ("*.mission");
        filter.add_pattern ("*.xml");
//            filter.add_pattern ("*.json");
        chooser.add_filter (filter);

        filter = new Gtk.FileFilter ();
        filter.set_filter_name ("All Files");
        filter.add_pattern ("*");
        chooser.add_filter (filter);

            // Process response:
        if (chooser.run () == Gtk.ResponseType.ACCEPT) {
            last_file = chooser.get_filename ();
            if (conf.compat_vers != null)
                m.version = conf.compat_vers;
            m.to_xml_file(last_file);
        }
        chooser.close ();
    }

    private void load_file(string fname)
    {
        var ms = new Mission ();
        if(ms.read_xml_file (fname) == true)
        {
            ms.dump();
            ls.import_mission(ms);
            var mmax = view.get_max_zoom_level();
            var mmin = view.get_min_zoom_level();
            view.center_on(ms.cy, ms.cx);

            if (ms.zoom < mmin)
                ms.zoom = mmin;

            if (ms.zoom > mmax)
                ms.zoom = mmax;

            view.set_property("zoom-level", ms.zoom);
            markers.add_list_store(ls);
            last_file = fname;
        }
        else
        {
            mwp_warning_box("Failed to open file");
        }
    }

    private void mwp_warning_box(string warnmsg,
                                 Gtk.MessageType klass=Gtk.MessageType.WARNING )
    {
        Gtk.MessageDialog msg = new Gtk.MessageDialog (window,
                                                       Gtk.DialogFlags.MODAL,
                                                       klass,
                                                       Gtk.ButtonsType.OK,
                                                       warnmsg);
        msg.run();
        msg.destroy();
    }

    public void on_file_open ()
    {
        Gtk.FileChooserDialog chooser = new Gtk.FileChooserDialog (
            "Select a mission file", null, Gtk.FileChooserAction.OPEN,
            "_Cancel",
            Gtk.ResponseType.CANCEL,
            "_Open",
            Gtk.ResponseType.ACCEPT);
        chooser.select_multiple = false;

        Gtk.FileFilter filter = new Gtk.FileFilter ();
	filter.set_filter_name ("Mission");
	filter.add_pattern ("*.mission");
	filter.add_pattern ("*.xml");
//	filter.add_pattern ("*.json");
	chooser.add_filter (filter);

	filter = new Gtk.FileFilter ();
	filter.set_filter_name ("All Files");
	filter.add_pattern ("*");
	chooser.add_filter (filter);

            // Process response:
        if (chooser.run () == Gtk.ResponseType.ACCEPT) {
            ls.clear_mission();
            var fn = chooser.get_filename ();
            load_file(fn);
        }
        chooser.close ();
    }

    public void run()
    {
        Gtk.main();
    }

    private void download_quad()
    {
        wp_resp= {};
        wpmgr.wp_flag = WPDL.REPLACE;
        request_wp(1);
    }

    private bool scary_warning()
    {
        bool ok = false;
        const string text =
            "You are about to upload using an undocumented, beta status protocol\n\nAre you sure you want to do this?";

        Gtk.MessageDialog msg = new Gtk.MessageDialog (window,
                                                       Gtk.DialogFlags.MODAL,
                                                       Gtk.MessageType.QUESTION,
                                                       Gtk.ButtonsType.YES_NO,
                                                       text);
        var id = msg.run();
        msg.destroy();
        if(id == Gtk.ResponseType.YES)
            ok = true;
        return ok;
    }


    public static int main (string[] args)
    {
        if (GtkClutter.init (ref args) != InitError.SUCCESS)
            return 1;

        try {
            var opt = new OptionContext("");
            opt.set_help_enabled(true);
            opt.add_main_entries(options, null);
            opt.parse(ref args);
        } catch (OptionError e) {
            stderr.printf("Error: %s\n", e.message);
            stderr.printf("Run '%s --help' to see a full list of available "+
                          "options\n", args[0]);
            return 1;
        }

        MWPlanner app = new MWPlanner();
        app.run ();
        return 0;
    }

}

public class PosFormat : GLib.Object
{
    public static string lat(double _lat, bool dms)
    {
        if(dms == false)
            return "%.6f".printf(_lat);
        else
            return position(_lat, "%02d:%02d:%04.1f%c", "NS");
    }

    public static string lon(double _lon, bool dms)
    {
        if(dms == false)
            return "%.6f".printf(_lon);
        else
            return position(_lon, "%03d:%02d:%04.1f%c", "EW");
    }

    public static string pos(double _lat, double _lon, bool dms)
    {
        if(dms == false)
            return "%.6f %.6f".printf(_lat,_lon);
        else
        {
            var slat = lat(_lat,dms);
            var slon = lon(_lon,dms);
            StringBuilder sb = new StringBuilder ();
            sb.append(slat);
            sb.append(" ");
            sb.append(slon);
            return sb.str;
        }
    }

    private static string position(double coord, string fmt, string ind)
    {
        var neg = (coord < 0.0);
        var ds = Math.fabs(coord);
        int d = (int)ds;
        var rem = (ds-d)*3600.0;
        int m = (int)rem/60;
        double s = rem - m*60;
        if ((int)s*10 == 600)
        {
            m+=1;
            s = 0;
        }
        if (m == 60)
        {
            m = 0;
            d+=1;
        }
        var q = (neg) ? ind.get_char(1) : ind.get_char(0);
        return fmt.printf((int)d,(int)m,s,q);
    }

}
