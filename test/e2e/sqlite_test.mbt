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
