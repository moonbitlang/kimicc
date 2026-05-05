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
async test "sqlite public tcl select1 passes through testfixture harness" {
  let result = run_sqlite_public_tcl_test(
    "test/select1.test", "sqlite_public_tcl_select1",
  )
  if result.code != 0 {
    abort("SQLite public Tcl select1 failed:\n" + result.output)
  }
  if result.output == "sqlite-public-tests-skipped\n" {
    return
  }
  assert_true(result.output.contains("0 errors out of 192 tests"))
}
