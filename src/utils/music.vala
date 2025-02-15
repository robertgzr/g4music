namespace G4 {
    public const string UNKNOWN_ALBUM = _("Unknown Album");
    public const string UNKNOWN_ARTIST = _("Unknown Artist");
    public const int UNKNOWN_TRACK = int.MAX;

    public class Music : Object {
        public string album = "";
        public string artist = "";
        public string title = "";
        public string uri = "";
        public int track = UNKNOWN_TRACK;
        public int64 modified_time = 0;

        //  for runtime
        public string? cover_uri = null;
        public bool showing = true;

        //  for sorting
        private string _album_key = "";
        private string _artist_key = "";
        private string _title_key = "";
        private string? _cover_key = null;
        private int _order = 0;

        public Music (string uri, string title, int64 time) {
            this.title = title;
            this.uri = uri;
            this.modified_time = time;
        }

        public Music.empty () {
        }

        public unowned string cover_key {
            get {
                return _cover_key ?? uri;
            }
            set {
                _cover_key = value;
            }
        }

        public string get_artist_and_title () {
            return artist == UNKNOWN_ARTIST ? title : @"$artist - $title";
        }

        public bool from_gst_tags (Gst.TagList tags) {
            var changed = false;
            unowned string? al = null, ar = null, ti = null;
            if (tags.peek_string_index (Gst.Tags.ALBUM, 0, out al)
                    && al != null && al?.length > 0 && album != (!)al) {
                album = (!)al;
                _album_key = album.collate_key_for_filename ();
                changed = true;
            }
            if (tags.peek_string_index (Gst.Tags.ARTIST, 0, out ar)
                    && ar != null && ar?.length > 0 && artist != (!)ar) {
                artist = (!)ar;
                _artist_key = artist.collate_key_for_filename ();
                changed = true;
            }
            if (tags.peek_string_index (Gst.Tags.TITLE, 0, out ti)
                    && ti != null && ti?.length > 0 && title != (!)ti) {
                title = (!)ti;
                _title_key = title.collate_key_for_filename ();
                changed = true;
            }
            uint tr = 0;
            if (tags.get_uint (Gst.Tags.TRACK_NUMBER, out tr)
                    && (int) tr > 0 && track != tr) {
                track = (int) tr;
                changed = true;
            }
            return changed;
        }

        public Music.deserialize (DataInputBytes dis) throws IOError {
            album = dis.read_string ();
            artist = dis.read_string ();
            title = dis.read_string ();
            track = (int) dis.read_uint32 ();
            modified_time = (int64) dis.read_uint64 ();
            uri = dis.read_string ();
            _album_key = album.collate_key_for_filename ();
            _artist_key = artist.collate_key_for_filename ();
            _title_key = title.collate_key_for_filename ();
        }

        public void serialize (DataOutputBytes dos) throws IOError {
            dos.write_string (album);
            dos.write_string (artist);
            dos.write_string (title);
            dos.write_uint32 (track);
            dos.write_uint64 (modified_time);
            dos.write_string (uri);
        }

        public void parse_tags () {
            var file = File.new_for_uri (uri);
            var name = title;
            this.title = "";

            if (file.is_native ()) {
                var tags = parse_gst_tags (file);
                if (tags != null)
                    from_gst_tags ((!)tags);
            }

            if (title.length == 0 || artist.length == 0) {
                //  guess tags from the file name
                var end = name.last_index_of_char ('.');
                if (end > 0) {
                    name = name.substring (0, end);
                }

                int track_index = 0;
                var pos = name.index_of_char ('.');
                if (pos > 0) {
                    // assume prefix number as track index
                    int.try_parse (name.substring (0, pos), out track_index, null, 10);
                    name = name.substring (pos + 1);
                }

                //  split the file name by '-'
                var sa = split_string (name, "-");
                var len = sa.length;
                if (title.length == 0) {
                    title = len >= 1 ? sa[len - 1] : name;
                    _title_key = title.collate_key_for_filename ();
                }
                if (artist.length == 0) {
                    artist = len >= 2 ? sa[len - 2] : UNKNOWN_ARTIST;
                    _artist_key = artist.collate_key_for_filename ();
                }
                if (track_index == UNKNOWN_TRACK) {
                    if (track_index == 0 && len >= 3)
                        int.try_parse (sa[0], out track_index, null, 10);
                    if (track_index > 0)
                        this.track = track_index;
                }
            }
            if (album.length == 0) {
                //  assume folder name as the album
                album = file.get_parent ()?.get_basename () ?? UNKNOWN_ALBUM;
                _album_key = album.collate_key_for_filename ();
            }
        }

        public static int compare_by_album (Music s1, Music s2) {
            int ret = strcmp (s1._album_key, s2._album_key);
            if (ret != 0) return ret;
            ret = s1.track - s2.track;
            if (ret != 0) return ret;
            ret = strcmp (s1._title_key, s2._title_key);
            if (ret != 0) return ret;
            return strcmp (s1.uri, s2.uri);
        }

        public static int compare_by_artist (Music s1, Music s2) {
            int ret = strcmp (s1._artist_key, s2._artist_key);
            if (ret != 0) return ret;
            ret = strcmp (s1._title_key, s2._title_key);
            if (ret != 0) return ret;
            return strcmp (s1.uri, s2.uri);
        }

        public static int compare_by_artist_album (Music s1, Music s2) {
            int ret = strcmp (s1._artist_key, s2._artist_key);
            if (ret != 0) return ret;
            return compare_by_album (s1, s2);
        }

        public static int compare_by_title (Music s1, Music s2) {
            int ret = strcmp (s1._title_key, s2._title_key);
            if (ret != 0) return ret;
            ret = strcmp (s1._artist_key, s2._artist_key);
            if (ret != 0) return ret;
            return strcmp (s1.uri, s2.uri);
        }

        public static int compare_by_order (Music s1, Music s2) {
            return s1._order - s2._order;
        }

        public static int compare_by_date_ascending (Music s1, Music s2) {
            var diff = s2.modified_time - s1.modified_time;
            return (int) diff.clamp (-1, 1);
        }

        public static void shuffle_order (GenericArray<Music> arr) {
            for (var i = arr.length - 1; i > 0; i--) {
                var r = Random.int_range (0, i);
                var s = arr[i];
                arr[i] = arr[r];
                arr[r] = s;
                arr[i]._order = i;
            }
        }
    }

    public bool is_music_type (string content_type) {
        return ContentType.is_mime_type (content_type, "audio/*")
                && !content_type.has_suffix ("pls")
                && !content_type.has_suffix ("url");
    }

    public unichar find_first_letter (string text) {
        var index = 0;
        var next = 0;
        unichar c = 0;
        while (text.get_next_char (ref next, out c)) {
            if (c.isalpha () || c.iswide_cjk ())
                return c;
            index = next;
        }
        return 0;
    }

    public string get_display_name (string uri) {
        var file = File.new_for_uri (uri);
        var name = file.get_basename () ?? "";
        if (name.length == 0 || name == "/")
            name = file.get_parse_name ();
        return name;
    }

    public string get_uri_with_end_sep (File file) {
        var uri = file.get_uri ();
        if (uri[uri.length - 1] != '/')
            uri += "/";
        return uri;
    }

    public string parse_abbreviation (string text) {
        var sb = new StringBuilder ();
        var char_count = 0;
        foreach (var s in text.split (" ")) {
            var c = find_first_letter (s);
            if (c > 0) {
                sb.append_unichar (c);
                char_count++;
                if (char_count >= 2)
                    break;
            }
        }

        if (char_count >= 2) {
            return sb.str.up ();
        } else if (text.char_count () > 2) {
            var index = text.index_of_nth_char (2);
            return text.substring (0, index).up ();
        }
        return text.up ();
    }

    public GenericArray<string> split_string (string text, string delimiter) {
        var ar = text.split ("-");
        var sa = new GenericArray<string> (ar.length);
        foreach (var str in ar) {
            var s = str.strip ();
            if (s.length > 0)
                sa.add (s);
        }
        return sa;
    }
}
