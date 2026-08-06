///|
#borrow(path)
extern "c" fn kimicc_pp_read_file(path : Bytes) -> Bytes = "kimicc_pp_read_file"

///|
#borrow(path)
extern "c" fn kimicc_pp_file_exists(path : Bytes) -> Bool = "kimicc_pp_file_exists"

///|
fn pp_file_exists(path : String) -> Bool {
  kimicc_pp_file_exists(@utf8.encode(path))
}

///|
fn pp_read_file(path : String) -> String? {
  if !pp_file_exists(path) {
    return None
  }
  Some(@utf8.decode_lossy(kimicc_pp_read_file(@utf8.encode(path))))
}
