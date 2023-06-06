namespace G4 {

    public class DirInfo {
        public File dir;
        public int64 time;

        public DirInfo (File file, FileInfo? info = null) {
            dir = file;
            time = info?.get_modification_date_time ()?.to_unix () ?? 0;
        }
    }

    public class DirCache : Object {
        private static uint32 MAGIC = 0x44495243; //  'DIRC'

        private class ChildInfo {
            public FileType type;
            public string name;
            public int64 time;
    
            public ChildInfo (FileType type, string name, int64 time) {
                this.type = type;
                this.name = name;
                this.time = time;
            }
        }

        private File _dir;
        private File _file;
        private int64 _time;
        private GenericArray<ChildInfo> _children = new GenericArray<ChildInfo> (128);

        public DirCache (File dir, int64 time = 0) {
            _dir = dir;
            _time = time;
            var cache_dir = Environment.get_user_cache_dir ();
            var name = Checksum.compute_for_string (ChecksumType.MD5, dir.get_uri ());
            _file = File.new_build_filename (cache_dir, Config.APP_ID, "dir-cache", name);
        }

        public bool check_valid () {
            try {
                if (_time == 0) {
                    var info = _dir.query_info (FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
                    _time = info.get_modification_date_time ()?.to_unix () ?? 0;
                }
                var info = _file.query_info (FileAttribute.TIME_MODIFIED, FileQueryInfoFlags.NONE);
                return _time <= (info.get_modification_date_time ()?.to_unix () ?? 0);
            } catch (Error e) {
            }
            return false;
        }

        public void add_child (FileInfo info) {
            var time = info.get_modification_date_time ()?.to_unix () ?? 0;
            var child = new ChildInfo (info.get_file_type (), info.get_name (), time);
            _children.add (child);
        }

        public bool load (Queue<DirInfo> stack, GenericArray<Object> musics) {
            try {
                var mapped = new MappedFile (_file.get_path () ?? "", false);
                var dis = new DataInputBytes (mapped.get_bytes ());

                var magic = dis.read_uint32 ();
                if (magic != MAGIC)
                    throw new IOError.INVALID_DATA (@"Magic:$magic");
                var base_name = _dir.get_basename () ?? "";
                var bname = dis.read_string ();
                if (bname != base_name)
                    throw new IOError.INVALID_DATA (@"Name:$bname!=$base_name");

                var count = dis.read_size ();
                for (var i = 0; i < count; i++) {
                    var type = dis.read_byte ();
                    var name = dis.read_string ();
                    var time = (int64) dis.read_uint64 ();
                    var child = _dir.get_child (name);
                    if (type == FileType.DIRECTORY) {
                        stack.push_head (new DirInfo (child));
                    } else {
                        musics.add (new Music (child.get_uri (), name, time));
                    }
                }
                return true;
            } catch (Error e) {
                if (e.code != FileError.NOENT)
                    print ("Load dirs error: %s\n", e.message);
            }
            return false;
        }

        public void save () {
            try {
                var parent = _file.get_parent ();
                var exists = parent?.query_exists () ?? false;
                if (!exists)
                    parent?.make_directory_with_parents ();
                var fos = _file.replace (null, false, FileCreateFlags.NONE);
                var dos = new DataOutputBytes ();
                dos.write_uint32 (MAGIC);
                dos.write_string (_dir.get_basename () ?? "");
                dos.write_size (_children.length);
                foreach (var child in _children) {
                    dos.write_byte (child.type);
                    dos.write_string (child.name);
                    dos.write_uint64 (child.time);
                }
                dos.write_to (fos);
            } catch (Error e) {
                print ("Save dirs error: %s\n", e.message);
            }
        }
    }
}
