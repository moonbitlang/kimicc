///|
/// Property tests for the generated Metal kernel's table staging.
///
/// These exist because of a real bug. ds4's IQ2_XXS kernel stages its
/// 256-entry codebook into threadgroup memory with a loop that copies a
/// fixed four entries per thread. That covers the table exactly when
/// there are two simdgroups -- 2 x 32 x 4 = 256 -- and its source never
/// says so. Mirrored faithfully and generated at four simdgroups, half
/// the threads wrote past the end of threadgroup memory, and the Metal
/// compiler accepted it silently: an out-of-bounds threadgroup write is
/// not a compile-time error, so the gate that proves a kernel *builds*
/// could never have caught it.
///
/// The invariant is pure index arithmetic, which means it can be checked
/// symbolically with no GPU and no Metal -- in CI, where the compile
/// gate itself is forced to skip.

///|
/// The visit list of the strided staging loop the generator emits:
///
///   for (idx = 32*sgitg + tiisg; idx < n; idx += 32*nsg)
///
/// Thread identifiers run over `[0, 32*nsg)` and the stride is exactly
/// that width, so each index below `n` is reached from exactly one
/// thread, for any `nsg`.
fn strided_visits(nsg : Int, n : Int) -> Array[Int] {
  strided_visits_with(nsg, n, 32 * nsg)
}

///|
/// The same walk with the stride supplied, so a stride read back out of
/// the generated source can be simulated directly.
fn strided_visits_with(nsg : Int, n : Int, stride : Int) -> Array[Int] {
  let out : Array[Int] = []
  for sgitg in 0..<nsg {
    for tiisg in 0..<32 {
      let mut idx = 32 * sgitg + tiisg
      while idx < n {
        out.push(idx)
        idx = idx + stride
      }
    }
  }
  out
}

///|
/// The visit list of ds4's fixed-count form, kept here as the thing we
/// deliberately diverged from: each thread writes `per_thread` entries
/// starting at `tid * per_thread`, with no bound on `n`.
fn fixed_visits(nsg : Int, per_thread : Int) -> Array[Int] {
  let out : Array[Int] = []
  for sgitg in 0..<nsg {
    for tiisg in 0..<32 {
      let base = (32 * sgitg + tiisg) * per_thread
      for i in 0..<per_thread {
        out.push(base + i)
      }
    }
  }
  out
}

///|
/// Every index below `n` is written exactly once, and nothing outside
/// `[0, n)` is touched -- the property whose violation the compiler
/// could not see.
fn covers_exactly(visits : Array[Int], n : Int) -> Bool {
  let seen = Array::make(n, 0)
  for idx in visits {
    if idx < 0 || idx >= n {
      return false
    }
    seen[idx] = seen[idx] + 1
  }
  for count in seen {
    if count != 1 {
      return false
    }
  }
  true
}

///|
/// The generated form covers both tables exactly, at every simdgroup
/// width -- including widths where the table is smaller than the thread
/// count and most threads must copy nothing.
test "the strided staging loop covers both tables at any simdgroup width" {
  for nsg in [1, 2, 3, 4, 5, 8, 16, 32] {
    if !covers_exactly(strided_visits(nsg, 256), 256) {
      fail("codebook coverage failed at nsg=\{nsg}")
    }
    if !covers_exactly(strided_visits(nsg, 128), 128) {
      fail("sign-table coverage failed at nsg=\{nsg}")
    }
  }
}

///|
/// The same property over random widths, so the claim is not just the
/// hand-picked list above.
test "strided staging covers exactly over random widths" {
  let state = @splitmix.new(seed=20260816)
  for case_index in 0..<200 {
    let nsg = 1 + (state.next_uint() % 64).reinterpret_as_int()
    let n = 1 + (state.next_uint() % 4096).reinterpret_as_int()
    if !covers_exactly(strided_visits(nsg, n), n) {
      fail("coverage failed at case \{case_index}: nsg=\{nsg} n=\{n}")
    }
  }
}

///|
/// ds4's fixed-count form, recorded as the reason for the divergence: it
/// covers the 256-entry codebook only at two simdgroups. At one it
/// leaves half the table uninitialised; above two it writes out of
/// bounds. This test documents the invariant its source leaves unstated.
test "ds4's fixed-count staging is correct only at two simdgroups" {
  for nsg in [1, 2, 3, 4, 8] {
    let exact = covers_exactly(fixed_visits(nsg, 4), 256)
    if nsg == 2 {
      if !exact {
        fail("expected the fixed form to be exact at nsg=2")
      }
    } else if exact {
      fail("expected the fixed form to be wrong at nsg=\{nsg}")
    }
  }
  // The sign table carries the same constraint at two entries per thread.
  for nsg in [1, 2, 4] {
    let exact = covers_exactly(fixed_visits(nsg, 2), 128)
    if (nsg == 2) != exact {
      fail("sign-table fixed form: unexpected result at nsg=\{nsg}")
    }
  }
}

///|
/// Reads the staging loop's stride back out of the generated MSL, so the
/// coverage properties below are checked against what the generator
/// actually emitted rather than against a private restatement of the
/// arithmetic. A regression that hardcodes the stride, or emits the
/// wrong bound, changes this text and fails the test.
///
/// The emitted form is `for (int idx = ...; idx < N; idx += STRIDE)`.
fn emitted_stride(source : String, n : Int) -> Int raise {
  let needle = "idx < " + n.to_string() + "; idx += "
  match source.find(needle) {
    Some(at) => {
      let rest = source[at + needle.length():].to_owned()
      let mut digits = ""
      for c in rest {
        if c >= '0' && c <= '9' {
          digits = digits + c.to_string()
        } else {
          break
        }
      }
      if digits == "" {
        fail("no stride digits after `\{needle}`")
      }
      @string.parse_int(digits) catch {
        _ => fail("bad stride `\{digits}`")
      }
    }
    None => fail("generated source has no staging loop bounded by \{n}")
  }
}

///|
/// The generator's own output covers both tables exactly. This is the
/// regression guard: the stride comes from the emitted text, not from
/// this file's model of it.
test "the emitted staging loops cover both tables exactly" {
  for nsg in [1, 2, 4, 8] {
    let source = @ds4_metal.generate({
      in_dim: 4096,
      out_rows: 2048,
      nr0: 4,
      nsg,
    })
    let grid_stride = emitted_stride(source, 256)
    let sign_stride = emitted_stride(source, 128)
    if grid_stride != 32 * nsg || sign_stride != 32 * nsg {
      fail(
        "emitted stride \{grid_stride}/\{sign_stride} is not the thread count at nsg=\{nsg}",
      )
    }
    if !covers_exactly(strided_visits_with(nsg, 256, grid_stride), 256) {
      fail("emitted codebook loop does not cover exactly at nsg=\{nsg}")
    }
    if !covers_exactly(strided_visits_with(nsg, 128, sign_stride), 128) {
      fail("emitted sign loop does not cover exactly at nsg=\{nsg}")
    }
  }
}
