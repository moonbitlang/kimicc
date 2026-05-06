///|
async test "sqlite object supports basic api smoke" {
  let driver =
    #|#include "sqlite3.h"
    #|#include <stdio.h>
    #|#include <string.h>
    #|
    #|int main(void) {
    #|  sqlite3 *db = 0;
    #|  char *msg = 0;
    #|  int rc = sqlite3_initialize();
    #|  if (rc != SQLITE_OK) {
    #|    printf("initialize rc=%d\n", rc);
    #|    return 1;
    #|  }
    #|  rc = sqlite3_open(":memory:", &db);
    #|  if (rc != SQLITE_OK) {
    #|    printf("open rc=%d err=%s\n", rc, db ? sqlite3_errmsg(db) : "null");
    #|    return 2;
    #|  }
    #|  if (!sqlite3_complete("select 1;")) {
    #|    printf("complete failed\n");
    #|    return 3;
    #|  }
    #|  if (sqlite3_stricmp("AbC", "aBc") != 0) {
    #|    printf("stricmp failed\n");
    #|    return 4;
    #|  }
    #|  msg = sqlite3_mprintf("%d-%s", 42, "ok");
    #|  if (msg == 0 || strcmp(msg, "42-ok") != 0) {
    #|    printf("mprintf failed: %s\n", msg ? msg : "null");
    #|    return 5;
    #|  }
    #|  sqlite3_free(msg);
    #|  sqlite3_close(db);
    #|  printf("basic-api-ok\n");
    #|  return 0;
    #|}
  let result = run_driver_with_sqlite_object(driver, "sqlite_basic_api")
  if result.code != 0 {
    abort("SQLite basic API smoke failed:\n" + result.output)
  }
  assert_true(result.output.contains("basic-api-ok"))
}

///|
async test "sqlite object prepares and steps simple select" {
  let driver =
    #|#include "sqlite3.h"
    #|#include <stdio.h>
    #|
    #|int main(void) {
    #|  sqlite3 *db = 0;
    #|  sqlite3_stmt *stmt = 0;
    #|  int rc = sqlite3_open(":memory:", &db);
    #|  if (rc != SQLITE_OK) {
    #|    printf("open rc=%d err=%s\n", rc, db ? sqlite3_errmsg(db) : "null");
    #|    return 1;
    #|  }
    #|  rc = sqlite3_prepare_v2(db, "select 1;", -1, &stmt, 0);
    #|  if (rc != SQLITE_OK) {
    #|    printf("prepare rc=%d err=%s\n", rc, sqlite3_errmsg(db));
    #|    sqlite3_close(db);
    #|    return 2;
    #|  }
    #|  rc = sqlite3_step(stmt);
    #|  if (rc != SQLITE_ROW) {
    #|    printf("step rc=%d\n", rc);
    #|    sqlite3_finalize(stmt);
    #|    sqlite3_close(db);
    #|    return 3;
    #|  }
    #|  printf("select-value=%d\n", sqlite3_column_int(stmt, 0));
    #|  sqlite3_finalize(stmt);
    #|  sqlite3_close(db);
    #|  return 0;
    #|}
  let result = run_driver_with_sqlite_object(driver, "sqlite_prepare_step")
  if result.code != 0 {
    abort("SQLite prepare/step failed:\n" + result.output)
  }
  assert_true(result.output.contains("select-value=1"))
}

///|
async test "sqlite object creates file database with readable mode" {
  let driver =
    #|#include "sqlite3.h"
    #|#include <stdio.h>
    #|#include <sys/stat.h>
    #|#include <unistd.h>
    #|
    #|int main(void) {
    #|  sqlite3 *db = 0;
    #|  struct stat st;
    #|  const char *path = "/tmp/kimicc_sqlite_mode_e2e.db";
    #|  mode_t old_mask = umask(0);
    #|  unlink(path);
    #|  int rc = sqlite3_open(path, &db);
    #|  if (rc != SQLITE_OK) {
    #|    printf("open rc=%d err=%s\n", rc, db ? sqlite3_errmsg(db) : "null");
    #|    umask(old_mask);
    #|    return 1;
    #|  }
    #|  sqlite3_close(db);
    #|  umask(old_mask);
    #|  if (stat(path, &st) != 0) {
    #|    perror("stat");
    #|    return 2;
    #|  }
    #|  printf("mode=%o\n", (int)(st.st_mode & 0777));
    #|  unlink(path);
    #|  return (st.st_mode & 0777) == 0644 ? 0 : 3;
    #|}
  let result = run_driver_with_sqlite_object(driver, "sqlite_file_mode")
  if result.code != 0 {
    abort("SQLite file mode smoke failed:\n" + result.output)
  }
  assert_true(result.output.contains("mode=644"))
}

///|
async test "sqlite object creates inserts and reads rows" {
  let driver =
    #|#include "sqlite3.h"
    #|#include <stdio.h>
    #|#include <string.h>
    #|
    #|int main(void) {
    #|  sqlite3 *db = 0;
    #|  sqlite3_stmt *stmt = 0;
    #|  char *err = 0;
    #|  int rc = sqlite3_open(":memory:", &db);
    #|  if (rc != SQLITE_OK) {
    #|    printf("open rc=%d err=%s\n", rc, db ? sqlite3_errmsg(db) : "null");
    #|    return 1;
    #|  }
    #|  rc = sqlite3_exec(db,
    #|    "create table t(id integer primary key, name text);"
    #|    "insert into t(name) values('alpha'),('beta');",
    #|    0, 0, &err);
    #|  if (rc != SQLITE_OK) {
    #|    printf("exec rc=%d err=%s\n", rc, err ? err : sqlite3_errmsg(db));
    #|    sqlite3_free(err);
    #|    sqlite3_close(db);
    #|    return 2;
    #|  }
    #|  rc = sqlite3_prepare_v2(db, "select id, name from t order by id;", -1, &stmt, 0);
    #|  if (rc != SQLITE_OK) {
    #|    printf("prepare rc=%d err=%s\n", rc, sqlite3_errmsg(db));
    #|    sqlite3_close(db);
    #|    return 3;
    #|  }
    #|  int seen = 0;
    #|  while ((rc = sqlite3_step(stmt)) == SQLITE_ROW) {
    #|    int id = sqlite3_column_int(stmt, 0);
    #|    const unsigned char *name = sqlite3_column_text(stmt, 1);
    #|    printf("row=%d:%s\n", id, name);
    #|    if ((id == 1 && strcmp((const char *)name, "alpha") == 0) ||
    #|        (id == 2 && strcmp((const char *)name, "beta") == 0)) {
    #|      seen++;
    #|    }
    #|  }
    #|  if (rc != SQLITE_DONE) {
    #|    printf("step rc=%d err=%s\n", rc, sqlite3_errmsg(db));
    #|    sqlite3_finalize(stmt);
    #|    sqlite3_close(db);
    #|    return 4;
    #|  }
    #|  sqlite3_finalize(stmt);
    #|  sqlite3_close(db);
    #|  if (seen != 2) {
    #|    printf("seen=%d\n", seen);
    #|    return 5;
    #|  }
    #|  printf("create-insert-read-ok\n");
    #|  return 0;
    #|}
  let result = run_driver_with_sqlite_object(
    driver, "sqlite_create_insert_read",
  )
  if result.code != 0 {
    abort("SQLite create/insert/read failed:\n" + result.output)
  }
  assert_true(result.output.contains("create-insert-read-ok"))
}

///|
async test "sqlite object handles bound statements and aggregates" {
  let driver =
    #|#include "sqlite3.h"
    #|#include <stdio.h>
    #|
    #|int main(void) {
    #|  sqlite3 *db = 0;
    #|  sqlite3_stmt *insert = 0;
    #|  sqlite3_stmt *query = 0;
    #|  char *err = 0;
    #|  const char *names[3] = {"alpha", "beta", "gamma"};
    #|  int values[3] = {10, 20, 12};
    #|  int rc = sqlite3_open(":memory:", &db);
    #|  if (rc != SQLITE_OK) {
    #|    printf("open rc=%d err=%s\n", rc, db ? sqlite3_errmsg(db) : "null");
    #|    return 1;
    #|  }
    #|  rc = sqlite3_exec(db, "create table t(name text, v integer);", 0, 0, &err);
    #|  if (rc != SQLITE_OK) {
    #|    printf("create rc=%d err=%s\n", rc, err ? err : sqlite3_errmsg(db));
    #|    sqlite3_free(err);
    #|    sqlite3_close(db);
    #|    return 2;
    #|  }
    #|  rc = sqlite3_prepare_v2(db, "insert into t(name, v) values(?, ?);", -1, &insert, 0);
    #|  if (rc != SQLITE_OK) {
    #|    printf("insert prepare rc=%d err=%s\n", rc, sqlite3_errmsg(db));
    #|    sqlite3_close(db);
    #|    return 3;
    #|  }
    #|  for (int i = 0; i < 3; i++) {
    #|    sqlite3_bind_text(insert, 1, names[i], -1, SQLITE_STATIC);
    #|    sqlite3_bind_int(insert, 2, values[i]);
    #|    rc = sqlite3_step(insert);
    #|    if (rc != SQLITE_DONE) {
    #|      printf("insert step %d rc=%d err=%s\n", i, rc, sqlite3_errmsg(db));
    #|      sqlite3_finalize(insert);
    #|      sqlite3_close(db);
    #|      return 4;
    #|    }
    #|    sqlite3_reset(insert);
    #|    sqlite3_clear_bindings(insert);
    #|  }
    #|  sqlite3_finalize(insert);
    #|  rc = sqlite3_exec(db, "update t set v = v + 10 where name = 'gamma';", 0, 0, &err);
    #|  if (rc != SQLITE_OK || sqlite3_changes(db) != 1) {
    #|    printf("update rc=%d changes=%d err=%s\n", rc, sqlite3_changes(db),
    #|           err ? err : sqlite3_errmsg(db));
    #|    sqlite3_free(err);
    #|    sqlite3_close(db);
    #|    return 5;
    #|  }
    #|  rc = sqlite3_prepare_v2(db, "select count(*), sum(v) from t where v >= ?;", -1, &query, 0);
    #|  if (rc != SQLITE_OK) {
    #|    printf("query prepare rc=%d err=%s\n", rc, sqlite3_errmsg(db));
    #|    sqlite3_close(db);
    #|    return 6;
    #|  }
    #|  sqlite3_bind_int(query, 1, 20);
    #|  rc = sqlite3_step(query);
    #|  if (rc != SQLITE_ROW) {
    #|    printf("query step rc=%d err=%s\n", rc, sqlite3_errmsg(db));
    #|    sqlite3_finalize(query);
    #|    sqlite3_close(db);
    #|    return 7;
    #|  }
    #|  int count = sqlite3_column_int(query, 0);
    #|  int sum = sqlite3_column_int(query, 1);
    #|  printf("aggregate=%d:%d\n", count, sum);
    #|  sqlite3_finalize(query);
    #|  sqlite3_close(db);
    #|  if (count != 2 || sum != 42) return 8;
    #|  printf("bound-aggregate-ok\n");
    #|  return 0;
    #|}
  let result = run_driver_with_sqlite_object(driver, "sqlite_bound_aggregate")
  if result.code != 0 {
    abort("SQLite bound statement aggregate failed:\n" + result.output)
  }
  assert_true(result.output.contains("bound-aggregate-ok"))
}

///|
async test "sqlite object matches clang baseline for SQL script runner" {
  let sql =
    #|create table account(
    #|  id integer primary key,
    #|  name text not null unique,
    #|  balance integer not null check(balance >= 0)
    #|);
    #|create index account_balance_idx on account(balance, name);
    #|insert into account(name, balance)
    #|  values('alpha', 10), ('beta', 25), ('gamma', 17);
    #|begin;
    #|update account set balance = balance + 5 where name in ('alpha', 'gamma');
    #|insert into account(name, balance)
    #|  select 'delta', sum(balance) from account where name != 'beta';
    #|commit;
    #|select name, balance from account where balance >= 15 order by balance, name;
    #|select count(*) as n, sum(balance) as total, max(balance) as high
    #|  from account;
  let result = run_sql_script_against_clang_baseline(
    sql, "sqlite_sql_script_core",
  )
  assert_true(result.output.contains("row|name=gamma|balance=22"))
  assert_true(result.output.contains("row|name=delta|balance=37"))
  assert_true(result.output.contains("row|n=4|total=99|high=37"))
  assert_true(result.output.contains("script-ok"))
}

///|
async test "sqlite direct object matches clang baseline for SQL script runner" {
  let sql =
    #|create table account(
    #|  id integer primary key,
    #|  name text not null unique,
    #|  balance integer not null check(balance >= 0)
    #|);
    #|create index account_balance_idx on account(balance, name);
    #|insert into account(name, balance)
    #|  values('alpha', 10), ('beta', 25), ('gamma', 17);
    #|begin;
    #|update account set balance = balance + 5 where name in ('alpha', 'gamma');
    #|insert into account(name, balance)
    #|  select 'delta', sum(balance) from account where name != 'beta';
    #|commit;
    #|select name, balance from account where balance >= 15 order by balance, name;
    #|select count(*) as n, sum(balance) as total, max(balance) as high
    #|  from account;
  let result = run_sql_script_compiler_against_clang_baseline(
    sql,
    "sqlite_direct_sql_script_core",
    DirectObject,
  )
  assert_true(result.output.contains("row|name=gamma|balance=22"))
  assert_true(result.output.contains("row|name=delta|balance=37"))
  assert_true(result.output.contains("row|n=4|total=99|high=37"))
  assert_true(result.output.contains("script-ok"))
}

///|
fn sqlite_public_smoke_script_paths() -> Array[String] {
  [
    "test/select1.test", "test/select2.test", "test/select3.test", "test/select4.test",
    "test/select5.test", "test/select6.test", "test/select7.test", "test/select8.test",
    "test/select9.test", "test/selectA.test", "test/selectB.test", "test/selectC.test",
    "test/selectD.test", "test/selectE.test", "test/selectF.test", "test/selectG.test",
    "test/selectH.test", "test/with6.test",
  ]
}

///|
async test "sqlite public tcl smoke batch passes through testfixture harness" {
  let result = run_sqlite_public_tcl_batch(
    sqlite_public_smoke_script_paths(),
    "sqlite_public_tcl_smoke_batch",
  )
  if result.code != 0 {
    abort("SQLite public Tcl smoke batch failed:\n" + result.output)
  }
  if result.output == "sqlite-public-tests-skipped\n" {
    return
  }
  assert_true(result.output.contains("### test/selectH.test"))
  assert_true(result.output.contains("### test/with6.test"))
  assert_true(result.output.contains("0 errors out of 36717 tests"))
  assert_true(result.output.contains("0 errors out of 18 tests"))
  assert_true(result.output.contains("with6-400... Ok"))
}

///|
async test "sqlite direct object public tcl smoke batch passes" {
  let result = run_sqlite_public_tcl_batch_with(
    sqlite_public_smoke_script_paths(),
    "sqlite_direct_public_tcl_smoke_batch",
    DirectObject,
  )
  if result.code != 0 {
    abort(
      "SQLite direct-object public Tcl select smoke failed:\n" + result.output,
    )
  }
  if result.output == "sqlite-public-tests-skipped\n" {
    return
  }
  assert_true(result.output.contains("### test/selectH.test"))
  assert_true(result.output.contains("### test/with6.test"))
  assert_true(result.output.contains("0 errors out of 36717 tests"))
  assert_true(result.output.contains("0 errors out of 18 tests"))
  assert_true(result.output.contains("with6-400... Ok"))
}

///|
fn assert_sqlite_veryquick_residuals(
  output : String,
  compiler : String,
) -> Unit {
  if !output.contains("24 errors out of") {
    abort(
      "SQLite " +
      compiler +
      " veryquick output missing residual summary:\n" +
      output,
    )
  }
  for
    marker in [
      "func-38.100", "func-39.120", "func-39.130", "func-39.140", "func-39.150",
      "func-39.160", "func-39.170", "func-39.180", "func-39.190", "json101-20.2",
      "json101-20.3", "json501-9.1", "json501-9.2", "json501-9.3", "literal-2.3.1",
      "literal-2.3.2", "literal-2.3.3", "literal-2.4.1", "literal-2.4.2", "literal-2.4.3",
      "literal-3.4.1", "literal-3.4.2", "literal-3.4.3", "types3-1.1",
    ] {
    if !output.contains(marker) {
      abort(
        "SQLite " +
        compiler +
        " veryquick residual output missing " +
        marker +
        ":\n" +
        output,
      )
    }
  }
}

///|
fn assert_sqlite_full_residuals(output : String, compiler : String) -> Unit {
  if !output.contains("26 errors out of") {
    abort(
      "SQLite " + compiler + " full output missing residual summary:\n" + output,
    )
  }
  for
    marker in [
      "FAILED: test/json101.test", "FAILED: test/func.test", "FAILED: test/literal.test",
      "FAILED: test/json501.test", "FAILED: test/loadext.test", "FAILED: test/types3.test",
    ] {
    if !output.contains(marker) {
      abort(
        "SQLite " +
        compiler +
        " full residual output missing " +
        marker +
        ":\n" +
        output,
      )
    }
  }
}

///|
fn sqlite_residual_script_paths() -> Array[String] {
  [
    "test/func.test", "test/json101.test", "test/json501.test", "test/literal.test",
    "test/types3.test", "test/loadext.test",
  ]
}

///|
fn sqlite_release_gate_script_paths() -> Array[String] {
  [
    "test/selectC.test", "ext/expert/expert1.test", "ext/fts5/test/fts5contentless.test",
    "ext/fts5/test/fts5aa.test", "ext/fts5/test/fts5origintext4.test", "ext/intck/intck1.test",
    "ext/intck/intck2.test", "ext/recover/recover1.test", "ext/rtree/rtree2.test",
    "ext/rtree/rtree7.test", "ext/rtree/rtree9.test", "test/avtrans.test", "test/decimal.test",
    "test/func7.test", "test/corruptI.test", "test/incrcorrupt.test",
  ]
}

///|
fn assert_sqlite_residual_script_outputs(
  output : String,
  compiler : String,
) -> Unit {
  for script in sqlite_residual_script_paths() {
    let marker = "### " + script
    if !output.contains(marker) {
      abort(
        "SQLite " +
        compiler +
        " residual script output missing " +
        marker +
        ":\n" +
        output,
      )
    }
  }
  for
    marker in [
      "func-38.100", "func-39.120", "func-39.130", "func-39.140", "func-39.150",
      "func-39.160", "func-39.170", "func-39.180", "func-39.190", "json101-20.2",
      "json101-20.3", "json501-9.1", "json501-9.2", "json501-9.3", "literal-2.3.1",
      "literal-2.3.2", "literal-2.3.3", "literal-2.4.1", "literal-2.4.2", "literal-2.4.3",
      "literal-3.4.1", "literal-3.4.2", "literal-3.4.3", "types3-1.1", "loadext-2.1",
      "loadext-2.2",
    ] {
    if !output.contains(marker) {
      abort(
        "SQLite " +
        compiler +
        " residual script output missing " +
        marker +
        ":\n" +
        output,
      )
    }
  }
}

///|
fn assert_sqlite_release_gate_output(
  output : String,
  compiler : String,
) -> Unit {
  for script in sqlite_release_gate_script_paths() {
    let marker = "### " + script
    if !output.contains(marker) {
      abort(
        "SQLite " +
        compiler +
        " release gate output missing " +
        marker +
        ":\n" +
        output,
      )
    }
  }
}

///|
async test "sqlite public veryquick residual failures match clang when enabled" {
  if !sqlite_public_conformance_enabled("veryquick") {
    return
  }
  let kimicc = run_sqlite_public_tcl_script_tail_with(
    "test/veryquick.test",
    "sqlite_public_veryquick",
    Kimicc,
    220,
  )
  if kimicc.output == "sqlite-public-tests-skipped\n" {
    return
  }
  let clang = run_sqlite_public_tcl_script_tail_with(
    "test/veryquick.test",
    "sqlite_public_veryquick",
    Clang,
    220,
  )
  if kimicc.code != clang.code {
    abort(
      "SQLite veryquick exit code differs:\nkimicc:\n" +
      kimicc.output +
      "\nclang:\n" +
      clang.output,
    )
  }
  if kimicc.code == 0 {
    return
  }
  assert_sqlite_veryquick_residuals(kimicc.output, "kimicc")
  assert_sqlite_veryquick_residuals(clang.output, "clang")
}

///|
async test "sqlite public release gate scripts pass with clang baseline when enabled" {
  if !sqlite_public_conformance_enabled("release") {
    return
  }
  let kimicc = run_sqlite_public_tcl_batch_with(
    sqlite_release_gate_script_paths(),
    "sqlite_public_release_gate",
    Kimicc,
  )
  if kimicc.output == "sqlite-public-tests-skipped\n" {
    return
  }
  let clang = run_sqlite_public_tcl_batch_with(
    sqlite_release_gate_script_paths(),
    "sqlite_public_release_gate",
    Clang,
  )
  if kimicc.code != 0 {
    abort("SQLite kimicc release gate failed:\n" + kimicc.output)
  }
  if clang.code != 0 {
    abort("SQLite clang release gate failed:\n" + clang.output)
  }
  assert_sqlite_release_gate_output(kimicc.output, "kimicc")
  assert_sqlite_release_gate_output(clang.output, "clang")
}

///|
async test "sqlite public residual scripts match clang when enabled" {
  if !sqlite_public_conformance_enabled("residuals") {
    return
  }
  let kimicc = run_sqlite_public_tcl_batch_collect_with(
    sqlite_residual_script_paths(),
    "sqlite_public_residuals",
    Kimicc,
  )
  if kimicc.output == "sqlite-public-tests-skipped\n" {
    return
  }
  let clang = run_sqlite_public_tcl_batch_collect_with(
    sqlite_residual_script_paths(),
    "sqlite_public_residuals",
    Clang,
  )
  if kimicc.code != clang.code {
    abort(
      "SQLite residual script exit code differs:\nkimicc:\n" +
      kimicc.output +
      "\nclang:\n" +
      clang.output,
    )
  }
  if kimicc.code == 0 {
    return
  }
  assert_sqlite_residual_script_outputs(kimicc.output, "kimicc")
  assert_sqlite_residual_script_outputs(clang.output, "clang")
}

///|
async test "sqlite public full residual failures match clang when enabled" {
  if !sqlite_public_conformance_enabled("full") {
    return
  }
  let kimicc = run_sqlite_public_tcl_runner_tail_with(
    "--jobs 4 full",
    "sqlite_public_full",
    Kimicc,
    320,
  )
  if kimicc.output == "sqlite-public-tests-skipped\n" {
    return
  }
  let clang = run_sqlite_public_tcl_runner_tail_with(
    "--jobs 4 full",
    "sqlite_public_full",
    Clang,
    320,
  )
  if kimicc.code != clang.code {
    abort(
      "SQLite full exit code differs:\nkimicc:\n" +
      kimicc.output +
      "\nclang:\n" +
      clang.output,
    )
  }
  if kimicc.code == 0 {
    return
  }
  assert_sqlite_full_residuals(kimicc.output, "kimicc")
  assert_sqlite_full_residuals(clang.output, "clang")
}
