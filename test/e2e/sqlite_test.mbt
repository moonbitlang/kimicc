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
