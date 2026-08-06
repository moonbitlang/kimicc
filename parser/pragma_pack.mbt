///|
/// Source-position-indexed `#pragma pack` state.
///
/// `#pragma pack` is positional: the alignment cap in effect depends on where a
/// struct definition sits in the token stream, not on any attribute attached to
/// the declaration. The parser also backtracks by restoring `Lexer::pos`, so
/// carrying the pack stack as streaming lexer state would let a rewind replay
/// or skip directives.
///
/// Both problems go away by precomputing the directives into a table sorted by
/// byte offset and answering `pack_at(pos)` as a pure function of position.
/// `events` holds `(offset_of_directive_end, pack_in_effect_after_it)`.
struct PragmaPackTable {
  events : Array[(Int, Int?)]
}

///|
/// Scans `input` for `#pragma pack` directives and records the resulting cap
/// after each one.
///
/// Recognized spellings, matching GCC/MSVC:
///
/// - `#pragma pack(N)` sets the cap to `N`
/// - `#pragma pack()` clears the cap back to natural alignment
/// - `#pragma pack(push, N)` pushes the current cap and sets `N`
/// - `#pragma pack(push)` pushes the current cap and keeps it
/// - `#pragma pack(pop)` restores the cap from the stack
///
/// Unrecognized `pack` forms leave the cap unchanged. Directives inside string
/// literals, character literals, and comments are ignored, since a `#` there is
/// not a directive.
fn PragmaPackTable::scan(input : String) -> PragmaPackTable {
  let events : Array[(Int, Int?)] = []
  let stack : Array[Int?] = []
  let mut current : Int? = None
  let len = input.length()
  let mut i = 0
  let mut at_line_start = true
  while i < len {
    let c = input[i]
    // Skip over regions where a `#` cannot begin a directive.
    if c is '"' || c is '\'' {
      let quote = c
      i += 1
      while i < len && input[i] != quote {
        if input[i] is '\\' {
          i += 1
        }
        i += 1
      }
      i += 1
      at_line_start = false
      continue
    }
    if c is '/' && i + 1 < len && input[i + 1] is '*' {
      i += 2
      while i + 1 < len && !(input[i] is '*' && input[i + 1] is '/') {
        i += 1
      }
      i += 2
      continue
    }
    if c is '/' && i + 1 < len && input[i + 1] is '/' {
      while i < len && input[i] != '\n' {
        i += 1
      }
      continue
    }
    if c is '\n' {
      at_line_start = true
      i += 1
      continue
    }
    if c is ' ' || c is '\t' || c is '\r' {
      i += 1
      continue
    }
    if c is '#' && at_line_start {
      // Consume the whole directive line, then decide whether it was a pack.
      let start = i
      let mut end = i
      while end < len && input[end] != '\n' {
        end += 1
      }
      match parse_pack_directive(input, start, end) {
        Some(action) => {
          match action {
            PackSet(value) => current = value
            PackPush(value) => {
              stack.push(current)
              match value {
                Some(_) => current = value
                None => ()
              }
            }
            PackPop =>
              match stack.pop() {
                Some(restored) => current = restored
                None => current = None
              }
          }
          events.push((end, current))
        }
        None => ()
      }
      i = end
      at_line_start = false
      continue
    }
    at_line_start = false
    i += 1
  }
  { events, }
}

///|
/// Returns the `#pragma pack` cap in effect at the current source position.
///
/// Callers must sample this *before* parsing an aggregate body, because the
/// closing `}` may be followed by a `#pragma pack(pop)` that the lexer has
/// already scanned past by the time the declaration is constructed.
fn Parser::current_pack(self : Parser) -> Int? {
  self.pragma_pack.pack_at(self.lexer.pos)
}

///|
/// Combines an aggregate's GNU `packed` attribute with the `#pragma pack` cap
/// in effect at its definition.
///
/// `__attribute__((packed))` means "align every field to 1", which is the
/// strongest possible cap, so it wins over any pragma.
fn combine_pack(is_packed : Bool, pragma : Int?) -> Int? {
  if is_packed {
    Some(1)
  } else {
    pragma
  }
}

///|
/// One `#pragma pack` state transition.
priv enum PackAction {
  PackSet(Int?)
  PackPush(Int?)
  PackPop
}

///|
/// Recognizes `#pragma pack(...)` on the directive line `input[start:end]`,
/// returning the transition it encodes, or `None` when the line is some other
/// directive or an unrecognized `pack` form.
fn parse_pack_directive(input : String, start : Int, end : Int) -> PackAction? {
  let mut i = start + 1 // past '#'
  fn skip_spaces() -> Unit {
    while i < end && (input[i] is ' ' || input[i] is '\t' || input[i] is '\r') {
      i += 1
    }
  }

  fn read_word() -> String {
    let word_start = i
    while i < end &&
          (
            input[i] is ('a'..='z') ||
            input[i] is ('A'..='Z') ||
            input[i] is ('0'..='9') ||
            input[i] is '_'
          ) {
      i += 1
    }
    input[word_start:i].to_owned()
  }

  skip_spaces()
  if read_word() != "pragma" {
    return None
  }
  skip_spaces()
  if read_word() != "pack" {
    return None
  }
  skip_spaces()
  if i >= end || input[i] != '(' {
    return None
  }
  i += 1
  skip_spaces()
  if i < end && input[i] is ')' {
    return Some(PackSet(None))
  }
  // Check the bare `pack(N)` form before reading a keyword, because `read_word`
  // also accepts digits and would otherwise swallow the number.
  if i < end && input[i] is ('0'..='9') {
    return match read_pack_number(input, i, end) {
      Some(n) => Some(PackSet(Some(n)))
      None => None
    }
  }
  let keyword = read_word()
  if keyword is "push" {
    skip_spaces()
    if i < end && input[i] is ',' {
      i += 1
      skip_spaces()
      match read_pack_number(input, i, end) {
        Some(n) => return Some(PackPush(Some(n)))
        None => return None
      }
    }
    return Some(PackPush(None))
  }
  if keyword is "pop" {
    // `#pragma pack(pop, N)` also exists; the trailing value re-sets the cap
    // after popping, but no supported header uses it, so treat it as a plain
    // pop rather than guessing.
    return Some(PackPop)
  }
  None
}

///|
/// Reads a decimal pack value, rejecting anything that is not a positive power
/// of two (the only values C compilers accept).
fn read_pack_number(input : String, from : Int, end : Int) -> Int? {
  let mut i = from
  let mut value = 0
  let mut digits = 0
  while i < end && input[i] is ('0'..='9') {
    value = value * 10 + (input[i].to_int() - '0')
    digits += 1
    i += 1
  }
  if digits == 0 || value <= 0 || value > 16 {
    return None
  }
  if (value & (value - 1)) != 0 {
    return None
  }
  Some(value)
}

///|
/// Returns the pack cap in effect at byte offset `pos`, or `None` for natural
/// alignment.
fn PragmaPackTable::pack_at(self : PragmaPackTable, pos : Int) -> Int? {
  // Binary search for the last directive that ends at or before `pos`.
  let events = self.events
  if events.length() == 0 {
    return None
  }
  for lo = 0, hi = events.length(); lo < hi; {
    let mid = lo + (hi - lo) / 2
    if events[mid].0 <= pos {
      continue mid + 1, hi
    } else {
      continue lo, mid
    }
  } nobreak {
    if lo == 0 {
      None
    } else {
      events[lo - 1].1
    }
  } where {
    proof_invariant: 0 <= lo && lo <= hi && hi <= events.length(),
    proof_invariant: lo == 0 || events[lo - 1].0 <= pos,
    proof_invariant: hi == events.length() || events[hi].0 > pos,
    proof_reasoning: (
      #|`events` is built in increasing offset order by `scan`, so it is sorted
      #|on `.0` and the boundary witnesses generalize:
      #|  - `events[lo-1].0 <= pos` implies all events[0..lo) end at or before pos
      #|  - `events[hi].0 > pos` implies all events[hi..len) end after pos
      #|
      #|Preservation:
      #|  - when events[mid].0 <= pos we set lo = mid+1, and events[lo-1] is
      #|    events[mid], which satisfies the invariant
      #|  - otherwise we set hi = mid, and events[hi] is events[mid] > pos
      #|
      #|Termination: hi - lo strictly decreases, since lo <= mid < hi.
      #|
      #|At exit lo == hi, so every event before lo ends at or before pos and
      #|every event from lo on ends after it. The last directive in effect is
      #|therefore events[lo-1], or none at all when lo == 0.
    ),
  }
}
